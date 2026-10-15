//
//  SearchScope.swift
//  Mailwerk
//
//  Zweck: Bereich einer Suche – immer die gerade gezeigte Ansicht:
//  - „Alle Eingänge“: die Posteingänge aller Postfächer mit
//    eingeschaltetem Abruf,
//  - „Mit Kennzeichnung“: die gekennzeichneten Mails dieser Posteingänge
//    (keine Serversuche – Kennzeichen liegen vollständig im Cache),
//  - ein Ordner: nur dieser Ordner.
//
//  Abgrenzung: Reine Beschreibung; gesucht wird im MessageStore (Cache)
//  bzw. im MailFetchService (Server).
//
//  Abhängigkeiten: MailboxSelection, MailFolder.
//

import Foundation

/// Bereich einer Suche.
struct SearchScope: Equatable {
    /// Postfächer, in denen gesucht wird.
    let accountIDs: [UUID]
    /// IMAP-Ordner (in jedem der Postfächer).
    let folder: String
    /// `true` = nur gekennzeichnete Mails.
    let flaggedOnly: Bool

    /// `true`, wenn zusätzlich auf dem Server gesucht werden kann.
    var allowsServerSearch: Bool { !flaggedOnly && !accountIDs.isEmpty }

    /// Bereich zur gezeigten Ansicht.
    ///
    /// - Parameters:
    ///   - selection: Gezeigte Ansicht.
    ///   - fetchingAccountIDs: Postfächer mit eingeschaltetem Abruf (für
    ///     die Sammelansichten).
    /// - Returns: Der Suchbereich.
    static func make(for selection: MailboxSelection, fetchingAccountIDs: [UUID]) -> SearchScope {
        switch selection {
        case .allInboxes:
            return SearchScope(accountIDs: fetchingAccountIDs, folder: MailFolder.inboxPath, flaggedOnly: false)
        case .flagged:
            return SearchScope(accountIDs: fetchingAccountIDs, folder: MailFolder.inboxPath, flaggedOnly: true)
        case .folder(let accountID, let path, _):
            return SearchScope(accountIDs: [accountID], folder: path, flaggedOnly: false)
        }
    }
}
