//
//  SyncState.swift
//  Mailwerk
//
//  Stand einer Ansicht: wann ihr Inhalt zuletzt erfolgreich vom Server
//  abgerufen wurde. Grundlage für die Zeile „Aktualisiert: …" im Titel.
//

import Foundation

nonisolated enum SyncState: Equatable, Sendable {
    /// Mindestens ein beteiligter Ordner wurde noch nie abgerufen.
    case never
    /// Ältester Abrufzeitpunkt der beteiligten Ordner.
    case at(Date)

    /// Stand einer Ansicht aus einem oder mehreren Ordnern.
    ///
    /// Eine Sammelansicht wie „Alle Eingänge" ist nur so aktuell wie der
    /// Ordner, der am längsten nicht abgerufen wurde. Fehlt für einen
    /// Ordner jeder Abruf, gilt die ganze Ansicht als nie abgerufen.
    /// - Parameter stamps: letzter Abruf je Ordner, `nil` = nie.
    static func oldest(_ stamps: [Date?]) -> SyncState {
        guard !stamps.isEmpty else { return .never }
        var oldest: Date?
        for stamp in stamps {
            guard let stamp else { return .never }
            oldest = min(oldest ?? stamp, stamp)
        }
        return oldest.map { .at($0) } ?? .never
    }
}
