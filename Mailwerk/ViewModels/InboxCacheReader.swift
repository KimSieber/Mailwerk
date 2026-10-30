//
//  InboxCacheReader.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 24.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Liest alles, was die Mailliste aus dem Cache braucht, in einem
//  Durchgang abseits des Hauptthreads: die Einträge der gezeigten Ansicht,
//  die Abrufzeitpunkte für die Standzeile, die Zähler „Ungelesen“ und „Mit
//  Kennzeichnung“ sowie den Beginn der Zeitfenster für „Ältere laden“.
//
//  Hintergrund (v0.2.3b, Befunde P-01/P-07 des Prüfberichts): Bisher las
//  das ViewModel die Liste synchron auf dem Hauptthread, und die Ansicht
//  fragte Zähler und Fensterbeginn bei jedem Neuzeichnen einzeln ab. Jetzt
//  entsteht eine Momentaufnahme (`Snapshot`) im Hintergrund; das ViewModel
//  übernimmt sie auf dem Main-Actor und die Ansicht liest nur noch Werte.
//
//  Die Anfrage (`Request`) beschreibt die Ansicht ohne Bezug zur Oberfläche
//  (keine `MailboxSelection`), damit sie den Main-Actor verlassen darf.
//  Sortiert wird weiterhin im ViewModel.
//
//  Abgrenzung: Welche Ansicht gezeigt wird, Sortierung und Übernahme →
//  InboxViewModel; Abfragen → MessageStore.
//
//  Abhängigkeiten: MessageStore, MessageListItem, FolderKey, MailFolder.
//

import Foundation

/// Liest die Daten der Mailliste im Hintergrund.
nonisolated enum InboxCacheReader {

    /// Woher die Einträge der Liste kommen.
    enum Source: Sendable, Equatable {
        /// Posteingänge der Postfächer („Alle Eingänge“).
        case inboxes([UUID])
        /// Ungelesene der Posteingänge, dazu die schon gezeigten Mails.
        case unread([UUID], keeping: Set<String>)
        /// Gekennzeichnete der Posteingänge.
        case flagged([UUID])
        /// Mehrere Ordner, je Postfach einer (Sicht „Spam“).
        case folders([FolderKey])
        /// Ein Ordner eines Postfachs.
        case folder(accountID: UUID, path: String)
    }

    /// Anfrage für eine Momentaufnahme.
    struct Request: Sendable, Equatable {
        /// Quelle der Einträge.
        let source: Source
        /// Ordner, deren letzter Abruf die Standzeile bestimmt.
        let syncFolders: [FolderKey]
        /// Postfächer für die Zähler „Ungelesen“ und „Mit Kennzeichnung“.
        let countAccountIDs: [UUID]
        /// Ordner, deren Fensterbeginn für „Ältere laden“ gebraucht wird.
        let windowFolders: [FolderKey]
    }

    /// Ergebnis einer Anfrage.
    struct Snapshot: Sendable {
        /// Einträge der Ansicht, absteigend nach Datum.
        let items: [MessageListItem]
        /// Letzter Abruf je Ordner aus `syncFolders` (`nil` = noch nie).
        let syncDates: [Date?]
        /// Anzahl ungelesener Mails in den Posteingängen.
        let unreadCount: Int
        /// Anzahl gekennzeichneter Mails in den Posteingängen.
        let flaggedCount: Int
        /// Gespeicherter Fensterbeginn je Ordner; fehlt ein Ordner, gilt
        /// das Standardfenster.
        let windowStarts: [FolderKey: Date]
    }

    /// Liest eine Momentaufnahme.
    ///
    /// Verarbeitung: Läuft dank `@concurrent` nicht auf dem Aufrufer-Actor,
    /// sondern im Hintergrund; alle Abfragen gehen über die Leseverbindung
    /// der Ablage und warten daher nicht auf einen laufenden Abruf.
    ///
    /// - Parameters:
    ///   - request: Beschreibung der Ansicht.
    ///   - store: Ablage (Standard: `MessageStore.shared`; Tests übergeben eigene).
    /// - Returns: Momentaufnahme.
    @concurrent
    static func read(_ request: Request, store: MessageStore = .shared) async -> Snapshot {
        readSync(request, store: store)
    }

    /// Liest eine Momentaufnahme im aufrufenden Thread.
    ///
    /// Verarbeitung: Gemeinsamer Kern von `read`; einzeln aufrufbar für Tests.
    ///
    /// - Parameters:
    ///   - request: Beschreibung der Ansicht.
    ///   - store: Ablage.
    /// - Returns: Momentaufnahme.
    static func readSync(_ request: Request, store: MessageStore) -> Snapshot {
        let items: [MessageListItem]
        switch request.source {
        case .inboxes(let accountIDs):
            items = store.allMessages(accountIDs: accountIDs, folder: MailFolder.inboxPath)
        case .unread(let accountIDs, let keeping):
            items = store.unreadInboxMessages(accountIDs: accountIDs, keeping: keeping)
        case .flagged(let accountIDs):
            items = store.flaggedInboxMessages(accountIDs: accountIDs)
        case .folders(let folders):
            items = store.messages(in: folders)
        case .folder(let accountID, let path):
            items = store.folderMessages(accountID: accountID, folder: path)
        }

        let syncDates = request.syncFolders.map {
            store.lastSync(accountID: $0.accountID, folder: $0.folder)
        }

        var windowStarts: [FolderKey: Date] = [:]
        for key in request.windowFolders {
            if let start = store.windowStart(accountID: key.accountID, folder: key.folder) {
                windowStarts[key] = start
            }
        }

        return Snapshot(
            items: items,
            syncDates: syncDates,
            unreadCount: store.unreadInboxCount(accountIDs: request.countAccountIDs),
            flaggedCount: store.flaggedInboxCount(accountIDs: request.countAccountIDs),
            windowStarts: windowStarts
        )
    }
}
