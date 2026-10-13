//
//  ComposeViewModel.swift
//  Mailwerk
//
//  Zweck: Zustand und Ablauf des Verfassen-Fensters für neue Mails,
//  Antworten, Allen antworten und Weiterleiten.
//
//  - Vorbelegung über den ReplyBuilder bzw. aus einem mailto:-Link
//  - Verwaltung eigener und übernommener Anhänge
//  - Eingebettete Bilder des Zitats: Beim Antworten und Weiterleiten gehen
//    die im zitierten HTML angesprochenen Bilder (`cid:`) als Inline-Teile
//    mit derselben Content-ID mit, damit das Zitat beim Empfänger
//    vollständig ist. Fehlende Bilder werden beim Senden nachgeladen
//    (InlineImageLoader). In der Anhangliste erscheinen sie nicht; die
//    Vorschau des Zitats zeigt sie eingesetzt.
//  - Bilder im eigenen Text (z. B. eingefügtes Foto, später Logo der
//    Signatur) gehen ebenfalls als Inline-Teile mit; das HTML spricht sie
//    per `cid:` an (RichTextHTML).
//  - Signatur des Absende-Postfachs: Eine einfache Signatur steht
//    markiert im Mailtext (frei bearbeitbar), eine HTML-Signatur als
//    eigener Block darunter (Text änderbar, Gestaltung bleibt). Beim
//    Wechsel des Postfachs wird sie ausgetauscht – auch wenn darin etwas
//    geändert oder sie ganz gelöscht wurde (erneutes Löschen ist ein
//    Fingertipp).
//  - Zusammenbau von HTML- und Textteil (eigener Text, Signatur, Zitat)
//  - Versand über den MailSendService, inkl. Bezug auf die Originalmail
//  - Erkennen ungespeicherter Eingaben beim Abbrechen
//
//  Abgrenzung: Die Darstellung liegt in ComposeView, der eigentliche
//  Versand und die Nacharbeiten im MailSendService.
//
//  Abhängigkeiten: AccountStore, ReplyBuilder, RichTextHTML,
//  MailSendService, AttachmentManager, MessageStore, InlineImages,
//  InlineImageLoader, SignatureStore, SignatureEditing, HTMLSignatureBlock.
//

import Foundation
import Observation

/// Zustand und Ablauf des Verfassen-Fensters.
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
    /// HTML-Signatur als eigener Block unter dem Mailtext; `nil` = keiner.
    var htmlSignature: HTMLSignatureBlock?

    // MARK: Zustand

    /// true, solange der Versand läuft.
    var isSending = false
    /// Fortschrittstext während des Versands.
    var statusText: String?
    /// Fehlermeldung für die Anzeige; `nil` = kein Fehler.
    var errorMessage: String?
    /// Hinweise nach erfolgreichem Versand (z. B. Kopie nicht abgelegt).
    var warnings: [String] = []
    /// Ein Anhang der weitergeleiteten Mail ließ sich nicht laden; die
    /// Ansicht fragt, ob ohne ihn gesendet werden soll. `nil` = kein Fehler.
    var attachmentFailure: AttachmentFailure?

    /// Nicht ladbarer Anhang der weitergeleiteten Mail samt Grund.
    struct AttachmentFailure {
        /// Betroffener Anhang.
        let attachment: CachedAttachment
        /// Fehlertext.
        let reason: String
    }

    // MARK: Bezug zur Originalmail

    /// Art des Verfassens (neu, antworten, allen antworten, weiterleiten).
    let kind: ComposeKind
    /// Originalnachricht bei Antwort oder Weiterleitung.
    private let original: CachedMessage?
    /// Quelle für Postfächer und Passwörter.
    private let accountStore: AccountStore
    /// Zitat bzw. weitergeleiteter Inhalt als HTML (mit `cid:`-Verweisen,
    /// so wird er gesendet).
    private(set) var quotedHTML: String?
    /// Zitat für die Vorschau im Fenster, mit eingesetzten Bildern. Wird
    /// nur bei geänderten Bildern neu gebildet, nicht bei jeder Eingabe.
    private(set) var quotedPreviewHTML: String?
    /// Zitat bzw. weitergeleiteter Inhalt als Text.
    private(set) var quotedText: String?
    /// Message-ID der Originalnachricht für den Header In-Reply-To.
    private var inReplyTo: String?
    /// References-Kette für das Threading.
    private var references: String?

    /// Steuerung des Formatierungs-Editors (Fett, Listen, Schriftgröße …).
    let controller = RichTextController()

    // MARK: Signatur

    /// Speicher der Signaturen; gesetzt, sobald das Fenster erscheint.
    private var signatureStore: SignatureStore?
    /// Signatur-Block direkt nach dem Einsetzen; unverändert zählt er beim
    /// Abbrechen nicht als Eingabe.
    private var initialSignatureHTML: String?

    /// Legt das Verfassen-Fenster an und belegt es vor.
    ///
    /// Verarbeitung: Ermittelt die Vorbelegung über den ReplyBuilder (die
    /// eigene Adresse entfällt bei „Allen antworten“). Beim Antworten und
    /// Weiterleiten werden die vom Zitat angesprochenen Bilder vorgemerkt.
    /// Beim Weiterleiten werden die Anhänge der Originalmail übernommen;
    /// noch nicht geladene Anhänge und Bilder werden erst beim Senden
    /// nachgeladen. Ein mailto:-Link überschreibt
    /// Empfänger, Betreff und Text. Erst ganz am Ende wird der
    /// Ausgangszustand für die Änderungserkennung festgehalten – einmal,
    /// aus den fertig vorbelegten Feldern.
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
            .senderAddress
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

        if let original, kind != .new {
            // Eingebettete Bilder, die das Zitat anspricht, gehen mit.
            originalAttachments = MessageStore.shared.attachments(forMessage: original.id)
            pendingInlineImages = quotedHTML == nil
                ? []
                : InlineImages.referencedImages(originalAttachments, html: original.htmlBody)
            updateQuotedPreview()
        }

        if kind == .forward, let original {
            // Anhänge der Originalmail übernehmen (ohne die Bilder im
            // Text); fehlende Daten werden erst beim Senden nachgeladen.
            pendingOriginalAttachments = InlineImages.visibleAttachments(
                originalAttachments, html: original.htmlBody
            )
            attachments = pendingOriginalAttachments.compactMap { attachment in
                guard let data = attachment.data else { return nil }
                return OutgoingAttachment(
                    filename: attachment.filename,
                    mimeType: attachment.contentType,
                    data: data
                )
            }
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
        }

        initialState = currentState
    }

    // MARK: - Änderungserkennung

    /// Ausgangszustand nach der Vorbelegung – dient dem Vergleich beim Abbrechen.
    private struct State: Equatable {
        /// Empfänger.
        let to: [MailAddress]
        /// Kopie-Empfänger.
        let cc: [MailAddress]
        /// Blindkopie-Empfänger.
        let bcc: [MailAddress]
        /// Betreff.
        let subject: String
        /// Anzahl der Anhänge.
        let attachmentCount: Int
    }

    /// Zustand direkt nach der Vorbelegung; Grundlage von `hasContent`.
    /// Der Startwert gilt nur, bis `init` ihn am Ende setzt.
    private var initialState = State(to: [], cc: [], bcc: [], subject: "", attachmentCount: 0)
    /// Vorbelegter Text (nur aus mailto:-Links); unverändert zählt er
    /// beim Abbrechen nicht als Eingabe.
    private var initialBody = NSAttributedString()

    /// Aktueller Zustand der Eingaben, vergleichbar mit `initialState`.
    private var currentState: State {
        State(to: to, cc: cc, bcc: bcc, subject: subject, attachmentCount: attachments.count)
    }

    /// Anhänge der weitergeleiteten Mail (inkl. noch nicht geladener).
    private var pendingOriginalAttachments: [CachedAttachment] = []
    /// Alle Anhänge der Originalmail aus dem Cache, einschließlich
    /// eingebetteter Bilder.
    private var originalAttachments: [CachedAttachment] = []
    /// Vom Zitat angesprochene eingebettete Bilder (mit oder ohne Daten).
    private var pendingInlineImages: [CachedAttachment] = []
    /// Bilder, auf die der Nutzer nach einem Ladefehler verzichtet hat.
    private var skippedInlineImageIDs: Set<String> = []

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
    /// ginge. Eine reine Vorbelegung (Antworten, Weiterleiten, Signatur)
    /// zählt nicht.
    var hasContent: Bool {
        (body.length > 0 && !body.isEqual(to: initialBody))
            || currentState != initialState
            || htmlSignature?.editedHTML != initialSignatureHTML
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

    // MARK: - Signatur

    /// Verbindet das Fenster mit dem Signatur-Speicher und setzt die
    /// Signatur des vorbelegten Postfachs ein.
    ///
    /// Verarbeitung: Nur beim ersten Aufruf. Danach gilt der Text samt
    /// Signatur als Ausgangszustand – eine unveränderte Signatur zählt beim
    /// Abbrechen nicht als Eingabe.
    ///
    /// - Parameter store: Speicher der Signaturen.
    func attachSignatures(_ store: SignatureStore) {
        guard signatureStore == nil else { return }
        signatureStore = store
        applySignature()
        initialBody = body
        initialSignatureHTML = htmlSignature?.editedHTML
    }

    /// Tauscht die Signatur nach einem Wechsel des Absende-Postfachs aus.
    func accountDidChange() {
        guard signatureStore != nil else { return }
        applySignature()
    }

    /// Übernimmt den geänderten Inhalt des HTML-Signatur-Blocks.
    ///
    /// - Parameter html: Aktuelles HTML aus der Web-Ansicht.
    func updateHTMLSignature(_ html: String) {
        htmlSignature?.editedHTML = html
    }

    /// Entfernt den HTML-Signatur-Block (Knopf ✕).
    func removeHTMLSignature() {
        htmlSignature = nil
    }

    /// Setzt die Signatur des gewählten Postfachs ein bzw. tauscht sie aus.
    ///
    /// Verarbeitung: Die bisherige Signatur (markierter Text bzw. Block)
    /// wird entfernt und die Signatur des Postfachs eingesetzt – immer, auch
    /// wenn der Nutzer die vorige gelöscht hatte. Eine einfache kommt an die
    /// Stelle der alten (bzw. nach einer Leerzeile ans Ende), eine
    /// HTML-Signatur als Block unter den Text.
    private func applySignature() {
        guard let signatureStore else { return }
        let signature = accountID.flatMap { signatureStore.signature(for: $0) }
        let removed = SignatureEditing.replacingSignature(nil, in: body)

        htmlSignature = nil
        switch signature?.kind {
        case .simple?:
            let marked = SignatureEditing.markedSignature(html: signature?.html ?? "", logoData: signature?.logoData)
            body = SignatureEditing.replacingSignature(marked, in: body).text
        case .html?:
            if removed.hadSignature { body = removed.text }
            if let signature { htmlSignature = HTMLSignatureBlock(signature: signature) }
        case nil:
            if removed.hadSignature { body = removed.text }
        }
    }

    // MARK: - Anhänge

    /// Verzichtet auf einen Anhang der weitergeleiteten Mail, der sich
    /// nicht laden ließ.
    ///
    /// Verarbeitung: Der Anhang (oder das eingebettete Bild) wird aus den
    /// nachzuladenden entfernt; ein erneutes Senden versucht ihn nicht
    /// mehr. Bereits geladene Anhänge bleiben.
    ///
    /// - Parameter attachment: Nicht ladbarer Anhang.
    func skipAttachment(_ attachment: CachedAttachment) {
        pendingOriginalAttachments.removeAll { $0.id == attachment.id }
        pendingInlineImages.removeAll { $0.id == attachment.id }
        if attachment.isInline { skippedInlineImageIDs.insert(attachment.id) }
        attachmentFailure = nil
    }

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
    /// Originalmail (Postfach, Ordner, UID) und den Bildern des eigenen
    /// Texts als Inline-Teile und übergibt sie dem
    /// MailSendService. Warnungen der Nacharbeiten landen in `warnings`,
    /// Fehler in `errorMessage`. Lässt sich ein Anhang nicht laden, steht
    /// er in `attachmentFailure`; gesendet wird dann nicht.
    ///
    /// - Returns: true, wenn versendet wurde und das Fenster geschlossen werden kann.
    @MainActor
    func send() async -> Bool {
        guard let accountID else { return false }
        isSending = true
        defer { isSending = false; statusText = nil }

        // Fehlende Anhänge und Bilder der Originalmail nachladen
        if missingAttachmentCount > 0 {
            statusText = "Anhänge werden geladen …"
            if !(await loadMissingAttachments()) { return false }
        }
        if needsInlineImageLoad {
            statusText = "Bilder werden geladen …"
            if !(await loadMissingInlineImages()) { return false }
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
            attachments: attachments + outgoingInlineImages + RichTextHTML.images(in: body)
                + (htmlSignature?.attachments ?? []),
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
    /// Verarbeitung: Wandelt den eigenen Text (samt einfacher Signatur) in
    /// HTML, hängt einen HTML-Signatur-Block direkt an und darunter das
    /// Zitat bzw. den weitergeleiteten Inhalt.
    ///
    /// - Returns: Vollständiger HTML-Body.
    func composedHTML() -> String {
        var own = RichTextHTML.html(from: body)
        if let htmlSignature { own += "<div>" + htmlSignature.sendHTML + "</div>" }
        guard let quotedHTML else { return own }
        return own + "<br>" + quotedHTML
    }

    /// Baut den Textteil der Nachricht.
    ///
    /// Verarbeitung: Wandelt den eigenen Text in reinen Text, hängt eine
    /// HTML-Signatur als Text an und darunter nach einer Leerzeile das
    /// Zitat bzw. den weitergeleiteten Inhalt.
    ///
    /// - Returns: Vollständige Nur-Text-Alternative.
    func composedText() -> String {
        var own = RichTextHTML.plainText(from: body)
        if let signatureText = htmlSignature?.plainText, !signatureText.isEmpty {
            own += "\n" + signatureText
        }
        guard let quotedText else { return own }
        return own + "\n\n" + quotedText
    }

    // MARK: - Eingebettete Bilder

    /// Bildet die Vorschau des Zitats mit den vorhandenen Bildern neu.
    private func updateQuotedPreview() {
        quotedPreviewHTML = quotedHTML.map { InlineImages.resolve($0, images: pendingInlineImages) }
    }

    /// Geladene Bilder des Zitats als Inline-Teile zum Senden.
    private var outgoingInlineImages: [OutgoingAttachment] {
        pendingInlineImages.compactMap { image in
            guard let data = image.data, let contentID = image.contentID else { return nil }
            return OutgoingAttachment(
                filename: image.filename, mimeType: image.contentType, data: data, contentID: contentID
            )
        }
    }

    /// `true`, wenn vor dem Senden Bilder nachzuladen sind: ein
    /// angesprochenes Bild ohne Daten oder ein Verweis, zu dem noch kein
    /// Eintrag im Cache liegt (Mail vor der Speicherung eingebetteter
    /// Bilder geladen).
    private var needsInlineImageLoad: Bool {
        guard let original, quotedHTML != nil else { return false }
        if pendingInlineImages.contains(where: { $0.data == nil }) { return true }
        let known = Set(originalAttachments.compactMap { attachment -> String? in
            guard attachment.isInline, let id = attachment.contentID else { return nil }
            return InlineImages.normalizedContentID(id)
        })
        return !InlineImages.referencedContentIDs(in: original.htmlBody).isSubset(of: known)
    }

    /// Lädt fehlende Bilder des Zitats nach.
    ///
    /// Verarbeitung: Ein Durchgang über den InlineImageLoader; danach
    /// gelten die angesprochenen Bilder ohne die übersprungenen. Fehlt
    /// danach noch ein Bild, steht es in `attachmentFailure`; gesendet wird
    /// dann nicht, die Ansicht fragt, ob ohne das Bild gesendet werden
    /// soll. Scheitert schon der Abruf und gibt es kein benennbares Bild
    /// (nur Verweise ohne Eintrag), wird ohne diese Bilder gesendet.
    ///
    /// - Returns: true, wenn gesendet werden kann; false bei einem Fehler.
    @MainActor
    private func loadMissingInlineImages() async -> Bool {
        guard let original else { return true }
        var reason = "Das Bild ist auf dem Server nicht zu finden."
        do {
            originalAttachments = try await InlineImageLoader.loadMissing(
                for: original, existing: originalAttachments, accountStore: accountStore
            )
            pendingInlineImages = InlineImages.referencedImages(originalAttachments, html: original.htmlBody)
                .filter { !skippedInlineImageIDs.contains($0.id) }
            updateQuotedPreview()
        } catch {
            reason = error.localizedDescription
        }
        if let missing = pendingInlineImages.first(where: { $0.data == nil }) {
            attachmentFailure = AttachmentFailure(attachment: missing, reason: reason)
            return false
        }
        return true
    }

    /// Lädt fehlende Anhänge der weitergeleiteten Mail vom Server nach.
    ///
    /// Verarbeitung: Holt jeden noch nicht geladenen Anhang über den
    /// AttachmentManager (im Ordner der Originalmail) und fügt ihn den
    /// mitzusendenden Anhängen hinzu. Beim ersten Fehler wird abgebrochen
    /// und der Anhang samt Grund in `attachmentFailure` gesetzt. Schon
    /// geladene Anhänge bleiben, ein erneuter Versuch lädt nur den Rest.
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
                attachmentFailure = AttachmentFailure(
                    attachment: attachment, reason: error.localizedDescription
                )
                return false
            }
        }
        return true
    }
}
