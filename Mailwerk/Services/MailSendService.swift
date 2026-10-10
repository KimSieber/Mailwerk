//
//  MailSendService.swift
//  Mailwerk
//
//  Zweck: Versendet eine verfasste Nachricht und erledigt die Nacharbeiten
//  auf dem Server.
//
//  Ablauf in drei Schritten:
//  1. SMTP-Versand (verschlüsselt über MailServerFactory). Schlägt dieser
//     Schritt fehl, wird ein Fehler geworfen – die Nachricht ist NICHT raus.
//  2. Kopie im Gesendet-Ordner ablegen (IMAP APPEND, inkl. Bcc-Header).
//  3. Originalnachricht als beantwortet (\Answered) bzw. weitergeleitet
//     ($Forwarded) markieren – auf dem Server und im lokalen Cache. Die
//     Markierung erfolgt in dem Ordner, in dem die Originalnachricht liegt;
//     UIDs sind nur innerhalb eines Ordners eindeutig.
//
//  Die Schritte 2 und 3 laufen erst nach erfolgreichem Versand. Scheitern sie,
//  ist die Nachricht trotzdem gesendet – das Ergebnis enthält dann Warnungen
//  statt eines Fehlers, damit der Nutzer nicht fälschlich erneut sendet.
//  Versendete Nachricht und Gesendet-Kopie tragen dieselbe Message-ID.
//
//  Abgrenzung: Zusammenstellen des Inhalts (Zitat, HTML, Anhänge) erledigt
//  der ComposeViewModel; hier wird nur geprüft, versendet und nachgearbeitet.
//
//  Abhängigkeiten: SwiftMail (SMTP/IMAP), MailServerFactory (TLS-Vorgaben
//  für SMTP), MailSession (IMAP-Verbindung und Zugangsdaten), AccountStore,
//  MessageStore (Cache-Markierung).
//

import Foundation
import SwiftMail

/// Ein Anhang, der mitgesendet wird.
struct OutgoingAttachment: Equatable {
    /// Dateiname, wie er beim Empfänger erscheint.
    let filename: String
    /// MIME-Typ, z. B. "application/pdf".
    let mimeType: String
    /// Inhalt des Anhangs.
    let data: Data
}

/// Eine versandfertige Nachricht.
struct OutgoingMail {
    /// Absende-Postfach.
    var accountID: UUID
    /// Empfänger (To).
    var to: [MailAddress]
    /// Kopie-Empfänger (Cc).
    var cc: [MailAddress] = []
    /// Blindkopie-Empfänger (Bcc); erscheinen nur in der eigenen Gesendet-Kopie.
    var bcc: [MailAddress] = []
    /// Betreff.
    var subject: String
    /// Vollständiger HTML-Body inkl. Zitat bzw. weitergeleitetem Inhalt.
    var htmlBody: String
    /// Nur-Text-Alternative desselben Inhalts.
    var textBody: String
    /// Mitzusendende Anhänge.
    var attachments: [OutgoingAttachment] = []
    /// Message-ID der beantworteten Nachricht (Header In-Reply-To).
    var inReplyTo: String?
    /// References-Kette für das Threading beim Empfänger.
    var references: String?
    /// Bezugsnachricht, die nach dem Versand markiert wird.
    var origin: Origin?

    /// Bezug auf die Originalnachricht einer Antwort oder Weiterleitung.
    /// Enthält alles, um genau diese Nachricht auf dem Server und im Cache
    /// wiederzufinden.
    struct Origin: Equatable {
        /// Art der Markierung nach dem Versand.
        enum Kind: Equatable { case replied, forwarded }

        /// Beantwortet oder weitergeleitet.
        let kind: Kind
        /// Kennung im lokalen Cache (`CachedMessage.id`).
        let cachedMessageID: String
        /// Postfach der Originalmail (kann vom Absende-Postfach abweichen).
        let accountID: UUID
        /// IMAP-Ordner der Originalmail. Pflicht, weil die UID nur
        /// innerhalb dieses Ordners eindeutig ist.
        let folder: String
        /// UID der Originalmail im Ordner `folder`.
        let uid: UInt32
    }
}

extension OutgoingMail.Origin {
    /// Bildet den Bezug auf die Originalnachricht aus der Art des Verfassens.
    ///
    /// Verarbeitung: Antworten und Allen antworten ergeben `.replied`,
    /// Weiterleiten `.forwarded`. Postfach, Ordner und UID werden aus der
    /// Originalnachricht übernommen. Eine neue Mail hat keinen Bezug.
    ///
    /// - Parameters:
    ///   - composeKind: Art des Verfassens (neu, antworten, weiterleiten).
    ///   - original: Originalnachricht aus dem Cache; `nil` bei neuer Mail.
    /// - Returns: Der Bezug, oder `nil` bei neuer Mail bzw. ohne Original.
    init?(composeKind: ComposeKind, original: CachedMessage?) {
        guard let original else { return nil }
        let kind: Kind
        switch composeKind {
        case .reply, .replyAll: kind = .replied
        case .forward: kind = .forwarded
        case .new: return nil
        }
        self.init(
            kind: kind,
            cachedMessageID: original.id,
            accountID: original.accountID,
            folder: original.folder,
            uid: original.uid
        )
    }
}

/// Ergebnis eines erfolgreichen Versands.
struct SendReport: Equatable {
    /// Ordner, in dem die Gesendet-Kopie abgelegt wurde (nil = nicht abgelegt).
    var sentCopyFolder: String?
    /// Hinweise zu Nacharbeiten, die nach dem Versand nicht geklappt haben.
    var warnings: [String] = []
}

enum MailSendService {

    // MARK: - Fehler

    /// Fehler, bei denen die Nachricht nicht (sicher) versendet wurde.
    enum SendError: LocalizedError, Equatable {
        case invalidSender(String)
        case noRecipients
        case invalidRecipient(String)
        case messageTooLarge(size: Int, limit: Int)
        case rejected(String)
        case uncertain(String)
        case failed(String)

        /// Liefert die deutsche Meldung für den Nutzer.
        ///
        /// Verarbeitung: Ordnet jedem Fall einen verständlichen Text zu.
        /// `uncertain` weist ausdrücklich darauf hin, vor einem erneuten
        /// Versand zu prüfen, ob die Nachricht schon raus ist.
        ///
        /// - Returns: Meldungstext für die Anzeige.
        var errorDescription: String? {
            switch self {
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

        /// Formatiert eine Bytezahl als lesbare Größe.
        ///
        /// - Parameter bytes: Größe in Bytes.
        /// - Returns: Größe mit Einheit, z. B. "12,3 MB".
        private static func megabytes(_ bytes: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

    /// Fehler der Nacharbeiten nach dem Versand; werden zu Warnungen.
    private enum PostSendError: LocalizedError {
        case sentFolderNotFound

        /// Liefert die deutsche Meldung für den Nutzer.
        ///
        /// - Returns: Meldungstext für die Warnung.
        var errorDescription: String? {
            switch self {
            case .sentFolderNotFound:
                return "Auf dem Server wurde kein Gesendet-Ordner gefunden."
            }
        }
    }

    // MARK: - Versand

    /// Versendet eine Nachricht und erledigt anschließend die Nacharbeiten.
    ///
    /// Verarbeitung: Prüft Absender und Empfänger, baut die Nachricht mit
    /// eigener Message-ID, versendet sie per SMTP und legt danach die Kopie
    /// im Gesendet-Ordner ab. Bei Antworten und Weiterleitungen wird zuletzt
    /// die Originalnachricht markiert. Fehler der Nacharbeiten werden als
    /// Warnungen im Ergebnis gemeldet, nicht geworfen.
    ///
    /// - Parameters:
    ///   - mail: Versandfertige Nachricht.
    ///   - accountStore: Quelle für Postfach und Passwort.
    /// - Returns: Ablageort der Gesendet-Kopie und Warnungen.
    /// - Throws: `MailCredentialError`, wenn Postfach oder Passwort fehlen,
    ///   sonst `SendError`, wenn die Nachricht nicht oder nicht sicher
    ///   versendet wurde.
    static func send(_ mail: OutgoingMail, accountStore: AccountStore) async throws -> SendReport {
        let credentials = try accountStore.credentials(for: mail.accountID)
        let account = credentials.account
        let password = credentials.password

        // Absender prüfen – der Benutzername des Postfachs ist die Adresse
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
                email, bcc: mail.bcc, credentials: credentials
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

    /// Baut aus der verfassten Nachricht das SwiftMail-Objekt.
    ///
    /// Verarbeitung: Übernimmt Empfänger, Betreff, Text- und HTML-Teil sowie
    /// Anhänge. Erzeugt eine Message-ID aus der Absenderdomain, die für
    /// Versand und Gesendet-Kopie gleich bleibt, und setzt die
    /// Threading-Header In-Reply-To und References.
    ///
    /// - Parameters:
    ///   - mail: Verfasste Nachricht.
    ///   - account: Absende-Postfach (liefert den Absendernamen).
    ///   - senderAddress: Geprüfte Absenderadresse.
    /// - Returns: Versandfertiges `Email`-Objekt.
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

    /// Versendet die Nachricht per SMTP.
    ///
    /// Verarbeitung: Verbindet verschlüsselt, meldet sich an und prüft vorab
    /// das Größenlimit des Servers, um eine verständliche Meldung geben zu
    /// können. Danach wird versendet und die Verbindung in jedem Fall
    /// geschlossen. SMTP-Fehler werden nach ihrer Wiederholbarkeit in
    /// `rejected`, `uncertain` oder `failed` übersetzt.
    ///
    /// - Parameters:
    ///   - email: Versandfertige Nachricht.
    ///   - account: Absende-Postfach (SMTP-Server, Benutzername).
    ///   - password: Passwort des Postfachs.
    /// - Throws: `SendError` bei jedem Fehlschlag.
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

    /// Legt die versendete Nachricht im Gesendet-Ordner ab.
    ///
    /// Verarbeitung: Ergänzt einen Bcc-Header, damit die Bcc-Empfänger in
    /// der eigenen Kopie sichtbar bleiben, sucht den Gesendet-Ordner und
    /// legt die Kopie dort als gelesen ab (IMAP APPEND).
    ///
    /// - Parameters:
    ///   - email: Versendete Nachricht.
    ///   - bcc: Blindkopie-Empfänger für den Bcc-Header der Kopie.
    ///   - credentials: Absende-Postfach und Passwort.
    /// - Returns: Pfad des Gesendet-Ordners.
    /// - Throws: Verbindungsfehler oder `PostSendError.sentFolderNotFound`.
    private static func saveSentCopy(
        _ email: Email,
        bcc: [MailAddress],
        credentials: MailCredentials
    ) async throws -> String {
        var copy = email
        if !bcc.isEmpty {
            var headers = copy.additionalHeaders ?? [:]
            headers["Bcc"] = bcc.map { $0.emailAddress.description }.joined(separator: ", ")
            copy.additionalHeaders = headers
        }

        return try await MailSession.withIMAP(credentials) { imap in
            let folder = try await sentFolderPath(imap)
            try await imap.append(email: copy, to: folder, flags: [SwiftMail.Flag.seen])
            print("📤 [\(credentials.account.displayName)] Kopie abgelegt in \(folder)")
            return folder
        }
    }

    /// Ermittelt den Gesendet-Ordner des Postfachs.
    ///
    /// Verarbeitung: Bevorzugt den Ordner mit dem SPECIAL-USE-Attribut
    /// `\Sent`. Fehlt es, wird über gängige deutsche und englische
    /// Ordnernamen gesucht (letztes Segment des Pfads, ohne Groß-/Kleinschreibung).
    ///
    /// - Parameter imap: Angemeldete IMAP-Verbindung.
    /// - Returns: Vollständiger Pfad des Gesendet-Ordners.
    /// - Throws: Verbindungsfehler oder `PostSendError.sentFolderNotFound`.
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

    /// Markiert die Originalnachricht als beantwortet bzw. weitergeleitet.
    ///
    /// Verarbeitung: Meldet sich am Postfach der Originalnachricht an (es
    /// kann vom Absende-Postfach abweichen), wählt **deren Ordner** und setzt
    /// dort `\Answered` bzw. `$Forwarded` auf die UID. Danach wird der
    /// lokale Cache entsprechend aktualisiert.
    ///
    /// - Parameters:
    ///   - origin: Bezug auf die Originalnachricht (Postfach, Ordner, UID).
    ///   - accountStore: Quelle für Postfach und Passwort.
    /// - Throws: `MailCredentialError` oder Verbindungsfehler.
    private static func markOriginal(
        _ origin: OutgoingMail.Origin,
        accountStore: AccountStore
    ) async throws {
        let credentials = try accountStore.credentials(for: origin.accountID)
        let flag: SwiftMail.Flag = origin.kind == .replied
            ? .answered
            : .custom(MailFetchService.forwardedKeyword)

        try await MailSession.withIMAP(credentials) { imap in
            _ = try await imap.selectMailbox(origin.folder)
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
}
