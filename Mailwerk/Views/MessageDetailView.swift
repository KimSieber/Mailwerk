//
//  MessageDetailView.swift
//  Mailwerk
//
//  Zweck: Ansicht einer einzelnen Mail – Kopfdaten, Inhalt (HTML oder
//  Text), Anhänge mit Vorschau, Teilen und Nachladen sowie das
//  Aktionsmenü: Antworten/Weiterleiten, Kennzeichnen, Gelesen, Verschieben,
//  Spam-Aktionen (Blockieren/Vertrauen), Teilen, Drucken, Anlagen lokal
//  löschen und Mail löschen.
//
//  Eine ungelesene Mail wird beim Öffnen als gelesen markiert.
//
//  Aktionen an der Mail laufen über `MessageActions` (Server und Cache
//  gemeinsam). Meldungen und Rückfragen haben je einen Kanal
//  (`activeAlert`, `activeConfirmation`, siehe Dialogs.swift). Vorher
//  hingen drei Rückfragen und zwei Meldungen an derselben Ansicht und
//  wurden aus dem Menü heraus geöffnet – eine in SwiftUI unzuverlässige
//  Bauweise.
//
//  Abgrenzung: Laden der Mail aus dem Cache → MessageDetailLoader;
//  HTML-Darstellung → HTMLMailView; Verfassen → ComposeView; Ordnerwahl →
//  FolderMoveSheet; Anhang-Zeile → AttachmentRow; Teilen → MailShareSheet;
//  Druck → MailPrinter.
//
//  Abhängigkeiten: SwiftUI, QuickLook, MessageActions, SpamFilterService,
//  AttachmentManager, MessageStore, Dialogs.
//

import SwiftUI
import QuickLook
import WebKit

/// Ansicht einer einzelnen Mail.
struct MessageDetailView: View {
    /// Angezeigte Mail.
    let message: CachedMessage
    /// Quelle für Postfächer und Zugangsdaten.
    let accountStore: AccountStore
    /// Spamfilter für Blockieren und Vertrauen.
    let spamFilter: SpamFilterService
    /// Wird nach jeder Änderung aufgerufen (Liste neu laden).
    let onChange: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Gemessene Höhe des HTML-Inhalts.
    @State private var webViewHeight: CGFloat = 100
    /// Anhänge der Mail aus dem Cache.
    @State private var attachments: [CachedAttachment] = []
    /// Datei für die QuickLook-Vorschau; `nil` = keine Vorschau offen.
    @State private var previewURL: URL?
    /// Temporäre Dateien der geladenen Anhänge zum Teilen, je Anhang-ID.
    @State private var shareURLs: [String: URL] = [:]
    /// Anhänge, die gerade nachgeladen werden.
    @State private var downloadingIDs: Set<String> = []
    /// Teilen-Sheet sichtbar.
    @State private var showShareSheet = false
    /// Gelesen-Zustand (lokal nachgeführt).
    @State private var isUnread: Bool
    /// Kennzeichnung (lokal nachgeführt).
    @State private var isFlagged: Bool
    /// `true`, solange eine Aktion an der Mail läuft.
    @State private var isProcessingAction = false
    /// Ordnerwahl zum Verschieben sichtbar.
    @State private var showFolderPicker = false
    /// Zu verfassende Antwort bzw. Weiterleitung.
    @State private var composeRequest: ComposeRequest?
    /// Getippter mailto:-Link aus der Mail → neue Mail in Mailwerk.
    @State private var mailtoRequest: MailtoLink?
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?
    /// Einziger Rückfragekanal der Ansicht.
    @State private var activeConfirmation: ConfirmationRequest?

    /// Art einer Spam-Aktion.
    private enum SpamActionKind {
        case block, trust
    }

    /// Kapselt die Art der zu verfassenden Nachricht für das Sheet.
    private struct ComposeRequest: Identifiable {
        /// Kennung für SwiftUI.
        let id = UUID()
        /// Antworten, Allen antworten oder Weiterleiten.
        let kind: ComposeKind
    }

    /// Übernimmt die Mail und die Abhängigkeiten.
    ///
    /// - Parameters:
    ///   - message: Angezeigte Mail.
    ///   - accountStore: Quelle für Postfächer und Zugangsdaten.
    ///   - spamFilter: Spamfilter für Blockieren und Vertrauen.
    ///   - onChange: Wird nach jeder Änderung aufgerufen.
    init(
        message: CachedMessage,
        accountStore: AccountStore,
        spamFilter: SpamFilterService,
        onChange: (() -> Void)? = nil
    ) {
        self.message = message
        self.accountStore = accountStore
        self.spamFilter = spamFilter
        self.onChange = onChange
        _isUnread = State(initialValue: message.isUnread)
        _isFlagged = State(initialValue: message.isFlagged)
    }

    /// Ziel der Aktionen an dieser Mail.
    private var target: MessageActions.Target { MessageActions.Target(message) }

    /// Aufbau: Kopfdaten, Inhalt, Anhänge; Symbolleiste mit Antworten und
    /// Menü; Sheets, Vorschau, Meldung und Rückfrage.
    var body: some View {
        content
            .navigationTitle(message.accountDisplayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .sheet(item: $mailtoRequest) { link in
                ComposeView(
                    accountStore: accountStore,
                    kind: .new,
                    mailto: link,
                    onSent: { onChange?() }
                )
            }
            .sheet(item: $composeRequest) { request in
                ComposeView(
                    accountStore: accountStore,
                    kind: request.kind,
                    original: message,
                    onSent: { onChange?() }
                )
            }
            .sheet(isPresented: $showShareSheet) {
                MailShareSheet(message: message, attachments: attachments)
            }
            .sheet(isPresented: $showFolderPicker) {
                if let account = accountStore.accounts.first(where: { $0.id == message.accountID }) {
                    FolderMoveSheet(
                        account: account,
                        currentFolder: message.folder,
                        accountStore: accountStore
                    ) { path in
                        Task { await moveMessage(to: path) }
                    }
                }
            }
            .quickLookPreview($previewURL)
            .confirmationRequest($activeConfirmation)
            .task { await prepareOnOpen() }
    }

    // MARK: - Inhalt

    /// Kopfdaten, Inhalt und Anhänge in einem Scrollbereich. Trägt den
    /// Meldungskanal – getrennt vom Rückfragekanal am äußeren Element.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                messageBody
                if !attachments.isEmpty {
                    Divider()
                    attachmentList
                }
            }
            .padding()
        }
        .alertItem($activeAlert)
    }

    /// Betreff, Kennzeichnung, Absender, Empfänger, Kopie und Datum.
    @ViewBuilder
    private var header: some View {
        HStack {
            Text(message.subject)
                .font(.title2)
                .bold()
            if isFlagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
            }
        }
        Text("Von: \(message.from)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        if !message.to.isEmpty {
            Text("An: \(message.to)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if !message.headers.ccList.isEmpty {
            Text("Kopie: \(message.headers.ccList.joined(separator: ", "))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let date = message.date {
            Text(date, format: .dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits).year().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Inhalt der Mail: HTML bevorzugt, sonst Text.
    @ViewBuilder
    private var messageBody: some View {
        if let html = message.htmlBody {
            HTMLMailView(
                html: html,
                contentHeight: $webViewHeight,
                onMailto: { mailtoRequest = $0 }
            )
            .frame(height: max(100, webViewHeight))
        } else if let text = message.textBody {
            Text(text)
        } else {
            Text("Kein Inhalt verfügbar").foregroundStyle(.secondary)
        }
    }

    /// Liste der Anhänge mit Vorschau, Nachladen und Teilen.
    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Anhänge (\(attachments.count))", systemImage: "paperclip")
                .font(.headline)

            ForEach(attachments) { attachment in
                AttachmentRow(
                    attachment: attachment,
                    isDownloading: downloadingIDs.contains(attachment.id),
                    onTap: { handleTap(attachment) },
                    shareURL: shareURLs[attachment.id]
                )
            }
        }
    }

    // MARK: - Symbolleiste und Menü

    /// Antworten (Tipp antwortet direkt, langes Drücken zeigt alle
    /// Varianten) und das Aktionsmenü.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                replyButtons
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            } primaryAction: {
                composeRequest = ComposeRequest(kind: .reply)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if isProcessingAction {
                ProgressView()
            } else {
                messageMenu
            }
        }
    }

    /// Aktionsmenü der Mail.
    private var messageMenu: some View {
        Menu {
            Section {
                replyButtons
            }

            Section {
                Button {
                    Task { await toggleFlag() }
                } label: {
                    Label(
                        isFlagged ? "Kennzeichnung entfernen" : "Kennzeichnen",
                        systemImage: isFlagged ? "flag.slash" : "flag"
                    )
                }

                Button {
                    Task { await toggleRead() }
                } label: {
                    Label(
                        isUnread ? "Als gelesen markieren" : "Als ungelesen markieren",
                        systemImage: isUnread ? "envelope.open" : "envelope.badge"
                    )
                }

                Button {
                    showFolderPicker = true
                } label: {
                    Label("In Ordner verschieben", systemImage: "folder")
                }
            }

            Section {
                spamMenu
            }

            Section {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }

                Button {
                    printMessage()
                } label: {
                    Label("Drucken", systemImage: "printer")
                }

                if hasLocalAttachmentData {
                    Button(role: .destructive) {
                        confirmDeleteLocalAttachments()
                    } label: {
                        Label("Anlagen lokal löschen", systemImage: "trash")
                    }
                }

                Button(role: .destructive) {
                    confirmDeleteMessage()
                } label: {
                    Label("Mail löschen", systemImage: "trash.fill")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(isProcessingAction)
    }

    /// Untermenü „Spam / Vertrauen“ für Absenderadresse und Domain.
    @ViewBuilder
    private var spamMenu: some View {
        if let sender = FilterAddress.sender(fromHeader: message.from) {
            Menu {
                Button {
                    confirmSpamAction(.block, entryKind: .address, value: sender.address)
                } label: {
                    Label("\(sender.address) blockieren", systemImage: "person.crop.circle.badge.xmark")
                }
                Button {
                    confirmSpamAction(.block, entryKind: .domain, value: sender.domain)
                } label: {
                    Label("\(sender.domain) blockieren", systemImage: "globe.badge.chevron.backward")
                }
                Button {
                    confirmSpamAction(.trust, entryKind: .address, value: sender.address)
                } label: {
                    Label("\(sender.address) vertrauen", systemImage: "person.crop.circle.badge.checkmark")
                }
                Button {
                    confirmSpamAction(.trust, entryKind: .domain, value: sender.domain)
                } label: {
                    Label("\(sender.domain) vertrauen", systemImage: "globe")
                }
            } label: {
                Label("Spam / Vertrauen", systemImage: "shield")
            }
        }
    }

    /// Antworten, Allen antworten und Weiterleiten – im Menü und in der
    /// Symbolleiste.
    @ViewBuilder
    private var replyButtons: some View {
        Button {
            composeRequest = ComposeRequest(kind: .reply)
        } label: {
            Label("Antworten", systemImage: "arrowshape.turn.up.left")
        }

        Button {
            composeRequest = ComposeRequest(kind: .replyAll)
        } label: {
            Label("Allen antworten", systemImage: "arrowshape.turn.up.left.2")
        }

        Button {
            composeRequest = ComposeRequest(kind: .forward)
        } label: {
            Label("Weiterleiten", systemImage: "arrowshape.turn.up.right")
        }
    }

    /// `true`, wenn mindestens ein Anhang lokale Daten hat, die gelöscht
    /// werden könnten.
    private var hasLocalAttachmentData: Bool {
        attachments.contains { $0.data != nil }
    }

    // MARK: - Beim Öffnen

    /// Lädt die Anhänge, bereitet das Teilen vor und markiert eine
    /// ungelesene Mail als gelesen.
    ///
    /// Verarbeitung: Scheitert das Markieren, bleibt die Mail ungelesen;
    /// eine Meldung erscheint nicht, weil der Nutzer nichts ausgelöst hat.
    @MainActor
    private func prepareOnOpen() async {
        attachments = MessageStore.shared.attachments(forMessage: message.id)
        prepareShareURLs()

        guard isUnread else { return }
        do {
            try await MessageActions.setRead(true, for: target, accountStore: accountStore)
            isUnread = false
            onChange?()
        } catch {
            print("⚠️ Gelesen-Markierung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: - Aktionen an der Mail

    /// Schaltet gelesen/ungelesen um.
    @MainActor
    private func toggleRead() async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        let markAsRead = isUnread
        do {
            try await MessageActions.setRead(markAsRead, for: target, accountStore: accountStore)
            isUnread = !markAsRead
            onChange?()
        } catch {
            activeAlert = .failure("Status ändern fehlgeschlagen", error)
        }
    }

    /// Schaltet die Kennzeichnung um.
    @MainActor
    private func toggleFlag() async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        let newFlagged = !isFlagged
        do {
            try await MessageActions.setFlagged(newFlagged, for: target, accountStore: accountStore)
            isFlagged = newFlagged
            onChange?()
        } catch {
            activeAlert = .failure("Kennzeichnen fehlgeschlagen", error)
        }
    }

    /// Fragt vor dem Löschen der Mail nach.
    private func confirmDeleteMessage() {
        activeConfirmation = ConfirmationRequest(
            title: "Mail löschen?",
            message: "Die Mail wird auf dem Server gelöscht bzw. in den Papierkorb verschoben.",
            confirmLabel: "Löschen"
        ) {
            Task { await deleteMessage() }
        }
    }

    /// Löscht die Mail und kehrt zur Liste zurück.
    @MainActor
    private func deleteMessage() async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        do {
            try await MessageActions.delete(target, accountStore: accountStore)
            onChange?()
            dismiss()
        } catch {
            activeAlert = .failure("Löschen fehlgeschlagen", error)
        }
    }

    /// Verschiebt die Mail in den gewählten Ordner und kehrt zur Liste zurück.
    ///
    /// - Parameter path: Server-Pfad des Zielordners.
    @MainActor
    private func moveMessage(to path: String) async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        do {
            try await MessageActions.move(target, to: path, accountStore: accountStore)
            onChange?()
            dismiss()
        } catch {
            activeAlert = .failure("Verschieben fehlgeschlagen", error)
        }
    }

    // MARK: - Spam-Aktionen

    /// Fragt vor dem Blockieren bzw. Vertrauen nach.
    ///
    /// - Parameters:
    ///   - kind: Blockieren oder Vertrauen.
    ///   - entryKind: Adresse oder Domain.
    ///   - value: Einzutragende Adresse bzw. Domain.
    private func confirmSpamAction(_ kind: SpamActionKind, entryKind: FilterEntryKind, value: String) {
        let scope = entryKind == .domain
            ? "Alle künftigen Mails dieser Domain"
            : "Alle künftigen Mails dieses Absenders"
        let isBlock = kind == .block
        activeConfirmation = ConfirmationRequest(
            title: isBlock ? "\(value) blockieren?" : "\(value) vertrauen?",
            message: isBlock
                ? "\(scope) wandern in den Spam-Ordner. Diese Mail wird mitverschoben."
                : "\(scope) bleiben im Posteingang. Liegt diese Mail im Spam-Ordner, wird sie zurückgeholt.",
            confirmLabel: isBlock ? "Blockieren" : "Vertrauen",
            isDestructive: isBlock
        ) {
            Task { await performSpamAction(kind, entryKind: entryKind, value: value) }
        }
    }

    /// Trägt Adresse bzw. Domain in die Liste ein und verschiebt die Mail
    /// bei Bedarf.
    ///
    /// Verarbeitung: Wurde die Mail verschoben, zeigt diese Ansicht eine
    /// Mail, die hier nicht mehr liegt – also zurück zur Liste. Sonst
    /// bestätigt eine Meldung den Eintrag. Steht der Wert schon auf der
    /// anderen Liste, wird der Eintrag abgelehnt.
    ///
    /// - Parameters:
    ///   - kind: Blockieren oder Vertrauen.
    ///   - entryKind: Adresse oder Domain.
    ///   - value: Einzutragende Adresse bzw. Domain.
    @MainActor
    private func performSpamAction(_ kind: SpamActionKind, entryKind: FilterEntryKind, value: String) async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        do {
            let moved: Bool
            switch kind {
            case .block: moved = try await spamFilter.block(message, kind: entryKind)
            case .trust: moved = try await spamFilter.trust(message, kind: entryKind)
            }
            onChange?()
            if moved {
                dismiss()
            } else {
                activeAlert = AlertItem(
                    title: "Listeneintrag",
                    message: "\(value) steht jetzt auf der \(kind == .block ? "Blacklist" : "Whitelist")."
                )
            }
        } catch FilterListError.alreadyOnOtherList(let list) {
            let other = list == .white ? "Whitelist" : "Blacklist"
            activeAlert = AlertItem(
                title: "Listeneintrag",
                message: "\(value) steht bereits auf der \(other). Entferne den Eintrag dort zuerst."
            )
        } catch {
            activeAlert = .failure("Listeneintrag fehlgeschlagen", error)
        }
    }

    // MARK: - Teilen & Drucken

    /// Druckt die Mail samt Kopfdaten und Anhangliste.
    private func printMessage() {
        let html = Self.printableHTML(for: message, attachments: attachments)
        MailPrinter().print(html: html)
    }

    /// Formatiertes HTML mit Kopfdaten und Anhangliste für Druck und Teilen.
    ///
    /// Verarbeitung: Kopfdaten und Text werden für HTML maskiert; eine
    /// reine Textmail erscheint als vorformatierter Block. Breite Tabellen
    /// und Bilder werden auf die Seitenbreite begrenzt.
    ///
    /// - Parameters:
    ///   - message: Mail.
    ///   - attachments: Anhänge für die Liste am Ende.
    /// - Returns: Vollständiges HTML-Dokument.
    static func printableHTML(for message: CachedMessage, attachments: [CachedAttachment] = []) -> String {
        var header = "<b>Von:</b> \(Self.escaped(message.from))<br>"
        header += "<b>An:</b> \(Self.escaped(message.to))<br>"
        if !message.headers.ccList.isEmpty {
            header += "<b>Kopie:</b> \(Self.escaped(message.headers.ccList.joined(separator: ", ")))<br>"
        }
        if let date = message.date {
            let fmt = DateFormatter()
            fmt.dateStyle = .full
            fmt.timeStyle = .short
            fmt.locale = Locale(identifier: "de_DE")
            header += "<b>Datum:</b> \(fmt.string(from: date))<br>"
        }
        header += "<b>Betreff:</b> \(Self.escaped(message.subject))<br>"

        let body = message.htmlBody ?? "<pre>\(Self.escaped(message.textBody ?? ""))</pre>"

        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body {
                    font-family: -apple-system, Helvetica, sans-serif;
                    font-size: 12pt;
                    color: #333;
                    margin: 0;
                    padding: 0;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                .mail-header {
                    border-bottom: 1px solid #ccc;
                    padding-bottom: 8pt;
                    margin-bottom: 12pt;
                    font-size: 10pt;
                    line-height: 1.6;
                }
                table, div, td, th, img, video, object {
                    max-width: 100% !important;
                    height: auto !important;
                }
                table[width], td[width], th[width] {
                    width: auto !important;
                }
                img { display: block; }
                pre, code {
                    white-space: pre-wrap;
                    word-wrap: break-word;
                    max-width: 100%;
                }
            </style>
            </head>
            <body>
            <div class="mail-header">\(header)</div>
            \(body)
            \(attachmentSection(attachments))
            </body>
            </html>
            """
    }

    /// Anhangliste für Druck und Teilen.
    ///
    /// - Parameter attachments: Anhänge.
    /// - Returns: HTML-Abschnitt; leer ohne Anhänge.
    private static func attachmentSection(_ attachments: [CachedAttachment]) -> String {
        guard !attachments.isEmpty else { return "" }
        var rows = ""
        for a in attachments {
            let icon = attachmentIcon(for: a.contentType)
            let size = formattedSize(a.sizeBytes)
            rows += "<tr><td style=\"padding:4pt 8pt 4pt 0\">\(icon)</td>"
            rows += "<td style=\"padding:4pt 0\">\(escaped(a.filename))</td>"
            rows += "<td style=\"padding:4pt 0 4pt 12pt;color:#888\">\(size)</td></tr>"
        }
        return """
            <div style="border-top:1px solid #ccc;margin-top:16pt;padding-top:8pt;font-size:10pt">
            <b>Anlagen (\(attachments.count)):</b>
            <table style="margin-top:4pt">\(rows)</table>
            </div>
            """
    }

    /// Symbol für einen Anhang nach seinem MIME-Typ.
    ///
    /// - Parameter contentType: MIME-Typ.
    /// - Returns: Emoji für die Anhangliste.
    private static func attachmentIcon(for contentType: String) -> String {
        let ct = contentType.lowercased()
        if ct.hasPrefix("image/") { return "🖼️" }
        if ct.contains("pdf") { return "📄" }
        if ct.contains("zip") || ct.contains("archive") || ct.contains("compressed") { return "📦" }
        if ct.contains("text/") { return "📝" }
        if ct.contains("audio/") { return "🎵" }
        if ct.contains("video/") { return "🎬" }
        return "📎"
    }

    /// Lesbare Größe (B, KB, MB).
    ///
    /// - Parameter bytes: Größe in Bytes.
    /// - Returns: Größe mit Einheit.
    private static func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }

    /// Maskiert `&`, `<` und `>` für HTML.
    ///
    /// - Parameter text: Rohtext.
    /// - Returns: Maskierter Text.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Anlagen lokal löschen

    /// Fragt vor dem lokalen Löschen der Anhang-Daten nach.
    private func confirmDeleteLocalAttachments() {
        activeConfirmation = ConfirmationRequest(
            title: "Anlagen lokal löschen?",
            message: "Die Anhang-Daten werden lokal gelöscht, um Speicher freizugeben. Die Metadaten bleiben erhalten und die Anhänge können erneut vom Server geladen werden.",
            confirmLabel: "Löschen"
        ) {
            deleteLocalAttachments()
        }
    }

    /// Löscht die Daten aller Anhänge dieser Mail aus dem Cache; die
    /// Einträge bleiben, die Daten lassen sich neu laden.
    private func deleteLocalAttachments() {
        for attachment in attachments {
            MessageStore.shared.deleteAttachmentData(id: attachment.id)
        }
        attachments = MessageStore.shared.attachments(forMessage: message.id)
        shareURLs.removeAll()
    }

    // MARK: - Anhänge öffnen

    /// Öffnet die Vorschau eines Anhangs; fehlen die Daten, werden sie
    /// zuerst nachgeladen.
    ///
    /// - Parameter attachment: Angetippter Anhang.
    private func handleTap(_ attachment: CachedAttachment) {
        if attachment.data != nil {
            openPreview(attachment)
        } else {
            Task { await downloadAndPreview(attachment) }
        }
    }

    /// Schreibt den Anhang in eine temporäre Datei und öffnet QuickLook.
    ///
    /// - Parameter attachment: Anhang mit Daten.
    private func openPreview(_ attachment: CachedAttachment) {
        do {
            previewURL = try AttachmentManager.writeTempFile(for: attachment)
        } catch {
            activeAlert = .failure("Vorschau nicht möglich", error)
        }
    }

    /// Lädt einen Anhang vom Server nach und öffnet danach die Vorschau.
    ///
    /// - Parameter attachment: Anhang ohne Daten.
    @MainActor
    private func downloadAndPreview(_ attachment: CachedAttachment) async {
        downloadingIDs.insert(attachment.id)
        defer { downloadingIDs.remove(attachment.id) }
        do {
            let updated = try await AttachmentManager.downloadAttachment(
                attachment,
                message: message,
                accountStore: accountStore
            )
            if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                attachments[index] = updated
            }
            prepareShareURLs()
            openPreview(updated)
        } catch {
            activeAlert = .failure("Download fehlgeschlagen", error)
        }
    }

    /// Schreibt alle geladenen Anhänge als temporäre Dateien, damit das
    /// Teilen ohne Verzögerung bereitsteht.
    private func prepareShareURLs() {
        for attachment in attachments where attachment.data != nil && shareURLs[attachment.id] == nil {
            if let url = try? AttachmentManager.writeTempFile(for: attachment) {
                shareURLs[attachment.id] = url
            }
        }
    }
}
