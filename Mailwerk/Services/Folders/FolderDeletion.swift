//
//  FolderDeletion.swift
//  Mailwerk
//
//  Zweck: Entscheidet, ob ein Ordner gelöscht werden darf, und beschreibt
//  das Ergebnis für den Nutzer.
//
//  Mailwerk löscht nur leere Ordner: keine Mails, keine Unterordner,
//  kein reiner Container. SwiftMails `deleteMailbox` löscht einen Ordner
//  dagegen samt Inhalt ohne Rückfrage. Deshalb prüft Mailwerk unmittelbar
//  vor dem Löschen in derselben Verbindung:
//  1. Ordner vorhanden und wählbar? Unterordner? – anhand der Ordnerliste
//     (`precheck`, ohne Netz testbar);
//  2. Anzahl der Mails – per STATUS (`outcome(messageCount:)`).
//  Erst wenn beides „leer“ ergibt, wird gelöscht.
//
//  Abgrenzung: Die Verbindung und das Löschen selbst → MailActionService;
//  Rückfrage und Anzeige des Ergebnisses → FolderSidebarView.
//
//  Abhängigkeiten: MailFolder.
//

import Foundation

/// Prüfung und Ergebnis beim Löschen eines Ordners.
nonisolated enum FolderDeletion {

    /// Ergebnis eines Löschversuchs, wenn die Verbindung funktioniert hat.
    enum Outcome: Equatable {
        /// Ordner gelöscht.
        case deleted
        /// Den Ordner gibt es auf dem Server nicht (mehr).
        case notFound
        /// Reiner Container (`\Noselect`), nicht löschbar.
        case notSelectable
        /// Der Ordner hat Unterordner.
        case hasSubfolders
        /// Der Ordner enthält Mails.
        case notEmpty(messages: Int)
        /// Der Server meldet nicht, wie viele Mails der Ordner enthält.
        case unknownContent

        /// Hinweis für den Nutzer.
        ///
        /// - Returns: Meldungstext oder `nil` bei Erfolg.
        var userMessage: String? {
            switch self {
            case .deleted:
                return nil
            case .notFound:
                return "Den Ordner gibt es auf dem Server nicht mehr."
            case .notSelectable:
                return "Dieser Ordner ist nur ein Container und kann hier nicht gelöscht werden."
            case .hasSubfolders:
                return "Der Ordner enthält Unterordner – bitte zuerst diese löschen."
            case .notEmpty(let count):
                let mails = count == 1 ? "1 Mail" : "\(count) Mails"
                return "Der Ordner enthält \(mails) – bitte zuerst verschieben oder löschen."
            case .unknownContent:
                return "Der Server meldet nicht, ob der Ordner leer ist. Bitte im Webmail löschen."
            }
        }

        /// `true`, wenn der Ordner danach nicht mehr existiert und sein
        /// Cache entfernt werden kann (gelöscht oder schon vorher weg).
        var removesFolder: Bool {
            self == .deleted || self == .notFound
        }
    }

    /// Prüft anhand der Ordnerliste, ob ein Ordner grundsätzlich löschbar ist.
    ///
    /// Verarbeitung: Der Ordner muss mit genau diesem Pfad in der Liste
    /// stehen und wählbar sein. Unterordner werden am Pfad erkannt (Pfad +
    /// Trennzeichen als Anfang eines anderen Ordners) – unabhängig davon,
    /// ob der Server `\HasChildren` meldet.
    ///
    /// - Parameters:
    ///   - path: Server-Pfad des Ordners.
    ///   - folders: Vollständige Ordnerliste des Postfachs (mit INBOX).
    /// - Returns: Grund, warum nicht gelöscht wird, oder `nil`, wenn nur
    ///   noch die Anzahl der Mails zu prüfen ist.
    static func precheck(path: String, folders: [MailFolder]) -> Outcome? {
        guard let folder = folders.first(where: { $0.id == path }) else { return .notFound }
        guard folder.isSelectable else { return .notSelectable }
        if let delimiter = folder.hierarchyDelimiter, !delimiter.isEmpty {
            let childPrefix = path + delimiter
            if folders.contains(where: { $0.id.hasPrefix(childPrefix) }) {
                return .hasSubfolders
            }
        }
        return nil
    }

    /// Entscheidet anhand der gemeldeten Anzahl der Mails.
    ///
    /// - Parameter messageCount: Anzahl laut STATUS; `nil` = nicht gemeldet.
    /// - Returns: Grund, warum nicht gelöscht wird, oder `nil`, wenn der
    ///   Ordner leer ist und gelöscht werden darf.
    static func outcome(messageCount: Int?) -> Outcome? {
        guard let messageCount else { return .unknownContent }
        return messageCount > 0 ? .notEmpty(messages: messageCount) : nil
    }
}
