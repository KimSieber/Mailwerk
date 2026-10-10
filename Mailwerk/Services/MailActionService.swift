//
//  MailActionService.swift
//  Mailwerk
//
//  Zweck: IMAP-Aktionen an Mails und Ordnern – Gelesen und Kennzeichnung
//  setzen, Mails löschen und verschieben, Ordner anlegen und löschen,
//  Ordnerliste und Ordnerbaum abrufen. Reine Server-Operationen: Den
//  lokalen Cache aktualisiert der Aufrufer nach erfolgreicher Aktion.
//
//  Jede Aktion öffnet eine eigene Verbindung über `MailSession`. Fehler
//  der Verbindung oder des Servers werden als `ActionError.operationFailed`
//  gemeldet; Eingabefehler beim Anlegen (`FolderCreationPlanner.PlanError`)
//  und fehlende Zugangsdaten (`MailCredentialError`) bleiben unverändert,
//  weil sich ihre Meldung direkt an den Nutzer richtet.
//
//  Ordner löschen läuft als einzige Aktion nicht über SwiftMail, sondern
//  über `FolderDeletion` + `IMAPLineConnection`. Dieser eigene Weg wird
//  zurückgebaut, seit SwiftMail DELETE öffentlich anbietet (eigener Schritt).
//
//  Abgrenzung: Abruf → MailFetchService; Versand → MailSendService;
//  Spam-Aktionen → SpamFilterService.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailSession (Verbindung und
//  Zugangsdaten), FolderCreationPlanner, FolderDeletion, IMAPLineConnection,
//  FolderTreeBuilder, MessageStore (Ordnerliste offline).
//

import Foundation
import SwiftMail
import NIOIMAPCore

/// IMAP-Aktionen an Mails und Ordnern.
enum MailActionService {

    // MARK: - Fehlertypen

    /// Fehler einer Server-Aktion.
    enum ActionError: LocalizedError {
        /// Verbindung oder Server-Befehl ist gescheitert (mit Detailtext).
        case operationFailed(String)

        /// Liefert die deutsche Meldung für den Nutzer.
        ///
        /// - Returns: Meldungstext für die Anzeige.
        var errorDescription: String? {
            switch self {
            case .operationFailed(let detail):
                return "IMAP-Aktion fehlgeschlagen: \(detail)"
            }
        }
    }

    // MARK: - Flags setzen / entfernen

    /// Setzt oder entfernt `\Seen` auf dem Server.
    ///
    /// - Parameters:
    ///   - uid: UID der Mail im Ordner.
    ///   - isRead: `true` = als gelesen markieren, `false` = als ungelesen.
    ///   - accountID: Postfach der Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - folder: Ordner der Mail (UIDs gelten nur je Ordner).
    /// - Throws: `MailCredentialError` oder `ActionError`.
    static func setRead(
        uid: Int,
        isRead: Bool,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String = MailFetchService.inboxFolder
    ) async throws {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox(folder)
            try await server.store(
                flags: [Flag.seen],
                on: UIDSet([SwiftMail.UID(uid)]),
                operation: isRead ? .add : .remove
            )
        }
    }

    /// Setzt oder entfernt `\Flagged` auf dem Server.
    ///
    /// - Parameters:
    ///   - uid: UID der Mail im Ordner.
    ///   - isFlagged: `true` = kennzeichnen, `false` = Kennzeichnung entfernen.
    ///   - accountID: Postfach der Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - folder: Ordner der Mail (UIDs gelten nur je Ordner).
    /// - Throws: `MailCredentialError` oder `ActionError`.
    static func setFlagged(
        uid: Int,
        isFlagged: Bool,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String = MailFetchService.inboxFolder
    ) async throws {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox(folder)
            try await server.store(
                flags: [Flag.flagged],
                on: UIDSet([SwiftMail.UID(uid)]),
                operation: isFlagged ? .add : .remove
            )
        }
    }

    // MARK: - Löschen

    /// Löscht eine Mail.
    ///
    /// Verarbeitung: Hat das Postfach einen Papierkorb (SPECIAL-USE
    /// `\Trash`), wird die Mail dorthin verschoben. Sonst wird sie mit
    /// `\Deleted` markiert und per EXPUNGE endgültig entfernt.
    ///
    /// - Parameters:
    ///   - uid: UID der Mail im Ordner.
    ///   - accountID: Postfach der Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - folder: Ordner der Mail.
    /// - Returns: Pfad des Papierkorbs oder `nil`, wenn endgültig gelöscht wurde.
    /// - Throws: `MailCredentialError` oder `ActionError`.
    @discardableResult
    static func deleteMessage(
        uid: Int,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String = MailFetchService.inboxFolder
    ) async throws -> String? {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            let folders = try await fetchMailboxList(server)
            let trashFolder = folders.first { $0.specialUse == .trash }

            _ = try await server.selectMailbox(folder)
            let imapUID = SwiftMail.UID(uid)

            if let trash = trashFolder {
                _ = try await server.move(message: imapUID, to: trash.id)
                print("🗑️ Mail UID \(uid) nach \(trash.id) verschoben")
                return trash.id
            } else {
                try await server.store(
                    flags: [Flag.deleted],
                    on: UIDSet([imapUID]),
                    operation: .add
                )
                try await server.expunge()
                print("🗑️ Mail UID \(uid) gelöscht (EXPUNGE)")
                return nil
            }
        }
    }

    // MARK: - Verschieben

    /// Verschiebt eine Mail in einen anderen Ordner desselben Postfachs.
    ///
    /// - Parameters:
    ///   - uid: UID der Mail im bisherigen Ordner.
    ///   - toFolder: Server-Pfad des Zielordners.
    ///   - accountID: Postfach der Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - folder: Bisheriger Ordner der Mail.
    /// - Returns: UID im Zielordner, sofern der Server sie meldet (UIDPLUS).
    ///   Ohne diese Angabe muss der Aufrufer die Mail aus dem Cache
    ///   entfernen, statt sie umzuziehen.
    /// - Throws: `MailCredentialError` oder `ActionError`.
    @discardableResult
    static func moveMessage(
        uid: Int,
        toFolder: String,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String = MailFetchService.inboxFolder
    ) async throws -> UInt32? {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox(folder)
            let copyUID = try await server.move(message: SwiftMail.UID(uid), to: toFolder)
            let newUID = copyUID?.mapping.first?.destination.value
            print("📁 Mail UID \(uid) von \(folder) nach \(toFolder) verschoben (neue UID: \(newUID.map(String.init) ?? "unbekannt"))")
            return newUID
        }
    }

    // MARK: - Ordner anlegen

    /// Legt einen Ordner unter einem fertigen Pfad an (z. B. den
    /// vorgeschlagenen Spam-Ordner).
    ///
    /// Verarbeitung: Der Server kann den Pfad um sein Namespace-Präfix
    /// ergänzen. Deshalb wird der tatsächlich vorhandene Pfad über eine
    /// frische Ordnerliste ermittelt.
    ///
    /// - Parameters:
    ///   - path: Gewünschter Server-Pfad.
    ///   - accountID: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: Tatsächlicher Server-Pfad des neuen Ordners.
    /// - Throws: `MailCredentialError` oder `ActionError`.
    static func createFolder(
        _ path: String,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws -> String {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            try await server.createMailbox(path)
            print("📁 Ordner \(path) angelegt")

            let folders = try await fetchMailboxList(server)
            let created = folders.first { $0.id == path }
                ?? folders.first { $0.id.hasSuffix(path) }
            return created?.id ?? path
        }
    }

    /// Legt einen Ordner an, den der Nutzer in der Seitenleiste benannt hat.
    ///
    /// Verarbeitung: Namensprüfung und Pfad bestimmt `FolderCreationPlanner`
    /// anhand einer frischen Ordnerliste aus derselben Verbindung – so
    /// zählen auch Ordner, die gerade erst anderswo angelegt wurden.
    ///
    /// - Parameters:
    ///   - name: Lesbarer Name, wie eingegeben.
    ///   - parentPath: Server-Pfad des übergeordneten Ordners, `nil` für
    ///     die oberste Ebene.
    ///   - accountID: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: Server-Pfad des neuen Ordners.
    /// - Throws: `FolderCreationPlanner.PlanError` bei ungültigem oder
    ///   doppeltem Namen, `MailCredentialError` oder `ActionError`.
    @discardableResult
    static func createFolder(
        named name: String,
        parentPath: String?,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws -> String {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            let folders = try await fetchMailboxList(server, includeInbox: true)
            let prefix = await server.namespaces?.personal.first?.prefix
            let path = try FolderCreationPlanner.plan(
                name: name,
                parentPath: parentPath,
                listing: FolderListing(folders: folders, namespacePrefix: prefix)
            )
            try await server.createMailbox(path)
            print("📁 Ordner \(path) angelegt")
            return path
        }
    }

    // MARK: - Ordner löschen

    /// Port, auf dem der eigene IMAP-Weg zum Löschen arbeitet (TLS ab dem
    /// ersten Byte). Andere Ports bietet die Seitenleiste nicht an.
    static let folderDeletionPort = 993

    /// Zeitbudget für den gesamten Lösch-Dialog.
    private static let folderDeletionTimeout: Duration = .seconds(30)

    /// Löscht einen leeren Ordner über den eigenen IMAP-Weg.
    ///
    /// Verarbeitung: Prüfung auf Mails und Unterordner und das Löschen
    /// laufen in einer Verbindung (siehe `FolderDeletion`). Ein Wächter
    /// trennt die Verbindung nach Ablauf des Zeitbudgets; das beendet auch
    /// einen hängenden Lesevorgang.
    ///
    /// - Parameters:
    ///   - path: Server-Pfad des Ordners.
    ///   - accountID: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: `.deleted` oder den Grund, warum nicht gelöscht wurde.
    /// - Throws: `MailCredentialError`, `FolderDeletion.DeletionError` oder
    ///   `ActionError` (auch bei einem anderen Port als 993).
    static func deleteFolder(
        _ path: String,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws -> FolderDeletion.Outcome {
        let credentials = try accountStore.credentials(for: accountID)
        let account = credentials.account
        guard account.imapPort == folderDeletionPort else {
            throw ActionError.operationFailed(
                "Ordner lassen sich nur bei einer Verbindung über Port \(folderDeletionPort) löschen."
            )
        }

        let connection = try IMAPLineConnection(host: account.imapHost, port: account.imapPort)
        let watchdog = Task {
            try await Task.sleep(for: folderDeletionTimeout)
            connection.close()
        }
        defer {
            watchdog.cancel()
            connection.close()
        }

        do {
            try await connection.open()
            let outcome = try await FolderDeletion.run(
                on: connection,
                username: account.username,
                password: credentials.password,
                path: path
            )
            print("📁 Ordner \(path) löschen: \(outcome)")
            return outcome
        } catch let error as FolderDeletion.DeletionError {
            throw error
        } catch {
            throw ActionError.operationFailed(error.localizedDescription)
        }
    }

    // MARK: - Ordnerliste

    /// Ordnerliste inklusive INBOX und Namespace-Präfix – Grundlage des
    /// Ordnerbaums in der Seitenleiste.
    ///
    /// Verarbeitung: Das Präfix hat SwiftMail bereits beim Anmelden per
    /// NAMESPACE erfragt; es kostet keinen eigenen Befehl.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: Ordner und Namespace-Präfix.
    /// - Throws: `MailCredentialError` oder `ActionError`.
    static func fetchFolderListing(
        accountID: UUID,
        accountStore: AccountStore
    ) async throws -> FolderListing {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            let folders = try await fetchMailboxList(server, includeInbox: true)
            let prefix = await server.namespaces?.personal.first?.prefix
            return FolderListing(folders: folders, namespacePrefix: prefix)
        }
    }

    /// Fertiger Ordnerbaum eines Postfachs für die Seitenleiste.
    ///
    /// Verarbeitung: Die Ordnerliste wird dabei im Cache gespeichert, damit
    /// die Leiste auch offline ihre Ordner zeigt.
    ///
    /// - Parameters:
    ///   - account: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: Wurzelknoten des Ordnerbaums.
    /// - Throws: `MailCredentialError` oder `ActionError`.
    static func fetchFolderTree(
        for account: MailAccount,
        accountStore: AccountStore
    ) async throws -> [FolderNode] {
        let listing = try await fetchFolderListing(
            accountID: account.id, accountStore: accountStore
        )
        MessageStore.shared.saveFolderListing(listing, accountID: account.id)
        return FolderTreeBuilder.build(listing: listing, configuredSpamFolder: account.spamFolder)
    }

    /// Ordnerliste über eine bereits bestehende Verbindung.
    ///
    /// Verarbeitung: Für Abläufe, die ihre Verbindung selbst führen und
    /// die Liste darin brauchen (Spamfilter).
    ///
    /// - Parameter server: Angemeldete IMAP-Verbindung.
    /// - Returns: Ordner ohne INBOX.
    /// - Throws: IMAP-Fehler.
    static func mailboxes(on server: SwiftMail.IMAPServer) async throws -> [MailFolder] {
        try await fetchMailboxList(server)
    }

    // MARK: - Interne Helfer

    /// Führt eine Aktion über eine eigene Verbindung aus und vereinheitlicht
    /// die Fehler.
    ///
    /// Verarbeitung: Fehlende Zugangsdaten und Eingabefehler beim Anlegen
    /// werden unverändert weitergegeben; alle anderen Fehler werden zu
    /// `ActionError.operationFailed`.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - body: Aktion auf der angemeldeten Verbindung.
    /// - Returns: Ergebnis von `body`.
    /// - Throws: `MailCredentialError`, `FolderCreationPlanner.PlanError`
    ///   oder `ActionError`.
    private static func withIMAPConnection<T>(
        accountID: UUID,
        accountStore: AccountStore,
        body: (SwiftMail.IMAPServer) async throws -> T
    ) async throws -> T {
        let credentials = try accountStore.credentials(for: accountID)
        do {
            return try await MailSession.withIMAP(credentials, body)
        } catch let error as FolderCreationPlanner.PlanError {
            throw error
        } catch {
            throw ActionError.operationFailed(error.localizedDescription)
        }
    }

    /// Listet alle Ordner des Servers.
    ///
    /// Verarbeitung: Anzeigename ist das letzte Pfadsegment. SPECIAL-USE-
    /// Attribute werden übernommen, ebenso `\Noselect` (nicht auswählbar).
    /// Sonderordner stehen zuerst, danach alphabetisch.
    ///
    /// - Parameters:
    ///   - server: Angemeldete IMAP-Verbindung.
    ///   - includeInbox: `true` = INBOX mitliefern (Ordnerbaum); sonst
    ///     wird sie ausgelassen (Verschiebeziele, Papierkorb-Suche).
    /// - Returns: Ordner des Postfachs.
    /// - Throws: IMAP-Fehler.
    private static func fetchMailboxList(
        _ server: SwiftMail.IMAPServer,
        includeInbox: Bool = false
    ) async throws -> [MailFolder] {
        let mailboxes = try await server.listMailboxes(wildcard: "*")

        return mailboxes.compactMap { (mailbox) -> MailFolder? in
            let fullPath = mailbox.name
            let delimiter = mailbox.hierarchyDelimiter.map { String($0) } ?? "."
            let displayName = fullPath.components(separatedBy: delimiter).last ?? fullPath

            if !includeInbox && fullPath.uppercased() == "INBOX" { return nil }

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
                specialUse: specialUse,
                hierarchyDelimiter: mailbox.hierarchyDelimiter,
                isSelectable: mailbox.isSelectable
            )
        }
        .sorted {
            let a = $0.specialUse != nil ? 0 : 1
            let b = $1.specialUse != nil ? 0 : 1
            if a != b { return a < b }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
