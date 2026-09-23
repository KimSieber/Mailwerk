//
//  OutgoingAttachment.swift
//  Mailwerk
//
//  Created by Kim Sieber on 21.09.26.
//


//
//  MailSendService.swift
//  Mailwerk
//
//  Versand einer Nachricht in drei Schritten:
//
//  1. SMTP-Versand (verschlüsselt über MailServerFactory). Schlägt dieser
//     Schritt fehl, wird ein Fehler geworfen – die Nachricht ist NICHT raus.
//  2. Kopie im Gesendet-Ordner ablegen (IMAP APPEND, inkl. Bcc-Header).
//  3. Originalnachricht als beantwortet (\Answered) bzw. weitergeleitet
//     ($Forwarded) markieren – auf dem Server und im lokalen Cache.
//
//  Die Schritte 2 und 3 laufen erst nach erfolgreichem Versand. Scheitern sie,
//  ist die Nachricht trotzdem gesendet – das Ergebnis enthält dann Warnungen
//  statt eines Fehlers, damit der Nutzer nicht fälschlich erneut sendet.
//
//  Versendete Nachricht und Gesendet-Kopie tragen dieselbe Message-ID.
//

import Foundation
import SwiftMail

/// Ein Anhang, der mitgesendet wird.
struct OutgoingAttachment: Equatable {
    let filename: String
    let mimeType: String
    let data: Data
}

/// Eine versandfertige Nachricht.
struct OutgoingMail {
    var accountID: UUID
    var to: [MailAddress]
    var cc: [MailAddress] = []
    var bcc: [MailAddress] = []
    var subject: String
    /// Vollständiger HTML-Body inkl. Zitat bzw. weitergeleitetem Inhalt
    var htmlBody: String
    /// Nur-Text-Alternative desselben Inhalts
    var textBody: String
    var attachments: [OutgoingAttachment] = []
    var inReplyTo: String?
    var references: String?
    /// Bezugsnachricht, die nach dem Versand markiert wird
    var origin: Origin?

    struct Origin: Equatable {
        enum Kind: Equatable { case replied, forwarded }
        let kind: Kind
        let cachedMessageID: String     // CachedMessage.id
        let accountID: UUID             // Postfach der Originalmail (kann vom Absende-Postfach abweichen)
        let uid: UInt32
    }
}

/// Ergebnis eines erfolgreichen Versands.
struct SendReport: Equatable {
    /// Ordner, in dem die Gesendet-Kopie abgelegt wurde (nil = nicht abgelegt)
    var sentCopyFolder: String?
    /// Hinweise zu Nacharbeiten, die nach dem Versand nicht geklappt haben
    var warnings: [String] = []
}

enum MailSendService {

    // MARK: - Fehler

    enum SendError: LocalizedError, Equatable {
        case accountNotFound
        case noPassword
        case invalidSender(String)
        case noRecipients
        case invalidRecipient(String)
        case messageTooLarge(size: Int, limit: Int)
        case rejected(String)
        case uncertain(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .accountNotFound:
                return "Das Absende-Postfach wurde nicht gefunden."
            case .noPassword:
                return "Für das Absende-Postfach ist kein Passwort gespeichert."
            case .invalidSender(let address):
                return "Die Absenderadresse „\(address)“ ist ungültig. Bitte den Benutzernamen des Postfachs prüfen."
            case .noRecipients:
                return "Bitte mindestens einen Empfänger angeben."
            case .invalidRecipient(let address):
                return "Die Empfängeradresse „\(address)“ ist ungültig."
            case .messageTooLarge(let size, let limit):
                return "Die Nachricht ist mit \(Self.megabytes(size)) zu groß. Der Server erlaubt höchstens \(Self.megabytes(limit))."
            case .rejected(let detail):
                return "Der Server hat die Nachricht abgelehnt: \(detail)"
            case .uncertain(let detail):
                return "Es ist unklar, ob die Nachricht versendet wurde (\(detail)). Bitte vor einem erneuten Versand im Gesendet-Ordner oder beim Empfänger prüfen."
            case .failed(let detail):
                return "Versand fehlgeschlagen: \(detail)"
            }
        }

        private static func megabytes(_ bytes: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

    private enum PostSendError: LocalizedError {
        case sentFolderNotFound

        var errorDescription: String? {
            switch self {
            case .sentFolderNotFound:
                return "Auf dem Server wurde kein Gesendet-Ordner gefunden."
            }
        }
    }

    // MARK: - Versand

    static func send(_ mail: OutgoingMail, accountStore: AccountStore) async throws -> SendReport {
        let (account, password) = try credentials(for: mail.accountID, in: accountStore)

        // Absender prüfen – bei manitu ist der Benutzername die Adresse
        let senderAddress = account.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard senderAddress.isValidEmail() else {
            throw SendError.invalidSender(senderAddress)
        }

        // Empfänger prüfen
        let allRecipients = mail.to + mail.cc + mail.bcc
        guard !allRecipients.isEmpty else { throw SendError.noRecipients }
        if let invalid = allRecipients.first(where: { !$0.isValid }) {
            throw SendError.invalidRecipient(invalid.address)
        }

        let email = makeEmail(mail, account: account, senderAddress: senderAddress)

        // 1. Versand – Fehler brechen hier ab
        try await submit(email, account: account, password: password)
        print("✉️ [\(account.displayName)] Nachricht versendet: \(email.messageID?.description ?? "-")")

        // 2. + 3. Nacharbeiten – Fehler werden zu Warnungen
        var report = SendReport()
        do {
            report.sentCopyFolder = try await saveSentCopy(
                email, bcc: mail.bcc, account: account, password: password
            )
        } catch {
            report.warnings.append(
                "Die Nachricht wurde gesendet, die Kopie konnte aber nicht im Gesendet-Ordner abgelegt werden: \(error.localizedDescription)"
            )
        }

        if let origin = mail.origin {
            do {
                try await markOriginal(origin, accountStore: accountStore)
            } catch {
                let what = origin.kind == .replied ? "beantwortet" : "weitergeleitet"
                report.warnings.append(
                    "Die Nachricht wurde gesendet, die Originalnachricht konnte aber nicht als \(what) markiert werden: \(error.localizedDescription)"
                )
            }
        }
        return report
    }

    // MARK: - Nachricht aufbauen

    private static func makeEmail(
        _ mail: OutgoingMail,
        account: MailAccount,
        senderAddress: String
    ) -> Email {
        let attachments = mail.attachments.map {
            SwiftMail.Attachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
        }
        var email = Email(
            sender: SwiftMail.EmailAddress(name: account.senderName, address: senderAddress),
            recipients: mail.to.map(\.emailAddress),
            ccRecipients: mail.cc.map(\.emailAddress),
            bccRecipients: mail.bcc.map(\.emailAddress),
            subject: mail.subject,
            textBody: mail.textBody,
            htmlBody: mail.htmlBody,
            attachments: attachments.isEmpty ? nil : attachments
        )

        // Eine Message-ID für Versand UND Gesendet-Kopie
        let domain = senderAddress.split(separator: "@").last.map(String.init) ?? "localhost"
        email.messageID = MessageID.generate(domain: domain)

        var headers: [String: String] = [:]
        if let inReplyTo = mail.inReplyTo { headers["In-Reply-To"] = inReplyTo }
        if let references = mail.references { headers["References"] = references }
        email.additionalHeaders = headers.isEmpty ? nil : headers
        return email
    }

    // MARK: - 1. SMTP

    private static func submit(_ email: Email, account: MailAccount, password: String) async throws {
        let smtp = MailServerFactory.smtpServer(for: account)
        do {
            try await smtp.connect()
            try await smtp.login(username: account.username, password: password)

            // Größenlimit des Servers vorab prüfen → verständliche Meldung
            if let limit = await smtp.maximumMessageSizeOctets, limit > 0 {
                let use8Bit = await smtp.supports8BitMIME
                let size = email.constructContent(use8BitMIME: use8Bit).utf8.count
                if size > limit {
                    throw SendError.messageTooLarge(size: size, limit: limit)
                }
            }

            _ = try await smtp.sendEmail(email)
            try? await smtp.disconnect()
        } catch let error as SendError {
            try? await smtp.disconnect()
            throw error
        } catch let error as SMTPSendError {
            try? await smtp.disconnect()
            switch error.retryDisposition {
            case .permanent:
                let detail = error.response.map { "\($0.code) \($0.message)" } ?? error.localizedDescription
                throw SendError.rejected(detail)
            case .unsafeToRetry:
                throw SendError.uncertain(error.localizedDescription)
            case .retryable:
                throw SendError.failed(error.localizedDescription)
            }
        } catch {
            try? await smtp.disconnect()
            throw SendError.failed(error.localizedDescription)
        }
    }

    // MARK: - 2. Gesendet-Kopie

    /// Legt die Nachricht (mit Bcc-Header, damit die Bcc-Empfänger in der
    /// eigenen Kopie sichtbar bleiben) gelesen im Gesendet-Ordner ab.
    /// - Returns: Pfad des Gesendet-Ordners
    private static func saveSentCopy(
        _ email: Email,
        bcc: [MailAddress],
        account: MailAccount,
        password: String
    ) async throws -> String {
        var copy = email
        if !bcc.isEmpty {
            var headers = copy.additionalHeaders ?? [:]
            headers["Bcc"] = bcc.map { $0.emailAddress.description }.joined(separator: ", ")
            copy.additionalHeaders = headers
        }

        return try await withIMAP(account: account, password: password) { imap in
            let folder = try await sentFolderPath(imap)
            try await imap.append(email: copy, to: folder, flags: [SwiftMail.Flag.seen])
            print("📤 [\(account.displayName)] Kopie abgelegt in \(folder)")
            return folder
        }
    }

    /// Gesendet-Ordner: bevorzugt über das SPECIAL-USE-Attribut \Sent,
    /// sonst über gängige Ordnernamen.
    private static func sentFolderPath(_ imap: IMAPServer) async throws -> String {
        let mailboxes = try await imap.listMailboxes(wildcard: "*")

        if let sent = mailboxes.first(where: { $0.attributes.contains(.sent) }) {
            return sent.name
        }

        let knownNames: Set<String> = [
            "sent", "sent items", "sent messages", "sent mail",
            "gesendet", "gesendete objekte", "gesendete elemente", "gesendete nachrichten"
        ]
        let byName = mailboxes.first { mailbox in
            let lastSegment = mailbox.hierarchyDelimiter
                .flatMap { mailbox.name.components(separatedBy: $0).last } ?? mailbox.name
            return knownNames.contains(lastSegment.lowercased())
        }
        guard let byName else { throw PostSendError.sentFolderNotFound }
        return byName.name
    }

    // MARK: - 3. Original markieren

    private static func markOriginal(
        _ origin: OutgoingMail.Origin,
        accountStore: AccountStore
    ) async throws {
        // Das Original kann in einem anderen Postfach liegen als dem Absende-Postfach
        let (account, password) = try credentials(for: origin.accountID, in: accountStore)
        let flag: SwiftMail.Flag = origin.kind == .replied
            ? .answered
            : .custom(MailFetchService.forwardedKeyword)

        try await withIMAP(account: account, password: password) { imap in
            _ = try await imap.selectMailbox("INBOX")
            let uidSet = SwiftMail.UIDSet([SwiftMail.UID(origin.uid)])
            try await imap.store(flags: [flag], on: uidSet, operation: .add)
        }

        switch origin.kind {
        case .replied:
            MessageStore.shared.updateAnswered(messageID: origin.cachedMessageID, isAnswered: true)
        case .forwarded:
            MessageStore.shared.updateForwarded(messageID: origin.cachedMessageID, isForwarded: true)
        }
    }

    // MARK: - Helfer

    private static func credentials(
        for accountID: UUID,
        in accountStore: AccountStore
    ) throws -> (MailAccount, String) {
        guard let account = accountStore.accounts.first(where: { $0.id == accountID }) else {
            throw SendError.accountNotFound
        }
        guard let password = try accountStore.password(for: account) else {
            throw SendError.noPassword
        }
        return (account, password)
    }

    /// Baut eine (verschlüsselte) IMAP-Verbindung auf, führt `body` aus und
    /// schließt die Verbindung in jedem Fall wieder.
    private static func withIMAP<T>(
        account: MailAccount,
        password: String,
        _ body: (IMAPServer) async throws -> T
    ) async throws -> T {
        let imap = MailServerFactory.imapServer(for: account)
        do {
            try await imap.connect()
            try await imap.login(username: account.username, password: password)
            let result = try await body(imap)
            try await imap.logout()
            return result
        } catch {
            try? await imap.disconnect()
            throw error
        }
    }
}