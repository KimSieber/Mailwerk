//
//  MacListSelection.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 31.10.2026
//  Geändert: 31.10.2026
//
//  Zweck: Regeln der Mehrfachauswahl in der Mailliste des Mac – wie in
//  Apple Mail: Klick wählt eine Mail und öffnet sie, ⌘-Klick und ⇧-Klick
//  erweitern die Auswahl; bei mehreren ausgewählten Mails zeigt die
//  Mailansicht „n Mails ausgewählt“ statt einer Mail.
//
//  Die Liste meldet ihre Auswahl als Menge von Kennungen. Darin können
//  auch Zeilen stehen, die keine Mail der Liste sind (Treffer der
//  Serversuche); sie zählen nicht. Besteht eine Meldung nur aus solchen
//  Zeilen, bleibt alles, wie es ist – der Treffer öffnet sich über seinen
//  eigenen Knopf.
//
//  Abgrenzung: Anwenden auf Mailansicht und Liste → InboxView;
//  Sammelaktionen → InboxViewModel, MessageSelection.
//
//  Abhängigkeiten: keine (reine Logik).
//

import Foundation

/// Auswertung der Listenauswahl auf dem Mac.
nonisolated enum MacListSelection {

    /// Was die Mailansicht nach einer neuen Auswahl zeigt.
    enum Outcome: Equatable {
        /// Nichts ausgewählt: Mailansicht schließen.
        case empty
        /// Genau eine Mail: sie öffnen.
        case open(String)
        /// Mehrere Mails: „n Mails ausgewählt“.
        case multiple(Set<String>)
        /// Nur Zeilen ohne Mail (Serversuche): nichts ändern.
        case ignore
    }

    /// Wertet eine von der Liste gemeldete Auswahl aus.
    ///
    /// Verarbeitung: Nur Kennungen von Mails der Liste zählen; je nach
    /// Anzahl wird geschlossen, geöffnet oder die Mehrfachauswahl gezeigt.
    ///
    /// - Parameters:
    ///   - selection: Gemeldete Kennungen.
    ///   - visibleIDs: Kennungen der Mails in der Liste.
    /// - Returns: Anzuwendendes Ergebnis.
    static func outcome(for selection: Set<String>, visibleIDs: [String]) -> Outcome {
        let mails = pruned(selection, visibleIDs: visibleIDs)
        guard let first = mails.first else {
            return selection.isEmpty ? .empty : .ignore
        }
        return mails.count == 1 ? .open(first) : .multiple(mails)
    }

    /// Auswahl ohne Mails, die nicht (mehr) in der Liste stehen – z. B.
    /// nach Löschen, Verschieben oder einem neuen Abruf.
    ///
    /// - Parameters:
    ///   - selection: Bisherige Auswahl.
    ///   - visibleIDs: Kennungen der Mails in der Liste.
    /// - Returns: Verbleibende Auswahl.
    static func pruned(_ selection: Set<String>, visibleIDs: [String]) -> Set<String> {
        selection.intersection(visibleIDs)
    }
}
