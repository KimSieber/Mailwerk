//
//  ComposeViewModel.swift
//  Mailwerk
//
//  Zustand und Ablauf des Verfassen-Fensters: Vorbelegung über den
//  ReplyBuilder, Anhänge, Zusammenbau von HTML- und Textteil, Versand
//  über den MailSendService.
//

import Foundation
import Observation

@Observable
final class ComposeViewModel {

    // MARK: Eingaben

    var accountID: UUID?
    var to: [MailAddress] = []
    var cc: [MailAddress] = []
    var bcc: [MailAddress] = []
    var showBcc = false
    var subject = ""
    var body = NSAttributedString(string: "", attributes: RichTextController.defaultAttributes)
    var attachments: [OutgoingAttachment] = []

    // MARK: Zustand

    var isSending = false
    var statusText: String?
    var errorMessage: String?
    /// Hinweise nach erfolgreichem Versand (z. B. Kopie nicht abgelegt)
    var warnings: [String] = []

    // MARK: Bezug zur Originalmail

    let kind: ComposeKind
    private let original: CachedMessage?
    private let accountStore: AccountStore
    private(set) var quotedHTML: String?
    private(set) var quotedText: String?
    private var inReplyTo: String?
    private var references: String?

    let controller = RichTextController()

    init(accountStore: AccountStore, kind: ComposeKind, original: CachedMessage? = nil) {
        self.accountStore = accountStore
        self.kind = kind
        self.original = original

        // Nur die Adresse des antwortenden Postfachs entfällt bei „Allen
        // antworten" – andere eigene Postfächer bleiben als Empfänger stehen.
        let replyingAccountID = original?.accountID ?? accountStore.defaultAccountID
        let ownAddress = accountStore.accounts
            .first { $0.id == replyingAccountID }?
            .username
            .lowercased()
        let ownAddresses = Set([ownAddress].compactMap { $0 })

        let prefill = ReplyBuilder.prefill(
            kind: kind,
            original: original,
            defaultAccountID: accountStore.defaultAccountID,
            ownAddresses: ownAddresses
        )
        accountID = prefill.accountID
        to = prefill.to
        cc = prefill.cc
        subject = prefill.subject
        quotedHTML = prefill.quotedHTML
        quotedText = prefill.quotedText
        inReplyTo = prefill.inReplyTo
        references = prefill.references

        // Aus der Vorbelegung bilden, nicht aus den Eigenschaften: im
        // Initialisierer darf noch nicht aus self gelesen werden.
        initialState = State(
            to: prefill.to,
            cc: prefill.cc,
            bcc: [],
            subject: prefill.subject,
            attachmentCount: 0
        )

        if kind == .forward, let original {
            // Anhänge der Originalmail übernehmen; fehlende Daten werden
            // erst beim Senden nachgeladen.
            pendingOriginalAttachments = MessageStore.shared.attachments(forMessage: original.id)
            attachments = pendingOriginalAttachments.compactMap { attachment in
                guard let data = attachment.data else { return nil }
                return OutgoingAttachment(
                    filename: attachment.filename,
                    mimeType: attachment.contentType,
                    data: data
                )
            }
            initialState = State(
                to: to, cc: cc, bcc: bcc,
                subject: subject, attachmentCount: attachments.count
            )
        }
    }

    // MARK: - Änderungserkennung

    /// Ausgangszustand nach der Vorbelegung – dient dem Vergleich beim Abbrechen.
    private struct State: Equatable {
        let to: [MailAddress]
        let cc: [MailAddress]
        let bcc: [MailAddress]
        let subject: String
        let attachmentCount: Int
    }

    private var initialState: State

    private var currentState: State {
        State(to: to, cc: cc, bcc: bcc, subject: subject, attachmentCount: attachments.count)
    }

    /// Anhänge der weitergeleiteten Mail (inkl. noch nicht geladener).
    private var pendingOriginalAttachments: [CachedAttachment] = []

    // MARK: - Abgeleitete Werte

    var accounts: [MailAccount] { accountStore.accounts }

    var selectedAccount: MailAccount? {
        guard let accountID else { return nil }
        return accountStore.accounts.first { $0.id == accountID }
    }

    var canSend: Bool {
        accountID != nil && !to.isEmpty && !isSending
    }

    /// true, wenn der Nutzer etwas geändert hat, das beim Abbrechen verloren
    /// ginge. Eine reine Vorbelegung (Antworten, Weiterleiten) zählt nicht.
    var hasContent: Bool {
        body.length > 0 || currentState != initialState
    }

    var totalAttachmentBytes: Int {
        attachments.reduce(0) { $0 + $1.data.count }
    }

    /// Noch nicht geladene Anhänge der weitergeleiteten Mail.
    var missingAttachmentCount: Int {
        guard kind == .forward else { return 0 }
        return pendingOriginalAttachments.filter { $0.data == nil }.count
    }

    // MARK: - Anhänge

    func addAttachment(filename: String, mimeType: String, data: Data) {
        attachments.append(
            OutgoingAttachment(filename: filename, mimeType: mimeType, data: data)
        )
    }

    func removeAttachment(_ attachment: OutgoingAttachment) {
        attachments.removeAll { $0 == attachment }
    }

    // MARK: - Versand

    /// - Returns: true, wenn versendet wurde und das Fenster geschlossen werden kann.
    @MainActor
    func send() async -> Bool {
        guard let accountID else { return false }
        isSending = true
        defer { isSending = false; statusText = nil }

        // Fehlende Anhänge der Originalmail nachladen
        if missingAttachmentCount > 0 {
            statusText = "Anhänge werden geladen …"
            if !(await loadMissingAttachments()) { return false }
        }

        statusText = "Nachricht wird gesendet …"
        let mail = OutgoingMail(
            accountID: accountID,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            htmlBody: composedHTML(),
            textBody: composedText(),
            attachments: attachments,
            inReplyTo: inReplyTo,
            references: references,
            origin: origin()
        )

        do {
            let report = try await MailSendService.send(mail, accountStore: accountStore)
            warnings = report.warnings
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Inhalt zusammenbauen

    /// Eigener Text, darunter das Zitat bzw. der weitergeleitete Inhalt.
    func composedHTML() -> String {
        let own = RichTextHTML.html(from: body)
        guard let quotedHTML else { return own }
        return own + "<br>" + quotedHTML
    }

    func composedText() -> String {
        let own = RichTextHTML.plainText(from: body)
        guard let quotedText else { return own }
        return own + "\n\n" + quotedText
    }

    private func origin() -> OutgoingMail.Origin? {
        guard let original else { return nil }
        switch kind {
        case .reply, .replyAll:
            return .init(
                kind: .replied,
                cachedMessageID: original.id,
                accountID: original.accountID,
                uid: original.uid
            )
        case .forward:
            return .init(
                kind: .forwarded,
                cachedMessageID: original.id,
                accountID: original.accountID,
                uid: original.uid
            )
        case .new:
            return nil
        }
    }

    @MainActor
    private func loadMissingAttachments() async -> Bool {
        guard let original else { return true }
        for attachment in pendingOriginalAttachments where attachment.data == nil {
            do {
                let loaded = try await AttachmentManager.downloadAttachment(
                    attachment, message: original, accountStore: accountStore
                )
                guard let data = loaded.data else { continue }
                attachments.append(
                    OutgoingAttachment(
                        filename: loaded.filename,
                        mimeType: loaded.contentType,
                        data: data
                    )
                )
                if let index = pendingOriginalAttachments.firstIndex(where: { $0.id == loaded.id }) {
                    pendingOriginalAttachments[index] = loaded
                }
            } catch {
                errorMessage = "Anhang „\(attachment.filename)“ konnte nicht geladen werden: \(error.localizedDescription)"
                return false
            }
        }
        return true
    }
}
