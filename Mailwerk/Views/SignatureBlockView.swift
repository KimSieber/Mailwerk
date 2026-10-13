//
//  SignatureBlockView.swift
//  Mailwerk
//
//  Zweck: Zeigt eine HTML-Signatur beim Verfassen als eigenen Block unter
//  dem Mailtext – direkt bearbeitbar wie im Browser (`contenteditable`):
//  Text lässt sich ändern und löschen, Tabellen, Spaltenbreiten und
//  Ausrichtung bleiben erhalten. Formatieren ist hier nicht vorgesehen.
//  Oben rechts entfernt ✕ den ganzen Block.
//
//  Technik: WKWebView ohne eigenes Scrollen; die Höhe folgt dem Inhalt.
//  JavaScript aus der Signatur ist abgeschaltet. Ein Skript der App (in
//  einer eigenen „Welt“, getrennt vom Seiteninhalt) macht den Inhalt
//  bearbeitbar und meldet nach jeder Eingabe das aktuelle HTML und die
//  Höhe zurück. Navigation ist gesperrt; ein Tipp auf einen Link öffnet
//  ihn nicht.
//
//  Abgrenzung: Zustand und Versand → ComposeViewModel, HTMLSignatureBlock;
//  Verfassen-Fenster → ComposeView.
//
//  Abhängigkeiten: SwiftUI, WebKit, HTMLSignatureBlock.
//

import SwiftUI
import WebKit

/// HTML-Signatur als bearbeitbarer Block mit Entfernen-Knopf.
struct SignatureBlockView: View {
    /// Angezeigter Block.
    let block: HTMLSignatureBlock
    /// Meldet geändertes HTML.
    let onChange: (String) -> Void
    /// Entfernt den Block.
    let onRemove: () -> Void

    /// Gemessene Höhe des Inhalts.
    @State private var contentHeight: CGFloat = 0

    /// Block mit Entfernen-Knopf oben rechts.
    var body: some View {
        ZStack(alignment: .topTrailing) {
            EditableHTMLView(
                block: block,
                contentHeight: $contentHeight,
                onChange: onChange
            )
            .frame(height: max(30, contentHeight))
            .padding(.trailing, 28)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(4)
            .help("Signatur entfernen")
            .accessibilityLabel("Signatur entfernen")
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Web-Ansicht

/// Bearbeitbare Web-Ansicht für die Signatur.
private struct EditableHTMLView {
    /// Angezeigter Block; eine neue Kennung lädt neu.
    let block: HTMLSignatureBlock
    /// Gemessene Höhe des Inhalts.
    @Binding var contentHeight: CGFloat
    /// Meldet geändertes HTML.
    let onChange: (String) -> Void

    /// Name der Nachricht vom App-Skript an die App.
    static let messageName = "mailwerkSignature"

    /// Skript der App: Inhalt bearbeitbar machen, Änderungen und Höhe melden.
    static let script = """
    (function() {
      function report(withHTML) {
        var height = Math.ceil(document.body.getBoundingClientRect().height);
        window.webkit.messageHandlers.\(messageName).postMessage({
          html: withHTML ? document.body.innerHTML : null,
          height: height
        });
      }
      document.body.setAttribute('contenteditable', 'true');
      document.body.addEventListener('input', function() { report(true); });
      window.addEventListener('load', function() { report(false); });
      new ResizeObserver(function() { report(false); }).observe(document.body);
      report(false);
    })();
    """

    /// Grundgerüst um das HTML der Signatur.
    ///
    /// - Parameter html: HTML der Signatur.
    /// - Returns: Vollständige Seite; Hintergrund durchsichtig, Schrift wie im Editor.
    static func page(for html: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; background: transparent; }
        body { display: flow-root; padding: 0 4px; font: -apple-system-body;
               font-family: -apple-system, sans-serif; font-size: 16px;
               overflow-wrap: break-word; outline: none; }
        img { max-width: 100%; height: auto; }
        </style></head><body>\(html)</body></html>
        """
    }

    /// Legt den Coordinator an.
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Erzeugt die Web-Ansicht samt App-Skript.
    ///
    /// - Parameter coordinator: Empfänger der Meldungen.
    /// - Returns: Konfigurierte Web-Ansicht.
    static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let world = WKContentWorld.defaultClient
        configuration.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world)
        )
        configuration.userContentController.add(
            WeakMessageHandler(coordinator), contentWorld: world, name: messageName
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    /// Vermittelt zwischen Web-Ansicht und SwiftUI.
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        /// Aktuelle Ansicht (für Bindung und Rückruf).
        var parent: EditableHTMLView
        /// Kennung des zuletzt geladenen Blocks.
        private var loadedID: UUID?

        /// Legt den Coordinator an.
        ///
        /// - Parameter parent: Ansicht.
        init(_ parent: EditableHTMLView) {
            self.parent = parent
        }

        /// Lädt den Block, wenn er neu ist (andere Kennung).
        ///
        /// - Parameter webView: Web-Ansicht.
        func loadIfNeeded(in webView: WKWebView) {
            guard loadedID != parent.block.id else { return }
            loadedID = parent.block.id
            webView.loadHTMLString(EditableHTMLView.page(for: parent.block.displayHTML), baseURL: nil)
        }

        /// Erlaubt nur das Laden der Seite selbst, keine Navigation.
        ///
        /// Verarbeitung: Bewusst die Form mit Rückruf statt `async` – die
        /// `async`-Form von Objective-C-Delegate-Methoden brachte den
        /// Compiler schon zum Absturz.
        ///
        /// - Parameters:
        ///   - webView: Web-Ansicht.
        ///   - navigationAction: Gewünschte Navigation.
        ///   - decisionHandler: Erlauben nur für das Laden der Seite selbst.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }

        /// Nimmt Meldungen des App-Skripts entgegen (HTML, Höhe).
        ///
        /// - Parameters:
        ///   - userContentController: Absender.
        ///   - message: Meldung mit `html` (optional) und `height`.
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }
            if let html = body["html"] as? String {
                parent.onChange(html)
            }
            if let height = body["height"] as? Double {
                let value = CGFloat(height)
                if abs(value - parent.contentHeight) > 0.5 {
                    parent.contentHeight = value
                }
            }
        }
    }
}

/// Hält den Empfänger der Skript-Meldungen nur schwach – die
/// Web-Konfiguration würde ihn sonst dauerhaft festhalten.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    /// Eigentlicher Empfänger.
    private weak var target: WKScriptMessageHandler?

    /// Legt den Vermittler an.
    ///
    /// - Parameter target: Eigentlicher Empfänger.
    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    /// Reicht die Meldung weiter.
    ///
    /// - Parameters:
    ///   - userContentController: Absender.
    ///   - message: Meldung.
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

#if os(iOS)
extension EditableHTMLView: UIViewRepresentable {
    /// Legt die Web-Ansicht einmalig an.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Web-Ansicht.
    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(coordinator: context.coordinator)
        context.coordinator.loadIfNeeded(in: webView)
        return webView
    }

    /// Übernimmt einen neuen Block.
    ///
    /// - Parameters:
    ///   - webView: Web-Ansicht.
    ///   - context: Kontext mit dem Coordinator.
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.loadIfNeeded(in: webView)
    }
}
#else
extension EditableHTMLView: NSViewRepresentable {
    /// Legt die Web-Ansicht einmalig an.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Web-Ansicht.
    func makeNSView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(coordinator: context.coordinator)
        context.coordinator.loadIfNeeded(in: webView)
        return webView
    }

    /// Übernimmt einen neuen Block.
    ///
    /// - Parameters:
    ///   - webView: Web-Ansicht.
    ///   - context: Kontext mit dem Coordinator.
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.loadIfNeeded(in: webView)
    }
}
#endif
