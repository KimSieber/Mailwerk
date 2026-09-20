//
//  MessageDetailView.swift
//  Mailwerk
//

import SwiftUI
import QuickLook

struct MessageDetailView: View {
    let message: CachedMessage
    let accountStore: AccountStore
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

    init(
        message: CachedMessage,
        accountStore: AccountStore,
        onChange: (() -> Void)? = nil
    ) {
        self.message = message
        self.accountStore = accountStore
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
                if isProcessingAction {
                    ProgressView()
                } else {
                    messageMenu
                }
            }
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
                        accountStore: accountStore
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
                Button(action: {}) {
                    Label("Antworten", systemImage: "arrowshape.turn.up.left")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Allen antworten", systemImage: "arrowshape.turn.up.left.2")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Weiterleiten", systemImage: "arrowshape.turn.up.right")
                }
                .disabled(true)
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
                Button(action: {}) {
                    Label("Als Spam verschieben", systemImage: "xmark.bin")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Absender → Blacklist", systemImage: "person.crop.circle.badge.xmark")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Absender-Domain → Blacklist", systemImage: "globe.badge.chevron.backward")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Absender → Whitelist", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Absender-Domain → Whitelist", systemImage: "globe")
                }
                .disabled(true)
            }

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
                accountStore: accountStore
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
                accountStore: accountStore
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
                accountStore: accountStore
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
                accountStore: accountStore
            )
            MessageStore.shared.deleteMessage(id: message.id)
            onChange?()
            dismiss()
        } catch {
            errorMessage = "Verschieben fehlgeschlagen: \(error.localizedDescription)"
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
