//
//  EditAccountView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 20.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Formular zum Bearbeiten eines Postfachs – Bezeichnung,
//  Absendername, E-Mail-Adresse, Benutzername, Passwort, Server, Kopie in
//  „Gesendet“, Farbe, Signatur, Abruf – mit Verbindungstest. Die Zeile „Signatur“ öffnet
//  deren Pflege-Seite; sie speichert unabhängig von „Sichern“ dieses
//  Formulars. Ebenso wirkt der Schalter „Abruf“ sofort (nur dieses Gerät). Jede Zeile zeigt ihre Beschriftung und ein
//  Beispiel (LabeledInputField). Ein leeres Passwortfeld lässt das
//  gespeicherte Passwort unverändert. Scheitert das Speichern, bleibt das
//  Formular offen und eine Meldung erklärt den Grund.
//
//  Postfach mit Anmeldung per OAuth 2 (z. B. Microsoft): Die Server sind
//  fest. E-Mail-Adresse und Benutzername sind wie bei anderen Postfächern
//  änderbar (keine neue Anmeldung nötig). Statt Passwort und Servern
//  zeigt das Formular den Stand der
//  Anmeldung und den Knopf „Erneut bei … anmelden“ (Anmeldefenster, danach
//  sofort gespeichert – unabhängig von „Sichern“). Der Schalter „Kopie in
//  ‚Gesendet‘ ablegen“ bleibt.
//
//  Die E-Mail-Adresse ist Pflicht und muss gültig sein. Der Benutzername
//  erscheint nur, wenn er von der Adresse abweicht; leer heißt „Anmeldung
//  mit der E-Mail-Adresse“ (`MailAccount.loginName`). Ältere Postfächer
//  ohne Adressfeld zeigen ihren Benutzernamen als Adresse und bekommen sie
//  beim Sichern eingetragen.
//
//  Mac: feste Kopfleiste oben (✕ Abbrechen, ✓ Sichern)
//  statt der Symbolleiste, die mitten im Inhalt stand; darunter scrollt
//  das ganze Formular im gruppierten Stil (Karten, Überschriften darüber,
//  Fußtexte vollständig darunter).
//
//  Abgrenzung: Neues Postfach → AddAccountView; Speichern →
//  AccountStore; Verbindungstest → MailConnectionTester; Signatur →
//  SignatureEditorView.
//
//  Abhängigkeiten: SwiftUI, AccountStore, MailConnectionTester,
//  ColorPickerGrid, MailAddress (Prüfung der Adresse), Dialogs,
//  LabeledInputField, PlatformInputModifiers, SignatureStore,
//  SignatureEditorView, OAuthSignInState, SignInRequiredBadge, AppTheme
//  (getönte Fläche, Abschnitte als Karten), SheetHeaderBar,
//  PlatformSheetSize.
//

import SwiftUI

/// Formular „Postfach bearbeiten“.
struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    /// Speicher der Signaturen.
    @Environment(SignatureStore.self) private var signatureStore
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
    /// Kopie in „Gesendet“ ablegen.
    @State private var savesSentCopy: Bool
    /// Farbe des Postfachs; `nil` = keine.
    @State private var selectedColor: AccountColor?
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?

    // Verbindungstest
    /// Verbindungstest läuft.
    @State private var isTesting = false
    /// Ergebnis des letzten Verbindungstests.
    @State private var testResult: TestResult?
    /// Erneute Anmeldung beim Anbieter läuft.
    @State private var isRenewing = false
    /// Ergebnis der letzten erneuten Anmeldung; `nil` = keine.
    @State private var renewResult: TestResult?
    /// Zustand „neu anmelden“ der Postfächer.
    private let signInState = OAuthSignInState.shared

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
        _savesSentCopy = State(initialValue: account.savesSentCopy)
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

    /// Art der gespeicherten Signatur für die Zeile „Signatur“.
    private var signatureSummary: String {
        switch signatureStore.signature(for: account.id)?.kind {
        case .simple: return "Einfach"
        case .html:   return "HTML"
        case nil:     return "Keine"
        }
    }

    /// Postfach mit Anmeldename und Adresse aus dem Formular – für
    /// Verbindungstest und erneute Anmeldung vor dem Sichern.
    private var formAccount: MailAccount {
        var copy = account
        copy.username = loginName
        copy.emailAddress = MailAccount.normalized(emailAddress)
        return copy
    }

    /// Anbieter der Anmeldung per OAuth 2; `nil` = Anmeldung mit Passwort.
    private var provider: OAuthProvider? {
        account.oauthConfiguration
    }

    /// Pflichtfelder gefüllt, Ports gültig (1–65535) und E-Mail-Adresse gültig;
    /// bei Anmeldung per OAuth 2 ohne Ports und Server (die sind fest).
    private var isValid: Bool {
        if provider != nil { return !displayName.isEmpty && hasValidEmailAddress }
        return !displayName.isEmpty && hasValidEmailAddress
            && !imapHost.isEmpty && !smtpHost.isEmpty
            && MailAccount.port(from: imapPort) != nil
            && MailAccount.port(from: smtpPort) != nil
    }

    /// Formular mit Konto, Servern, Farbe und Verbindungstest.
    var body: some View {
        NavigationStack {
            Form {
                if let provider {
                    oauthSections(provider)
                } else {
                    passwordSections
                }

                Section("Farbe") {
                    ColorPickerGrid(selection: $selectedColor)
                }
                .cardRowBackground()

                Section {
                    NavigationLink {
                        SignatureEditorView(
                            account: account,
                            signature: signatureStore.signature(for: account.id)
                        )
                    } label: {
                        LabeledContent("Signatur", value: signatureSummary)
                    }
                } header: {
                    Text("Signatur")
                } footer: {
                    Text("Erscheint beim Verfassen unter dem eigenen Text, bei Antworten und Weiterleitungen über dem Zitat. Wird über iCloud auf allen Geräten abgeglichen.")
                }
                .cardRowBackground()

                Section {
                    Toggle("Abruf über „Alle Eingänge“", isOn: Binding(
                        get: { accountStore.isFetchEnabled(account.id) },
                        set: { accountStore.setFetchEnabled($0, for: account.id) }
                    ))
                    // Einzelner Schalter: auf dem Mac als Schalter statt Häkchen.
                    .toggleStyle(.switch)
                } header: {
                    Text("Abruf")
                } footer: {
                    Text("Gilt nur auf diesem Gerät. Ausgeschaltet wird das Postfach nur abgerufen, wenn du einen seiner Ordner öffnest; seine Mails erscheinen dann nicht in „Alle Eingänge“.")
                }
                .cardRowBackground()

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
                .cardRowBackground()
            }
            .macGroupedForm()
            .appBackground()
            .navigationTitle("Postfach bearbeiten")
            .macSheetHeader("Postfach bearbeiten") {
                HeaderCircleButton.cancel { dismiss() }
            } trailing: {
                HeaderCircleButton.confirm("Sichern", isEnabled: isValid) { save() }
            }
            #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!isValid)
                }
            }
            #endif
        }
        .alertItem($activeAlert)
        .macSheetFrame(.form)
    }

    // MARK: - Abschnitte

    /// Abschnitte eines Postfachs mit Passwort: Konto, IMAP, SMTP.
    @ViewBuilder
    private var passwordSections: some View {
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
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk, der Absendername erscheint beim Empfänger vor der Adresse. Den Benutzernamen nur eintragen, wenn sich der Anbieter nicht mit der E-Mail-Adresse anmeldet.")
                if !emailAddress.isEmpty && !hasValidEmailAddress {
                    Text("Die E-Mail-Adresse ist ungültig.")
                        .foregroundStyle(.red)
                }
            }
        }
        .cardRowBackground()

        Section("IMAP (Empfang)") {
            LabeledInputField(label: "Host", example: "z. B. imap.mail.org",
                              text: $imapHost)
                .plainTextInput()
            LabeledInputField(label: "Port", example: "z. B. 993",
                              text: $imapPort)
                .numberInput()
        }
        .cardRowBackground()

        Section {
            LabeledInputField(label: "Host", example: "z. B. smtp.mail.org",
                              text: $smtpHost)
                .plainTextInput()
            LabeledInputField(label: "Port", example: "z. B. 587",
                              text: $smtpPort)
                .numberInput()
            Toggle("Kopie in „Gesendet“ ablegen", isOn: $savesSentCopy)
                // Einzelner Schalter: auf dem Mac als Schalter statt Häkchen.
                .toggleStyle(.switch)
        } header: {
            Text("SMTP (Versand)")
        } footer: {
            Text("Ausschalten, wenn der Anbieter gesendete Mails selbst in „Gesendet“ ablegt (z. B. Gmail) – sonst erscheinen sie dort doppelt.")
        }
        .cardRowBackground()
    }

    /// Abschnitte eines Postfachs mit Anmeldung per OAuth 2: Konto,
    /// Anmeldung mit Stand und „Erneut anmelden“, Versand.
    ///
    /// - Parameter provider: Anbieter.
    /// - Returns: Die Abschnitte.
    @ViewBuilder
    private func oauthSections(_ provider: OAuthProvider) -> some View {
        oauthAccountSection(provider)
        oauthStatusSection(provider)
        sentCopySection
    }

    /// Abschnitt „Konto“ eines Postfachs mit Anmeldung per OAuth 2.
    ///
    /// - Parameter provider: Anbieter (für den Hinweis zum Benutzernamen).
    /// - Returns: Der Abschnitt.
    private func oauthAccountSection(_ provider: OAuthProvider) -> some View {
        Section {
            LabeledInputField(label: "Bezeichnung", example: "z. B. Outlook",
                              text: $displayName)
            LabeledInputField(label: "Absendername", example: "z. B. Max Müller",
                              text: $senderName)
                .textContentType(.name)
            LabeledInputField(label: "E-Mail-Adresse", example: "z. B. max.mueller@outlook.com",
                              text: $emailAddress)
                .emailInput()
            LabeledInputField(label: "Benutzername", example: "leer = E-Mail-Adresse",
                              text: $username)
                .emailInput()
        } header: {
            Text("Konto")
        } footer: {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Die Bezeichnung dient nur zur Anzeige in Mailwerk, der Absendername erscheint beim Empfänger vor der Adresse. Den Benutzernamen nur eintragen, wenn du dich bei \(provider.name) mit einer anderen Adresse anmeldest als mit der E-Mail-Adresse.")
                if !emailAddress.isEmpty && !hasValidEmailAddress {
                    Text("Die E-Mail-Adresse ist ungültig.")
                        .foregroundStyle(.red)
                }
            }
        }
        .cardRowBackground()
    }

    /// Abschnitt „Anmeldung“: Stand, „Erneut anmelden“ und dessen Ergebnis.
    ///
    /// - Parameter provider: Anbieter.
    /// - Returns: Der Abschnitt.
    private func oauthStatusSection(_ provider: OAuthProvider) -> some View {
        Section {
            if signInState.isSignInRequired(account.id) {
                Label {
                    Text("Anmeldung abgelaufen")
                } icon: {
                    SignInRequiredBadge(font: .body)
                }
                .foregroundStyle(.red)
            } else {
                Label("Angemeldet bei \(provider.name)", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await renewSignIn() }
            } label: {
                if isRenewing {
                    ProgressView()
                } else {
                    Label("Erneut bei \(provider.name) anmelden", systemImage: "person.badge.key")
                }
            }
            .disabled(isRenewing || !signInState.canSignIn)

            if let result = renewResult {
                switch result {
                case .success:
                    Label("Neu angemeldet", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Anmeldung")
        } footer: {
            Text("Mailwerk meldet sich mit einer Freigabe von \(provider.name) an, nicht mit dem Passwort. Nach einer Passwortänderung oder wenn die Anmeldung abgelaufen ist, hier erneut anmelden.")
        }
        .cardRowBackground()
    }

    /// Abschnitt „Versand“: Kopie in „Gesendet“ ablegen.
    private var sentCopySection: some View {
        Section {
            Toggle("Kopie in „Gesendet“ ablegen", isOn: $savesSentCopy)
                // Einzelner Schalter: auf dem Mac als Schalter statt Häkchen.
                .toggleStyle(.switch)
        } header: {
            Text("Versand")
        } footer: {
            Text("Ausschalten, wenn der Anbieter gesendete Mails selbst in „Gesendet“ ablegt – sonst erscheinen sie dort doppelt.")
        }
        .cardRowBackground()
    }

    // MARK: - Aktionen

    /// Speichert die Änderungen und schließt das Formular.
    ///
    /// Verarbeitung: Gespeichert wird nur bei gültigen Ports (`isValid`);
    /// sonst bleiben die bisherigen Ports erhalten. Bei Anmeldung per OAuth 2
    /// bleiben die Server unverändert. Scheitert das Speichern (z. B.
    /// Schlüsselbund), bleibt das Formular offen.
    private func save() {
        var updated = account
        updated.displayName = displayName
        updated.senderName = MailAccount.normalized(senderName)
        updated.username = loginName
        updated.emailAddress = MailAccount.normalized(emailAddress)
        if provider == nil {
            updated.imapHost = imapHost
            updated.imapPort = MailAccount.port(from: imapPort) ?? account.imapPort
            updated.smtpHost = smtpHost
            updated.smtpPort = MailAccount.port(from: smtpPort) ?? account.smtpPort
        }
        updated.storesSentCopy = savesSentCopy
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
        if provider != nil {
            await testStoredConnection()
            return
        }
        guard let imapPortInt = MailAccount.port(from: imapPort),
              let smtpPortInt = MailAccount.port(from: smtpPort) else {
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
                username: loginName, login: .password(testPassword)
            )
            try await MailConnectionTester.testSMTP(
                host: smtpHost, port: smtpPortInt,
                username: loginName, login: .password(testPassword)
            )
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    /// Prüft IMAP und SMTP eines Postfachs mit Anmeldung per OAuth 2.
    ///
    /// Verarbeitung: Geprüft wird mit dem Benutzernamen aus dem Formular;
    /// das Access-Token holt der OAuthTokenService (bei Bedarf erneuert).
    /// Ist die Anmeldung abgelaufen, sagt das die Meldung.
    @MainActor
    private func testStoredConnection() async {
        guard let provider else { return }
        isTesting = true
        defer { isTesting = false }
        do {
            try await MailConnectionTester.test(
                MailCredentials(account: formAccount, secret: .oauth(provider))
            )
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    /// Meldet das Postfach erneut beim Anbieter an.
    ///
    /// Verarbeitung: Öffnet das Anmeldefenster mit dem Benutzernamen aus
    /// dem Formular; das neue Refresh-Token wird sofort gespeichert
    /// (`OAuthSignInState.renewSignIn`), unabhängig von „Sichern“. Schließt
    /// der Nutzer das Fenster, bleibt alles, wie es war.
    @MainActor
    private func renewSignIn() async {
        isRenewing = true
        defer { isRenewing = false }
        renewResult = nil
        do {
            try await signInState.renewSignIn(for: formAccount, accountStore: accountStore)
            renewResult = .success
        } catch OAuthError.cancelled {
            return
        } catch {
            renewResult = .failure(error.localizedDescription)
        }
    }
}