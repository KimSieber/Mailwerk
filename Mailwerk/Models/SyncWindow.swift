//
//  SyncWindow.swift
//  Mailwerk
//
//  Zeitfenster des Caches je Ordner. Standard sind die letzten 30 Tage;
//  „Ältere Nachrichten laden" schiebt den Fensterbeginn blockweise zurück.
//  Nachgeladene Mails bleiben bis zum nächsten App-Start, danach gilt
//  wieder das Standardfenster (Entscheidung v0.1.7e).
//
//  Reine Datumslogik, damit sie ohne Server testbar ist.
//

import Foundation

nonisolated enum SyncWindow {

    /// Sicherheitsgrenze für leere Zeiträume je Tipp (600 × 30 Tage ≈ 50
    /// Jahre). Im Normalfall endet die Suche vorher, weil es keine älteren
    /// Mails mehr gibt.
    static let maxBlocksPerLoad = 600

    /// Ein nachzuladender Zeitraum in IMAP-Semantik: SINCE schließt den
    /// Tag ein, BEFORE schließt ihn aus.
    struct Block: Equatable {
        let since: Date
        let before: Date
    }

    /// Beginn des Standardfensters.
    static func standardStart(now: Date, days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    /// Nächster Zeitraum vor `start`. Der Beginn liegt auf Tagesanfang,
    /// damit das Aufräumen (exakter Zeitvergleich) keine Mails des
    /// Grenztags entfernt, die SEARCH SINCE (tagesgenau) geliefert hat.
    static func nextBlock(before start: Date, days: Int, calendar: Calendar = .current) -> Block {
        let earlier = calendar.date(byAdding: .day, value: -days, to: start)!
        return Block(since: calendar.startOfDay(for: earlier), before: start)
    }

    /// Ab wann beim Refresh aufgeräumt wird: am Standardbeginn oder – wenn
    /// ältere Mails nachgeladen wurden – am früheren Fensterbeginn.
    static func cleanupCutoff(standardStart: Date, windowStart: Date?) -> Date {
        guard let windowStart else { return standardStart }
        return min(standardStart, windowStart)
    }
}

/// Ergebnis von „Ältere Nachrichten laden" für einen Ordner.
nonisolated enum OlderFetchResult: Equatable, Sendable {
    /// Zeitraum geladen; `hasMore` = auf dem Server gibt es noch Älteres.
    case loaded(count: Int, windowStart: Date, hasMore: Bool)
    /// Auf dem Server gibt es nichts Älteres.
    case noOlder
}
