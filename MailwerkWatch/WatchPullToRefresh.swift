//
//  WatchPullToRefresh.swift
//  MailwerkWatch
//  Autor: Kim Sieber
//  Erstellt: 30.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Aktualisieren durch Herunterziehen auf der Watch. SwiftUI bietet
//  `.refreshable` laut Dokumentation auch unter watchOS an, führt die
//  Aktion auf der Uhr aber nicht aus. Dieser Modifier erkennt das Ziehen
//  selbst: Wird die Liste weiter als `triggerDistance` über ihren Anfang
//  hinausgezogen, gibt die Uhr ein kurzes Haptik-Signal und
//  startet die Aktion – einmal je Zug; erst wenn die Liste wieder an ihrem
//  Anfang anliegt, ist der nächste Zug möglich.
//
//  Ausgelöst wird allein über die Zugstrecke. Finger und Krone lassen sich
//  auf der Uhr nicht unterscheiden (gemessen am 30.10.2026): Die
//  Scroll-Phase bleibt auch beim Ziehen „idle“, und eine zusätzliche
//  Fingergeste (`simultaneousGesture`) blockiert das Scrollen.
//
//  Abgrenzung: Was aktualisiert wird → Aufrufer (WatchConnector.refresh);
//  Anzeige „Aktualisiere …“ → WatchMailListView, WatchRootView.
//
//  Abhängigkeiten: SwiftUI (onScrollGeometryChange, sensoryFeedback;
//  watchOS 11+).
//

import SwiftUI

/// Entscheidet, wann ein Zug die Aktualisierung auslöst (ohne Oberfläche).
struct WatchPullTrigger {
    /// Zugstrecke über den Listenanfang hinaus, ab der aktualisiert wird (pt).
    static let triggerDistance: CGFloat = 44
    /// Höchstens so weit gezogen gilt die Liste als „liegt am Anfang an“ (pt).
    static let restDistance: CGFloat = 2

    /// Lage der Liste relativ zu ihrem Anfang.
    enum Zone: Equatable {
        /// Liegt am Anfang an oder ist nach unten gescrollt.
        case rest
        /// Über den Anfang hinausgezogen, Grenze noch nicht erreicht.
        case pulling
        /// Über die Grenze hinausgezogen.
        case beyond
    }

    /// `true` = dieser Zug hat bereits ausgelöst.
    private(set) var hasFired = false

    /// Ordnet die Zugstrecke einer Zone zu.
    ///
    /// - Parameter overscroll: Strecke über den Anfang hinaus (pt); negativ
    ///   oder 0, wenn nicht gezogen wird.
    /// - Returns: Zone.
    static func zone(overscroll: CGFloat) -> Zone {
        if overscroll <= restDistance { return .rest }
        return overscroll >= triggerDistance ? .beyond : .pulling
    }

    /// Strecke über den Listenanfang hinaus aus den Scroll-Angaben.
    ///
    /// - Parameters:
    ///   - contentOffsetY: Senkrechter Versatz des Inhalts (pt).
    ///   - topInset: Oberer Einzug, z. B. für den Titel (pt).
    /// - Returns: Positive Strecke beim Ziehen über den Anfang hinaus.
    static func overscroll(contentOffsetY: CGFloat, topInset: CGFloat) -> CGFloat {
        -(contentOffsetY + topInset)
    }

    /// Prüft bei jedem Zonenwechsel, ob jetzt ausgelöst wird.
    ///
    /// Verarbeitung: Am Anfang wird der Zug zurückgesetzt; ausgelöst wird nur
    /// jenseits der Grenze und nur einmal je Zug.
    ///
    /// - Parameter zone: Neue Zone.
    /// - Returns: `true` = Aktualisierung starten.
    mutating func shouldFire(zone: Zone) -> Bool {
        if zone == .rest {
            hasFired = false
            return false
        }
        guard zone == .beyond, !hasFired else { return false }
        hasFired = true
        return true
    }
}

/// Modifier für eine scrollbare Ansicht (List, ScrollView).
private struct WatchPullToRefreshModifier: ViewModifier {
    /// Auszuführende Aktualisierung.
    let action: () async -> Void

    /// Auslöse-Logik.
    @State private var trigger = WatchPullTrigger()
    /// Zählt Auslösungen; jede Änderung gibt ein Haptik-Signal.
    @State private var fireCount = 0

    /// Inhalt mit Beobachtung des Versatzes.
    ///
    /// - Parameter content: Scrollbare Ansicht.
    /// - Returns: Ansicht mit Herunterziehen.
    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always)
            .onScrollGeometryChange(for: WatchPullTrigger.Zone.self) { geometry in
                WatchPullTrigger.zone(overscroll: WatchPullTrigger.overscroll(
                    contentOffsetY: geometry.contentOffset.y,
                    topInset: geometry.contentInsets.top
                ))
            } action: { _, zone in
                guard trigger.shouldFire(zone: zone) else { return }
                fireCount += 1
                Task { await action() }
            }
            .sensoryFeedback(.impact, trigger: fireCount)
    }
}

extension View {
    /// Aktualisieren durch Herunterziehen (Ersatz für `.refreshable` auf der Watch).
    ///
    /// - Parameter action: Aktualisierung, z. B. `WatchConnector.shared.refresh()`.
    /// - Returns: Ansicht mit Herunterziehen.
    func watchPullToRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(WatchPullToRefreshModifier(action: action))
    }
}
