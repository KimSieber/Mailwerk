//
//  ComposeViewModel.swift
//  Mailwerk
//
//  Zweck: Zustand und Ablauf des Verfassen-Fensters für neue Mails,
//  Antworten, Allen antworten und Weiterleiten.
//
//  - Vorbelegung über den ReplyBuilder bzw. aus einem mailto:-Link
//  - Verwaltung eigener und übernommener Anhänge
//  - Zusammenbau von HTML- und Textteil (eigener Text plus Zitat)
//  - Versand über den MailSendService, inkl. Bezug auf die Originalmail
//  - Erkennen ungespeicherter Eingaben beim Abbrechen
//
//  Abgrenzung: Die Darstellung liegt in ComposeView, der eigentliche
//  Versand und die Nacharbeiten im MailSendService.
//
//  Abhängigkeiten: AccountStore, ReplyBuilder, RichTextHTML,
//  MailSendService, AttachmentManager, MessageStore.
//

import Foundation
import Observation

@Observable
final class ComposeViewModel {

    // MARK: Eingaben

    /// Gewähltes Absende-Postfach; `nil` = noch nicht gewählt.
    var accountID: UUID?
    /// Empfänger (To).
    var to: [MailAddress] = []
    /// Kopie-Empfänger (Cc).
    var cc: [MailAddress] = []
    /// Blindkopie-Empfänger (Bcc).
    var bcc: [MailAddress] = []
    /// true, wenn das Bcc-Feld eingeblendet ist.
    var showBcc = false
    /// Betreff.
    var subject = ""
    /// Eigener, formatierter Text (ohne Zitat).
    var body = NSAttributedString(string: "", attributes: RichTextController.defaultAttributes)
    /// Mitzusendende Anhänge (eigene und übernommene).
    var attachments: [OutgoingAttachment] = []

    // MARK: Zustand

    /// true, solange der Versand läuft.
    var isSending = false
    /// Fortschrittstext während des Versands.
    var statusText: String?
    /// Fehlermeldung für die Anzeige; `nil` = kein Fehler.
    var errorMessage: String?
    /// Hinweise nach erfolgreichem Versand (z. B. Kopie nicht abgelegt).
    var warnings: [String] = []

    // MARK: Bezug zur Originalmail

    /// Art des Verfassens (neu, antworten, allen antworten, weiterleiten).
    let kind: ComposeKind
    /// Originalnachricht bei Antwort oder Weiterleitung.
    private let original: CachedMessage?
    /// Quelle für Postfächer und Passwörter.
    private let accountStore: AccountStore
    /// Zitat bzw. weitergeleiteter Inhalt als HTML.
    private(set) var quotedHTML: String?
    /// Zitat bzw. weitergeleiteter Inhalt als Text.
    private(set) var quotedText: String?
    /// Message-ID der Originalnachricht für den Header In-Reply-To.
    private var inReplyTo: String?
    /// References-Kette für das Threading.
    private var references: String?

    /// Steuerung des Formatierungs-Editors (Fett, Listen, Schriftgröße …).
    let controller = RichTextController()

    /// Legt das Verfassen-Fenster an und belegt es vor.
    ///
    /// Verarbeitung: Ermittelt die Vorbelegung über den ReplyBuilder (die
    /// eigene Adresse entfällt bei „Allen antworten“). Beim Weiterleiten
    /// werden die Anhänge der Originalmail übernommen; noch nicht geladene
    /// werden erst beim Senden nachgeladen. Ein mailto:-Link überschreibt
    /// Empfänger, Betreff und Text. Zuletzt wird der Ausgangszustand für
    /// die Änderungserkennung festgehalten.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Standard-Postfach.
    ///   - kind: Art des Verfassens.
    ///   - original: Originalnachricht bei Antwort oder Weiterleitung.
    ///   - mailto: Getippter mailto:-Link zur Vorbelegung.
    init(
        accountStore: AccountStore,
        kind: ComposeKind,
        original: CachedMessage? = nil,
        mailto: MailtoLink? = nil
    ) {
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

        // Getippter mailto:-Link aus einer Mail: Felder vorbelegen.
        // Ungültige Adressen fallen weg.
        if let mailto {
            to = mailto.to.compactMap { MailAddress(parsing: $0) }
            cc = mailto.cc.compactMap { MailAddress(parsing: $0) }
            bcc = mailto.bcc.compactMap { MailAddress(parsing: $0) }
            showBcc = !bcc.isEmpty
            if let linkSubject = mailto.subject { subject = linkSubject }
            if let linkBody = mailto.body {
                body = NSAttributedString(string: linkBody, attributes: RichTextController.defaultAttributes)
            }
            initialBody = body
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

    /// Zustand direkt nach der Vorbelegung; Grundlage von `hasContent`.
    private var initialState: State
    /// Vorbelegter Text (nur aus mailto:-Links); unverändert zählt er
    /// beim Abbrechen nicht als Eingabe.
    private var initialBody = NSAttributedString()

    /// Aktueller Zustand der Eingaben, vergleichbar mit `initialState`.
    private var currentState: State {
        State(to: to, cc: cc, bcc: bcc, subject: subject, attachmentCount: attachments.count)
    }

    /// Anhänge der weitergeleiteten Mail (inkl. noch nicht geladener).
    private var pendingOriginalAttachments: [CachedAttachment] = []

    // MARK: - Abgeleitete Werte

    /// Alle eingerichteten Postfächer für die Absenderauswahl.
    var accounts: [MailAccount] { accountStore.accounts }

    /// Das gewählte Absende-Postfach; `nil`, solange keines gewählt ist.
    var selectedAccount: MailAccount? {
        guard let accountID else { return nil }
        return accountStore.accounts.first { $0.id == accountID }
    }

    /// true, wenn Absender und mindestens ein Empfänger gesetzt sind und
    /// gerade nicht gesendet wird.
    var canSend: Bool {
        accountID != nil && !to.isEmpty && !isSending
    }

    /// true, wenn der Nutzer etwas geändert hat, das beim Abbrechen verloren
    /// ginge. Eine reine Vorbelegung (Antworten, Weiterleiten) zählt nicht.
    var hasContent: Bool {
        (body.length > 0 && !body.isEqual(to: initialBody)) || currentState != initialState
    }

    /// Gesamtgröße aller geladenen Anhänge in Bytes.
    var totalAttachmentBytes: Int {
        attachments.reduce(0) { $0 + $1.data.count }
    }

    /// Noch nicht geladene Anhänge der weitergeleiteten Mail.
    var missingAttachmentCount: Int {
        guard kind == .forward else { return 0 }
        return pendingOriginalAttachments.filter { $0.data == nil }.count
    }

    // MARK: - Anhänge

    /// Fügt einen eigenen Anhang hinzu.
    ///
    /// - Parameters:
    ///   - filename: Dateiname, wie er beim Empfänger erscheint.
    ///   - mimeType: MIME-Typ der Datei.
    ///   - data: Inhalt der Datei.
    func addAttachment(filename: String, mimeType: String, data: Data) {
        attachments.append(
            OutgoingAttachment(filename: filename, mimeType: mimeType, data: data)
        )
    }

    /// Entfernt einen Anhang aus der Nachricht.
    ///
    /// - Parameter attachment: Zu entfernender Anhang (Vergleich über Gleichheit).
    func removeAttachment(_ attachment: OutgoingAttachment) {
        attachments.removeAll { $0 == attachment }
    }

    // MARK: - Versand

    /// Versendet die Nachricht.
    ///
    /// Verarbeitung: Lädt zuerst fehlende Anhänge der weitergeleiteten Mail
    /// nach, baut dann die versandfertige Nachricht samt Bezug auf die
    /// Originalmail (Postfach, Ordner, UID) und übergibt sie dem
    /// MailSendService. Warnungen der Nacharbeiten landen in `warnings`,
    /// Fehler in `errorMessage`.
    ///
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
            origin: OutgoingMail.Origin(composeKind: kind, original: original)
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

    /// Baut den HTML-Teil der Nachricht.
    ///
    /// Verarbeitung: Wandelt den eigenen Text in HTML und hängt das Zitat
    /// bzw. den weitergeleiteten Inhalt darunter an.
    ///
    /// - Returns: Vollständiger HTML-Body.
    func composedHTML() -> String {
        let own = RichTextHTML.html(from: body)
        guard let quotedHTML else { return own }
        return own + "<br>" + quotedHTML
    }

    /// Baut den Textteil der Nachricht.
    ///
    /// Verarbeitung: Wandelt den eigenen Text in reinen Text und hängt das
    /// Zitat bzw. den weitergeleiteten Inhalt nach einer Leerzeile an.
    ///
    /// - Returns: Vollständige Nur-Text-Alternative.
    func composedText() -> String {
        let own = RichTextHTML.plainText(from: body)
        guard let quotedText else { return own }
        return own + "\n\n" + quotedText
    }

    /// Lädt fehlende Anhänge der weitergeleiteten Mail vom Server nach.
    ///
    /// Verarbeitung: Holt jeden noch nicht geladenen Anhang über den
    /// AttachmentManager (im Ordner der Originalmail) und fügt ihn den
    /// mitzusendenden Anhängen hinzu. Beim ersten Fehler wird abgebrochen
    /// und die Meldung in `errorMessage` gesetzt.
    ///
    /// - Returns: true, wenn alle Anhänge vorliegen; false bei einem Fehler.
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
