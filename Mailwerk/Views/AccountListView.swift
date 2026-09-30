//
//  AccountListView.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//
//  v0.1.8d: Ein Postfach zu entfernen löscht auch seinen gesamten Cache
//  und sein Passwort aus dem Schlüsselbund. Deshalb gibt es davor eine
//  Rückfrage – auch beim Wischen.
//
//  Bewusst ein Hinweisdialog (`alert`) statt eines `confirmationDialog`
//  wie an anderen Stellen: Der erscheint mittig und zeigt beide Knöpfe.
//  Ein `confirmationDialog` wird am Listeneintrag als Sprechblase gezeigt
//  und blendet „Abbrechen“ aus, weil ein Tipp daneben abbricht – für eine
//  nicht umkehrbare Aktion zu wenig deutlich.
//

import SwiftUI

struct AccountListView: View {
    let accountStore: AccountStore
    @State private var showingAddAccount = false
    @State private var editingAccount: MailAccount?
    @State private var deleteError: String?
    /// Postfächer, deren Entfernen gerade bestätigt werden soll.
    @State private var pendingDeletion: [MailAccount]?
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
                        .onDelete { offsets in
                            // Erst bestätigen lassen – die Indizes gelten
                            // nur jetzt, also die Postfächer gleich merken.
                            pendingDeletion = offsets.map { accountStore.accounts[$0] }
                        }
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
                deletionTitle,
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { accounts in
                Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
                Button("Entfernen", role: .destructive) { deleteAccounts(accounts) }
            } message: { _ in
                Text("Die gespeicherten Mails und das Passwort werden gelöscht. Auf dem Server bleibt alles erhalten.")
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
        .macSheetFrame(.list)
    }

    // MARK: - Standard-Postfach

    private var defaultAccountBinding: Binding<UUID?> {
        Binding(
            get: { accountStore.defaultAccountID },
            set: { accountStore.setDefaultAccount($0) }
        )
    }

    // MARK: - Löschen

    /// Titel der Rückfrage – nennt das Postfach beim Namen.
    private var deletionTitle: String {
        guard let pendingDeletion else { return "" }
        if pendingDeletion.count == 1, let account = pendingDeletion.first {
            return "„\(account.displayName)“ entfernen?"
        }
        return "\(pendingDeletion.count) Postfächer entfernen?"
    }

    private func deleteAccounts(_ toDelete: [MailAccount]) {
        pendingDeletion = nil
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
