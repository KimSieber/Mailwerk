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
//  Gemessen wird die Höhe des `body`. Damit die Randabstände des ersten
//  und letzten Absatzes darin enthalten sind, bildet der `body` einen
//  eigenen Block (`display: flow-root`). Ohne das ragen diese Abstände
//  über den `body` hinaus („margin collapsing“), die Messung fällt um
//  sie zu klein aus, und das Ende der Mail wird abgeschnitten – bei
//  schlichten Mails aus Absätzen um 20–30 Punkte.
//
//  Der Inhalt wird nur neu geladen, wenn sich das HTML oder die Freigabe
//  externer Inhalte tatsächlich geändert hat. SwiftUI ruft `update…View`
//  bei jeder Änderung der Umgebung auf – auch, wenn diese Ansicht selbst
//  ihre Höhe meldet.
//  Ohne die Prüfung würde die Mail dabei jedes Mal neu geladen und
//  neu vermessen.
//
//  Sicherheit: JavaScript aus der Mail ist abgeschaltet; die Mail kann
//  nicht wegnavigieren. Links öffnen extern bzw. als neue Mail. Extern
//  geöffnet wird über `openURL` aus der SwiftUI-Umgebung – das gibt es
//  auch in der Teilen-Erweiterung, `UIApplication.shared` dagegen nicht.
//  Externe Inhalte (Bilder, Stylesheets, Schriften von fremden Servern)
//  sperrt eine Content-Security-Policy im Kopf des Grundgerüsts, solange
//  `allowsRemoteContent` nicht gesetzt ist (RemoteContentPolicy). Die
//  Sperre der Navigation allein reicht dafür nicht: Bilder und Stylesheets
//  sind keine Navigation und laufen nicht durch den Navigation-Delegate.
//  Ändert sich die Freigabe, wird der Inhalt mit der anderen Regel neu
//  geladen.
//
//  Die App misst die Höhe per `evaluateJavaScript`. Dieses Skript gehört
//  der App, nicht der Mail; weder `allowsContentJavaScript = false` noch
//  die CSP der Seite gelten dafür.
//
//  Dunkelmodus: Mails ohne eigene Farben übernehmen den Hintergrund der
//  App und bekommen helle Schrift. Mails mit eigenen Farben
//  (MailAppearance) bleiben hell – weißer Grund mit schmalem Innenrand,
//  dunkle Standardschrift –, wie in Apple Mail.
//
//  Zoomen: Jede Mail lässt sich per Geste vergrößern, auch wenn ihr eigener
//  Viewport das verbietet (iOS `ignoresViewportScaleLimits`, macOS
//  `allowsMagnification`). Das Grundgerüst selbst begrenzt den Zoom nicht.
//  Der Zoom gilt nur für die geöffnete Mail.
//
//  Scrollen auf dem Mac: Die Web-Ansicht ist so hoch wie
//  ihr Inhalt; gescrollt wird der äußere ScrollView der Mailansicht. Eine
//  gewöhnliche WKWebView nimmt Mausrad- und Trackpad-Ereignisse aber
//  selbst an, sodass sich HTML-Mails nur am Rand scrollen ließen. Die
//  Unterklasse `MailWebView` reicht diese Ereignisse deshalb an den
//  nächsten Responder (den äußeren ScrollView) weiter – außer bei
//  vergrößerter Mail, wo die Web-Ansicht zum Verschieben selbst scrollt.
//  Vergrößern, Textauswahl, Links und Kontextmenü bleiben unberührt.
//
//  Wiederverwendung (v0.2.3d, P-12): Die Web-Ansicht kommt aus einem
//  Vorrat (MailWebViewPool) und geht beim Schließen zurückgesetzt dorthin
//  zurück – das Öffnen der nächsten Mail spart Erzeugen und Prozessstart.
//  Ob die Mail eigene Farben hat, kann die Mailansicht vorberechnet
//  übergeben (`usesOwnColors`, MessageDisplayHints); sonst wird es hier
//  ermittelt.
//
//  Abgrenzung: Aufbau der Mailansicht und Freigabe → MessageDetailView;
//  Zitat in der Antwort → ComposeView (immer gesperrt); Einordnung von
//  Links → MailLinkAction; Regeln für externe Inhalte → RemoteContentPolicy;
//  helle Darstellung → MailAppearance.
//
//  Abhängigkeiten: SwiftUI, WebKit, MailLinkAction, RemoteContentPolicy,
//  MailAppearance, MailWebViewPool, Log.
//

import SwiftUI
import WebKit
import os
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// HTML-Inhalt einer Mail (macOS).
struct HTMLMailView: NSViewRepresentable {
    /// HTML-Body der Mail.
    let html: String
    /// Gemessene Höhe des Inhalts.
    @Binding var contentHeight: CGFloat
    /// `true`, wenn externe Inhalte für diese Anzeige freigegeben sind.
    var allowsRemoteContent: Bool = false
    /// Getippter mailto:-Link – öffnet eine neue Mail in Mailwerk.
    var onMailto: ((MailtoLink) -> Void)? = nil
    /// Vorberechnet: `true`, wenn die Mail eigene Farben hat; `nil` =
    /// beim Laden ermitteln (MailAppearance).
    var usesOwnColors: Bool? = nil
    /// Wird einmal je geladenem Inhalt aufgerufen, sobald er fertig geladen
    /// ist (Messpunkt „Mail sichtbar“, MessageOpenTimer).
    var onLoaded: (() -> Void)? = nil

    /// Legt den Coordinator (Navigation, Höhenmessung) an.
    ///
    /// - Returns: Coordinator mit Verweis auf diese Ansicht.
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Legt die Web-Ansicht einmalig an – aus dem Vorrat, sonst neu.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Konfigurierte Web-Ansicht.
    func makeNSView(context: Context) -> WKWebView {
        let webView = MailWebViewPool.shared.take()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    /// Gibt die Web-Ansicht beim Schließen zurückgesetzt in den Vorrat.
    ///
    /// - Parameters:
    ///   - webView: Nicht mehr angezeigte Web-Ansicht.
    ///   - coordinator: Zugehöriger Coordinator.
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        MailWebViewPool.shared.recycle(webView)
    }

    /// Übernimmt Änderungen; lädt nur bei geändertem HTML oder geänderter
    /// Freigabe neu.
    ///
    /// - Parameters:
    ///   - webView: Angezeigte Web-Ansicht.
    ///   - context: Kontext mit dem Coordinator.
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.openURL = context.environment.openURL
        context.coordinator.loadIfChanged(
            LoadedContent(html: html, allowsRemoteContent: allowsRemoteContent, usesOwnColors: usesOwnColors),
            in: webView
        )
    }
}
#else
/// HTML-Inhalt einer Mail (iOS).
struct HTMLMailView: UIViewRepresentable {
    /// HTML-Body der Mail.
    let html: String
    /// Gemessene Höhe des Inhalts.
    @Binding var contentHeight: CGFloat
    /// `true`, wenn externe Inhalte für diese Anzeige freigegeben sind.
    var allowsRemoteContent: Bool = false
    /// Getippter mailto:-Link – öffnet eine neue Mail in Mailwerk.
    var onMailto: ((MailtoLink) -> Void)? = nil
    /// Vorberechnet: `true`, wenn die Mail eigene Farben hat; `nil` =
    /// beim Laden ermitteln (MailAppearance).
    var usesOwnColors: Bool? = nil
    /// Wird einmal je geladenem Inhalt aufgerufen, sobald er fertig geladen
    /// ist (Messpunkt „Mail sichtbar“, MessageOpenTimer).
    var onLoaded: (() -> Void)? = nil

    /// Legt den Coordinator (Navigation, Höhenmessung) an.
    ///
    /// - Returns: Coordinator mit Verweis auf diese Ansicht.
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Legt die Web-Ansicht einmalig an – aus dem Vorrat, sonst neu.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Konfigurierte Web-Ansicht.
    func makeUIView(context: Context) -> WKWebView {
        let webView = MailWebViewPool.shared.take()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    /// Gibt die Web-Ansicht beim Schließen zurückgesetzt in den Vorrat.
    ///
    /// - Parameters:
    ///   - webView: Nicht mehr angezeigte Web-Ansicht.
    ///   - coordinator: Zugehöriger Coordinator.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        MailWebViewPool.shared.recycle(webView)
    }

    /// Übernimmt Änderungen; lädt nur bei geändertem HTML oder geänderter
    /// Freigabe neu.
    ///
    /// - Parameters:
    ///   - webView: Angezeigte Web-Ansicht.
    ///   - context: Kontext mit dem Coordinator.
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.openURL = context.environment.openURL
        context.coordinator.loadIfChanged(
            LoadedContent(html: html, allowsRemoteContent: allowsRemoteContent, usesOwnColors: usesOwnColors),
            in: webView
        )
    }
}
#endif

extension HTMLMailView {
    /// Erzeugt eine sicher konfigurierte Web-Ansicht.
    ///
    /// Verarbeitung: JavaScript aus der Mail ist aus, der Hintergrund
    /// transparent (Hell-/Dunkelmodus); auf iOS scrollt die umgebende
    /// Ansicht, nicht die Web-Ansicht. Zoomen per Geste ist immer möglich,
    /// auch wenn die Mail es in ihrem Viewport verbietet.
    ///
    /// - Returns: Neue Web-Ansicht.
    static func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        // Skripte aus der Mail nie ausführen (wie Apple Mail). Die App
        // selbst misst die Höhe weiter per evaluateJavaScript – das ist
        // davon nicht betroffen.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        #if os(iOS)
        // Zoomen per Geste auch bei Mails, deren Viewport es verbietet
        // (user-scalable=no, maximum-scale=1).
        config.ignoresViewportScaleLimits = true
        #endif
        #if os(macOS)
        // Mausrad/Trackpad an den äußeren ScrollView weiterreichen.
        let webView: WKWebView = MailWebView(frame: .zero, configuration: config)
        #else
        let webView = WKWebView(frame: .zero, configuration: config)
        #endif
        // Transparenter Hintergrund, damit die Mail im Hell- und Dunkelmodus
        // den Hintergrund der App übernimmt. Die beiden Plattformen bieten
        // dafür unterschiedliche Wege an.
        #if os(macOS)
        // Auf macOS ist `isOpaque` nur lesbar und `backgroundColor` fehlt.
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        // Scrollen übernimmt der äußere ScrollView; Tippen (Links) und
        // Textauswahl bleiben in der Mail möglich.
        webView.scrollView.isScrollEnabled = false
        #endif
        return webView
    }

    /// Inhalt einer Anzeige: HTML der Mail und Freigabe externer Inhalte.
    /// Neu geladen wird, sobald sich einer der beiden Werte ändert.
    struct LoadedContent: Equatable {
        /// HTML-Body der Mail.
        let html: String
        /// `true`, wenn externe Inhalte freigegeben sind.
        let allowsRemoteContent: Bool
        /// Vorberechnet: eigene Farben; `nil` = beim Laden ermitteln.
        var usesOwnColors: Bool? = nil
    }

    /// Baut das vollständige Dokument: Grundgerüst mit Sicherheitsregeln,
    /// Schrift, Farben und Breitenbegrenzung, darin das HTML der Mail.
    ///
    /// Verarbeitung: Die Meta-Zeilen aus `RemoteContentPolicy` stehen im
    /// Kopf vor dem Inhalt der Mail, damit sie für alles darin gelten. Die
    /// Farbregeln hängen davon ab, ob die Mail eigene Farben mitbringt
    /// (`colorStyle(usesOwnColors:)`); solche Mails melden sich zusätzlich
    /// als hell (`color-scheme`), damit auch Bedienelemente darin hell
    /// bleiben. Der Viewport begrenzt den Zoom nicht.
    ///
    /// - Parameters:
    ///   - html: HTML-Body der Mail.
    ///   - allowsRemoteContent: `true`, wenn externe Inhalte geladen
    ///     werden dürfen.
    ///   - usesOwnColors: Vorberechnet: eigene Farben; `nil` = hier per
    ///     MailAppearance ermitteln.
    /// - Returns: HTML-Dokument zum Laden in die Web-Ansicht.
    static func document(for html: String, allowsRemoteContent: Bool, usesOwnColors precomputed: Bool? = nil) -> String {
        let usesOwnColors = precomputed ?? MailAppearance.usesOwnColors(html)
        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            \(RemoteContentPolicy.headTags(allowsRemoteContent: allowsRemoteContent))
            <meta name="viewport" content="width=device-width, initial-scale=1">
            \(usesOwnColors ? #"<meta name="color-scheme" content="light">"# : "")
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
                    /* Eigener Block: Randabstände des ersten und letzten
                       Absatzes bleiben im body und zählen zur gemessenen
                       Höhe. !important, weil Mails body-Stile mitbringen. */
                    display: flow-root !important;
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
            \(colorStyle(usesOwnColors: usesOwnColors))
            </style>
            </head>
            <body>\(html)</body>
            </html>
            """
    }

    /// Farbregeln für den Dunkelmodus.
    ///
    /// Verarbeitung: Ohne eigene Farben wird die Schrift im Dunkelmodus
    /// hell, der Hintergrund bleibt der der App. Mit eigenen Farben bleibt
    /// die Mail hell: weißer Grund für die ganze Fläche und ein schmaler
    /// Innenrand, damit der Text im dunklen Umfeld nicht am Rand der
    /// weißen Fläche klebt. Im Hellmodus ändert sich in beiden Fällen
    /// nichts.
    ///
    /// - Parameter usesOwnColors: `true`, wenn die Mail eigene Farben
    ///   mitbringt.
    /// - Returns: CSS-Regeln zum Einfügen in den `<style>`-Block.
    static func colorStyle(usesOwnColors: Bool) -> String {
        if usesOwnColors {
            return """
                @media (prefers-color-scheme: dark) {
                    html { background-color: #FFFFFF; }
                    body { padding: 8px !important; }
                }
                """
        }
        return """
            @media (prefers-color-scheme: dark) {
                body { color: #F0F0F0; }
                a { color: #0A84FF; }
            }
            """
    }

    /// Lädt den Inhalt als vollständiges Dokument in die Web-Ansicht.
    ///
    /// - Parameters:
    ///   - content: HTML der Mail und Freigabe externer Inhalte.
    ///   - webView: Ziel-Ansicht.
    /// - Returns: Die gestartete Navigation (zum Erkennen ihres Endes).
    @discardableResult
    static func load(_ content: LoadedContent, in webView: WKWebView) -> WKNavigation? {
        let page = document(
            for: content.html,
            allowsRemoteContent: content.allowsRemoteContent,
            usesOwnColors: content.usesOwnColors
        )
        return webView.loadHTMLString(page, baseURL: nil)
    }

    /// Steuert Navigation und Höhenmessung der Web-Ansicht.
    class Coordinator: NSObject, WKNavigationDelegate {
        /// Aktuelle Fassung der Ansicht (für Binding und Rückrufe).
        var parent: HTMLMailView
        /// Öffnet Links außerhalb der App (aus der SwiftUI-Umgebung);
        /// `nil`, bis die Ansicht das erste Mal aktualisiert wurde.
        var openURL: OpenURLAction?
        /// Zuletzt geladener Inhalt; `nil` = noch nichts geladen.
        private var loaded: LoadedContent?
        /// Navigation des zuletzt geladenen Inhalts, bis sie fertig ist.
        /// Unterscheidet ihn von einem leeren Dokument, das eine Ansicht aus
        /// dem Vorrat (MailWebViewPool) eventuell noch lädt.
        private var contentNavigation: WKNavigation?

        /// Legt den Coordinator an.
        ///
        /// - Parameter parent: Zugehörige Ansicht.
        init(_ parent: HTMLMailView) {
            self.parent = parent
        }

        /// Lädt den Inhalt nur, wenn er sich vom zuletzt geladenen
        /// unterscheidet (HTML oder Freigabe). In Debug-Builds wird jedes
        /// tatsächliche Laden ausgegeben (`⏱ HTML geladen …`).
        ///
        /// - Parameters:
        ///   - content: Anzuzeigender Inhalt.
        ///   - webView: Ziel-Ansicht.
        func loadIfChanged(_ content: LoadedContent, in webView: WKWebView) {
            guard content != loaded else { return }
            loaded = content
            #if DEBUG
            Log.view.debug("⏱ HTML geladen: \(content.html.utf8.count / 1024) KB, extern: \(content.allowsRemoteContent, privacy: .public)")
            #endif
            contentNavigation = HTMLMailView.load(content, in: webView)
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
                    openURL?(target)
                case .compose(let link):
                    parent.onMailto?(link)
                case .ignore:
                    Log.view.info("🔗 Link ignoriert: \(url.scheme ?? "?", privacy: .public)")
                }
                return .cancel
            }

            // Eigener Inhalt: erlaubt. Alles andere (Weiterleitungen,
            // Formulare, iframes, Meta-Refresh): blockiert.
            return url.scheme == "about" ? .allow : .cancel
        }

        /// Inhalt geladen → Höhe messen, kurz darauf ein zweites Mal. Beim
        /// Ende der Navigation des Mail-Inhalts einmal `onLoaded` melden.
        ///
        /// - Parameters:
        ///   - webView: Web-Ansicht der Mail.
        ///   - navigation: Abgeschlossene Navigation; nur die des
        ///     Mail-Inhalts löst `onLoaded` aus.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let navigation, navigation === contentNavigation {
                contentNavigation = nil
                parent.onLoaded?()
            }
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

#if os(macOS)
/// Web-Ansicht der Mailanzeige auf dem Mac: reicht Scroll-Ereignisse an den
/// äußeren ScrollView weiter (siehe Dateikopf).
final class MailWebView: WKWebView {
    /// Scroll-Ereignis von Mausrad bzw. Trackpad.
    ///
    /// Verarbeitung: Bei normaler Größe geht das Ereignis an den nächsten
    /// Responder – den ScrollView der Mailansicht. Ist die Mail per Geste
    /// vergrößert, scrollt die Web-Ansicht selbst, damit sich der
    /// vergrößerte Ausschnitt verschieben lässt.
    ///
    /// - Parameter event: Scroll-Ereignis.
    override func scrollWheel(with event: NSEvent) {
        if magnification > 1.01 {
            super.scrollWheel(with: event)
        } else if let next = nextResponder {
            next.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
#endif
