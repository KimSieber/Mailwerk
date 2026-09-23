//
//  AccountListView.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//

import SwiftUI

struct AccountListView: View {
    let accountStore: AccountStore
    @State private var showingAddAccount = false
    @State private var editingAccount: MailAccount?
    @State private var deleteError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if accountStore.accounts.isEmpty {
                    ContentUnavailableView(
                        "Keine Postfächer",
                        systemImage: "envelope",
                        description: Text("Füge dein erstes Postfach hinzu.")
                    )
                } else {
                    Section {
                        ForEach(accountStore.accounts) { account in
                            Button {
                                editingAccount = account
                            } label: {
                                HStack(spacing: 10) {
                                    // Farbpunkt, falls eine Farbe gewählt ist
                                    if let colorHex = account.colorHex {
                                        Circle()
                                            .fill(Color(hex: colorHex))
                                            .frame(width: 12, height: 12)
                                    }
                                    VStack(alignment: .leading) {
                                        Text(account.displayName)
                                            .font(.headline)
                                        Text(account.username)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                        .onDelete(perform: deleteAccounts)
                    }

                    Section {
                        Picker("Standard-Postfach", selection: defaultAccountBinding) {
                            Text("Keins").tag(UUID?.none)
                            ForEach(accountStore.accounts) { account in
                                Text(account.displayName).tag(Optional(account.id))
                            }
                        }
                        .pickerStyle(.menu)
                    } footer: {
                        Text("Wird beim Verfassen einer neuen Mail als Absender vorbelegt.")
                    }
                }
            }
            .navigationTitle("Postfächer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Label("Postfach hinzufügen", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView(accountStore: accountStore)
            }
            .sheet(item: $editingAccount) { account in
                EditAccountView(accountStore: accountStore, account: account)
            }
            .alert(
                "Löschen fehlgeschlagen",
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    // MARK: - Standard-Postfach

    private var defaultAccountBinding: Binding<UUID?> {
        Binding(
            get: { accountStore.defaultAccountID },
            set: { accountStore.setDefaultAccount($0) }
        )
    }

    // MARK: - Löschen

    private func deleteAccounts(at offsets: IndexSet) {
        // Erst die Konten ermitteln, dann löschen – sonst verschieben sich
        // die Indizes nach jedem removeAccount().
        let toDelete = offsets.map { accountStore.accounts[$0] }
        var failures: [String] = []

        for account in toDelete {
            do {
                try accountStore.removeAccount(account)
            } catch {
                failures.append("„\(account.displayName)“: \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            deleteError = failures.joined(separator: "\n")
        }
    }
}
