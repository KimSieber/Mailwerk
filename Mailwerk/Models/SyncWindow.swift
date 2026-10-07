//
//  SyncWindow.swift
//  Mailwerk
//
//  Zweck: Zeitfenster des Caches je Ordner. Standard sind die letzten
//  30 Tage; „Ältere Nachrichten laden“ schiebt den Fensterbeginn
//  blockweise zurück. Nachgeladene Mails bleiben dauerhaft im Cache, der
//  Fensterbeginn übersteht Neustarts. Nach Alter wird nichts gelöscht.
//
//  Der Fensterbeginn rückt nur zurück, wenn ein Zeitraum vollständig
//  geladen wurde. Sonst entstünden Lücken, die kein späterer Abruf mehr
//  schließt.
//
//  Reine Datumslogik, damit sie ohne Server testbar ist.
//
//  Abgrenzung: Abruf über den Server im MailFetchService, Ablage des
//  Fensterbeginns im MessageStore.
//
//  Abhängigkeiten: keine (reine Datentypen).
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
        /// Erster Tag des Zeitraums (eingeschlossen).
        let since: Date
        /// Ende des Zeitraums (ausgeschlossen).
        let before: Date
    }

    /// Beginn des Standardfensters.
    ///
    /// - Parameters:
    ///   - now: Bezugszeitpunkt.
    ///   - days: Länge des Fensters in Tagen.
    ///   - calendar: Kalender für die Datumsrechnung.
    /// - Returns: `now` minus `days` Tage.
    static func standardStart(now: Date, days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    /// Nächster Zeitraum vor `start`.
    ///
    /// Verarbeitung: Der Beginn liegt auf Tagesanfang, weil SEARCH SINCE
    /// tagesgenau arbeitet – so schließen die Zeiträume lückenlos
    /// aneinander an.
    ///
    /// - Parameters:
    ///   - start: Bisheriger Fensterbeginn (Ende des neuen Zeitraums).
    ///   - days: Länge des Zeitraums in Tagen.
    ///   - calendar: Kalender für die Datumsrechnung.
    /// - Returns: Der Zeitraum unmittelbar vor `start`.
    static func nextBlock(before start: Date, days: Int, calendar: Calendar = .current) -> Block {
        let earlier = calendar.date(byAdding: .day, value: -days, to: start)!
        return Block(since: calendar.startOfDay(for: earlier), before: start)
    }

    /// Bestimmt den Fensterbeginn nach dem Laden eines Zeitraums.
    ///
    /// Verarbeitung: Nur wenn alle Mails des Zeitraums gespeichert wurden,
    /// rückt der Fensterbeginn auf den Anfang des Zeitraums. Fehlt auch
    /// nur eine, bleibt der bisherige Beginn stehen; der nächste Tipp auf
    /// „Ältere laden“ versucht denselben Zeitraum erneut. Bereits
    /// gespeicherte Mails werden dabei nicht doppelt geladen.
    ///
    /// - Parameters:
    ///   - previous: Fensterbeginn vor dem Laden.
    ///   - loaded: Anfang des geladenen Zeitraums.
    ///   - failedCount: Anzahl der Mails, die nicht gespeichert wurden.
    /// - Returns: Zu speichernder Fensterbeginn.
    static func startAfterLoading(previous: Date, loaded: Date, failedCount: Int) -> Date {
        failedCount == 0 ? loaded : previous
    }
}

/// Ergebnis von „Ältere Nachrichten laden“ für einen Ordner.
nonisolated enum OlderFetchResult: Equatable, Sendable {
    /// Zeitraum geladen. `hasMore` = auf dem Server gibt es noch Älteres;
    /// `failed` = Anzahl der Mails, die nicht geladen werden konnten
    /// (dann ist der Fensterbeginn nicht weitergerückt).
    case loaded(count: Int, failed: Int, windowStart: Date, hasMore: Bool)
    /// Auf dem Server gibt es nichts Älteres.
    case noOlder
}
