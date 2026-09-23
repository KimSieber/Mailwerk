//
//  EditAccountView.swift
//  Mailwerk
//
//  Created by Kim Sieber on 20.09.26.
//

import SwiftUI

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    let accountStore: AccountStore
    let account: MailAccount

    // Formularfelder, vorbelegt mit den aktuellen Werten
    @State private var displayName: String
    @State private var senderName: String
    @State private var username: String
    @State private var password: String = ""  // leer = nicht ändern
    @State private var imapHost: String
    @State private var imapPort: String
    @State private var smtpHost: String
    @State private var smtpPort: String
    @State private var selectedColor: AccountColor?
    @State private var saveError: String?

    // Verbindungstest
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult: Equatable {
        case success
        case failure(String)
    }

    init(accountStore: AccountStore, account: MailAccount) {
        self.accountStore = accountStore
        self.account = account
        _displayName = State(initialValue: account.displayName)
        _senderName = State(initialValue: account.senderName ?? "")
        _username = State(initialValue: account.username)
        _imapHost = State(initialValue: account.imapHost)
        _imapPort = State(initialValue: String(account.imapPort))
        _smtpHost = State(initialValue: account.smtpHost)
        _smtpPort = State(initialValue: String(account.smtpPort))
        _selectedColor = State(initialValue: AccountColor.from(hex: account.colorHex))
    }

    private var isValid: Bool {
        !displayName.isEmpty && !username.isEmpty
            && !imapHost.isEmpty && !smtpHost.isEmpty
            && Int(imapPort) != nil && Int(smtpPort) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bezeichnung", text: $displayName)
                    TextField("Absendername", text: $senderName)
                        .textContentType(.name)
                    TextField("Benutzername / E-Mail", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Neues Passwort (leer = unverändert)", text: $password)
                } header: {
                    Text("Konto")
                } footer: {
                    Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk. Der Absendername erscheint beim Empfänger vor deiner Adresse.")
                }

                Section("IMAP (Empfang)") {
                    TextField("Host", text: $imapHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $imapPort)
                        .keyboardType(.numberPad)
                }

                Section("SMTP (Versand)") {
                    TextField("Host", text: $smtpHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $smtpPort)
                        .keyboardType(.numberPad)
                }

                Section("Farbe") {
                    ColorPickerGrid(selection: $selectedColor)
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView()
                        } else {
                            Text("Verbindung testen")
                        }
                    }
                    .disabled(!isValid || isTesting)

                    if let result = testResult {
                        switch result {
                        case .success:
                            Label("Verbindung erfolgreich",
                                  systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message,
                                  systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Postfach bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!isValid)
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
        var updated = account
        updated.displayName = displayName
        updated.senderName = MailAccount.normalized(senderName)
        updated.username = username
        updated.imapHost = imapHost
        updated.imapPort = Int(imapPort) ?? 993
        updated.smtpHost = smtpHost
        updated.smtpPort = Int(smtpPort) ?? 587
        updated.colorHex = selectedColor?.rawValue

        do {
            try accountStore.updateAccount(
                updated,
                newPassword: password.isEmpty ? nil : password
            )
            dismiss()
        } catch {
            // Formular bleibt offen, damit keine Eingaben verloren gehen
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func testConnection() async {
        guard let imapPortInt = Int(imapPort),
              let smtpPortInt = Int(smtpPort) else {
            testResult = .failure("Ungültiger Port")
            return
        }

        // Aktuelles oder bestehendes Passwort verwenden
        let testPassword: String
        if !password.isEmpty {
            testPassword = password
        } else if let existing = try? accountStore.password(for: account) {
            testPassword = existing
        } else {
            testResult = .failure("Kein Passwort vorhanden")
            return
        }

        isTesting = true
        defer { isTesting = false }

        do {
            try await MailConnectionTester.testIMAP(
                host: imapHost, port: imapPortInt,
                username: username, password: testPassword
            )
            try await MailConnectionTester.testSMTP(
                host: smtpHost, port: smtpPortInt,
                username: username, password: testPassword
            )
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}