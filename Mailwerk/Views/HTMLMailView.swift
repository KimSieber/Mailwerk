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
        webView.isOpaque = false
        webView.backgroundColor = .clear
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
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
                }
                img { max-width: 100%; height: auto; }
                a { color: #007AFF; }
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

