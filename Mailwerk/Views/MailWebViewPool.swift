//
//  MailWebViewPool.swift
//  Mailwerk
//
//  Zweck: Hält fertig eingerichtete Web-Ansichten für die Anzeige von
//  Mails bereit (v0.2.3d, Prüfbericht P-12). Bisher entstand für jede
//  geöffnete Mail eine neue WKWebView; die erste einer Sitzung startete
//  zusätzlich den WebKit-Prozess. Beim schnellen Durchsehen vieler Mails
//  kostete das bei jedem Öffnen spürbar Zeit.
//
//  Ablauf:
//  - `prewarm`: kurz nach dem Start eine Ansicht erzeugen und ein leeres
//    Dokument laden – der WebKit-Prozess läuft dann schon.
//  - `take`: HTMLMailView entnimmt beim Öffnen eine Ansicht; ist keine
//    vorrätig, entsteht wie bisher eine neue.
//  - `recycle`: beim Schließen zurücksetzen und zurücklegen (höchstens
//    `capacity` Stück; weitere werden verworfen).
//
//  Zurücksetzen: Laden abbrechen, Verbindung zur alten Mail lösen
//  (Navigation-Delegate), Zoom auf 100 %, aus der Ansichtshierarchie
//  lösen und ein leeres Dokument laden – beim nächsten Öffnen blitzt kein
//  alter Inhalt auf.
//
//  Sicherheit: Unverändert. Jede Ansicht stammt aus derselben Fabrik
//  (`HTMLMailView.createWebView`: JavaScript aus der Mail aus); die
//  Sperre externer Inhalte steckt in jedem geladenen Dokument
//  (RemoteContentPolicy), die Navigationssperre im Coordinator, der beim
//  Entnehmen neu gesetzt wird.
//
//  Abhängigkeiten: WebKit, HTMLMailView (Fabrik), Log.
//

import WebKit
import os

/// Vorrat an Web-Ansichten für die Mailanzeige.
@MainActor
final class MailWebViewPool {

    /// Gemeinsamer Vorrat der App.
    static let shared = MailWebViewPool(capacity: 2, factory: HTMLMailView.createWebView)

    /// Höchstzahl vorrätiger Ansichten.
    let capacity: Int
    /// Erzeugt eine neue, sicher eingerichtete Ansicht.
    private let factory: () -> WKWebView
    /// Vorrätige Ansichten (lesbar nur für die Tests).
    private(set) var available: [WKWebView] = []

    /// Legt den Vorrat an.
    ///
    /// - Parameters:
    ///   - capacity: Höchstzahl vorrätiger Ansichten.
    ///   - factory: Erzeugt eine neue Ansicht.
    init(capacity: Int, factory: @escaping () -> WKWebView) {
        self.capacity = capacity
        self.factory = factory
    }

    /// Wärmt den Vorrat vor: eine Ansicht mit leerem Dokument, damit der
    /// WebKit-Prozess schon läuft. Ist bereits eine vorrätig, passiert nichts.
    func prewarm() {
        guard available.isEmpty else { return }
        let webView = factory()
        webView.loadHTMLString("", baseURL: nil)
        available.append(webView)
        Log.view.info("🌐 Web-Ansicht vorgewärmt")
    }

    /// Entnimmt eine Ansicht; ist keine vorrätig, entsteht eine neue.
    ///
    /// - Returns: Einsatzbereite Ansicht (ohne Navigation-Delegate).
    func take() -> WKWebView {
        available.popLast() ?? factory()
    }

    /// Setzt eine Ansicht zurück und legt sie zurück, sofern Platz ist.
    ///
    /// - Parameter webView: Nicht mehr angezeigte Ansicht.
    func recycle(_ webView: WKWebView) {
        Self.reset(webView)
        guard available.count < capacity, !available.contains(where: { $0 === webView }) else { return }
        available.append(webView)
    }

    /// Setzt eine Ansicht auf den Grundzustand zurück.
    ///
    /// - Parameter webView: Zurückzusetzende Ansicht.
    private static func reset(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        #if os(macOS)
        webView.magnification = 1
        #else
        webView.scrollView.setZoomScale(1, animated: false)
        #endif
        webView.removeFromSuperview()
        webView.loadHTMLString("", baseURL: nil)
    }
}
