//
//  AddAccountView.swift
//  Mailwerk
//
//  Zweck: Formular zum Einrichten eines Postfachs – Bezeichnung,
//  Absendername, Zugangsdaten, IMAP- und SMTP-Server – mit
//  Verbindungstest. Speichern legt das Postfach an und das Passwort im
//  Schlüsselbund ab; scheitert das, bleibt das Formular mit allen
//  Eingaben offen und eine Meldung erklärt den Grund.
//
//  Abgrenzung: Eingabeprüfung, Verbindungstest und Aufbau des Postfachs
//  → AddAccountViewModel; Bearbeiten → EditAccountView.
//
//  Abhängigkeiten: SwiftUI, AddAccountViewModel, AccountStore, Dialogs,
//  PlatformInputModifiers (Eingabearten der Felder).
//

import SwiftUI

/// Formular „Postfach hinzufügen“.
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    /// Eingaben und Verbindungstest.
    @State private var viewModel = AddAccountViewModel()
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?
    /// Quelle für Postfächer; hier wird das neue Postfach eingetragen.
    let accountStore: AccountStore

    /// Formular mit Konto, IMAP, SMTP und Verbindungstest.
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bezeichnung", text: $viewModel.displayName)
                    TextField("Absendername", text: $viewModel.senderName)
                        .textContentType(.name)
                    TextField("Benutzername / E-Mail", text: $viewModel.username)
                        .plainTextInput()
                    SecureField("Passwort", text: $viewModel.password)
                } header: {
                    Text("Konto")
                } footer: {
                    Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk. Der Absendername erscheint beim Empfänger vor deiner Adresse.")
                }

                Section("IMAP (Empfang)") {
                    TextField("Host", text: $viewModel.imapHost)
                        .plainTextInput()
                    TextField("Port", text: $viewModel.imapPort)
                        .numberInput()
                }

                Section("SMTP (Versand)") {
                    TextField("Host", text: $viewModel.smtpHost)
                        .plainTextInput()
                    TextField("Port", text: $viewModel.smtpPort)
                        .numberInput()
                }

                Section {
                    Button {
                        Task { await viewModel.testConnection() }
                    } label: {
                        if viewModel.isTesting {
                            ProgressView()
                        } else {
                            Text("Verbindung testen")
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isTesting)

                    if let result = viewModel.testResult {
                        switch result {
                        case .success:
                            Label("Verbindung erfolgreich", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Postfach hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!viewModel.isValid)
                }
            }
        }
        .alertItem($activeAlert)
        .macSheetFrame(.form)
    }

    // MARK: - Aktionen

    /// Legt das Postfach an und schließt das Formular.
    ///
    /// Verarbeitung: Scheitert das Speichern (z. B. Schlüsselbund), bleibt
    /// das Formular offen, damit keine Eingaben verloren gehen.
    private func save() {
        let account = viewModel.makeAccount()
        do {
            try accountStore.addAccount(account, password: viewModel.password)
            dismiss()
        } catch {
            activeAlert = .failure("Speichern fehlgeschlagen", error)
        }
    }
}
