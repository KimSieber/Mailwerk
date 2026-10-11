//
//  EditAccountView.swift
//  Mailwerk
//
//  Zweck: Formular zum Bearbeiten eines Postfachs – Bezeichnung,
//  Absendername, E-Mail-Adresse, Benutzername, Passwort, Server, Farbe –
//  mit Verbindungstest. Jede Zeile zeigt ihre Beschriftung und ein
//  Beispiel (LabeledInputField). Ein leeres Passwortfeld lässt das
//  gespeicherte Passwort unverändert. Scheitert das Speichern, bleibt das
//  Formular offen und eine Meldung erklärt den Grund.
//
//  Die E-Mail-Adresse ist Pflicht und muss gültig sein. Der Benutzername
//  erscheint nur, wenn er von der Adresse abweicht; leer heißt „Anmeldung
//  mit der E-Mail-Adresse“ (`MailAccount.loginName`). Ältere Postfächer
//  ohne Adressfeld zeigen ihren Benutzernamen als Adresse und bekommen sie
//  beim Sichern eingetragen.
//
//  Abgrenzung: Neues Postfach → AddAccountView; Speichern →
//  AccountStore; Verbindungstest → MailConnectionTester.
//
//  Abhängigkeiten: SwiftUI, AccountStore, MailConnectionTester,
//  ColorPickerGrid, MailAddress (Prüfung der Adresse), Dialogs,
//  LabeledInputField, PlatformInputModifiers.
//

import SwiftUI

/// Formular „Postfach bearbeiten“.
struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    /// Quelle für Postfächer und Passwörter.
    let accountStore: AccountStore
    /// Bearbeitetes Postfach (Stand beim Öffnen).
    let account: MailAccount

    // Formularfelder, vorbelegt mit den aktuellen Werten
    /// Bezeichnung in Mailwerk.
    @State private var displayName: String
    /// Absendername beim Empfänger.
    @State private var senderName: String
    /// E-Mail-Adresse (Pflicht).
    @State private var emailAddress: String
    /// Abweichender Anmeldename; leer = Anmeldung mit der E-Mail-Adresse.
    @State private var username: String
    /// Neues Passwort; leer = nicht ändern.
    @State private var password: String = ""
    /// IMAP-Server.
    @State private var imapHost: String
    /// IMAP-Port als Text.
    @State private var imapPort: String
    /// SMTP-Server.
    @State private var smtpHost: String
    /// SMTP-Port als Text.
    @State private var smtpPort: String
    /// Farbe des Postfachs; `nil` = keine.
    @State private var selectedColor: AccountColor?
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?

    // Verbindungstest
    /// Verbindungstest läuft.
    @State private var isTesting = false
    /// Ergebnis des letzten Verbindungstests.
    @State private var testResult: TestResult?

    /// Ergebnis des Verbindungstests.
    enum TestResult: Equatable {
        /// IMAP und SMTP erreichbar.
        case success
        /// Fehlgeschlagen (mit Meldung).
        case failure(String)
    }

    /// Belegt das Formular mit den Werten des Postfachs vor.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Passwörter.
    ///   - account: Zu bearbeitendes Postfach.
    init(accountStore: AccountStore, account: MailAccount) {
        self.accountStore = accountStore
        self.account = account
        _displayName = State(initialValue: account.displayName)
        _senderName = State(initialValue: account.senderName ?? "")
        _emailAddress = State(initialValue: account.senderAddress)
        _username = State(initialValue: account.username == account.senderAddress ? "" : account.username)
        _imapHost = State(initialValue: account.imapHost)
        _imapPort = State(initialValue: String(account.imapPort))
        _smtpHost = State(initialValue: account.smtpHost)
        _smtpPort = State(initialValue: String(account.smtpPort))
        _selectedColor = State(initialValue: AccountColor.from(hex: account.colorHex))
    }

    /// Anmeldename: der eingetragene Benutzername, sonst die E-Mail-Adresse.
    private var loginName: String {
        MailAccount.loginName(username: username, emailAddress: emailAddress)
    }

    /// `true`, wenn die E-Mail-Adresse gültig ist.
    private var hasValidEmailAddress: Bool {
        MailAddress(address: emailAddress).isValid
    }

    /// Pflichtfelder gefüllt, Ports als Zahl lesbar und E-Mail-Adresse gültig.
    private var isValid: Bool {
        !displayName.isEmpty && hasValidEmailAddress
            && !imapHost.isEmpty && !smtpHost.isEmpty
            && Int(imapPort) != nil && Int(smtpPort) != nil
    }

    /// Formular mit Konto, Servern, Farbe und Verbindungstest.
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledInputField(label: "Bezeichnung", example: "z. B. Privat",
                                      text: $displayName)
                    LabeledInputField(label: "Absendername", example: "z. B. Max Müller",
                                      text: $senderName)
                        .textContentType(.name)
                    LabeledInputField(label: "E-Mail-Adresse", example: "z. B. max.mueller@mail.org",
                                      text: $emailAddress)
                        .emailInput()
                    LabeledInputField(label: "Benutzername", example: "leer = E-Mail-Adresse",
                                      text: $username)
                        .plainTextInput()
                    LabeledInputField(label: "Passwort", example: "leer = unverändert",
                                      text: $password, isSecure: true)
                } header: {
                    Text("Konto")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk, der Absendername erscheint beim Empfänger vor der Adresse. Den Benutzernamen nur eintragen, wenn sich der Anbieter nicht mit der E-Mail-Adresse anmeldet.")
                        if !emailAddress.isEmpty && !hasValidEmailAddress {
                            Text("Die E-Mail-Adresse ist ungültig.")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("IMAP (Empfang)") {
                    LabeledInputField(label: "Host", example: "z. B. imap.mail.org",
                                      text: $imapHost)
                        .plainTextInput()
                    LabeledInputField(label: "Port", example: "z. B. 993",
                                      text: $imapPort)
                        .numberInput()
                }

                Section("SMTP (Versand)") {
                    LabeledInputField(label: "Host", example: "z. B. smtp.mail.org",
                                      text: $smtpHost)
                        .plainTextInput()
                    LabeledInputField(label: "Port", example: "z. B. 587",
                                      text: $smtpPort)
                        .numberInput()
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
        }
        .alertItem($activeAlert)
        .macSheetFrame(.form)
    }

    // MARK: - Aktionen

    /// Speichert die Änderungen und schließt das Formular.
    ///
    /// Verarbeitung: Ungültige Ports fallen auf die Standardwerte zurück
    /// (die Eingabe ist durch `isValid` geprüft). Scheitert das Speichern
    /// (z. B. Schlüsselbund), bleibt das Formular offen.
    private func save() {
        var updated = account
        updated.displayName = displayName
        updated.senderName = MailAccount.normalized(senderName)
        updated.username = loginName
        updated.emailAddress = MailAccount.normalized(emailAddress)
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
            activeAlert = .failure("Speichern fehlgeschlagen", error)
        }
    }

    /// Prüft IMAP und SMTP mit den eingegebenen Werten.
    ///
    /// Verarbeitung: Angemeldet wird mit `loginName`. Ohne neues Passwort wird das gespeicherte gelesen; ein
    /// Fehler des Schlüsselbunds wird benannt, statt als „kein Passwort“
    /// zu erscheinen. Das Ergebnis steht in `testResult`.
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
        } else {
            // Gespeichertes Passwort lesen – ein Keychain-Fehler wird
            // benannt, statt als „kein Passwort" zu erscheinen.
            do {
                guard let existing = try accountStore.password(for: account) else {
                    testResult = .failure("Kein Passwort vorhanden")
                    return
                }
                testPassword = existing
            } catch {
                testResult = .failure("Passwort konnte nicht gelesen werden: \(error.localizedDescription)")
                return
            }
        }

        isTesting = true
        defer { isTesting = false }

        do {
            try await MailConnectionTester.testIMAP(
                host: imapHost, port: imapPortInt,
                username: loginName, password: testPassword
            )
            try await MailConnectionTester.testSMTP(
                host: smtpHost, port: smtpPortInt,
                username: loginName, password: testPassword
            )
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}