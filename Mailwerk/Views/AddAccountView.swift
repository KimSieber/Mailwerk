//
//  AddAccountView.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//


//
//  AddAccountView.swift
//  Mailwerk
//

import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AddAccountViewModel()
    let accountStore: AccountStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    TextField("Anzeigename", text: $viewModel.displayName)
                    TextField("Benutzername / E-Mail", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $viewModel.password)
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
                    Button("Speichern") {
                        let account = viewModel.makeAccount()
                        try? accountStore.addAccount(account, password: viewModel.password)
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }
}