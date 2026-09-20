//
//  MailActionService.swift
//  Mailwerk
//
//  IMAP-Aktionen: Flags setzen/entfernen, Nachrichten löschen/verschieben,
//  Ordnerliste abrufen. Reine Server-Operationen – der lokale Cache wird
//  vom Aufrufer (ViewModel/View) nach erfolgreicher Aktion aktualisiert.
//

import Foundation
import SwiftMail
import NIOIMAPCore

/// Repräsentiert einen IMAP-Ordner mit Name und optionaler Spezialrolle.
struct MailFolder: Identifiable, Hashable {
    let id: String          // Vollständiger IMAP-Pfad (z. B. "INBOX.Trash")
    let name: String        // Anzeigename (letztes Pfad-Segment)
    let specialUse: SpecialUse?

    enum SpecialUse: String {
        case drafts, sent, trash, junk, archive, flagged, all
    }
}

enum MailActionService {

    // MARK: - Fehlertypen

    enum ActionError: LocalizedError {
        case accountNotFound
        case noPassword
        case operationFailed(String)

        var errorDescription: String? {
            switch self {
            case .accountNotFound:
                return "Konto nicht gefunden"
            case .noPassword:
                return "Kein Passwort im Keychain"
            case .operationFailed(let detail):
                return "IMAP-Aktion fehlgeschlagen: \(detail)"
            }
        }
    }

    // MARK: - Flags setzen / entfernen

    /// Setzt oder entfernt \Seen auf dem Server.
    static func setRead(
        uid: Int,
        isRead: Bool,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox("INBOX")
            let imapUID = SwiftMail.UID(uid)
            let uidSet = UIDSet([imapUID])
            try await server.store(
                flags: [Flag.seen],
                on: uidSet,
                operation: isRead ? .add : .remove
            )
        }
    }

    /// Setzt oder entfernt \Flagged auf dem Server.
    static func setFlagged(
        uid: Int,
        isFlagged: Bool,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox("INBOX")
            let imapUID = SwiftMail.UID(uid)
            let uidSet = UIDSet([imapUID])
            try await server.store(
                flags: [Flag.flagged],
                on: uidSet,
                operation: isFlagged ? .add : .remove
            )
        }
    }

    // MARK: - Löschen

    /// Verschiebt die Nachricht in den Trash-Ordner (bevorzugt)
    /// oder setzt \Deleted + EXPUNGE als Fallback.
    /// Gibt den Namen des Trash-Ordners zurück (nil bei EXPUNGE-Fallback).
    @discardableResult
    static func deleteMessage(
        uid: Int,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws -> String? {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            // Trash-Ordner suchen
            let folders = try await fetchMailboxList(server)
            let trashFolder = folders.first { $0.specialUse == .trash }

            _ = try await server.selectMailbox("INBOX")
            let imapUID = SwiftMail.UID(uid)

            if let trash = trashFolder {
                try await server.move(
                    message: imapUID, to: trash.id
                )
                print("🗑️ Mail UID \(uid) nach \(trash.id) verschoben")
                return trash.id
            } else {
                let uidSet = UIDSet([imapUID])
                try await server.store(
                    flags: [Flag.deleted],
                    on: uidSet,
                    operation: .add
                )
                try await server.expunge()
                print("🗑️ Mail UID \(uid) gelöscht (EXPUNGE)")
                return nil
            }
        }
    }

    // MARK: - Verschieben

    /// Verschiebt eine Nachricht in einen anderen Ordner.
    static func moveMessage(
        uid: Int,
        toFolder: String,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox("INBOX")
            let imapUID = SwiftMail.UID(uid)
            try await server.move(
                message: imapUID, to: toFolder
            )
            print("📁 Mail UID \(uid) nach \(toFolder) verschoben")
        }
    }

    // MARK: - Ordnerliste

    /// Holt die Liste aller IMAP-Ordner für ein Konto.
    /// INBOX wird herausgefiltert (wir sind ja schon dort).
    static func fetchFolders(
        accountID: UUID,
        accountStore: AccountStore
    ) async throws -> [MailFolder] {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            try await fetchMailboxList(server)
        }
    }

    // MARK: - Interne Helfer

    /// Baut eine IMAP-Verbindung auf, führt die übergebene Operation aus
    /// und räumt die Verbindung anschließend sauber auf.
    private static func withIMAPConnection<T>(
        accountID: UUID,
        accountStore: AccountStore,
        body: (SwiftMail.IMAPServer) async throws -> T
    ) async throws -> T {
        let (account, password) = try resolveCredentials(
            accountID: accountID, accountStore: accountStore
        )
        let server = SwiftMail.IMAPServer(
            host: account.imapHost, port: account.imapPort
        )
        do {
            try await server.connect()
            try await server.login(
                username: account.username, password: password
            )
            let result = try await body(server)
            try await server.logout()
            return result
        } catch {
            try? await server.disconnect()
            throw ActionError.operationFailed(error.localizedDescription)
        }
    }

    /// Löst Account + Passwort aus dem AccountStore auf.
    private static func resolveCredentials(
        accountID: UUID,
        accountStore: AccountStore
    ) throws -> (MailAccount, String) {
        guard let account = accountStore.accounts.first(
            where: { $0.id == accountID }
        ) else {
            throw ActionError.accountNotFound
        }
        guard let password = try accountStore.password(for: account) else {
            throw ActionError.noPassword
        }
        return (account, password)
    }

    /// Listet alle Mailboxen auf dem Server und mappt SPECIAL-USE-Attribute.
    /// INBOX wird herausgefiltert.
    private static func fetchMailboxList(
        _ server: SwiftMail.IMAPServer
    ) async throws -> [MailFolder] {
        let mailboxes = try await server.listMailboxes(wildcard: "*")

        return mailboxes.compactMap { (mailbox) -> MailFolder? in
            let fullPath = mailbox.name
            // Letztes Segment als Anzeigename
            let delimStr = mailbox.hierarchyDelimiter.map { String($0) } ?? "."
            let displayName = fullPath.components(
                separatedBy: delimStr
            ).last ?? fullPath
            
            // INBOX nicht als Verschiebeziel anbieten
            if fullPath.uppercased() == "INBOX" { return nil }
            
            // SPECIAL-USE-Attribute auswerten
            let attrs = mailbox.attributes
            let specialUse: MailFolder.SpecialUse? = {
                if attrs.contains(.drafts)  { return .drafts }
                if attrs.contains(.sent)    { return .sent }
                if attrs.contains(.trash)   { return .trash }
                if attrs.contains(.junk)    { return .junk }
                if attrs.contains(.archive) { return .archive }
                if attrs.contains(.flagged) { return .flagged }
                return nil
            }()
            
            return MailFolder(
                id: fullPath,
                name: displayName,
                specialUse: specialUse
            )
        }
        // Spezialordner zuerst, dann alphabetisch
        .sorted {
            let a = $0.specialUse != nil ? 0 : 1
            let b = $1.specialUse != nil ? 0 : 1
            if a != b { return a < b }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
