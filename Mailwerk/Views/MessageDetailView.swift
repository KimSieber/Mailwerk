//
//  MessageDetailView.swift
//  Mailwerk
//

import SwiftUI
import QuickLook

struct MessageDetailView: View {
    let message: CachedMessage
    let accountStore: AccountStore
    let spamFilter: SpamFilterService
    let onChange: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var webViewHeight: CGFloat = 100
    @State private var attachments: [CachedAttachment] = []
    @State private var previewURL: URL?
    @State private var shareURLs: [String: URL] = [:]
    @State private var downloadingIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var showDeleteAttachmentsConfirm = false

    // MARK: - Basis-Aktionen (v0.1.2)
    @State private var isUnread: Bool
    @State private var isFlagged: Bool
    @State private var isProcessingAction = false
    @State private var showDeleteMessageConfirm = false
    @State private var showFolderPicker = false
    @State private var folders: [MailFolder] = []
    @State private var isLoadingFolders = false

    // MARK: - Verfassen (v0.1.4)
    @State private var composeRequest: ComposeRequest?

    // MARK: - Spam (v0.1.5)
    @State private var pendingSpamAction: SpamActionRequest?
    @State private var spamStatusMessage: String?

    /// Eine angefragte Listenaktion, die noch bestätigt werden muss.
    private struct SpamActionRequest: Identifiable {
        enum Kind { case block, trust }
        let id = UUID()
        let kind: Kind
        let entryKind: FilterEntryKind
        let value: String

        var title: String {
            switch kind {
            case .block: return "\(value) blockieren?"
            case .trust: return "\(value) vertrauen?"
            }
        }

        var explanation: String {
            let scope = entryKind == .domain
                ? "Alle künftigen Mails dieser Domain"
                : "Alle künftigen Mails dieses Absenders"
            switch kind {
            case .block:
                return "\(scope) wandern in den Spam-Ordner. Diese Mail wird mitverschoben."
            case .trust:
                return "\(scope) bleiben im Posteingang. Liegt diese Mail im Spam-Ordner, wird sie zurückgeholt."
            }
        }

        var confirmLabel: String {
            kind == .block ? "Blockieren" : "Vertrauen"
        }
    }

    /// Kapselt die Art der zu verfassenden Nachricht für das Sheet.
    private struct ComposeRequest: Identifiable {
        let id = UUID()
        let kind: ComposeKind
    }

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: - Header
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
                Divider()

                // MARK: - Body
                if let html = message.htmlBody {
                    HTMLMailView(html: html, contentHeight: $webViewHeight)
                        .frame(height: max(100, webViewHeight))
                } else if let text = message.textBody {
                    Text(text)
                } else {
                    Text("Kein Inhalt verfügbar").foregroundStyle(.secondary)
                }

                // MARK: - Anhänge
                if !attachments.isEmpty {
                    Divider()

                    Label(
                        "Anhänge (\(attachments.count))",
                        systemImage: "paperclip"
                    )
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
            .padding()
        }
        .navigationTitle(message.accountDisplayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Tap antwortet direkt, langes Drücken zeigt alle Varianten
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
        .sheet(item: $composeRequest) { request in
            ComposeView(
                accountStore: accountStore,
                kind: request.kind,
                original: message,
                onSent: { onChange?() }
            )
        }
        .quickLookPreview($previewURL)
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Anlagen lokal löschen?",
            isPresented: $showDeleteAttachmentsConfirm,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                deleteLocalAttachments()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Anhang-Daten werden lokal gelöscht, um Speicher freizugeben. Die Metadaten bleiben erhalten und die Anhänge können erneut vom Server geladen werden.")
        }
        .confirmationDialog(
            "Mail löschen?",
            isPresented: $showDeleteMessageConfirm,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                Task { await deleteMessageAction() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Mail wird auf dem Server gelöscht bzw. in den Papierkorb verschoben.")
        }
        .confirmationDialog(
            pendingSpamAction?.title ?? "",
            isPresented: Binding(
                get: { pendingSpamAction != nil },
                set: { if !$0 { pendingSpamAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingSpamAction
        ) { request in
            Button(request.confirmLabel, role: request.kind == .block ? .destructive : nil) {
                Task { await performSpamAction(request) }
            }
            Button("Abbrechen", role: .cancel) { pendingSpamAction = nil }
        } message: { request in
            Text(request.explanation)
        }
        .alert(
            "Listeneintrag",
            isPresented: Binding(
                get: { spamStatusMessage != nil },
                set: { if !$0 { spamStatusMessage = nil } }
            )
        ) {
            Button("OK") { spamStatusMessage = nil }
        } message: {
            Text(spamStatusMessage ?? "")
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheet(
                folders: folders,
                isLoading: isLoadingFolders
            ) { folder in
                Task { await moveMessageAction(to: folder) }
            }
        }
        .task {
            attachments = MessageStore.shared.attachments(forMessage: message.id)
            prepareShareURLs()

            // Ungelesene Mail beim Öffnen als gelesen markieren
            if isUnread {
                do {
                    try await MailActionService.setRead(
                        uid: Int(message.uid),
                        isRead: true,
                        accountID: message.accountID,
                        accountStore: accountStore,
                        folder: message.folder
                    )
                    MessageStore.shared.updateFlags(messageID: message.id, isUnread: false)
                    isUnread = false
                    onChange?()
                } catch {
                    print("⚠️ Gelesen-Markierung fehlgeschlagen: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Aktionsmenü

    private var messageMenu: some View {
        Menu {
            // ── Kommunikation ──
            Section {
                replyButtons
            }

            // ── Organisation ──
            Section {
                Button {
                    Task { await toggleFlagAction() }
                } label: {
                    Label(
                        isFlagged ? "Kennzeichnung entfernen" : "Kennzeichnen",
                        systemImage: isFlagged ? "flag.slash" : "flag"
                    )
                }
                .disabled(isProcessingAction)

                Button {
                    Task { await toggleReadAction() }
                } label: {
                    Label(
                        isUnread ? "Als gelesen markieren" : "Als ungelesen markieren",
                        systemImage: isUnread ? "envelope.open" : "envelope.badge"
                    )
                }
                .disabled(isProcessingAction)

                Button {
                    presentFolderPicker()
                } label: {
                    Label("In Ordner verschieben", systemImage: "folder")
                }
                .disabled(isProcessingAction)
            }

            // ── Spam ──
            Section {
                if let sender = FilterAddress.sender(fromHeader: message.from) {
                    Button {
                        pendingSpamAction = SpamActionRequest(
                            kind: .block, entryKind: .address, value: sender.address
                        )
                    } label: {
                        Label("\(sender.address) blockieren", systemImage: "person.crop.circle.badge.xmark")
                    }

                    Button {
                        pendingSpamAction = SpamActionRequest(
                            kind: .block, entryKind: .domain, value: sender.domain
                        )
                    } label: {
                        Label("\(sender.domain) blockieren", systemImage: "globe.badge.chevron.backward")
                    }

                    Button {
                        pendingSpamAction = SpamActionRequest(
                            kind: .trust, entryKind: .address, value: sender.address
                        )
                    } label: {
                        Label("\(sender.address) vertrauen", systemImage: "person.crop.circle.badge.checkmark")
                    }

                    Button {
                        pendingSpamAction = SpamActionRequest(
                            kind: .trust, entryKind: .domain, value: sender.domain
                        )
                    } label: {
                        Label("\(sender.domain) vertrauen", systemImage: "globe")
                    }
                } else {
                    Label("Absender nicht auswertbar", systemImage: "questionmark.circle")
                }
            }
            .disabled(isProcessingAction)

            // ── Sonstiges ──
            Section {
                Button(action: {}) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Drucken", systemImage: "printer")
                }
                .disabled(true)

                if hasLocalAttachmentData {
                    Button(role: .destructive) {
                        showDeleteAttachmentsConfirm = true
                    } label: {
                        Label("Anlagen lokal löschen", systemImage: "trash")
                    }
                }

                Button(role: .destructive) {
                    showDeleteMessageConfirm = true
                } label: {
                    Label("Mail löschen", systemImage: "trash.fill")
                }
                .disabled(isProcessingAction)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    /// Antworten, Allen antworten und Weiterleiten – im Menü und in der Toolbar.
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

    /// Prüft ob mindestens ein Anhang lokale Daten hat, die gelöscht werden könnten.
    private var hasLocalAttachmentData: Bool {
        attachments.contains { $0.data != nil }
    }

    // MARK: - Basis-Aktionen (v0.1.2)

    @MainActor
    private func toggleReadAction() async {
        isProcessingAction = true
        defer { isProcessingAction = false }

        let markAsRead = isUnread  // aktuell ungelesen → Tap markiert als gelesen
        do {
            try await MailActionService.setRead(
                uid: Int(message.uid),
                isRead: markAsRead,
                accountID: message.accountID,
                accountStore: accountStore,
                folder: message.folder
            )
            MessageStore.shared.updateFlags(messageID: message.id, isUnread: !markAsRead)
            isUnread = !markAsRead
            onChange?()
        } catch {
            errorMessage = "Aktion fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func toggleFlagAction() async {
        isProcessingAction = true
        defer { isProcessingAction = false }

        let newFlagged = !isFlagged
        do {
            try await MailActionService.setFlagged(
                uid: Int(message.uid),
                isFlagged: newFlagged,
                accountID: message.accountID,
                accountStore: accountStore,
                folder: message.folder
            )
            MessageStore.shared.updateFlagged(messageID: message.id, isFlagged: newFlagged)
            isFlagged = newFlagged
            onChange?()
        } catch {
            errorMessage = "Aktion fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteMessageAction() async {
        isProcessingAction = true
        defer { isProcessingAction = false }

        do {
            try await MailActionService.deleteMessage(
                uid: Int(message.uid),
                accountID: message.accountID,
                accountStore: accountStore,
                folder: message.folder
            )
            MessageStore.shared.deleteMessage(id: message.id)
            onChange?()
            dismiss()
        } catch {
            errorMessage = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func presentFolderPicker() {
        showFolderPicker = true
        guard folders.isEmpty else { return }
        Task { await loadFolders() }
    }

    @MainActor
    private func loadFolders() async {
        isLoadingFolders = true
        defer { isLoadingFolders = false }

        do {
            folders = try await MailActionService.fetchFolders(
                accountID: message.accountID,
                accountStore: accountStore
            )
        } catch {
            errorMessage = "Ordnerliste konnte nicht geladen werden: \(error.localizedDescription)"
            showFolderPicker = false
        }
    }

    @MainActor
    private func moveMessageAction(to folder: MailFolder) async {
        isProcessingAction = true
        defer { isProcessingAction = false }

        do {
            try await MailActionService.moveMessage(
                uid: Int(message.uid),
                toFolder: folder.id,
                accountID: message.accountID,
                accountStore: accountStore,
                folder: message.folder
            )
            MessageStore.shared.deleteMessage(id: message.id)
            onChange?()
            dismiss()
        } catch {
            errorMessage = "Verschieben fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Spam-Aktionen (v0.1.5)

    @MainActor
    private func performSpamAction(_ request: SpamActionRequest) async {
        pendingSpamAction = nil
        isProcessingAction = true
        defer { isProcessingAction = false }

        do {
            let moved: Bool
            switch request.kind {
            case .block:
                moved = try await spamFilter.block(message, kind: request.entryKind)
            case .trust:
                moved = try await spamFilter.trust(message, kind: request.entryKind)
            }
            onChange?()

            // Verschoben heißt: Diese Ansicht zeigt eine Mail, die hier nicht
            // mehr liegt – also zurück zur Liste.
            if moved {
                dismiss()
            } else {
                spamStatusMessage = "\(request.value) steht jetzt auf der \(request.kind == .block ? "Blacklist" : "Whitelist")."
            }
        } catch FilterListError.alreadyOnOtherList(let list) {
            let other = list == .white ? "Whitelist" : "Blacklist"
            spamStatusMessage = "\(request.value) steht bereits auf der \(other). Entferne den Eintrag dort zuerst."
        } catch {
            errorMessage = "Listeneintrag fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Anlagen lokal löschen

    private func deleteLocalAttachments() {
        for attachment in attachments {
            MessageStore.shared.deleteAttachmentData(id: attachment.id)
        }
        // Anhänge-Liste neu laden
        attachments = MessageStore.shared.attachments(forMessage: message.id)
        // Share-URLs bereinigen
        shareURLs.removeAll()
    }

    // MARK: - Tap-Handling

    private func handleTap(_ attachment: CachedAttachment) {
        if attachment.data != nil {
            openPreview(attachment)
        } else {
            Task { await downloadAndPreview(attachment) }
        }
    }

    private func openPreview(_ attachment: CachedAttachment) {
        do {
            let url = try AttachmentManager.writeTempFile(for: attachment)
            previewURL = url
        } catch {
            errorMessage = "Vorschau nicht möglich: \(error.localizedDescription)"
        }
    }

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
            errorMessage = "Download fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Share-URLs vorbereiten

    private func prepareShareURLs() {
        for attachment in attachments where attachment.data != nil {
            if shareURLs[attachment.id] == nil {
                if let url = try? AttachmentManager.writeTempFile(for: attachment) {
                    shareURLs[attachment.id] = url
                }
            }
        }
    }
}

// MARK: - Ordner-Auswahl (Sheet)

private struct FolderPickerSheet: View {
    let folders: [MailFolder]
    let isLoading: Bool
    let onSelect: (MailFolder) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Ordner werden geladen …")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if folders.isEmpty {
                    ContentUnavailableView(
                        "Keine Ordner gefunden",
                        systemImage: "folder"
                    )
                } else {
                    List(folders) { folder in
                        Button {
                            onSelect(folder)
                            dismiss()
                        } label: {
                            Label(folder.name, systemImage: icon(for: folder))
                        }
                    }
                }
            }
            .navigationTitle("In Ordner verschieben")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func icon(for folder: MailFolder) -> String {
        switch folder.specialUse {
        case .trash:   return "trash"
        case .sent:    return "paperplane"
        case .drafts:  return "doc"
        case .junk:    return "xmark.bin"
        case .archive: return "archivebox"
        case .flagged: return "flag"
        case .all:     return "tray.full"
        case nil:      return "folder"
        }
    }
}
