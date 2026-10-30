//
//  AccountListView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Postfachverwaltung – Liste der Postfächer mit Farbe, Name und
//  E-Mail-Adresse; Hinzufügen, Bearbeiten (Tipp) und Entfernen (Wischen);
//  je Postfach der Schalter „Abruf“ (nur dieses Gerät; aus = nicht über
//  „Alle Eingänge“ abrufen, Pause-Zeichen vor dem Namen); rotes
//  Warnzeichen, wenn die Anmeldung eines Postfachs abgelaufen ist, gelbes,
//  wenn sein letzter Abruf den Server nicht erreichte (Kennzeichen über
//  AccountStatusBadges, mit Tooltip); Wahl des Standard-Postfachs für
//  neue Mails.
//
//  Ein Postfach zu entfernen löscht auch seinen gesamten Cache, sein
//  Passwort aus dem Schlüsselbund und seine Signatur. Deshalb gibt es davor eine Rückfrage –
//  auch beim Wischen. Meldungen und Rückfragen laufen über je einen Kanal
//  (siehe Dialogs.swift).
//
//  Getönte Fläche, Abschnitte als Karten wie in der ganzen App (AppTheme).
//
//  Mac: Kopfleiste oben mit ✓ (Fertig) statt Symbolleiste
//  (SheetHeaderBar); Inhalt als gruppiertes Formular: die Postfächer in
//  einer Karte mit hohen Zeilen und „>“ als Hinweis auf Bearbeiten,
//  darunter eine eigene Karte „Postfach hinzufügen“ (statt Plus-Knopf)
//  und eine Karte „Standard-Postfach“ mit Menü und Erklärung in derselben
//  Zeile (unter der Beschriftung). Entfernen geht dort über
//  das Kontextmenü einer Zeile (Wischen gibt es nicht).
//
//  Abgrenzung: Anlegen → AddAccountView; Bearbeiten → EditAccountView;
//  Speichern und Entfernen → AccountStore.
//
//  Abhängigkeiten: SwiftUI, AccountStore, SignatureStore, Dialogs, Log,
//  AccountStatusBadges, OAuthSignInState, AccountFetchState, AppTheme,
//  ExternalMailtoPresenter (Blätter melden sich als offene Fenster),
//  SheetHeaderBar, PlatformSheetSize.
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
            listContainer {
                if accountStore.accounts.isEmpty {
                    ContentUnavailableView(
                        "Keine Postfächer",
                        systemImage: "envelope",
                        description: Text("Füge dein erstes Postfach hinzu.")
                    )
                    // Hinweis frei auf der getönten Fläche, ohne Karte.
                    .listRowBackground(Color.clear)
                    #if os(macOS)
                    addAccountSection
                        .cardRowBackground()
                    #endif
                } else {
                    accountSection
                        .cardRowBackground()
                    #if os(macOS)
                    addAccountSection
                        .cardRowBackground()
                    #endif
                    defaultAccountSection
                        .cardRowBackground()
                }
            }
            .appBackground()
            .navigationTitle("Postfächer")
            .macSheetHeader("Postfächer") {
                EmptyView()
            } trailing: {
                HeaderCircleButton.confirm("Fertig") { dismiss() }
            }
            #if !os(macOS)
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
            #endif
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

    /// Behälter der Abschnitte: auf iPhone/iPad eine Liste (Wischen zum
    /// Entfernen), auf dem Mac ein gruppiertes Formular (Karten wie iOS).
    ///
    /// - Parameter content: Abschnitte.
    /// - Returns: Liste bzw. Formular.
    private func listContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let rows = content()
        #if os(macOS)
        return Form { rows }
            .macGroupedForm()
        #else
        return List { rows }
        #endif
    }

    /// Zeilenhöhe der Postfächer: auf dem Mac etwas höher (45 pt).
    private static var rowMinHeight: CGFloat? {
        #if os(macOS)
        45
        #else
        nil
        #endif
    }

    /// Durchmesser des Farbpunkts: auf dem Mac etwas größer.
    private static var colorDotSize: CGFloat {
        #if os(macOS)
        14
        #else
        12
        #endif
    }

    #if os(macOS)
    /// Karte „Postfach hinzufügen“ (Mac): volle Breite, blaues Plus und
    /// blaue Schrift – gestaltet wie „Ältere Nachrichten laden“.
    private var addAccountSection: some View {
        Section {
            Button {
                showingAddAccount = true
            } label: {
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: "plus.circle.fill")
                    Text("Postfach hinzufügen")
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.small)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    /// Postfächer mit Farbpunkt, Name und E-Mail-Adresse sowie Schalter
    /// „Abruf“; Tipp auf den Namen bearbeitet, Wischen entfernt (nach
    /// Rückfrage).
    ///
    /// Verarbeitung: Knopf und Schalter liegen in derselben Zeile; der
    /// Knopf ist randlos, damit die Liste jedem seine eigenen Tipps gibt.
    private var accountSection: some View {
        Section {
            ForEach(accountStore.accounts) { account in
                HStack(spacing: AppSpacing.medium) {
                    Button {
                        editingAccount = account
                    } label: {
                        HStack(spacing: AppSpacing.medium) {
                            if let colorHex = account.colorHex {
                                Circle()
                                    .fill(Color(hex: colorHex))
                                    .frame(width: Self.colorDotSize, height: Self.colorDotSize)
                            }
                            VStack(alignment: .leading) {
                                HStack(spacing: AppSpacing.small) {
                                    AccountStatusBadges(
                                        needsSignIn: OAuthSignInState.shared.isSignInRequired(account.id),
                                        isUnreachable: AccountFetchState.shared.isUnreachable(account.id),
                                        isPaused: !accountStore.isFetchEnabled(account.id),
                                        font: .headline
                                    )
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
                    .accountStatusHelp(AccountStatusBadges.summary(
                        needsSignIn: OAuthSignInState.shared.isSignInRequired(account.id),
                        isUnreachable: AccountFetchState.shared.isUnreachable(account.id),
                        isPaused: !accountStore.isFetchEnabled(account.id)
                    ))

                    Toggle("Abruf", isOn: fetchBinding(for: account.id))
                        // Einzelner Schalter: auf dem Mac als Schalter statt Häkchen.
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help("Abruf über „Alle Eingänge“ (nur dieses Gerät)")
                        .accessibilityLabel("Abruf \(account.displayName)")

                    #if os(macOS)
                    // Hinweis: Ein Klick auf die Zeile bearbeitet.
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    #endif
                }
                .frame(minHeight: Self.rowMinHeight)
                #if os(macOS)
                // Mac: Entfernen über das Kontextmenü (kein Wischen).
                .contextMenu {
                    Button("Bearbeiten …") { editingAccount = account }
                    Divider()
                    Button("Entfernen …", role: .destructive) {
                        confirmRemoval(of: [account])
                    }
                }
                #endif
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
            #if os(macOS)
            // Mac: Erklärung unter der Beschriftung in derselben Zeile –
            // gehört sichtbar zur Auswahl, ohne Trennlinie dazwischen.
            Picker(selection: defaultAccountBinding) {
                defaultAccountOptions
            } label: {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Standard-Postfach")
                    Text(Self.defaultAccountHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: Self.rowMinHeight)
            #else
            Picker("Standard-Postfach", selection: defaultAccountBinding) {
                defaultAccountOptions
            }
            .pickerStyle(.menu)
            #endif
        } footer: {
            #if !os(macOS)
            Text(Self.defaultAccountHint)
            #endif
        }
    }

    /// Auswahl für das Standard-Postfach: „Keins“ und alle Postfächer.
    @ViewBuilder
    private var defaultAccountOptions: some View {
        Text("Keins").tag(UUID?.none)
        ForEach(accountStore.accounts) { account in
            Text(account.displayName).tag(Optional(account.id))
        }
    }

    /// Erklärung zum Standard-Postfach.
    private static let defaultAccountHint = "Wird beim Verfassen einer neuen Mail als Absender vorbelegt."

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
