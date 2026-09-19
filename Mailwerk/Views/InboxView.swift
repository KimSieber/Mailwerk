//
//  InboxView.swift
//  Mailwerk
//

import SwiftUI

struct InboxView: View {
    let accountStore: AccountStore
    @State private var viewModel: InboxViewModel
    @State private var showingAccounts = false

    init(accountStore: AccountStore) {
        self.accountStore = accountStore
        _viewModel = State(initialValue: InboxViewModel(accountStore: accountStore))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.messages.isEmpty && !viewModel.isLoading {
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
                            MessageDetailView(message: message)
                        } label: {
                            InboxRow(message: message)
                        }
                    }
                }
            }
            .navigationTitle("Mailwerk")
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAccounts = true
                    } label: {
                        Label("Postfächer", systemImage: "envelope.badge.person.crop")
                    }
                }
            }
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.refresh() }
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
                if let date = message.date {
                    Text(date, style: .date)
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
