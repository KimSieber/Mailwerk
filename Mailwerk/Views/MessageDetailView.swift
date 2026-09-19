//
//  MessageDetailView.swift
//  Mailwerk
//

import SwiftUI
import QuickLook

struct MessageDetailView: View {
    let message: CachedMessage
    let accountStore: AccountStore

    @State private var webViewHeight: CGFloat = 100
    @State private var attachments: [CachedAttachment] = []
    @State private var previewURL: URL?
    @State private var shareURLs: [String: URL] = [:]
    @State private var downloadingIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var showDeleteAttachmentsConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: - Header
                Text(message.subject)
                    .font(.title2)
                    .bold()
                Text("Von: \(message.from)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !message.to.isEmpty {
                    Text("An: \(message.to)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let date = message.date {
                    Text(date, style: .date)
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
                messageMenu
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
        .task {
            attachments = MessageStore.shared.attachments(forMessage: message.id)
            prepareShareURLs()
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
                Button(action: {}) {
                    Label("Kennzeichnen", systemImage: "flag")
                }
                .disabled(true)

                Button(action: {}) {
                    Label(
                        message.isUnread ? "Als gelesen markieren" : "Als ungelesen markieren",
                        systemImage: message.isUnread ? "envelope.open" : "envelope.badge"
                    )
                }
                .disabled(true)

                Button(action: {}) {
                    Label("In Ordner verschieben", systemImage: "folder")
                }
                .disabled(true)
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

                Button(role: .destructive, action: {}) {
                    Label("Mail löschen", systemImage: "trash.fill")
                }
                .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    /// Prüft ob mindestens ein Anhang lokale Daten hat, die gelöscht werden könnten.
    private var hasLocalAttachmentData: Bool {
        attachments.contains { $0.data != nil }
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
