//
//  InboxView.swift
//  Mailwerk
//

import SwiftUI

struct InboxView: View {
    let accountStore: AccountStore
    let filterLists: any FilterListRepository
    let spamSettings: SpamSettings
    @State private var viewModel: InboxViewModel
    @State private var showingAccounts = false
    @State private var showingSpamSettings = false
    @State private var showingCompose = false
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?
    @State private var processingMessageIDs: Set<String> = []

    init(
        accountStore: AccountStore,
        filterLists: any FilterListRepository,
        spamSettings: SpamSettings
    ) {
        self.accountStore = accountStore
        self.filterLists = filterLists
        self.spamSettings = spamSettings
        _viewModel = State(initialValue: InboxViewModel(
            accountStore: accountStore,
            filterLists: filterLists,
            spamSettings: spamSettings
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.messages.isEmpty && viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Postfächer werden abgerufen …")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.messages.isEmpty {
                    ContentUnavailableView(
                        "Keine Nachrichten",
                        systemImage: "tray",
                        description: Text(
                            accountStore.accounts.isEmpty
                                ? "Richte zuerst ein Postfach ein."
                                : "Zieh nach unten, um abzurufen."
                        )
                    )
                } else {
                    List(viewModel.messages) { message in
                        NavigationLink {
                            MessageDetailView(
                                message: message,
                                accountStore: accountStore,
                                spamFilter: viewModel.spamFilter,
                                onChange: { viewModel.loadFromCache() }
                            )
                        } label: {
                            InboxRow(
                                message: message,
                                colorHex: accountStore.accounts
                                    .first(where: { $0.id == message.accountID })?.colorHex
                            )
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Task { await toggleRead(message) }
                            } label: {
                                Label(
                                    message.isUnread ? "Gelesen" : "Ungelesen",
                                    systemImage: message.isUnread ? "envelope.open" : "envelope.badge"
                                )
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await toggleFlag(message) }
                            } label: {
                                Label(
                                    message.isFlagged ? "Entflaggen" : "Flaggen",
                                    systemImage: message.isFlagged ? "flag.slash" : "flag"
                                )
                            }
                            .tint(.orange)
                        }
                        .disabled(processingMessageIDs.contains(message.id))
                    }
                }
            }
            .navigationTitle("Mailwerk")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isLoading && !viewModel.messages.isEmpty {
                        ProgressView()
                    }
                }
                ToolbarItem {
                    Button {
                        showingCompose = true
                    } label: {
                        Label("Neue Nachricht", systemImage: "square.and.pencil")
                    }
                    .disabled(accountStore.accounts.isEmpty)
                }
                ToolbarItem {
                    Menu {
                        Button {
                            showingAccounts = true
                        } label: {
                            Label("Postfächer", systemImage: "envelope")
                        }
                        Button {
                            showingSpamSettings = true
                        } label: {
                            Label("Spamfilter", systemImage: "shield")
                        }
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                }
            }
            .refreshable { await viewModel.refresh() }
            .task {
                guard !hasLoadedOnce else { return }
                hasLoadedOnce = true
                await viewModel.refresh()
            }
            .sheet(isPresented: $showingAccounts) {
                AccountListView(accountStore: accountStore)
            }
            .alert(
                "Spam-Ordner anlegen?",
                isPresented: Binding(
                    get: { viewModel.pendingSpamFolders.first != nil },
                    set: { _ in }
                ),
                presenting: viewModel.pendingSpamFolders.first
            ) { pending in
                Button("Anlegen") {
                    Task { await viewModel.createSpamFolder(for: pending) }
                }
                Button("Nicht jetzt", role: .cancel) {
                    viewModel.dismissSpamFolderRequest(pending, declineForSession: true)
                }
            } message: { pending in
                Text("Das Postfach „\(pending.account.displayName)“ hat keinen Spam-Ordner. Ohne ihn kann der Filter dort nichts aussortieren. Vorgeschlagen wird „\(pending.proposal)“.")
            }
            .sheet(isPresented: $showingSpamSettings) {
                SpamSettingsView(settings: spamSettings, filterLists: filterLists)
            }
            .sheet(isPresented: $showingCompose) {
                ComposeView(
                    accountStore: accountStore,
                    kind: .new,
                    onSent: { viewModel.loadFromCache() }
                )
            }
            .alert(
                "Fehler beim Abrufen",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "Aktion fehlgeschlagen",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Swipe-Aktionen

    @MainActor
    private func toggleRead(_ message: CachedMessage) async {
        processingMessageIDs.insert(message.id)
        defer { processingMessageIDs.remove(message.id) }

        let markAsRead = message.isUnread
        do {
            try await MailActionService.setRead(
                uid: Int(message.uid),
                isRead: markAsRead,
                accountID: message.accountID,
                accountStore: accountStore,
                folder: message.folder
            )
            MessageStore.shared.updateFlags(messageID: message.id, isUnread: !markAsRead)
            viewModel.loadFromCache()
        } catch {
            errorMessage = "Status ändern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func toggleFlag(_ message: CachedMessage) async {
        processingMessageIDs.insert(message.id)
        defer { processingMessageIDs.remove(message.id) }

        let newFlagged = !message.isFlagged
        do {
            try await MailActionService.setFlagged(
                uid: Int(message.uid),
                isFlagged: newFlagged,
                accountID: message.accountID,
                accountStore: accountStore,
                folder: message.folder
            )
            MessageStore.shared.updateFlagged(messageID: message.id, isFlagged: newFlagged)
            viewModel.loadFromCache()
        } catch {
            errorMessage = "Kennzeichnen fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

private struct InboxRow: View {
    let message: CachedMessage
    let colorHex: String?

    var body: some View {
        HStack(spacing: 0) {
            // Farbstreifen am linken Rand (nur wenn Farbe gesetzt)
            if let hex = colorHex {
                Color(hex: hex)
                    .frame(width: 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.from)
                        .font(message.isUnread ? .headline : .subheadline)
                        .lineLimit(1)
                    Spacer()
                    if message.isAnswered {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Beantwortet")
                    }
                    if message.isForwarded {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Weitergeleitet")
                    }
                    if message.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if message.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(message.date ?? Date(), format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(message.subject)
                    .font(.subheadline)
                    .lineLimit(1)

                if let body = message.textBody {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, colorHex != nil ? 8 : 0)
        }
    }
}
