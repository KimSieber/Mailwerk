//
//  AccountListView.swift
//  Mailwerk
//
//  Zweck: Postfachverwaltung – Liste der Postfächer mit Farbe, Name und
//  E-Mail-Adresse; Hinzufügen, Bearbeiten (Tipp) und Entfernen (Wischen);
//  je Postfach der Schalter „Abruf“ (nur dieses Gerät; aus = nicht über
//  „Alle Eingänge“ abrufen, Pause-Zeichen vor dem Namen); rotes
//  Warnzeichen, wenn die Anmeldung eines Postfachs abgelaufen ist; Wahl
//  des Standard-Postfachs für neue Mails.
//
//  Ein Postfach zu entfernen löscht auch seinen gesamten Cache, sein
//  Passwort aus dem Schlüsselbund und seine Signatur. Deshalb gibt es davor eine Rückfrage –
//  auch beim Wischen. Meldungen und Rückfragen laufen über je einen Kanal
//  (siehe Dialogs.swift).
//
//  Getönte Fläche, Abschnitte als Karten wie in der ganzen App (AppTheme).
//
//  Abgrenzung: Anlegen → AddAccountView; Bearbeiten → EditAccountView;
//  Speichern und Entfernen → AccountStore.
//
//  Abhängigkeiten: SwiftUI, AccountStore, SignatureStore, Dialogs, Log,
//  FetchPausedBadge, SignInRequiredBadge, OAuthSignInState, AppTheme,
//  ExternalMailtoPresenter (Blätter melden sich als offene Fenster).
//

import SwiftUI
import os

/// Postfachverwaltung.
struct AccountListView: View {
    /// Quelle und Ablage der Postfächer.
    let accountStore: AccountStore
    /// Speicher der Signaturen (wird beim Entfernen eines Postfachs bereinigt).
    @Environment(SignatureStore.self) private var signatureStore
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
                    // Hinweis frei auf der getönten Fläche, ohne Karte.
                    .listRowBackground(Color.clear)
                } else {
                    accountSection
                        .cardRowBackground()
                    defaultAccountSection
                        .cardRowBackground()
                }
            }
            .appBackground()
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
                    .countsAsOpenWindow()
            }
            .sheet(item: $editingAccount) { account in
                EditAccountView(accountStore: accountStore, account: account)
                    .countsAsOpenWindow()
            }
            .confirmationRequest($activeConfirmation)
        }
        .alertItem($activeAlert)
        .macSheetFrame(.list)
    }

    // MARK: - Abschnitte

    /// Postfächer mit Farbpunkt, Name und E-Mail-Adresse sowie Schalter
    /// „Abruf“; Tipp auf den Namen bearbeitet, Wischen entfernt (nach
    /// Rückfrage).
    ///
    /// Verarbeitung: Knopf und Schalter liegen in derselben Zeile; der
    /// Knopf ist randlos, damit die Liste jedem seine eigenen Tipps gibt.
    private var accountSection: some View {
        Section {
            ForEach(accountStore.accounts) { account in
                HStack(spacing: 10) {
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
                                HStack(spacing: 6) {
                                    if OAuthSignInState.shared.isSignInRequired(account.id) {
                                        SignInRequiredBadge(font: .headline)
                                    }
                                    if !accountStore.isFetchEnabled(account.id) {
                                        FetchPausedBadge(font: .headline)
                                    }
                                    Text(account.displayName)
                                        .font(.headline)
                                }
                                Text(account.senderAddress)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .tint(.primary)

                    Toggle("Abruf", isOn: fetchBinding(for: account.id))
                        .labelsHidden()
                        .help("Abruf über „Alle Eingänge“ (nur dieses Gerät)")
                        .accessibilityLabel("Abruf \(account.displayName)")
                }
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

    /// Bindung an den Schalter „Abruf“ eines Postfachs.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: Bindung an `AccountStore.isFetchEnabled`.
    private func fetchBinding(for accountID: UUID) -> Binding<Bool> {
        Binding(
            get: { accountStore.isFetchEnabled(accountID) },
            set: { accountStore.setFetchEnabled($0, for: accountID) }
        )
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
            message: "Die gespeicherten Mails und die Zugangsdaten werden gelöscht. Auf dem Server bleibt alles erhalten.",
            confirmLabel: "Entfernen"
        ) {
            removeAccounts(accounts)
        }
    }

    /// Entfernt die Postfächer samt Cache, Passwort und Signatur.
    ///
    /// Verarbeitung: Scheitert ein Postfach, werden die übrigen trotzdem
    /// entfernt; die Fehler erscheinen gesammelt. Lässt sich die Signatur
    /// nicht löschen, wird das nur protokolliert – das Postfach ist dann
    /// schon entfernt, die Signatur bleibt ohne Wirkung.
    ///
    /// - Parameter accounts: Zu entfernende Postfächer.
    private func removeAccounts(_ accounts: [MailAccount]) {
        var failures: [String] = []
        for account in accounts {
            do {
                try accountStore.removeAccount(account)
                do {
                    try signatureStore.remove(accountID: account.id)
                } catch {
                    Log.store.error("⚠️ Signatur nicht entfernt: \(error.localizedDescription, privacy: .public)")
                }
            } catch {
                failures.append("„\(account.displayName)“: \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            activeAlert = AlertItem(title: "Entfernen fehlgeschlagen", message: failures.joined(separator: "\n"))
        }
    }
}
