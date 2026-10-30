//
//  SearchScope.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 15.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Bereich einer Suche – immer die gerade gezeigte Ansicht:
//  - „Alle Eingänge“: die Posteingänge aller Postfächer mit
//    eingeschaltetem Abruf,
//  - „Ungelesen“: dieselben Posteingänge; die Liste zeigt davon nur die
//    Treffer der Sicht (keine Serversuche – ungelesene Mails liegen
//    vollständig im Cache),
//  - „Mit Kennzeichnung“: die gekennzeichneten Mails dieser Posteingänge
//    (keine Serversuche – Kennzeichen liegen vollständig im Cache),
//  - „Spam“: die Spam-Ordner dieser Postfächer,
//  - ein Ordner: nur dieser Ordner.
//
//  Ein Bereich besteht aus Paaren von Postfach und Ordner (`FolderKey`),
//  weil der Spam-Ordner je Postfach anders heißen kann.
//
//  Nebenläufigkeit: `nonisolated` und `Sendable`, damit die Ablage den
//  Bereich auch außerhalb des Hauptthreads nutzen kann (v0.2.3b). Nur
//  `make(for:…)` bleibt am Main-Actor, weil es die Ansicht
//  (`MailboxSelection`) auswertet.
//
//  Abgrenzung: Reine Beschreibung; gesucht wird im MessageStore (Cache)
//  bzw. im MailFetchService (Server).
//
//  Abhängigkeiten: MailboxSelection, MailFolder, FolderKey.
//

import Foundation

/// Bereich einer Suche.
nonisolated struct SearchScope: Equatable, Sendable {
    /// Ordner je Postfach, in denen gesucht wird.
    let folders: [FolderKey]
    /// `true` = nur gekennzeichnete Mails.
    let flaggedOnly: Bool
    /// `true`, wenn die Ansicht eine Serversuche zulässt.
    let serverSearchable: Bool

    /// `true`, wenn zusätzlich auf dem Server gesucht werden kann.
    var allowsServerSearch: Bool { serverSearchable && !folders.isEmpty }

    /// Bereich aus einzelnen Ordnern.
    ///
    /// - Parameters:
    ///   - folders: Ordner je Postfach.
    ///   - flaggedOnly: Nur gekennzeichnete Mails.
    ///   - serverSearchable: Serversuche zulässig.
    init(folders: [FolderKey], flaggedOnly: Bool, serverSearchable: Bool) {
        self.folders = folders
        self.flaggedOnly = flaggedOnly
        self.serverSearchable = serverSearchable
    }

    /// Bereich über denselben Ordner in mehreren Postfächern. Eine
    /// Serversuche ist zulässig, solange nicht nur Gekennzeichnetes gilt.
    ///
    /// - Parameters:
    ///   - accountIDs: Postfächer.
    ///   - folder: IMAP-Ordner (in jedem der Postfächer).
    ///   - flaggedOnly: Nur gekennzeichnete Mails.
    init(accountIDs: [UUID], folder: String, flaggedOnly: Bool) {
        self.init(
            folders: accountIDs.map { FolderKey(accountID: $0, folder: folder) },
            flaggedOnly: flaggedOnly,
            serverSearchable: !flaggedOnly
        )
    }

    /// Bereich zur gezeigten Ansicht.
    ///
    /// - Parameters:
    ///   - selection: Gezeigte Ansicht.
    ///   - fetchingAccountIDs: Postfächer mit eingeschaltetem Abruf (für
    ///     die Sammelansichten).
    ///   - spamFolders: Spam-Ordner dieser Postfächer (für die Sicht „Spam“).
    /// - Returns: Der Suchbereich.
    @MainActor
    static func make(
        for selection: MailboxSelection,
        fetchingAccountIDs: [UUID],
        spamFolders: [FolderKey] = []
    ) -> SearchScope {
        switch selection {
        case .allInboxes:
            return SearchScope(accountIDs: fetchingAccountIDs, folder: MailFolder.inboxPath, flaggedOnly: false)
        case .unread:
            return SearchScope(
                folders: fetchingAccountIDs.map { FolderKey(accountID: $0, folder: MailFolder.inboxPath) },
                flaggedOnly: false,
                serverSearchable: false
            )
        case .flagged:
            return SearchScope(accountIDs: fetchingAccountIDs, folder: MailFolder.inboxPath, flaggedOnly: true)
        case .spam:
            return SearchScope(folders: spamFolders, flaggedOnly: false, serverSearchable: true)
        case .folder(let accountID, let path, _):
            return SearchScope(accountIDs: [accountID], folder: path, flaggedOnly: false)
        }
    }
}
