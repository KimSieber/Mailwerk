//
//  SenderIconRecord.swift
//  Mailwerk
//
//  Zweck: Gespeichertes Logo einer Domain samt Zeitpunkt der letzten
//  Prüfung – und die Regel, wann erneut geladen wird.
//
//  Auch ein erfolgloser Versuch wird gespeichert (`imageData` = `nil`),
//  damit nicht bei jedem Anzeigen neu angefragt wird. Erneut versucht wird
//  nach 30 Tagen; vorhandene Logos werden nach 90 Tagen aufgefrischt.
//
//  Abgrenzung: Speichern und Lesen → MessageStore; Laden → SenderIconFetcher.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Gespeichertes Logo einer Domain.
nonisolated struct SenderIconRecord: Equatable, Sendable {
    /// Hauptdomain (siehe `SenderDomain.iconDomain`).
    let domain: String
    /// Bild als PNG; `nil` = kein Logo gefunden.
    let imageData: Data?
    /// Zeitpunkt der letzten Prüfung.
    let checkedAt: Date

    /// Wartezeit bis zum erneuten Versuch, wenn kein Logo gefunden wurde.
    static let retryAfterMiss: TimeInterval = 30 * 24 * 60 * 60
    /// Wartezeit bis zum Auffrischen eines vorhandenen Logos.
    static let refreshAfterHit: TimeInterval = 90 * 24 * 60 * 60

    /// Prüft, ob die Domain erneut geladen werden soll.
    ///
    /// Verarbeitung: Ohne Logo nach 30 Tagen, mit Logo nach 90 Tagen. Ein
    /// Prüfzeitpunkt in der Zukunft (verstellte Uhr) gilt als abgelaufen,
    /// damit kein Eintrag dauerhaft hängen bleibt.
    ///
    /// - Parameter now: Bezugszeitpunkt.
    /// - Returns: `true`, wenn neu geladen werden soll.
    func isDue(now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(checkedAt)
        guard age >= 0 else { return true }
        return age >= (imageData == nil ? Self.retryAfterMiss : Self.refreshAfterHit)
    }
}
