//
//  FetchClassifier.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 30.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Ordnet die Kopfdaten eines Abrufs dem Cache zu: Welche Mails
//  sind neu und müssen geladen werden, bei welchen bekannten Mails haben
//  sich die Flags geändert, welchen fehlen noch Kopfdaten (ältere
//  Header-Version), und welche Antworten ohne UID werden übergangen.
//
//  Grundsatz „nur Änderungen schreiben“: Bekannte Mails bekommen neue
//  Flags nur, wenn sie sich vom gespeicherten Stand unterscheiden – das
//  spart bei jedem Abruf Schreibzugriffe (Prüfbericht P-04).
//
//  Reine Logik ohne IMAP- und Datenbankzugriff (Code-Review v0.3.1,
//  Regel 4); den Cache-Stand liest der MailFetchService vorher ein.
//
//  Abhängigkeiten: FlagState, CachedFlagState, CachedMessage (Cache-ID).
//

import Foundation

/// Einordnung der Kopfdaten eines Abrufs gegen den Cache.
nonisolated enum FetchClassifier {

    /// Eine Antwort der Kopfdaten-Abfrage, auf das Nötige reduziert.
    struct Entry: Equatable {
        /// UID; `nil`, wenn der Server keine meldete.
        let uid: UInt32?
        /// Ausgewertete Flags.
        let flags: FlagState
    }

    /// Was der Cache zum Ordner bereits weiß.
    struct CacheSnapshot {
        /// Cache-IDs aller Mails des Ordners.
        let messageIDs: Set<String>
        /// Gespeicherte Flags je Cache-ID.
        let flags: [String: CachedFlagState]
        /// Cache-IDs der Mails mit älterer Header-Version.
        let needsHeaders: Set<String>
    }

    /// Verweis auf einen Eintrag der Eingabe.
    struct Target: Equatable {
        /// Position in der Eingabe (und in den Kopfdaten).
        let index: Int
        /// UID der Mail.
        let uid: UInt32
        /// Cache-ID der Mail.
        let messageID: String
    }

    /// Ergebnis der Einordnung.
    struct Classification: Equatable {
        /// Neue Mails, in Eingabereihenfolge.
        var newMessages: [Target] = []
        /// Bekannte Mails mit geänderten Flags.
        var flagUpdates: [Target] = []
        /// Bekannte Mails, denen Kopfdaten nachzutragen sind.
        var headerBackfills: [Target] = []
        /// Antworten ohne UID.
        var skippedCount = 0
    }

    /// Ordnet die Antworten der Kopfdaten-Abfrage dem Cache zu.
    ///
    /// Verarbeitung: Ohne UID → übergangen. Nicht im Cache → neu. Im
    /// Cache → Flag-Update, wenn die Flags vom gespeicherten Stand
    /// abweichen oder keiner gespeichert ist; Kopfdaten nachtragen, wenn
    /// die Mail in `needsHeaders` steht. Beides kann zusammen zutreffen.
    ///
    /// - Parameters:
    ///   - entries: Antworten der Kopfdaten-Abfrage.
    ///   - cache: Stand des Caches für den Ordner.
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Einordnung mit Verweisen auf die Eingabe.
    static func classify(
        _ entries: [Entry],
        cache: CacheSnapshot,
        accountID: UUID,
        folder: String
    ) -> Classification {
        var result = Classification()
        for (index, entry) in entries.enumerated() {
            guard let uid = entry.uid else {
                result.skippedCount += 1
                continue
            }
            let messageID = CachedMessage.makeID(accountID: accountID, folder: folder, uid: uid)
            let target = Target(index: index, uid: uid, messageID: messageID)
            guard cache.messageIDs.contains(messageID) else {
                result.newMessages.append(target)
                continue
            }
            if cache.flags[messageID].map(entry.flags.matches) != true {
                result.flagUpdates.append(target)
            }
            if cache.needsHeaders.contains(messageID) {
                result.headerBackfills.append(target)
            }
        }
        return result
    }
}
