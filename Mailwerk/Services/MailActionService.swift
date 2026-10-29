//
//  MailActionService.swift
//  Mailwerk
//
//  Zweck: IMAP-Aktionen an Mails und Ordnern – Gelesen und Kennzeichnung
//  setzen, Mails löschen und verschieben, Ordner anlegen und löschen,
//  Ordnerliste und Ordnerbaum abrufen. Reine Server-Operationen: Den
//  lokalen Cache aktualisiert der Aufrufer nach erfolgreicher Aktion.
//
//  Gelesen, Kennzeichnung, Löschen und Verschieben gibt es auch für
//  mehrere Mails eines Ordners (`uids:`): ein Befehl mit allen UIDs über
//  eine Verbindung, statt Mail für Mail.
//
//  Jede Aktion öffnet eine eigene Verbindung über `MailSession`. Fehler
//  der Verbindung oder des Servers werden als `ActionError.operationFailed`
//  gemeldet. Fehler, deren Meldung sich direkt an den Nutzer richtet
//  (`UserFacingError`, etwa ein ungültiger Ordnername), und fehlende
//  Zugangsdaten (`MailCredentialError`) bleiben unverändert.
//
//  Ordner löschen: Mailwerk löscht nur leere Ordner. SwiftMails
//  `deleteMailbox` löscht samt Inhalt; deshalb prüft `FolderDeletion`
//  in derselben Verbindung unmittelbar vorher Ordnerliste und Anzahl der
//  Mails.
//
//  Ordnerbaum (v0.2.3d): Abruf der Ordnerliste, Speichern und Aufbau des
//  Baums laufen im Hintergrund (`loadFolderTree`, `cachedFolderTree`); die
//  übrigen Aktionen bleiben am Main-Actor (sie warten fast nur auf den
//  Server, Messung 2).
//
//  Abgrenzung: Abruf → MailFetchService; Versand → MailSendService;
//  Spam-Aktionen → SpamFilterService.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailSession (Verbindung und
//  Zugangsdaten), UserFacingError, FolderCreationPlanner, FolderDeletion,
//  FolderTreeBuilder, MailFolder, MessageStore (Ordnerliste offline),
//  Log.
//

import Foundation
import SwiftMail
import NIOIMAPCore
import os

/// IMAP-Aktionen an Mails und Ordnern.
enum MailActionService {

    // MARK: - Fehlertypen

    /// Fehler einer Server-Aktion.
    nonisolated enum ActionError: LocalizedError {
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
        uid: UInt32,
        isRead: Bool,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String = MailFolder.inboxPath
    ) async throws {
        try await setRead(
            uids: [uid], isRead: isRead, accountID: accountID,
            accountStore: accountStore, folder: folder
        )
    }

    /// Setzt oder entfernt `\Seen` an mehreren Mails eines Ordners.
    ///
    /// - Parameters:
    ///   - uids: UIDs der Mails im Ordner.
    ///   - isRead: `true` = als gelesen markieren, `false` = als ungelesen.
    ///   - accountID: Postfach der Mails.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - folder: Ordner der Mails (UIDs gelten nur je Ordner).
    /// - Throws: `MailCredentialError` oder `ActionError`.
    static func setRead(
        uids: [UInt32],
        isRead: Bool,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String
    ) async throws {
        try await storeFlag(
            .seen, set: isRead, uids: uids, folder: folder,
            accountID: accountID, accountStore: accountStore
        )
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
        uid: UInt32,
        isFlagged: Bool,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String = MailFolder.inboxPath
    ) async throws {
        try await setFlagged(
            uids: [uid], isFlagged: isFlagged, accountID: accountID,
            accountStore: accountStore, folder: folder
        )
    }

    /// Setzt oder entfernt `\Flagged` an mehreren Mails eines Ordners.
    ///
    /// - Parameters:
    ///   - uids: UIDs der Mails im Ordner.
    ///   - isFlagged: `true` = kennzeichnen, `false` = Kennzeichnung entfernen.
    ///   - accountID: Postfach der Mails.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - folder: Ordner der Mails (UIDs gelten nur je Ordner).
    /// - Throws: `MailCredentialError` oder `ActionError`.
    static func setFlagged(
        uids: [UInt32],
        isFlagged: Bool,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String
    ) async throws {
        try await storeFlag(
            .flagged, set: isFlagged, uids: uids, folder: folder,
            accountID: accountID, accountStore: accountStore
        )
    }

    /// Setzt oder entfernt ein Flag an Mails eines Ordners.
    ///
    /// Verarbeitung: Ordner auswählen, dann ein `UID STORE +FLAGS` bzw.
    /// `-FLAGS` für alle UIDs.
    ///
    /// - Parameters:
    ///   - flag: Zu setzendes Flag.
    ///   - set: `true` = setzen, `false` = entfernen.
    ///   - uids: UIDs der Mails im Ordner.
    ///   - folder: Ordner der Mail.
    ///   - accountID: Postfach der Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Throws: `MailCredentialError` oder `ActionError`.
    private static func storeFlag(
        _ flag: SwiftMail.Flag,
        set: Bool,
        uids: [UInt32],
        folder: String,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox(folder)
            try await server.store(
                flags: [flag],
                on: UIDSet(uids.map { SwiftMail.UID($0) }),
                operation: set ? .add : .remove
            )
        }
    }

    // MARK: - Löschen

    /// Löscht eine Mail.
    ///
    /// Verarbeitung: siehe `deleteMessages(uids:…)`.
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
        uid: UInt32,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String = MailFolder.inboxPath
    ) async throws -> String? {
        try await deleteMessages(
            uids: [uid], accountID: accountID, accountStore: accountStore, folder: folder
        )
    }

    /// Löscht mehrere Mails eines Ordners.
    ///
    /// Verarbeitung: Hat das Postfach einen Papierkorb (SPECIAL-USE
    /// `\Trash`), werden die Mails mit einem Befehl dorthin verschoben.
    /// Sonst werden sie mit `\Deleted` markiert und per EXPUNGE endgültig
    /// entfernt.
    ///
    /// - Parameters:
    ///   - uids: UIDs der Mails im Ordner.
    ///   - accountID: Postfach der Mails.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - folder: Ordner der Mails.
    /// - Returns: Pfad des Papierkorbs oder `nil`, wenn endgültig gelöscht wurde.
    /// - Throws: `MailCredentialError` oder `ActionError`.
    @discardableResult
    static func deleteMessages(
        uids: [UInt32],
        accountID: UUID,
        accountStore: AccountStore,
        folder: String
    ) async throws -> String? {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            let folders = try await fetchMailboxList(server)
            let trashFolder = folders.first { $0.specialUse == .trash }

            _ = try await server.selectMailbox(folder)
            let set = UIDSet(uids.map { SwiftMail.UID($0) })

            if let trash = trashFolder {
                _ = try await server.move(messages: set, to: trash.id)
                Log.actions.info("🗑️ \(uids.count) Mail(s) nach \(trash.id, privacy: .public) verschoben")
                return trash.id
            } else {
                try await server.store(
                    flags: [SwiftMail.Flag.deleted],
                    on: set,
                    operation: .add
                )
                try await server.expunge()
                Log.actions.info("🗑️ \(uids.count) Mail(s) gelöscht (EXPUNGE)")
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
        uid: UInt32,
        toFolder: String,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String = MailFolder.inboxPath
    ) async throws -> UInt32? {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox(folder)
            let copyUID = try await server.move(message: SwiftMail.UID(uid), to: toFolder)
            let newUID = copyUID?.mapping.first?.destination.value
            Log.actions.info("📁 Mail UID \(uid) von \(folder, privacy: .public) nach \(toFolder, privacy: .public) verschoben (neue UID: \(newUID.map(String.init) ?? "unbekannt", privacy: .public))")
            return newUID
        }
    }

    /// Verschiebt mehrere Mails eines Ordners in einen anderen Ordner
    /// desselben Postfachs – ein Befehl für alle UIDs.
    ///
    /// Verarbeitung: Neue UIDs im Zielordner werden nicht ausgewertet; der
    /// Aufrufer entfernt die Mails aus dem Cache des bisherigen Ordners.
    ///
    /// - Parameters:
    ///   - uids: UIDs der Mails im bisherigen Ordner.
    ///   - toFolder: Server-Pfad des Zielordners.
    ///   - accountID: Postfach der Mails.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - folder: Bisheriger Ordner der Mails.
    /// - Throws: `MailCredentialError` oder `ActionError`.
    static func moveMessages(
        uids: [UInt32],
        toFolder: String,
        accountID: UUID,
        accountStore: AccountStore,
        folder: String
    ) async throws {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server in
            _ = try await server.selectMailbox(folder)
            _ = try await server.move(messages: UIDSet(uids.map { SwiftMail.UID($0) }), to: toFolder)
            Log.actions.info("📁 \(uids.count) Mail(s) von \(folder, privacy: .public) nach \(toFolder, privacy: .public) verschoben")
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
            Log.actions.info("📁 Ordner \(path, privacy: .public) angelegt")

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
            Log.actions.info("📁 Ordner \(path, privacy: .public) angelegt")
            return path
        }
    }

    // MARK: - Ordner löschen

    /// Löscht einen leeren Ordner.
    ///
    /// Verarbeitung: In einer Verbindung, unmittelbar vor dem Löschen:
    /// 1. frische Ordnerliste – vorhanden, wählbar, ohne Unterordner?
    /// 2. STATUS – keine Mails?
    /// 3. erst dann DELETE.
    /// Die Prüfung ist nötig, weil DELETE enthaltene Mails ohne Rückfrage
    /// mitlöscht.
    ///
    /// - Parameters:
    ///   - path: Server-Pfad des Ordners.
    ///   - accountID: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: `.deleted` oder den Grund, warum nicht gelöscht wurde.
    /// - Throws: `MailCredentialError` oder `ActionError` (auch, wenn der
    ///   Server das Löschen ablehnt).
    static func deleteFolder(
        _ path: String,
        accountID: UUID,
        accountStore: AccountStore
    ) async throws -> FolderDeletion.Outcome {
        try await withIMAPConnection(
            accountID: accountID, accountStore: accountStore
        ) { server -> FolderDeletion.Outcome in
            let folders = try await fetchMailboxList(server, includeInbox: true)
            if let blocked = FolderDeletion.precheck(path: path, folders: folders) {
                Log.actions.info("📁 Ordner \(path, privacy: .public) nicht gelöscht: \(String(describing: blocked), privacy: .public)")
                return blocked
            }
            let status = try await server.mailboxStatus(path)
            if let blocked = FolderDeletion.outcome(messageCount: status.messageCount) {
                Log.actions.info("📁 Ordner \(path, privacy: .public) nicht gelöscht: \(String(describing: blocked), privacy: .public)")
                return blocked
            }
            try await server.deleteMailbox(path)
            Log.actions.info("📁 Ordner \(path, privacy: .public) gelöscht")
            return FolderDeletion.Outcome.deleted
        }
    }

    // MARK: - Ordnerliste

    /// Fertiger Ordnerbaum eines Postfachs für die Seitenleiste.
    ///
    /// Verarbeitung: Zugangsdaten auf dem Main-Actor lesen; Abruf, Zerlegen
    /// der Antwort, Speichern im Cache (offline verfügbar) und Aufbau des
    /// Baums laufen im Hintergrund (`loadFolderTree`, v0.2.3d). Bisher
    /// geschah das auf dem Hauptthread – Microhang 373 ms beim Neuaufbau der
    /// Ordnerübersicht nach dem Anlegen eines Ordners (Messung 2).
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
        let credentials = try accountStore.credentials(for: account.id)
        return try await loadFolderTree(credentials, spamFolder: account.spamFolder)
    }

    /// Lädt die Ordnerliste, speichert sie und baut den Baum – im Hintergrund.
    ///
    /// Verarbeitung: Fehler wie in `withIMAPConnection`: an den Nutzer
    /// gerichtete Fehler unverändert, alle anderen als
    /// `ActionError.operationFailed`.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Zugang.
    ///   - spamFolder: Gemerkter Spam-Ordner (für die Rolle im Baum).
    /// - Returns: Wurzelknoten des Ordnerbaums.
    /// - Throws: `UserFacingError` oder `ActionError`.
    @concurrent
    nonisolated private static func loadFolderTree(
        _ credentials: MailCredentials,
        spamFolder: String?
    ) async throws -> [FolderNode] {
        let listing: FolderListing
        do {
            listing = try await MailSession.withIMAP(credentials) { server in
                let folders = try await fetchMailboxList(server, includeInbox: true)
                let prefix = await server.namespaces?.personal.first?.prefix
                return FolderListing(folders: folders, namespacePrefix: prefix)
            }
        } catch let error as any UserFacingError {
            throw error
        } catch {
            throw ActionError.operationFailed(error.localizedDescription)
        }
        MessageStore.shared.saveFolderListing(listing, accountID: credentials.account.id)
        return FolderTreeBuilder.build(listing: listing, configuredSpamFolder: spamFolder)
    }

    /// Gespeicherter Ordnerbaum eines Postfachs (offline), im Hintergrund
    /// gelesen und aufgebaut.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - spamFolder: Gemerkter Spam-Ordner (für die Rolle im Baum).
    /// - Returns: Wurzelknoten; `nil`, wenn keine Ordnerliste gespeichert ist.
    @concurrent
    nonisolated static func cachedFolderTree(accountID: UUID, spamFolder: String?) async -> [FolderNode]? {
        MessageStore.shared.folderListing(accountID: accountID).map {
            FolderTreeBuilder.build(listing: $0, configuredSpamFolder: spamFolder)
        }
    }

    /// Ordnerliste über eine bereits bestehende Verbindung.
    ///
    /// Verarbeitung: Für Abläufe, die ihre Verbindung selbst führen und
    /// die Liste darin brauchen (Spamfilter).
    ///
    /// - Parameter server: Angemeldete IMAP-Verbindung.
    /// - Returns: Ordner ohne INBOX.
    /// - Throws: IMAP-Fehler.
    nonisolated static func mailboxes(on server: SwiftMail.IMAPServer) async throws -> [MailFolder] {
        try await fetchMailboxList(server)
    }

    // MARK: - Interne Helfer

    /// Führt eine Aktion über eine eigene Verbindung aus und vereinheitlicht
    /// die Fehler.
    ///
    /// Verarbeitung: Fehlende Zugangsdaten und Fehler, deren Meldung sich
    /// an den Nutzer richtet (`UserFacingError`), werden unverändert
    /// weitergegeben; alle anderen Fehler werden zu
    /// `ActionError.operationFailed`.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    ///   - body: Aktion auf der angemeldeten Verbindung.
    /// - Returns: Ergebnis von `body`.
    /// - Throws: `MailCredentialError`, `UserFacingError` oder `ActionError`.
    private static func withIMAPConnection<T>(
        accountID: UUID,
        accountStore: AccountStore,
        body: (SwiftMail.IMAPServer) async throws -> T
    ) async throws -> T {
        let credentials = try accountStore.credentials(for: accountID)
        do {
            return try await MailSession.withIMAP(credentials, body)
        } catch let error as any UserFacingError {
            throw error
        } catch {
            throw ActionError.operationFailed(error.localizedDescription)
        }
    }

    /// Listet alle Ordner des Servers.
    ///
    /// Verarbeitung: Anzeigename ist das letzte Pfadsegment. Meldet der
    /// Server kein Trennzeichen, ist die Hierarchie flach und der ganze
    /// Pfad der Name – ein Trennzeichen wird nicht geraten. SPECIAL-USE-
    /// Attribute werden übernommen, ebenso `\Noselect` (nicht auswählbar).
    /// Sonderordner stehen zuerst, danach alphabetisch.
    ///
    /// - Parameters:
    ///   - server: Angemeldete IMAP-Verbindung.
    ///   - includeInbox: `true` = INBOX mitliefern (Ordnerbaum); sonst
    ///     wird sie ausgelassen (Verschiebeziele, Papierkorb-Suche).
    /// - Returns: Ordner des Postfachs.
    /// - Throws: IMAP-Fehler.
    nonisolated private static func fetchMailboxList(
        _ server: SwiftMail.IMAPServer,
        includeInbox: Bool = false
    ) async throws -> [MailFolder] {
        let mailboxes = try await server.listMailboxes(wildcard: "*")

        return mailboxes.compactMap { (mailbox) -> MailFolder? in
            let fullPath = mailbox.name
            if !includeInbox && MailFolder.isInbox(fullPath) { return nil }

            let displayName: String
            if let delimiter = mailbox.hierarchyDelimiter, !delimiter.isEmpty {
                displayName = fullPath.components(separatedBy: delimiter).last ?? fullPath
            } else {
                displayName = fullPath
            }

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
