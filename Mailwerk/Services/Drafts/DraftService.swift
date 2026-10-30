//
//  DraftService.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 13.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Legt einen Entwurf im Ordner „Entwürfe“ des Absende-Postfachs ab
//  (IMAP APPEND mit den Kennzeichen „Entwurf“ und „gelesen“) und legt den
//  Ordner auf Wunsch an, wenn das Postfach keinen hat.
//
//  Der Entwurf wird wie eine versandfertige Mail gebaut (gleiche Teile,
//  Anhänge und eingebettete Bilder, Threading-Kopfzeilen) und trägt die
//  Bcc-Empfänger als Kopfzeile. Empfänger dürfen fehlen.
//
//  Ordnersuche: bevorzugt SPECIAL-USE `\Drafts`, sonst gängige Namen
//  („Drafts“, „Entwürfe“ …). Fehlt der Ordner, wird
//  `DraftError.draftsFolderMissing` geworfen; die Oberfläche fragt dann
//  nach und ruft `createDraftsFolder` auf.
//
//  Weiterbearbeiten: Wird ein Entwurf gesendet oder neu gesichert,
//  entfernt `removeDraft` die alte Fassung endgültig (UID EXPUNGE, nicht
//  über den Papierkorb) und aus dem Cache.
//
//  Abgrenzung: Inhalt und Marken des Entwurfs → DraftFormat,
//  ComposeViewModel; Bau der Nachricht → MailSendService.
//
//  Abhängigkeiten: SwiftMail, MailSendService (makeEmail, Bcc-Header),
//  MailSession, MailActionService (Ordner anlegen), DraftFormat,
//  MailboxNameCodec, MailboxListing (Ordnerliste), MessageStore (Cache), Log.
//

import Foundation
import SwiftMail
import os

/// Ablage von Entwürfen auf dem Server.
enum DraftService {

    /// Fehler beim Sichern eines Entwurfs.
    enum DraftError: LocalizedError, Equatable {
        /// Die Absenderadresse des Postfachs ist ungültig.
        case invalidSender(String)
        /// Das Postfach hat keinen Entwürfe-Ordner.
        case draftsFolderMissing

        /// Liefert die deutsche Meldung für den Nutzer.
        ///
        /// - Returns: Meldungstext.
        var errorDescription: String? {
            switch self {
            case .invalidSender(let address):
                return "Die Absenderadresse „\(address)“ ist ungültig. Bitte die E-Mail-Adresse des Postfachs prüfen."
            case .draftsFolderMissing:
                return "Das Postfach hat keinen Ordner für Entwürfe."
            }
        }
    }

    /// Ergebnis einer Ablage.
    struct SaveResult: Equatable {
        /// Server-Pfad des Entwürfe-Ordners.
        let folder: String
        /// UID des abgelegten Entwurfs, sofern der Server sie meldet (UIDPLUS).
        let uid: UInt32?
    }

    /// Legt eine verfasste Nachricht als Entwurf ab.
    ///
    /// Verarbeitung: Baut die Nachricht wie beim Versand, ergänzt den
    /// Bcc-Header, sucht den Entwürfe-Ordner und legt sie dort mit
    /// `\Draft` und `\Seen` ab.
    ///
    /// - Parameters:
    ///   - mail: Verfasste Nachricht (HTML mit Entwurfs-Marken).
    ///   - accountStore: Quelle für Postfach und Passwort.
    /// - Returns: Ordner und UID des Entwurfs.
    /// - Throws: `MailCredentialError`, `DraftError` oder Verbindungsfehler.
    static func save(_ mail: OutgoingMail, accountStore: AccountStore) async throws -> SaveResult {
        let credentials = try accountStore.credentials(for: mail.accountID)
        let account = credentials.account
        let senderAddress = account.senderAddress
        guard senderAddress.isValidEmail() else { throw DraftError.invalidSender(senderAddress) }

        let email = MailSendService.addingBccHeader(
            MailSendService.makeEmail(mail, account: account, senderAddress: senderAddress),
            bcc: mail.bcc
        )

        return try await MailSession.withIMAP(credentials) { imap in
            let folder = try await draftsFolderPath(imap)
            let result = try await imap.append(email: email, to: folder, flags: [.draft, .seen])
            Log.send.info("📝 [\(account.displayName, privacy: .private)] Entwurf abgelegt in \(folder, privacy: .public)")
            return SaveResult(folder: folder, uid: result.firstUID?.value)
        }
    }

    /// Entfernt eine alte Fassung eines Entwurfs endgültig – auf dem Server
    /// und im Cache.
    ///
    /// Verarbeitung: Wird nach dem Senden oder erneuten Sichern eines
    /// weiterbearbeiteten Entwurfs aufgerufen. Die alte Fassung wird im
    /// Entwürfe-Ordner mit `\Deleted` markiert und gezielt per UID EXPUNGE
    /// entfernt – nicht über den Papierkorb, andere Mails des Ordners
    /// bleiben unberührt. Kennt der Server UID EXPUNGE nicht (UIDPLUS fehlt),
    /// entfernt ein einfaches EXPUNGE alle markierten Mails des Ordners; im
    /// Entwürfe-Ordner sind das nur zum Löschen vorgesehene. Danach wird
    /// die Fassung aus dem Cache gelöscht.
    ///
    /// - Parameters:
    ///   - draft: Alte Fassung aus dem Cache (Postfach, Ordner, UID).
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Throws: `MailCredentialError` oder Verbindungs- und IMAP-Fehler.
    static func removeDraft(_ draft: CachedMessage, accountStore: AccountStore) async throws {
        let credentials = try accountStore.credentials(for: draft.accountID)
        let set = UIDSet([SwiftMail.UID(draft.uid)])
        try await MailSession.withIMAP(credentials) { imap in
            _ = try await imap.selectMailbox(draft.folder)
            try await imap.store(flags: [SwiftMail.Flag.deleted], on: set, operation: .add)
            do {
                try await imap.expunge(messages: set)
            } catch SwiftMail.IMAPError.commandNotSupported(_) {
                try await imap.expunge()
            }
        }
        MessageStore.shared.deleteMessage(id: draft.id)
        Log.send.info("📝 [\(credentials.account.displayName, privacy: .private)] Alte Fassung des Entwurfs entfernt aus \(draft.folder, privacy: .public)")
    }

    /// Legt den Entwürfe-Ordner an (Name „Drafts“, Mailwerk zeigt ihn als „Entwürfe“).
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: Server-Pfad des neuen Ordners.
    /// - Throws: Fehler beim Anlegen.
    @discardableResult
    static func createDraftsFolder(accountID: UUID, accountStore: AccountStore) async throws -> String {
        try await MailActionService.createFolder(
            named: DraftFormat.newDraftsFolderName,
            parentPath: nil,
            accountID: accountID,
            accountStore: accountStore
        )
    }

    /// Ermittelt den Entwürfe-Ordner des Postfachs.
    ///
    /// Verarbeitung: Bevorzugt SPECIAL-USE `\Drafts`, sonst das letzte
    /// Pfadsegment unter den gängigen Namen (lesbar dekodiert, ohne
    /// Groß-/Kleinschreibung – so wird auch „Entwürfe“ gefunden).
    ///
    /// - Parameter imap: Angemeldete IMAP-Verbindung.
    /// - Returns: Server-Pfad des Ordners.
    /// - Throws: Verbindungsfehler oder `DraftError.draftsFolderMissing`.
    private static func draftsFolderPath(_ imap: IMAPServer) async throws -> String {
        let mailboxes = try await imap.listMailboxes(wildcard: "*")
        let entries = mailboxes.map { mailbox in
            MailboxListing.Entry(
                path: mailbox.name,
                delimiter: mailbox.hierarchyDelimiter,
                specialUse: mailbox.attributes.contains(.drafts) ? .drafts : nil,
                isSelectable: mailbox.isSelectable
            )
        }
        guard let path = draftsFolder(in: entries) else { throw DraftError.draftsFolderMissing }
        return path
    }

    /// Bestimmt den Entwürfe-Ordner aus der Ordnerliste.
    ///
    /// Verarbeitung: Zuerst der Ordner mit SPECIAL-USE `\Drafts`; meldet
    /// der Server keinen, ein Ordner mit einem bekannten Namen
    /// (`DraftFormat.draftsFolderNames`, letztes Pfadsegment, dekodiert,
    /// ohne Groß-/Kleinschreibung).
    ///
    /// - Parameter entries: Ordner laut Server.
    /// - Returns: Server-Pfad oder `nil`, wenn keiner passt.
    static func draftsFolder(in entries: [MailboxListing.Entry]) -> String? {
        if let drafts = entries.first(where: { $0.specialUse == .drafts }) {
            return drafts.path
        }
        return entries.first { entry in
            let lastSegment = MailboxListing.displayName(path: entry.path, delimiter: entry.delimiter)
            let readable = MailboxNameCodec.displayName(lastSegment)
            return DraftFormat.draftsFolderNames.contains(readable.lowercased())
        }?.path
    }
}
