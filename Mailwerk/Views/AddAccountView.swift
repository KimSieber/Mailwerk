//
//  AddAccountView.swift
//  Mailwerk
//
//  Zweck: Formular zum Einrichten eines Postfachs – Bezeichnung,
//  Absendername, E-Mail-Adresse, Benutzername, Passwort, IMAP- und
//  SMTP-Server, Kopie in „Gesendet“ – mit Verbindungstest. Jede Zeile zeigt ihre Beschriftung
//  und ein Beispiel (LabeledInputField). Speichern legt das Postfach an
//  und das Passwort im Schlüsselbund ab; scheitert das, bleibt das
//  Formular mit allen Eingaben offen und eine Meldung erklärt den Grund.
//
//  Abgrenzung: Eingabeprüfung, Verbindungstest und Aufbau des Postfachs
//  → AddAccountViewModel; Bearbeiten → EditAccountView.
//
//  Abhängigkeiten: SwiftUI, AddAccountViewModel, AccountStore, Dialogs,
//  LabeledInputField, PlatformInputModifiers (Eingabearten der Felder).
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
                    LabeledInputField(label: "Bezeichnung", example: "z. B. Privat",
                                      text: $viewModel.displayName)
                    LabeledInputField(label: "Absendername", example: "z. B. Max Müller",
                                      text: $viewModel.senderName)
                        .textContentType(.name)
                    LabeledInputField(label: "E-Mail-Adresse", example: "z. B. max.mueller@mail.org",
                                      text: $viewModel.emailAddress)
                        .emailInput()
                    LabeledInputField(label: "Benutzername", example: "leer = E-Mail-Adresse",
                                      text: $viewModel.username)
                        .plainTextInput()
                    LabeledInputField(label: "Passwort", example: "erforderlich",
                                      text: $viewModel.password, isSecure: true)
                } header: {
                    Text("Konto")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk, der Absendername erscheint beim Empfänger vor der Adresse. Den Benutzernamen nur eintragen, wenn sich der Anbieter nicht mit der E-Mail-Adresse anmeldet.")
                        if !viewModel.emailAddress.isEmpty && !viewModel.hasValidEmailAddress {
                            Text("Die E-Mail-Adresse ist ungültig.")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("IMAP (Empfang)") {
                    LabeledInputField(label: "Host", example: "z. B. imap.mail.org",
                                      text: $viewModel.imapHost)
                        .plainTextInput()
                    LabeledInputField(label: "Port", example: "z. B. 993",
                                      text: $viewModel.imapPort)
                        .numberInput()
                }

                Section {
                    LabeledInputField(label: "Host", example: "z. B. smtp.mail.org",
                                      text: $viewModel.smtpHost)
                        .plainTextInput()
                    LabeledInputField(label: "Port", example: "z. B. 587",
                                      text: $viewModel.smtpPort)
                        .numberInput()
                    Toggle("Kopie in „Gesendet“ ablegen", isOn: $viewModel.savesSentCopy)
                } header: {
                    Text("SMTP (Versand)")
                } footer: {
                    Text("Ausschalten, wenn der Anbieter gesendete Mails selbst in „Gesendet“ ablegt (z. B. Gmail) – sonst erscheinen sie dort doppelt.")
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
