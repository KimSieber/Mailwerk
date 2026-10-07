//
//  HTMLMailView.swift
//  Mailwerk
//
//  Zweck: Zeigt den HTML-Teil einer Mail in einem WKWebView an und meldet
//  dessen Höhe, damit die umgebende Ansicht den Rahmen anpassen kann.
//
//  Zu breite Mails werden nach dem Laden auf Bildschirmbreite verkleinert
//  (CSS-`zoom` am body). Auslöser war eine Mail, deren Tabellenzeile eine
//  Mindestbreite von rund 590 px erzwingt; `max-width` hilft gegen
//  Tabellen-Mindestbreiten nicht. Nach dem Verkleinern ist die Seite so
//  breit wie der Bildschirm, Zoomen per Geste funktioniert wie gewohnt.
//
//  Der Inhalt wird nur neu geladen, wenn sich das HTML tatsächlich
//  geändert hat. SwiftUI ruft `update…View` bei jeder Änderung der
//  Umgebung auf – auch, wenn diese Ansicht selbst ihre Höhe meldet.
//  Ohne die Prüfung würde die Mail dabei jedes Mal neu geladen und
//  neu vermessen.
//
//  Sicherheit: JavaScript aus der Mail ist abgeschaltet; die Mail kann
//  nicht wegnavigieren. Links öffnen extern bzw. als neue Mail.
//
//  Abgrenzung: Aufbau der Mailansicht → MessageDetailView; Zitat in der
//  Antwort → ComposeView; Einordnung von Links → MailLinkAction.
//
//  Abhängigkeiten: SwiftUI, WebKit, MailLinkAction.
//

import SwiftUI
import WebKit

#if os(macOS)
/// HTML-Inhalt einer Mail (macOS).
struct HTMLMailView: NSViewRepresentable {
    /// HTML-Body der Mail.
    let html: String
    /// Gemessene Höhe des Inhalts.
    @Binding var contentHeight: CGFloat
    /// Getippter mailto:-Link – öffnet eine neue Mail in Mailwerk.
    var onMailto: ((MailtoLink) -> Void)? = nil

    /// Legt den Coordinator (Navigation, Höhenmessung) an.
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Legt die Web-Ansicht einmalig an.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Konfigurierte Web-Ansicht.
    func makeNSView(context: Context) -> WKWebView {
        let webView = Self.createWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    /// Übernimmt Änderungen; lädt nur bei geändertem HTML neu.
    ///
    /// - Parameters:
    ///   - webView: Angezeigte Web-Ansicht.
    ///   - context: Kontext mit dem Coordinator.
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.loadIfChanged(html, in: webView)
    }
}
#else
/// HTML-Inhalt einer Mail (iOS).
struct HTMLMailView: UIViewRepresentable {
    /// HTML-Body der Mail.
    let html: String
    /// Gemessene Höhe des Inhalts.
    @Binding var contentHeight: CGFloat
    /// Getippter mailto:-Link – öffnet eine neue Mail in Mailwerk.
    var onMailto: ((MailtoLink) -> Void)? = nil

    /// Legt den Coordinator (Navigation, Höhenmessung) an.
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Legt die Web-Ansicht einmalig an.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Konfigurierte Web-Ansicht.
    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.createWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    /// Übernimmt Änderungen; lädt nur bei geändertem HTML neu.
    ///
    /// - Parameters:
    ///   - webView: Angezeigte Web-Ansicht.
    ///   - context: Kontext mit dem Coordinator.
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.loadIfChanged(html, in: webView)
    }
}
#endif

extension HTMLMailView {
    /// Erzeugt eine sicher konfigurierte Web-Ansicht.
    ///
    /// Verarbeitung: JavaScript aus der Mail ist aus, der Hintergrund
    /// transparent (Hell-/Dunkelmodus); auf iOS scrollt die umgebende
    /// Ansicht, nicht die Web-Ansicht.
    ///
    /// - Returns: Neue Web-Ansicht.
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

    /// Lädt das HTML, eingebettet in ein Grundgerüst mit Schrift, Farben
    /// und Breitenbegrenzung.
    ///
    /// - Parameters:
    ///   - html: HTML-Body der Mail.
    ///   - webView: Ziel-Ansicht.
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

    /// Steuert Navigation und Höhenmessung der Web-Ansicht.
    class Coordinator: NSObject, WKNavigationDelegate {
        /// Aktuelle Fassung der Ansicht (für Binding und Rückrufe).
        var parent: HTMLMailView
        /// Zuletzt geladenes HTML; `nil` = noch nichts geladen.
        private var loadedHTML: String?

        /// Legt den Coordinator an.
        ///
        /// - Parameter parent: Zugehörige Ansicht.
        init(_ parent: HTMLMailView) {
            self.parent = parent
        }

        /// Lädt das HTML nur, wenn es sich vom zuletzt geladenen
        /// unterscheidet. In Debug-Builds wird jedes tatsächliche Laden
        /// ausgegeben (`⏱ HTML geladen …`).
        ///
        /// - Parameters:
        ///   - html: Anzuzeigendes HTML.
        ///   - webView: Ziel-Ansicht.
        func loadIfChanged(_ html: String, in webView: WKWebView) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            #if DEBUG
            print("⏱ HTML geladen: \(html.utf8.count / 1024) KB")
            #endif
            HTMLMailView.loadHTML(html, in: webView)
        }

        /// Entscheidet über eine Navigation.
        ///
        /// Verarbeitung: Die Mail selbst navigiert nie weg. Erlaubt ist nur
        /// das Laden des eigenen Inhalts (about:blank aus loadHTMLString);
        /// getippte Links gehen gezielt nach außen oder in eine neue Mail.
        ///
        /// - Parameters:
        ///   - webView: Betroffene Ansicht.
        ///   - navigationAction: Angeforderte Navigation.
        /// - Returns: `.allow` nur für den eigenen Inhalt, sonst `.cancel`.
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

        /// Inhalt geladen → Höhe messen, kurz darauf ein zweites Mal.
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

        /// Verkleinert bei Bedarf und meldet die Höhe an die Ansicht.
        ///
        /// - Parameter webView: Zu messende Ansicht.
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

