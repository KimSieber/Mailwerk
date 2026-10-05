//
//  MailPrinter.swift
//  Mailwerk
//
//  Zweck: Druckt eine HTML-Mail über einen temporären WKWebView.
//
//  UIMarkupTextPrintFormatter kann nur einfaches HTML; komplexe Mails
//  (verschachtelte Tabellen, CSS-Layout) blieben dort leer. Deshalb
//  rendert ein WKWebView den Inhalt vollständig und übergibt seinen
//  Print-Formatter an das System.
//
//  Sicherheit: JavaScript aus der Mail ist blockiert
//  (`allowsContentJavaScript = false`). Bilder und Stylesheets werden
//  weiterhin geladen, damit der Ausdruck vollständig ist.
//
//  Die Instanz hält sich selbst über `retainSelf`, bis der Druck
//  abgeschlossen ist, damit der WebView nicht zu früh freigegeben wird.
//
//  Abgrenzung: Anzeige einer Mail → HTMLMailView; Teilen → MailShareSheet.
//
//  Abhängigkeiten: WebKit.
//

import WebKit

#if os(iOS)
/// Druckt eine HTML-Mail auf iOS.
final class MailPrinter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var retainSelf: MailPrinter?

    /// Rendert den HTML-Inhalt und öffnet den Druckdialog.
    ///
    /// Verarbeitung: Legt einen temporären WKWebView mit sicherer
    /// Konfiguration an (kein JavaScript aus der Mail), lädt das HTML
    /// und wartet auf `didFinish`. Danach wird der Print-Formatter an
    /// den System-Druckdialog übergeben. Die Instanz hält sich selbst,
    /// bis der Druck abgeschlossen ist.
    ///
    /// - Parameter html: Vollständiger HTML-Body der Mail.
    func print(html: String) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842),
                                configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        self.retainSelf = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Navigation abgeschlossen → Druckdialog öffnen.
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

    /// Navigation fehlgeschlagen → aufräumen.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
    }

    private func cleanup() {
        webView = nil
        retainSelf = nil
    }
}
#else
/// Druckt eine HTML-Mail auf macOS.
final class MailPrinter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var retainSelf: MailPrinter?

    /// Rendert den HTML-Inhalt und öffnet den Druckdialog.
    ///
    /// Verarbeitung: Wie auf iOS, aber mit `printOperation` statt
    /// `UIPrintInteractionController`. Der Dialog wird modal im
    /// aktuellen Fenster geöffnet.
    ///
    /// - Parameter html: Vollständiger HTML-Body der Mail.
    func print(html: String) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842),
                                configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        self.retainSelf = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Navigation abgeschlossen → Druckdialog öffnen.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let printOp = webView.printOperation(with: .shared)
        if let window = NSApp.keyWindow {
            printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
        cleanup()
    }

    /// Navigation fehlgeschlagen → aufräumen.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
    }

    private func cleanup() {
        webView = nil
        retainSelf = nil
    }
}
#endif
