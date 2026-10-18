//
//  WatchMailSelection.swift
//  Mailwerk
//
//  Zweck: Welche Mails auf der Apple Watch liegen – die Begrenzung des
//  Speichers dort.
//
//  Regel (gilt für alle Postfächer mit eingeschaltetem Abruf gemeinsam):
//  - Posteingänge: die 50 neuesten Mails, dazu alle ungelesenen und alle
//    gekennzeichneten; zusammen höchstens 100. Sind es mehr, gewinnen die
//    neuesten.
//  - Spam-Ordner: zusätzlich die 20 neuesten, außerhalb der 100.
//
//  Grundlage ist der Cache des iPhones. Ungelesene oder gekennzeichnete
//  Mails, die älter sind als das Zeitfenster des iPhones, kennt die Watch
//  deshalb nicht.
//
//  Reine Logik, deshalb `nonisolated`; vollständig per Unit-Test abgedeckt.
//
//  Abgrenzung: Aufbau der Lieferung → WatchSnapshotBuilder.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Auswahl der Mails für die Watch.
nonisolated enum WatchMailSelection {

    /// Neueste Mails der Posteingänge, die immer dabei sind.
    static let newestCount = 50
    /// Höchstzahl der Mails aus den Posteingängen.
    static let inboxLimit = 100
    /// Höchstzahl der Mails aus den Spam-Ordnern.
    static let spamLimit = 20

    /// Was die Auswahl über eine Mail wissen muss.
    nonisolated struct Candidate: Equatable, Sendable {
        /// Cache-ID.
        let id: String
        /// Datum; `nil` = unbekannt (zählt als ältestes).
        let date: Date?
        /// `true` = ungelesen.
        let isUnread: Bool
        /// `true` = gekennzeichnet.
        let isFlagged: Bool
    }

    /// Auswahl aus den Posteingängen.
    ///
    /// Verarbeitung: Neueste zuerst; die ersten `newestCount` immer, danach
    /// nur ungelesene und gekennzeichnete; nach `inboxLimit` Mails ist
    /// Schluss. Bei gleichem Datum entscheidet die Cache-ID, damit die
    /// Auswahl stabil bleibt.
    ///
    /// - Parameter candidates: Mails aller Posteingänge, beliebige Reihenfolge.
    /// - Returns: Cache-IDs der ausgewählten Mails, neueste zuerst.
    static func inbox(_ candidates: [Candidate]) -> [String] {
        var result: [String] = []
        for (position, candidate) in sortedNewestFirst(candidates).enumerated() {
            guard result.count < inboxLimit else { break }
            if position < newestCount || candidate.isUnread || candidate.isFlagged {
                result.append(candidate.id)
            }
        }
        return result
    }

    /// Auswahl aus den Spam-Ordnern.
    ///
    /// - Parameter candidates: Mails aller Spam-Ordner, beliebige Reihenfolge.
    /// - Returns: Cache-IDs der `spamLimit` neuesten Mails, neueste zuerst.
    static func spam(_ candidates: [Candidate]) -> [String] {
        sortedNewestFirst(candidates).prefix(spamLimit).map(\.id)
    }

    /// Sortiert neueste zuerst; ohne Datum ans Ende, Gleichstand nach Cache-ID.
    ///
    /// - Parameter candidates: Mails.
    /// - Returns: Sortierte Mails.
    private static func sortedNewestFirst(_ candidates: [Candidate]) -> [Candidate] {
        candidates.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?) where l != r: return l > r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.id < rhs.id
            }
        }
    }
}
