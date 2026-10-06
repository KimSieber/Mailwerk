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
//  Auf dem Mac heißt das: bis der Druckdialog geschlossen ist.
//
//  Voraussetzung auf dem Mac: In der App-Sandbox muss „Printing“
//  freigegeben sein (Signing & Capabilities → App Sandbox → Hardware).
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
    ///
    /// Verarbeitung: Übergibt den Print-Formatter des WebViews an den
    /// System-Druckdialog und räumt nach dessen Schließen auf.
    ///
    /// - Parameters:
    ///   - webView: WebView mit dem geladenen Inhalt.
    ///   - navigation: Abgeschlossene Navigation (nicht verwendet).
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

    /// Navigation fehlgeschlagen → aufräumen, ohne zu drucken.
    ///
    /// - Parameters:
    ///   - webView: Betroffener WebView.
    ///   - navigation: Fehlgeschlagene Navigation.
    ///   - error: Fehler beim Laden.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
    }

    /// Gibt WebView und Selbstreferenz frei, damit die Instanz entfernt wird.
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
    ///
    /// Verarbeitung: Richtet die Seite ein (Breite an die Seite anpassen,
    /// Ränder), setzt die Größe der Druckansicht – ohne sie bricht macOS
    /// beim Seitenumbruch ab – und öffnet den Druckdialog als Sheet am
    /// aktiven Fenster. Aufgeräumt wird erst, wenn der Dialog geschlossen
    /// ist. Gibt es kein aktives Fenster, öffnet sich der Dialog als
    /// eigenes Fenster.
    ///
    /// - Parameters:
    ///   - webView: WebView mit dem geladenen Inhalt.
    ///   - navigation: Abgeschlossene Navigation (nicht verwendet).
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // Größe der Druckansicht setzen, sonst Abbruch in knowsPageRange.
        operation.view?.frame = webView.bounds

        if let window = NSApp.keyWindow {
            operation.runModal(
                for: window,
                delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        } else {
            operation.run()
            cleanup()
        }
    }

    /// Druckdialog geschlossen (gedruckt oder abgebrochen) → aufräumen.
    ///
    /// - Parameters:
    ///   - operation: Beendete Druckoperation.
    ///   - success: `true`, wenn gedruckt wurde.
    ///   - contextInfo: Nicht verwendet.
    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        cleanup()
    }

    /// Navigation fehlgeschlagen → aufräumen, ohne zu drucken.
    ///
    /// - Parameters:
    ///   - webView: Betroffener WebView.
    ///   - navigation: Fehlgeschlagene Navigation.
    ///   - error: Fehler beim Laden.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
    }

    /// Gibt WebView und Selbstreferenz frei, damit die Instanz entfernt wird.
    private func cleanup() {
        webView = nil
        retainSelf = nil
    }
}
#endif
