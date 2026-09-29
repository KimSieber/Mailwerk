//
//  MailPrinter.swift
//  Mailwerk
//
//  Druckt eine HTML-Mail über einen temporären WKWebView. Der WebView
//  rendert den Inhalt vollständig (Tabellen, CSS, Bilder) und übergibt
//  dann seinen Print-Formatter an das System.
//
//  UIMarkupTextPrintFormatter kann nur einfaches HTML; komplexe Mails
//  (verschachtelte Tabellen, CSS-Layout) blieben dort leer.
//
//  Die Instanz hält sich selbst über `retainSelf`, bis der Druck
//  abgeschlossen ist, damit der WebView nicht zu früh freigegeben wird.
//

import WebKit

#if os(iOS)
final class MailPrinter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var retainSelf: MailPrinter?

    func print(html: String) {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842))
        webView.navigationDelegate = self
        self.webView = webView
        self.retainSelf = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let formatter = webView.viewPrintFormatter()
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        controller.printInfo = info
        controller.printFormatter = formatter
        controller.present(animated: true) { [weak self] _, _, _ in
            self?.cleanup()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
    }

    private func cleanup() {
        webView = nil
        retainSelf = nil
    }
}
#else
final class MailPrinter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var retainSelf: MailPrinter?

    func print(html: String) {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        webView.navigationDelegate = self
        self.webView = webView
        self.retainSelf = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let printOp = webView.printOperation(with: .shared)
        if let window = NSApp.keyWindow {
            printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
        cleanup()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
    }

    private func cleanup() {
        webView = nil
        retainSelf = nil
    }
}
#endif
