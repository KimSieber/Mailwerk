//
//  AccountListView.swift
//  Mailwerk
//
//  Zweck: Postfachverwaltung – Liste der Postfächer mit Farbe, Name und
//  Benutzername; Hinzufügen, Bearbeiten (Tipp) und Entfernen (Wischen);
//  Wahl des Standard-Postfachs für neue Mails.
//
//  Ein Postfach zu entfernen löscht auch seinen gesamten Cache und sein
//  Passwort aus dem Schlüsselbund. Deshalb gibt es davor eine Rückfrage –
//  auch beim Wischen. Meldungen und Rückfragen laufen über je einen Kanal
//  (siehe Dialogs.swift).
//
//  Abgrenzung: Anlegen → AddAccountView; Bearbeiten → EditAccountView;
//  Speichern und Entfernen → AccountStore.
//
//  Abhängigkeiten: SwiftUI, AccountStore, Dialogs.
//

import SwiftUI

/// Postfachverwaltung.
struct AccountListView: View {
    /// Quelle und Ablage der Postfächer.
    let accountStore: AccountStore
    /// Dialog „Postfach hinzufügen“ sichtbar.
    @State private var showingAddAccount = false
    /// Gerade bearbeitetes Postfach; `nil` = keines.
    @State private var editingAccount: MailAccount?
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?
    /// Einziger Rückfragekanal der Ansicht.
    @State private var activeConfirmation: ConfirmationRequest?
    @Environment(\.dismiss) private var dismiss

    /// Aufbau: Liste der Postfächer, Standard-Postfach, Symbolleiste,
    /// Sheets, Meldung und Rückfrage.
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
                    accountSection
                    defaultAccountSection
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
            .confirmationRequest($activeConfirmation)
        }
        .alertItem($activeAlert)
        .macSheetFrame(.list)
    }

    // MARK: - Abschnitte

    /// Postfächer mit Farbpunkt, Name und Benutzername; Tipp bearbeitet,
    /// Wischen entfernt (nach Rückfrage).
    private var accountSection: some View {
        Section {
            ForEach(accountStore.accounts) { account in
                Button {
                    editingAccount = account
                } label: {
                    HStack(spacing: 10) {
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
                // Die Indizes gelten nur jetzt – die Postfächer gleich merken.
                confirmRemoval(of: offsets.map { accountStore.accounts[$0] })
            }
        }
    }

    /// Wahl des Standard-Postfachs für neue Mails.
    private var defaultAccountSection: some View {
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

    /// Bindung an das Standard-Postfach des AccountStore.
    private var defaultAccountBinding: Binding<UUID?> {
        Binding(
            get: { accountStore.defaultAccountID },
            set: { accountStore.setDefaultAccount($0) }
        )
    }

    // MARK: - Entfernen

    /// Fragt vor dem Entfernen nach; die Frage nennt das Postfach beim Namen.
    ///
    /// - Parameter accounts: Zu entfernende Postfächer.
    private func confirmRemoval(of accounts: [MailAccount]) {
        guard !accounts.isEmpty else { return }
        let title = accounts.count == 1
            ? "„\(accounts[0].displayName)“ entfernen?"
            : "\(accounts.count) Postfächer entfernen?"
        activeConfirmation = ConfirmationRequest(
            title: title,
            message: "Die gespeicherten Mails und das Passwort werden gelöscht. Auf dem Server bleibt alles erhalten.",
            confirmLabel: "Entfernen"
        ) {
            removeAccounts(accounts)
        }
    }

    /// Entfernt die Postfächer samt Cache und Passwort.
    ///
    /// Verarbeitung: Scheitert ein Postfach, werden die übrigen trotzdem
    /// entfernt; die Fehler erscheinen gesammelt.
    ///
    /// - Parameter accounts: Zu entfernende Postfächer.
    private func removeAccounts(_ accounts: [MailAccount]) {
        var failures: [String] = []
        for account in accounts {
            do {
                try accountStore.removeAccount(account)
            } catch {
                failures.append("„\(account.displayName)“: \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            activeAlert = AlertItem(title: "Entfernen fehlgeschlagen", message: failures.joined(separator: "\n"))
        }
    }
}
