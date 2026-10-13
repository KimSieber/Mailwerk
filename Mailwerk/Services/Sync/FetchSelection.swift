//
//  FetchSelection.swift
//  Mailwerk
//
//  Zweck: Regeln für den Abruf je Postfach. Ein Postfach lässt sich je
//  Gerät „ausschalten“ (pausieren):
//  - Die gemeinsame Abrufrunde über „Alle Eingänge“ übergeht es (Start,
//    Pull-to-Refresh, Netz zurück, neue Postfächer).
//  - Die Sammelsichten („Alle Eingänge“, „Mit Kennzeichnung“) blenden
//    seine Mails aus; ihr Stand und „Ältere Nachrichten laden“ beziehen
//    es nicht mit ein.
//  - Wird ein Ordner des Postfachs geöffnet, wird er trotzdem abgerufen.
//    Beim Posteingang eines pausierten Postfachs ersetzt dieser Abruf die
//    Runde: Spamfilter, Posteingang und Spam-Ordner.
//
//  Gespeichert werden die Kennungen der pausierten Postfächer lokal (nicht
//  über iCloud) als sortierte Textliste.
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Speichern → AccountStore; Abruf → InboxViewModel;
//  Ordnerliste → FolderCatalog.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Regeln für den Abruf je Postfach.
nonisolated enum FetchSelection {

    /// Art des Abrufs beim Öffnen eines Ordners.
    enum FolderRefresh: Equatable {
        /// Nur der geöffnete Ordner.
        case folderOnly
        /// Wie in der Abrufrunde: Spamfilter, Posteingang, Spam-Ordner.
        case fullAccount
    }

    /// Kennungen der Postfächer, die abgerufen und in den Sammelsichten
    /// gezeigt werden – in der Reihenfolge der Postfächer.
    ///
    /// - Parameters:
    ///   - accountIDs: Alle Postfächer in ihrer Reihenfolge.
    ///   - paused: Ausgeschaltete Postfächer.
    /// - Returns: Eingeschaltete Postfächer.
    static func activeIDs(_ accountIDs: [UUID], paused: Set<UUID>) -> [UUID] {
        accountIDs.filter { !paused.contains($0) }
    }

    /// Art des Abrufs beim Öffnen eines Ordners.
    ///
    /// - Parameters:
    ///   - isInbox: `true`, wenn der Posteingang geöffnet wird.
    ///   - isPaused: `true`, wenn das Postfach ausgeschaltet ist.
    /// - Returns: `.fullAccount` nur beim Posteingang eines ausgeschalteten
    ///   Postfachs, sonst `.folderOnly`.
    static func folderRefresh(isInbox: Bool, isPaused: Bool) -> FolderRefresh {
        isInbox && isPaused ? .fullAccount : .folderOnly
    }

    /// Liest die gespeicherte Liste der ausgeschalteten Postfächer.
    ///
    /// - Parameter stored: Gespeicherte Kennungen als Text; Ungültiges wird übergangen.
    /// - Returns: Kennungen.
    static func pausedIDs(from stored: [String]?) -> Set<UUID> {
        Set((stored ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// Speicherform der ausgeschalteten Postfächer.
    ///
    /// - Parameter paused: Kennungen.
    /// - Returns: Sortierte Textliste (gleiche Menge → gleiche Liste).
    static func storedValue(_ paused: Set<UUID>) -> [String] {
        paused.map(\.uuidString).sorted()
    }
}
