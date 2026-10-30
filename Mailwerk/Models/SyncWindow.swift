//
//  SyncWindow.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 30.09.2026
//  Geändert: 10.10.2026
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
//  Reine Datumslogik, damit sie ohne Server testbar ist. Länge des
//  Fensters und Kalender stehen nur hier; Abruf, Spam-Filter und Ansicht
//  rechnen alle über diese Funktionen.
//
//  Abgrenzung: Abruf über den Server im MailFetchService, Ablage des
//  Fensterbeginns im MessageStore.
//
//  Abhängigkeiten: keine (reine Datentypen).
//

import Foundation

/// Zeitfenster des Caches: Standardbeginn, nachzuladende Zeiträume und
/// Fortschreiben des Fensterbeginns.
nonisolated enum SyncWindow {

    /// Länge des Standardfensters und eines nachgeladenen Zeitraums in Tagen.
    static let standardDays = 30

    /// Kalender für alle Datumsrechnungen des Fensters und für IMAP SEARCH
    /// (SINCE/BEFORE sind gregorianische Kalendertage). Zeitzone des Geräts.
    static let calendar = Calendar(identifier: .gregorian)

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
    ///   - now: Bezugszeitpunkt (Standard: jetzt).
    ///   - days: Länge des Fensters in Tagen.
    ///   - calendar: Kalender für die Datumsrechnung.
    /// - Returns: `now` minus `days` Tage.
    static func standardStart(
        now: Date = Date(), days: Int = SyncWindow.standardDays, calendar: Calendar = SyncWindow.calendar
    ) -> Date {
        daysBefore(now, days: days, calendar: calendar)
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
    static func nextBlock(
        before start: Date, days: Int = SyncWindow.standardDays, calendar: Calendar = SyncWindow.calendar
    ) -> Block {
        let earlier = daysBefore(start, days: days, calendar: calendar)
        return Block(since: calendar.startOfDay(for: earlier), before: start)
    }

    /// Rechnet Kalendertage zurück.
    ///
    /// Verarbeitung: Kalenderrechnung, damit Sommer-/Winterzeit keine
    /// Stunde verschiebt. Liefert der Kalender kein Datum (nur bei
    /// unsinnigen Werten denkbar), wird mit 24-Stunden-Tagen gerechnet
    /// statt abzustürzen.
    ///
    /// - Parameters:
    ///   - date: Ausgangszeitpunkt.
    ///   - days: Anzahl der Tage.
    ///   - calendar: Kalender für die Datumsrechnung.
    /// - Returns: `date` minus `days` Tage.
    private static func daysBefore(_ date: Date, days: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -days, to: date)
            ?? date.addingTimeInterval(-Double(days) * 86_400)
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
