//
//  ComposeView.swift
//  Mailwerk
//
//  Created by Kim Sieber on 22.09.26.
//


//
//  ComposeView.swift
//  Mailwerk
//
//  Verfassen-Fenster für neue Mails, Antworten und Weiterleitungen.
//  Aufbau von oben nach unten: Absender, An, Cc (immer sichtbar),
//  Bcc auf Knopfdruck, Betreff, Anhänge, Editor mit Formatierungsleiste
//  und darunter der zitierte Originaltext (schreibgeschützt).
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct ComposeView: View {
    @State private var model: ComposeViewModel
    /// Wird nach erfolgreichem Versand aufgerufen (Inbox aktualisieren).
    private let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardConfirm = false
    @State private var showFileImporter = false
    @State private var showQuote = false
    @State private var quoteHeight: CGFloat = 200
    @State private var showWarnings = false
    #if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    #endif

    init(
        accountStore: AccountStore,
        kind: ComposeKind,
        original: CachedMessage? = nil,
        onSent: @escaping () -> Void = {}
    ) {
        _model = State(
            initialValue: ComposeViewModel(
                accountStore: accountStore, kind: kind, original: original
            )
        )
        self.onSent = onSent
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                editor
                Divider()
                bottomBar
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(model.hasContent)
            .confirmationDialog(
                "Entwurf verwerfen?",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Verwerfen", role: .destructive) { dismiss() }
                Button("Weiter bearbeiten", role: .cancel) {}
            } message: {
                Text("Die Nachricht wurde noch nicht gesendet und geht verloren.")
            }
            .alert(
                "Versand fehlgeschlagen",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert("Hinweis zum Versand", isPresented: $showWarnings) {
                Button("OK") {
                    onSent()
                    dismiss()
                }
            } message: {
                Text(model.warnings.joined(separator: "\n\n"))
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
        }
    }

    // MARK: - Kopfbereich

    private var header: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                senderRow
                Divider()
                RecipientField(label: "An", addresses: $model.to)
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    RecipientField(label: "Cc", addresses: $model.cc)
                    if !model.showBcc {
                        Button("Bcc") { model.showBcc = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }
                if model.showBcc {
                    Divider()
                    RecipientField(label: "Bcc", addresses: $model.bcc)
                }
                Divider()
                HStack(spacing: 8) {
                    Text("Betreff")
                        .foregroundStyle(.secondary)
                    TextField("", text: $model.subject)
                }
                if !model.attachments.isEmpty || model.missingAttachmentCount > 0 {
                    Divider()
                    attachmentList
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 260)
    }

    private var senderRow: some View {
        HStack(spacing: 8) {
            Text("Von")
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Menu {
                ForEach(model.accounts) { account in
                    Button {
                        model.accountID = account.id
                    } label: {
                        if account.id == model.accountID {
                            Label(account.displayName, systemImage: "checkmark")
                        } else {
                            Text(account.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let hex = model.selectedAccount?.colorHex {
                        Circle().fill(Color(hex: hex)).frame(width: 10, height: 10)
                    }
                    Text(model.selectedAccount?.displayName ?? "Postfach wählen")
                        .foregroundStyle(model.selectedAccount == nil ? .secondary : .primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(model.attachments.enumerated()), id: \.offset) { _, attachment in
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.secondary)
                    Text(attachment.filename)
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(attachment.data.count), countStyle: .file
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.removeAttachment(attachment)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(attachment.filename) entfernen")
                }
            }
            if model.missingAttachmentCount > 0 {
                Text("\(model.missingAttachmentCount) Anhang/Anhänge werden beim Senden vom Server geladen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !model.attachments.isEmpty {
                Text("Gesamt: \(ByteCountFormatter.string(fromByteCount: Int64(model.totalAttachmentBytes), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Editor und Zitat

    private var editor: some View {
        VStack(spacing: 0) {
            RichTextEditor(text: $model.body, controller: model.controller)
                .frame(minHeight: 160)

            if let quoted = model.quotedHTML {
                Divider()
                DisclosureGroup(isExpanded: $showQuote) {
                    HTMLMailView(html: quoted, contentHeight: $quoteHeight)
                        .frame(height: max(120, min(quoteHeight, 400)))
                } label: {
                    Label(
                        model.kind == .forward ? "Weitergeleitete Nachricht" : "Zitierter Text",
                        systemImage: "text.quote"
                    )
                    .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                if model.hasContent { showDiscardConfirm = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(model.isSending)
        }
        ToolbarItem(placement: .primaryAction) {
            if model.isSending {
                ProgressView()
            } else {
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(!model.canSend)
            }
        }
    }

    /// Untere Leiste: Anhänge links, Formatierung rechts (scrollt bei Bedarf).
    private var bottomBar: some View {
        HStack(spacing: 4) {
            attachmentMenu
                .padding(.leading, 8)
            Divider().frame(height: 20)
            FormattingToolbar(controller: model.controller)
        }
    }

    private var attachmentMenu: some View {
        Menu {
            Button {
                showFileImporter = true
            } label: {
                Label("Datei anhängen", systemImage: "doc")
            }
            #if os(iOS)
            // Fotos laufen über den System-Picker
            Button {
                showPhotoPicker = true
            } label: {
                Label("Foto anhängen", systemImage: "photo")
            }
            #endif
        } label: {
            Image(systemName: "paperclip")
        }
        .disabled(model.isSending)
        #if os(iOS)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        #endif
    }

    #if os(iOS)
    @State private var showPhotoPicker = false
    #endif

    private var title: String {
        switch model.kind {
        case .new:       return "Neue Nachricht"
        case .reply:     return "Antworten"
        case .replyAll:  return "Allen antworten"
        case .forward:   return "Weiterleiten"
        }
    }

    // MARK: - Aktionen

    private func send() async {
        let sent = await model.send()
        guard sent else { return }
        if model.warnings.isEmpty {
            onSent()
            dismiss()
        } else {
            showWarnings = true
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let type = UTType(filenameExtension: url.pathExtension)
                    model.addAttachment(
                        filename: url.lastPathComponent,
                        mimeType: type?.preferredMIMEType ?? "application/octet-stream",
                        data: data
                    )
                } catch {
                    model.errorMessage = "Datei „\(url.lastPathComponent)“ konnte nicht gelesen werden: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            model.errorMessage = error.localizedDescription
        }
    }

    #if os(iOS)
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let name = item.supportedContentTypes.first?.preferredFilenameExtension.map {
                "Foto.\($0)"
            } ?? "Foto.jpg"
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            model.addAttachment(filename: name, mimeType: mime, data: data)
        } catch {
            model.errorMessage = "Foto konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }
    #endif
}