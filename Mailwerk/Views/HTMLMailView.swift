//
//  HTMLMailView.swift
//  Mailwerk
//

import SwiftUI
import WebKit

#if os(macOS)
struct HTMLMailView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = Self.createWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        Self.loadHTML(html, in: webView)
    }
}
#else
struct HTMLMailView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.createWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        Self.loadHTML(html, in: webView)
    }
}
#endif

extension HTMLMailView {
    static func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
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
        webView.scrollView.isScrollEnabled = false
        // Interaktion vollständig deaktivieren: Der äußere SwiftUI-
        // ScrollView übernimmt das Scrollen, und Links sind in einer
        // Mail-Vorschau nicht nötig. Ohne das fressen komplexe
        // HTML-Mails (Google u. a.) die Gesten, und das Aktionsmenü
        // lässt sich nicht mehr scrollen.
        webView.isUserInteractionEnabled = false
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(webView)
            // Zweite Messung nach kurzer Verzögerung: Einige Mails lösen
            // nach dem ersten Layout noch CSS-Transitionen oder Bildladen
            // aus, die die Höhe verändern.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.measureHeight(webView)
            }
        }

        private func measureHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self.parent.contentHeight = height
                    }
                }
            }
        }
    }
}

