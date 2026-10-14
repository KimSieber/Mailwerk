//
//  ComposeViewModel.swift
//  Mailwerk
//
//  Zweck: Zustand und Ablauf des Verfassen-Fensters für neue Mails,
//  Antworten, Allen antworten und Weiterleiten.
//
//  - Vorbelegung über den ReplyBuilder bzw. aus einem mailto:-Link
//  - Vorbelegung aus geteilten Inhalten (Teilen-Erweiterung): Anhänge,
//    Text und Links, bei Links die Seitenüberschrift als Betreff
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
//  - Als Entwurf sichern (DraftService): gleicher Inhalt wie beim Senden,
//    im HTML mit Entwurfs-Marken (DraftFormat), damit Text, Signatur und
//    Zitat beim Weiterbearbeiten getrennt zurückkommen
//  - Entwurf weiterbearbeiten: Ein gesicherter Entwurf wird über
//    `init(accountStore:draft:attachments:)` vollständig wiederhergestellt
//    (Absender, Empfänger inkl. Bcc, Betreff, Text mit Formaten und
//    Bildern, Signatur, Zitat, Anhänge, Bezug zur Originalmail). Entwürfe
//    anderer Programme kommen vereinfacht als Ganzes in den Editor. Nach
//    dem Senden oder erneuten Sichern wird die alte Fassung endgültig
//    entfernt (DraftService.removeDraft).
//  - Erkennen ungespeicherter Eingaben beim Abbrechen
//
//  Abgrenzung: Die Darstellung liegt in ComposeView, der eigentliche
//  Versand und die Nacharbeiten im MailSendService.
//
//  Abhängigkeiten: AccountStore, ReplyBuilder, RichTextHTML,
//  MailSendService, AttachmentManager, MessageStore, InlineImages,
//  InlineImageLoader, SignatureStore, SignatureEditing, HTMLSignatureBlock,
//  DraftService, DraftFormat, RichTextImport, MailImageAttachment,
//  SharedContent; UIKit bzw. AppKit für das Link-Attribut (`.link`).
//

import Foundation
import Observation
import CoreGraphics
#if os(iOS)
import UIKit
#else
import AppKit
#endif

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
    /// true, solange ein Entwurf gesichert wird.
    var isSavingDraft = false
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
    /// Weiterbearbeiteter Entwurf (alte Fassung); wird nach dem Senden oder
    /// erneuten Sichern endgültig entfernt. `nil` = kein Entwurf.
    private let editedDraft: CachedMessage?
    /// Bezug zur Originalmail aus dem Datenblock eines Entwurfs; gilt, wenn
    /// ein Antwort- oder Weiterleitungs-Entwurf weiterbearbeitet wird.
    private var draftOrigin: DraftMetadata.Origin?
    /// HTML, dessen `cid:`-Verweise die mitzusendenden Bilder des Zitats
    /// bestimmen: das HTML der Originalmail bzw. das Zitat eines Entwurfs.
    private var imageReferenceHTML: String?
    /// Aus einem Entwurf wiederhergestellt: Die Signatur steht schon im
    /// Text und wird beim Erscheinen nicht neu eingesetzt.
    private var isRestoredDraft = false
    /// Hinweis nach dem Wiederherstellen eines Entwurfs (z. B. fehlende
    /// Bilder); `nil` = keiner.
    var restoreNotice: String?

    /// Mail, aus der Bilder des Zitats und übernommene Anhänge stammen: die
    /// Originalmail beim Antworten und Weiterleiten, der Entwurf beim
    /// Weiterbearbeiten.
    private var contentSource: CachedMessage? { editedDraft ?? original }
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
    /// eigene Adresse entfällt bei „Allen antworten“). Eine neue Mail geht
    /// vom übergebenen Postfach aus (Ordner eines Postfachs), sonst vom
    /// Standard-Postfach; Antworten und Weiterleiten immer vom Postfach der
    /// Originalmail. Beim Antworten und
    /// Weiterleiten werden die vom Zitat angesprochenen Bilder vorgemerkt.
    /// Beim Weiterleiten werden die Anhänge der Originalmail übernommen;
    /// noch nicht geladene Anhänge und Bilder werden erst beim Senden
    /// nachgeladen. Ein mailto:-Link überschreibt
    /// Empfänger, Betreff und Text. Geteilte Inhalte setzen Anhänge, Text
    /// und gegebenenfalls den Betreff. Erst ganz am Ende wird der
    /// Ausgangszustand für die Änderungserkennung festgehalten – einmal,
    /// aus den fertig vorbelegten Feldern; die Vorbelegung zählt beim
    /// Abbrechen also nicht als Eingabe.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Standard-Postfach.
    ///   - kind: Art des Verfassens.
    ///   - original: Originalnachricht bei Antwort oder Weiterleitung.
    ///   - mailto: Getippter mailto:-Link zur Vorbelegung.
    ///   - senderAccountID: Absende-Postfach einer neuen Mail; `nil` (oder
    ///     ein nicht mehr vorhandenes Postfach) = Standard-Postfach.
    ///   - shared: Aus einer anderen App geteilte Inhalte; `nil` = keine.
    init(
        accountStore: AccountStore,
        kind: ComposeKind,
        original: CachedMessage? = nil,
        mailto: MailtoLink? = nil,
        senderAccountID: UUID? = nil,
        shared: SharedContent? = nil
    ) {
        self.accountStore = accountStore
        self.kind = kind
        self.original = original
        self.editedDraft = nil

        // Nur die Adresse des antwortenden Postfachs entfällt bei „Allen
        // antworten" – andere eigene Postfächer bleiben als Empfänger stehen.
        let replyingAccountID = original?.accountID ?? accountStore.defaultAccountID
        let ownAddress = accountStore.accounts
            .first { $0.id == replyingAccountID }?
            .senderAddress
            .lowercased()
        let ownAddresses = Set([ownAddress].compactMap { $0 })

        // Neue Mail: Postfach des gezeigten Ordners, sonst Standard-Postfach
        let newMailAccountID = senderAccountID
            .flatMap { id in accountStore.accounts.contains(where: { $0.id == id }) ? id : nil }
            ?? accountStore.defaultAccountID
        let prefill = ReplyBuilder.prefill(
            kind: kind,
            original: original,
            defaultAccountID: newMailAccountID,
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
            imageReferenceHTML = original.htmlBody
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

        // Geteilte Inhalte: Anhänge, Text mit Links, Betreff
        if let shared {
            if let sharedSubject = shared.subject { subject = sharedSubject }
            attachments += shared.attachments.map {
                OutgoingAttachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
            }
            let parts = shared.bodyParts
            if !parts.isEmpty { body = ComposeViewModel.sharedBody(parts) }
            initialBody = body
        }

        initialState = currentState
    }

    /// Text einer neuen Mail aus geteilten Inhalten.
    ///
    /// Verarbeitung: Jeder Teil wird ein eigener Absatz; Links erscheinen
    /// mit ihrer Adresse als antippbarer Link (Attribut `.link`), den der
    /// Versand als `<a href>` überträgt. Den Abstand zu einer einfachen
    /// Signatur setzt das Einsetzen der Signatur (SignatureEditing).
    ///
    /// - Parameter parts: Absätze in ihrer Reihenfolge.
    /// - Returns: Formatierter Text in der Standardschrift.
    static func sharedBody(_ parts: [SharedBodyPart]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let attributes = RichTextController.defaultAttributes
        for (index, part) in parts.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "\n\n", attributes: attributes)) }
            switch part {
            case .text(let value):
                text.append(NSAttributedString(string: value, attributes: attributes))
            case .link(let url):
                var linkAttributes = attributes
                linkAttributes[.link] = url
                text.append(NSAttributedString(string: url.absoluteString, attributes: linkAttributes))
            }
        }
        return text
    }

    /// Legt das Verfassen-Fenster für einen gesicherten Entwurf an.
    ///
    /// Verarbeitung: Absender ist das Postfach des Entwurfs, An, Cc und
    /// Betreff kommen aus dem Cache. Ein Mailwerk-Entwurf (DraftFormat)
    /// liefert außerdem Bcc, Art, Threading und den Bezug zur Originalmail;
    /// Text vor und nach der Signatur kommen mit Formaten und Bildern in den
    /// Editor (`cid:` → Inline-Bild des Entwurfs mit derselben Content-ID).
    /// Eine einfache Signatur steht wieder markiert im Text, eine
    /// HTML-Signatur als Block; beide bleiben beim Wechsel des Postfachs
    /// austauschbar. Das Zitat bleibt unverändert, sein Text kommt aus dem
    /// Textteil des Entwurfs (sonst aus dem Zitat-HTML). Ein Entwurf eines
    /// anderen Programms kommt als Ganzes vereinfacht in den Editor. Anhänge
    /// werden übernommen; fehlende Daten lädt das Senden bzw. Sichern nach.
    /// Fehlen Bilder des Entwurfs, steht ein Hinweis in `restoreNotice`.
    /// Zuletzt wird der Ausgangszustand festgehalten – ein unveränderter
    /// Entwurf schließt ohne Rückfrage.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer.
    ///   - draft: Entwurf aus dem Cache.
    ///   - draftAttachments: Anhänge und Bilder des Entwurfs aus dem Cache.
    init(
        accountStore: AccountStore,
        draft: CachedMessage,
        attachments draftAttachments: [CachedAttachment]
    ) {
        let parts = DraftFormat.parse(draft.htmlBody ?? "")
        self.accountStore = accountStore
        self.kind = parts.map { ComposeViewModel.composeKind($0.metadata.kind) } ?? .new
        self.original = nil
        self.editedDraft = draft
        isRestoredDraft = true
        originalAttachments = draftAttachments

        accountID = accountStore.accounts.contains(where: { $0.id == draft.accountID }) ? draft.accountID : nil
        to = draft.headers.toList.compactMap { MailAddress(parsing: $0) }
        cc = draft.headers.ccList.compactMap { MailAddress(parsing: $0) }
        subject = draft.subject

        let images = ComposeViewModel.imageResolver(draftAttachments)
        if let parts {
            let metadata = parts.metadata
            bcc = metadata.bcc.compactMap { MailAddress(parsing: $0) }
            showBcc = !bcc.isEmpty
            inReplyTo = metadata.inReplyTo
            references = metadata.references
            draftOrigin = metadata.origin

            let text = NSMutableAttributedString(
                attributedString: RichTextImport.attributedString(fromHTML: parts.textBefore, images: images).text
            )
            if let signatureHTML = parts.signature {
                switch metadata.signature {
                case .simple:
                    let marked = NSMutableAttributedString(
                        attributedString: RichTextImport.attributedString(fromHTML: signatureHTML, images: images).text
                    )
                    marked.addAttribute(.mailwerkSignature, value: true, range: NSRange(location: 0, length: marked.length))
                    text.append(marked)
                case .html:
                    htmlSignature = HTMLSignatureBlock(restoredHTML: signatureHTML, images: draftAttachments)
                case .none:
                    break
                }
            }
            if !parts.textAfter.isEmpty {
                text.append(RichTextImport.attributedString(fromHTML: parts.textAfter, images: images).text)
            }
            body = text

            if let quote = parts.quote {
                quotedHTML = quote
                imageReferenceHTML = quote
                pendingInlineImages = InlineImages.referencedImages(draftAttachments, html: quote)
                updateQuotedPreview()
                // Eigener Text wie beim Senden, noch ohne Zitat
                let ownText = composedText()
                quotedText = DraftFormat.quotedText(draftText: draft.textBody, ownText: ownText)
                    ?? SignatureRules.plainText(fromHTML: quote)
            }
        } else if let html = draft.htmlBody, !html.isEmpty {
            body = RichTextImport.attributedString(fromHTML: html, images: images).text
        } else {
            body = NSAttributedString(string: draft.textBody ?? "", attributes: RichTextController.defaultAttributes)
        }

        // Anhänge des Entwurfs (ohne die Bilder im Text); fehlende Daten
        // werden beim Senden bzw. Sichern nachgeladen.
        pendingOriginalAttachments = InlineImages.visibleAttachments(draftAttachments, html: draft.htmlBody)
        attachments = pendingOriginalAttachments.compactMap { attachment in
            guard let data = attachment.data else { return nil }
            return OutgoingAttachment(filename: attachment.filename, mimeType: attachment.contentType, data: data)
        }

        if InlineImages.hasMissingImages(draftAttachments, html: draft.htmlBody) {
            restoreNotice = "Einige Bilder des Entwurfs konnten nicht geladen werden und fehlen im Text."
        }

        initialBody = body
        initialSignatureHTML = htmlSignature?.editedHTML
        initialState = currentState
    }

    /// Zuordnung `cid:`-Quelle → Bild im Editor für einen Entwurf.
    ///
    /// Verarbeitung: Nur Inline-Teile mit Daten; das Bild behält seine
    /// Content-ID, damit es beim erneuten Senden gleich angesprochen wird.
    ///
    /// - Parameter attachments: Anhänge des Entwurfs.
    /// - Returns: Zuordnung für RichTextImport.
    private static func imageResolver(_ attachments: [CachedAttachment]) -> RichTextImport.ImageResolver {
        var images: [String: CachedAttachment] = [:]
        for attachment in attachments where attachment.isInline && attachment.data != nil {
            if let contentID = attachment.contentID {
                images[InlineImages.normalizedContentID(contentID)] = attachment
            }
        }
        return { source, width in
            guard source.lowercased().hasPrefix("cid:") else { return nil }
            let key = InlineImages.normalizedContentID(String(source.dropFirst(4)))
            guard let image = images[key], let data = image.data else { return nil }
            return MailImageAttachment.make(
                from: data, displayWidth: width.map { CGFloat($0) }, contentID: image.contentID
            )
        }
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

    /// Noch nicht geladene Anhänge der weitergeleiteten Mail bzw. des
    /// weiterbearbeiteten Entwurfs.
    var missingAttachmentCount: Int {
        pendingOriginalAttachments.filter { $0.data == nil }.count
    }

    // MARK: - Signatur

    /// Verbindet das Fenster mit dem Signatur-Speicher und setzt die
    /// Signatur des vorbelegten Postfachs ein.
    ///
    /// Verarbeitung: Nur beim ersten Aufruf. Danach gilt der Text samt
    /// Signatur als Ausgangszustand – eine unveränderte Signatur zählt beim
    /// Abbrechen nicht als Eingabe. Ein wiederhergestellter Entwurf bringt
    /// seine Signatur schon mit; sie bleibt unverändert.
    ///
    /// - Parameter store: Speicher der Signaturen.
    func attachSignatures(_ store: SignatureStore) {
        guard signatureStore == nil else { return }
        signatureStore = store
        guard !isRestoredDraft else { return }
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
    /// MailSendService. War es ein weiterbearbeiteter Entwurf, wird danach
    /// dessen alte Fassung entfernt. Warnungen der Nacharbeiten landen in `warnings`,
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
                ?? Self.origin(kind: kind, draft: draftOrigin)
        )

        do {
            let report = try await MailSendService.send(mail, accountStore: accountStore)
            warnings = report.warnings
            if let warning = await removeEditedDraft() { warnings.append(warning) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Entwurf

    /// Ergebnis beim Sichern eines Entwurfs.
    enum DraftOutcome: Equatable {
        /// Gesichert; das Fenster kann schließen.
        case saved
        /// Das Postfach hat keinen Entwürfe-Ordner – nachfragen und mit
        /// `createFolder: true` erneut sichern.
        case needsDraftsFolder
        /// Fehlgeschlagen (Meldungstext); das Fenster bleibt offen.
        case failed(String)
    }

    /// Sichert die Nachricht als Entwurf im Ordner „Entwürfe“ des
    /// Absende-Postfachs.
    ///
    /// Verarbeitung: Lädt wie beim Senden fehlende Anhänge und Bilder der
    /// Originalmail nach – gelingt das nicht, wird nicht gesichert (der
    /// Entwurf wäre sonst unvollständig). Danach Ablage mit demselben Inhalt
    /// wie beim Senden, das HTML mit Entwurfs-Marken (`draftHTML`). Auf
    /// Wunsch wird zuvor der Entwürfe-Ordner angelegt. Erst nach dem
    /// Sichern der neuen Fassung wird eine alte (weiterbearbeiteter Entwurf)
    /// entfernt; scheitert das, steht ein Hinweis in `warnings`.
    ///
    /// - Parameter createFolder: `true` = fehlenden Entwürfe-Ordner anlegen.
    /// - Returns: Ergebnis für die Ansicht.
    @MainActor
    func saveDraft(createFolder: Bool = false) async -> DraftOutcome {
        guard let accountID else { return .failed("Bitte zuerst einen Absender wählen.") }
        isSavingDraft = true
        defer { isSavingDraft = false; statusText = nil }

        if missingAttachmentCount > 0 {
            statusText = "Anhänge werden geladen …"
            if !(await loadMissingAttachments()) { return failedLoad() }
        }
        if needsInlineImageLoad {
            statusText = "Bilder werden geladen …"
            if !(await loadMissingInlineImages()) { return failedLoad() }
        }

        statusText = "Entwurf wird gesichert …"
        let mail = OutgoingMail(
            accountID: accountID,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            htmlBody: draftHTML(),
            textBody: composedText(),
            attachments: attachments + outgoingInlineImages + RichTextHTML.images(in: body)
                + (htmlSignature?.attachments ?? []),
            inReplyTo: inReplyTo,
            references: references
        )

        do {
            if createFolder {
                try await DraftService.createDraftsFolder(accountID: accountID, accountStore: accountStore)
            }
            _ = try await DraftService.save(mail, accountStore: accountStore)
            if let warning = await removeEditedDraft() { warnings = [warning] }
            return .saved
        } catch DraftService.DraftError.draftsFolderMissing {
            return .needsDraftsFolder
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Ergebnis, wenn ein Anhang oder Bild für den Entwurf nicht geladen
    /// werden konnte. Die Rückfrage „ohne … senden“ gehört nur zum Versand
    /// und wird deshalb zurückgenommen.
    ///
    /// - Returns: Fehlschlag mit Grund.
    private func failedLoad() -> DraftOutcome {
        let failure = attachmentFailure
        attachmentFailure = nil
        let name = failure?.attachment.filename ?? "Ein Anhang"
        let reason = failure?.reason ?? ""
        return .failed("„\(name)“ konnte nicht geladen werden; der Entwurf wurde nicht gesichert. \(reason)")
    }

    /// HTML des Entwurfs mit Marken für Text, Signatur und Zitat.
    ///
    /// Verarbeitung: Der Mailtext wird an der eingesetzten einfachen
    /// Signatur geteilt (Text davor, Signatur, Text danach); eine
    /// HTML-Signatur steht als Signatur-Teil. Der Datenblock hält Art,
    /// Bcc, Bezug zur Originalmail, Threading und die Art der Signatur.
    ///
    /// - Returns: HTML des Entwurfs (DraftFormat).
    func draftHTML() -> String {
        let split = SignatureEditing.split(body)
        var signatureHTML: String?
        var signatureKind = DraftMetadata.SignatureKind.none
        if let signature = split.signature {
            signatureHTML = RichTextHTML.html(from: signature)
            signatureKind = .simple
        } else if let htmlSignature {
            signatureHTML = htmlSignature.sendHTML
            signatureKind = .html
        }

        let metadata = DraftMetadata(
            kind: Self.draftKind(kind),
            bcc: bcc.map(\.displayString),
            origin: kind == .new ? nil : original.map {
                DraftMetadata.Origin(cachedMessageID: $0.id, accountID: $0.accountID, folder: $0.folder, uid: $0.uid)
            } ?? draftOrigin,
            inReplyTo: inReplyTo,
            references: references,
            signature: signatureKind
        )
        return DraftFormat.html(DraftParts(
            metadata: metadata,
            textBefore: RichTextHTML.html(from: split.before),
            signature: signatureHTML,
            textAfter: split.after.length > 0 ? RichTextHTML.html(from: split.after) : "",
            quote: quotedHTML
        ))
    }

    /// Art des Verfassens im Datenblock des Entwurfs.
    ///
    /// - Parameter kind: Art des Verfassens.
    /// - Returns: Entsprechender Wert.
    static func draftKind(_ kind: ComposeKind) -> DraftMetadata.Kind {
        switch kind {
        case .new:      return .new
        case .reply:    return .reply
        case .replyAll: return .replyAll
        case .forward:  return .forward
        }
    }

    /// Art des Verfassens aus dem Datenblock eines Entwurfs.
    ///
    /// - Parameter kind: Wert im Datenblock.
    /// - Returns: Art des Verfassens.
    static func composeKind(_ kind: DraftMetadata.Kind) -> ComposeKind {
        switch kind {
        case .new:      return .new
        case .reply:    return .reply
        case .replyAll: return .replyAll
        case .forward:  return .forward
        }
    }

    /// Bezug zur Originalmail aus dem Datenblock eines Entwurfs.
    ///
    /// Verarbeitung: Antworten ergeben „beantwortet“, Weiterleiten
    /// „weitergeleitet“; eine neue Mail hat keinen Bezug.
    ///
    /// - Parameters:
    ///   - kind: Art des Verfassens.
    ///   - draft: Bezug aus dem Datenblock; `nil` = keiner.
    /// - Returns: Bezug für den Versand oder `nil`.
    static func origin(kind: ComposeKind, draft: DraftMetadata.Origin?) -> OutgoingMail.Origin? {
        guard let draft else { return nil }
        let originKind: OutgoingMail.Origin.Kind
        switch kind {
        case .reply, .replyAll: originKind = .replied
        case .forward:          originKind = .forwarded
        case .new:              return nil
        }
        return OutgoingMail.Origin(
            kind: originKind, cachedMessageID: draft.cachedMessageID,
            accountID: draft.accountID, folder: draft.folder, uid: draft.uid
        )
    }

    /// Entfernt die alte Fassung eines weiterbearbeiteten Entwurfs.
    ///
    /// Verarbeitung: Nur bei einem Entwurf; Fehler brechen nichts ab – die
    /// Mail ist schon gesendet bzw. neu gesichert –, sondern werden als
    /// Hinweis zurückgegeben.
    ///
    /// - Returns: Hinweistext bei einem Fehler, sonst `nil`.
    @MainActor
    private func removeEditedDraft() async -> String? {
        guard let editedDraft else { return nil }
        do {
            try await DraftService.removeDraft(editedDraft, accountStore: accountStore)
            return nil
        } catch {
            return "Die alte Fassung des Entwurfs konnte nicht entfernt werden: \(error.localizedDescription)"
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
        guard contentSource != nil, quotedHTML != nil else { return false }
        if pendingInlineImages.contains(where: { $0.data == nil }) { return true }
        let known = Set(originalAttachments.compactMap { attachment -> String? in
            guard attachment.isInline, let id = attachment.contentID else { return nil }
            return InlineImages.normalizedContentID(id)
        })
        return !InlineImages.referencedContentIDs(in: imageReferenceHTML).isSubset(of: known)
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
        guard let source = contentSource else { return true }
        var reason = "Das Bild ist auf dem Server nicht zu finden."
        do {
            originalAttachments = try await InlineImageLoader.loadMissing(
                for: source, existing: originalAttachments, accountStore: accountStore
            )
            pendingInlineImages = InlineImages.referencedImages(originalAttachments, html: imageReferenceHTML)
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
        guard let source = contentSource else { return true }
        for attachment in pendingOriginalAttachments where attachment.data == nil {
            do {
                let loaded = try await AttachmentManager.downloadAttachment(
                    attachment, message: source, accountStore: accountStore
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
