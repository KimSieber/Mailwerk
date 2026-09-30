//
//  HTMLMailView.swift
//  Mailwerk
//
//  v0.1.8b: Zu breite Mails werden nach dem Laden auf Bildschirmbreite
//  verkleinert (CSS-`zoom` am body). Auslöser war eine DHL-Mail, deren
//  Sprachleiste als Tabellenzeile eine Mindestbreite von ~590 px erzwingt;
//  `max-width` hilft gegen Tabellen-Mindestbreiten nicht. Nach dem
//  Verkleinern ist die Seite so breit wie der Bildschirm – wie jede
//  passende Mail, sodass Zoomen per Geste wie gewohnt funktioniert.
//

import SwiftUI
import WebKit

#if os(macOS)
struct HTMLMailView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    /// Getippter mailto:-Link – öffnet eine neue Mail in Mailwerk.
    var onMailto: ((MailtoLink) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = Self.createWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        Self.loadHTML(html, in: webView)
    }
}
#else
struct HTMLMailView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    /// Getippter mailto:-Link – öffnet eine neue Mail in Mailwerk.
    var onMailto: ((MailtoLink) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.createWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        Self.loadHTML(html, in: webView)
    }
}
#endif

extension HTMLMailView {
    static func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        // Skripte aus der Mail nie ausführen (wie Apple Mail). Die App
        // selbst misst die Höhe weiter per evaluateJavaScript – das ist
        // davon nicht betroffen.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        // Transparenter Hintergrund, damit die Mail im Hell- und Dunkelmodus
        // den Hintergrund der App übernimmt. Die beiden Plattformen bieten
        // dafür unterschiedliche Wege an.
        #if os(macOS)
        // Auf macOS ist `isOpaque` nur lesbar und `backgroundColor` fehlt.
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        // Scrollen übernimmt der äußere ScrollView; Tippen (Links) und
        // Textauswahl bleiben in der Mail möglich.
        webView.scrollView.isScrollEnabled = false
        #endif
        return webView
    }

    static func loadHTML(_ html: String, in webView: WKWebView) {
        let wrapped = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
                body {
                    font-family: -apple-system, sans-serif;
                    font-size: 16px;
                    line-height: 1.5;
                    color: #333;
                    margin: 0;
                    padding: 0;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                    -webkit-text-size-adjust: 100%;
                }
                /* Breite Tabellen und Container auf die Viewport-Breite
                   beschränken. !important überstimmt inline-Styles, die
                   viele HTML-Mails mitbringen (width: 600px o. ä.). */
                table, div, td, th, img, video, object {
                    max-width: 100% !important;
                    height: auto !important;
                }
                /* Feste Pixelbreiten an Tabellen aufheben */
                table[width], td[width], th[width] {
                    width: auto !important;
                }
                img { display: block; }
                a { color: #007AFF; }
                pre, code {
                    white-space: pre-wrap;
                    word-wrap: break-word;
                    max-width: 100%;
                    overflow-x: auto;
                }
                @media (prefers-color-scheme: dark) {
                    body { color: #F0F0F0; }
                    a { color: #0A84FF; }
                }
            </style>
            </head>
            <body>\(html)</body>
            </html>
            """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: HTMLMailView

        init(_ parent: HTMLMailView) {
            self.parent = parent
        }

        /// Die Mail selbst navigiert nie weg. Erlaubt ist nur das Laden
        /// des eigenen Inhalts (about:blank aus loadHTMLString); getippte
        /// Links gehen gezielt nach außen oder in eine neue Mail.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }

            if navigationAction.navigationType == .linkActivated {
                switch MailLinkAction(url: url) {
                case .openExternally(let target):
                    #if os(macOS)
                    _ = NSWorkspace.shared.open(target)
                    #else
                    _ = await UIApplication.shared.open(target)
                    #endif
                case .compose(let link):
                    parent.onMailto?(link)
                case .ignore:
                    print("🔗 Link ignoriert: \(url.scheme ?? "?")")
                }
                return .cancel
            }

            // Eigener Inhalt: erlaubt. Alles andere (Weiterleitungen,
            // Formulare, iframes, Meta-Refresh): blockiert.
            return url.scheme == "about" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(webView)
            // Zweite Messung nach kurzer Verzögerung: Einige Mails lösen
            // nach dem ersten Layout noch CSS-Transitionen oder Bildladen
            // aus, die die Höhe verändern.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.measureHeight(webView)
            }
        }

        /// Verkleinert eine zu breite Mail auf die Breite der Ansicht (nur
        /// einmal je Laden) und liefert danach die Höhe für den Rahmen.
        ///
        /// Höhe: Für nicht verkleinerte Mails wie bisher `body.scrollHeight`.
        /// Bei verkleinerten Mails meldet `body` je nach Engine unverkleinerte
        /// Werte; dort gilt die Höhe des Dokuments. Sie ist nie kleiner als
        /// der aktuelle Rahmen – unkritisch, weil zuerst im kleinen
        /// Startrahmen gemessen wird.
        ///
        /// Das Skript gehört der App; JavaScript aus der Mail bleibt aus.
        private static let fitAndMeasureScript = """
            (function () {
                var root = document.documentElement, body = document.body;
                if (!body) { return 0; }
                if (!body.style.zoom) {
                    var visible = root.clientWidth, full = root.scrollWidth;
                    if (full > visible + 1) { body.style.zoom = String(visible / full); }
                }
                return body.style.zoom ? root.scrollHeight : body.scrollHeight;
            })()
            """

        private func measureHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript(Self.fitAndMeasureScript) { result, _ in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self.parent.contentHeight = height
                    }
                }
            }
        }
    }
}

