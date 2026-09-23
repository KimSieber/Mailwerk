//
//  AddAccountView.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//

import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AddAccountViewModel()
    @State private var saveError: String?
    let accountStore: AccountStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bezeichnung", text: $viewModel.displayName)
                    TextField("Absendername", text: $viewModel.senderName)
                        .textContentType(.name)
                    TextField("Benutzername / E-Mail", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $viewModel.password)
                } header: {
                    Text("Konto")
                } footer: {
                    Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk. Der Absendername erscheint beim Empfänger vor deiner Adresse.")
                }

                Section("IMAP (Empfang)") {
                    TextField("Host", text: $viewModel.imapHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $viewModel.imapPort)
                }

                Section("SMTP (Versand)") {
                    TextField("Host", text: $viewModel.smtpHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $viewModel.smtpPort)
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
            .alert(
                "Speichern fehlgeschlagen",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Aktionen

    private func save() {
        let account = viewModel.makeAccount()
        do {
            try accountStore.addAccount(account, password: viewModel.password)
            dismiss()
        } catch {
            // Formular bleibt offen, damit keine Eingaben verloren gehen
            saveError = error.localizedDescription
        }
    }
}
