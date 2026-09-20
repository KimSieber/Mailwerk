//
//  InboxView.swift
//  Mailwerk
//

import SwiftUI

struct InboxView: View {
    let accountStore: AccountStore
    @State private var viewModel: InboxViewModel
    @State private var showingAccounts = false
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?
    @State private var processingMessageIDs: Set<String> = []
    
    init(accountStore: AccountStore) {
        self.accountStore = accountStore
        _viewModel = State(initialValue: InboxViewModel(accountStore: accountStore))
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
                                onChange: { viewModel.loadFromCache() }
                            )
                        } label: {
                            InboxRow(message: message)
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
                        showingAccounts = true
                    } label: {
                        Label("Postfächer", systemImage: "envelope.badge.person.crop")
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
                accountStore: accountStore
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
                accountStore: accountStore
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.from)
                    .font(message.isUnread ? .headline : .subheadline)
                Spacer()
                if message.isFlagged {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if message.hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let date = message.date {
                    Text(date, format: .dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits).year().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(message.subject)
                .font(message.isUnread ? .headline : .body)
                .lineLimit(1)
            Text(message.accountDisplayName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
