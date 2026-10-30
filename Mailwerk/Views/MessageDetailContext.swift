//
//  MessageDetailContext.swift
//  Mailwerk
//
//  Zweck: Was jede Mailansicht aus der Liste mitbekommt – Postfächer,
//  Spamfilter, Score-Obergrenze, Rückmeldung nach Änderungen, Suche nach
//  einer Person und die Darstellung in Gesendet/Entwürfen. Gebündelt, weil
//  die Liste die Mail an fünf Stellen öffnet (iPhone, iPad, Mac,
//  Servertreffer, Übergabe von der Watch) und jede Stelle sonst dieselben
//  sechs Werte einzeln weiterreicht (Code-Review v0.3.1, Regel 2).
//
//  Dazu die gemeinsame Platzhalter-Gestaltung von Lade- und Hinweiszustand
//  (`detailPlaceholder`): ganze Fläche, auf dem Mac mit der Kopfleiste der
//  Mailansicht darüber.
//
//  Abhängigkeiten: SwiftUI, AccountStore, SpamFilterService, SearchPerson.
//

import SwiftUI

/// Gemeinsame Angaben für die Mailansicht.
struct MessageDetailContext {
    /// Quelle für Postfächer und Passwörter.
    let accountStore: AccountStore
    /// Spamfilter für Blockieren und Vertrauen.
    let spamFilter: SpamFilterService
    /// Score-Obergrenze für vertrauenswürdige Absender (externe Inhalte).
    let scoreLimit: Double
    /// Wird nach Änderungen an der Mail aufgerufen (Liste neu laden).
    let onChange: () -> Void
    /// Suche nach einer Person in der Liste („Suchen nach …“ im Mailkopf);
    /// `nil` = nicht angeboten.
    var onSearchPerson: ((SearchPerson) -> Void)? = nil
    /// `true` in Gesendet und Entwürfen (Kreis im Mailkopf zeigt den Empfänger).
    var showsRecipients = false
}

extension View {
    /// Gestaltung von Lade- und Hinweiszustand der Mailansicht: ganze
    /// Fläche; auf dem Mac steht die Kopfleiste der Mailansicht darüber,
    /// damit beim Mailwechsel nichts springt.
    ///
    /// - Parameter header: Kopfleiste (nur auf dem Mac verwendet).
    /// - Returns: Gestaltete Ansicht.
    func detailPlaceholder<Header: View>(@ViewBuilder header: () -> Header) -> some View {
        #if os(macOS)
        let bar = header()
        return frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { bar }
        #else
        return frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}
