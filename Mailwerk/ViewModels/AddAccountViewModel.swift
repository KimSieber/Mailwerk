//
//  AddAccountViewModel.swift
//  Mailwerk
//
//  Zweck: Eingaben, Prüfung und Verbindungstest des Formulars „Postfach
//  hinzufügen“ sowie der Aufbau des neuen Postfachs – für beide Arten:
//  - Anderer Anbieter (IMAP/SMTP): Server und Passwort von Hand,
//    Speichern über den Knopf „Speichern“.
//  - Microsoft (Outlook.com, Hotmail, Live): Server fest vorgegeben, kein
//    Passwort. „Bei Microsoft anmelden“ öffnet das Anmeldefenster; danach
//    werden IMAP und SMTP mit dem neuen Token geprüft und das Postfach
//    samt Refresh-Token gespeichert (`signInAndSave`).
//
//  Die E-Mail-Adresse ist Pflicht und muss gültig sein – sie ist der
//  Absender beim Versand. Der Benutzername ist optional: Bleibt er leer,
//  meldet sich Mailwerk mit der E-Mail-Adresse an (`loginName`). Das gilt
//  auch bei Microsoft: Ist die E-Mail-Adresse nur ein Alias des
//  Microsoft-Kontos, gehört die Anmeldeadresse des Kontos in den
//  Benutzernamen – der Versandserver nimmt nur sie an.
//
//  Abgrenzung: Formular → AddAccountView; Speichern → AccountStore;
//  Verbindungstest → MailConnectionTester; Anmeldefenster →
//  OAuthSignInState.
//
//  Abhängigkeiten: Foundation, Observation, MailConnectionTester,
//  MailAccount, MailAddress (Prüfung der Adresse), AccountColor,
//  OAuthProvider, OAuthSignInState, OAuthTokenService, AccountStore.
//

import Foundation
import Observation

/// Zustand des Formulars „Postfach hinzufügen“.
@Observable
final class AddAccountViewModel {

    /// Art des neuen Postfachs.
    enum Kind: Hashable {
        /// Anmeldung per OAuth 2 bei einem Anbieter (Server fest).
        case oauth(OAuthProvider.ID)
        /// Anderer Anbieter mit IMAP/SMTP und Passwort.
        case imap
    }

    /// Gewählte Art; Standard ist der bisherige Weg mit Passwort.
    var kind: Kind = .imap

    /// Bezeichnung des Postfachs.
    var displayName = ""
    /// Name in der Absenderzeile.
    var senderName = ""
    /// E-Mail-Adresse (Pflicht).
    var emailAddress = ""
    /// Anmeldename; leer = Anmeldung mit der E-Mail-Adresse.
    var username = ""
    /// Passwort (geht nur in den Schlüsselbund).
    var password = ""
    /// Farbe des Postfachs; `nil` = keine.
    var selectedColor: AccountColor?

    /// IMAP-Server.
    var imapHost = ""
    /// IMAP-Port als Text.
    var imapPort = "993"
    /// SMTP-Server.
    var smtpHost = ""
    /// SMTP-Port als Text.
    var smtpPort = "587"
    /// Kopie in „Gesendet“ ablegen (Standard: ja).
    var savesSentCopy = true

    /// `true`, solange der Verbindungstest läuft.
    var isTesting = false
    /// Ergebnis des letzten Verbindungstests.
    var testResult: TestResult?
    /// Fortschritt der Anmeldung bei einem Anbieter; `nil` = keine läuft.
    var signInProgress: String?

    /// Ergebnis eines Verbindungstests.
    enum TestResult: Equatable {
        /// IMAP und SMTP erreichbar.
        case success
        /// Fehlgeschlagen (mit Meldung).
        case failure(String)
    }

    /// Anbieter der gewählten Art; `nil` bei IMAP/SMTP.
    var provider: OAuthProvider? {
        if case .oauth(let id) = kind { return OAuthProvider.provider(for: id) }
        return nil
    }

    /// Anmeldename: der eingetragene Benutzername, sonst die E-Mail-Adresse.
    var loginName: String {
        MailAccount.loginName(username: username, emailAddress: emailAddress)
    }

    /// `true`, wenn die E-Mail-Adresse gültig ist.
    var hasValidEmailAddress: Bool {
        MailAddress(address: emailAddress).isValid
    }

    /// `true`, wenn alle Pflichtfelder gefüllt, die Ports Zahlen und die
    /// E-Mail-Adresse gültig sind (Art IMAP/SMTP).
    var isValid: Bool {
        !displayName.isEmpty && hasValidEmailAddress && !password.isEmpty
            && !imapHost.isEmpty && !smtpHost.isEmpty
            && Int(imapPort) != nil && Int(smtpPort) != nil
    }

    /// `true`, wenn Bezeichnung und gültige E-Mail-Adresse für die
    /// Anmeldung bei einem Anbieter vorliegen.
    var isReadyForSignIn: Bool {
        !displayName.isEmpty && hasValidEmailAddress
    }

    /// Prüft Anmeldung bei IMAP und SMTP mit den Eingaben.
    ///
    /// Verarbeitung: Ungültige Ports werden ohne Verbindungsversuch gemeldet;
    /// angemeldet wird mit `loginName`. Das Ergebnis steht danach in
    /// `testResult`.
    @MainActor
    func testConnection() async {
        guard let imapPortInt = Int(imapPort), let smtpPortInt = Int(smtpPort) else {
            testResult = .failure("Ungültiger Port")
            return
        }
        isTesting = true
        defer { isTesting = false }

        do {
            try await MailConnectionTester.testIMAP(
                host: imapHost, port: imapPortInt, username: loginName, login: .password(password)
            )
            try await MailConnectionTester.testSMTP(
                host: smtpHost, port: smtpPortInt, username: loginName, login: .password(password)
            )
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    /// Meldet beim Anbieter an, prüft die Verbindung und speichert das Postfach.
    ///
    /// Verarbeitung: Öffnet das Anmeldefenster mit dem Anmeldenamen
    /// (`loginName`) als Vorschlag. Mit dem erhaltenen Token werden IMAP
    /// (Posteingang) und SMTP geprüft – angemeldet wird mit dem
    /// Anmeldenamen. Erst wenn
    /// beides klappt, wird das Postfach mit dem Refresh-Token gespeichert
    /// und das Access-Token übernommen. Schließt der Nutzer das
    /// Anmeldefenster, passiert nichts; andere Fehler stehen in
    /// `testResult`.
    ///
    /// - Parameter accountStore: Ablage für Postfach und Refresh-Token.
    /// - Returns: `true`, wenn das Postfach gespeichert wurde.
    @MainActor
    func signInAndSave(accountStore: AccountStore) async -> Bool {
        guard let provider else { return false }
        testResult = nil
        signInProgress = "Anmeldung bei \(provider.name) …"
        defer { signInProgress = nil }

        let login = loginName
        do {
            let tokens = try await OAuthSignInState.shared.signIn(provider: provider, loginHint: login)
            signInProgress = "Verbindung wird geprüft …"
            try await MailConnectionTester.testIMAP(
                host: provider.imapHost, port: provider.imapPort,
                username: login, login: .accessToken(tokens.accessToken)
            )
            try await MailConnectionTester.testSMTP(
                host: provider.smtpHost, port: provider.smtpPort,
                username: login, login: .accessToken(tokens.accessToken)
            )
            guard let refreshToken = tokens.refreshToken else { throw OAuthError.missingRefreshToken }
            let account = makeAccount(provider: provider)
            try accountStore.addAccount(account, refreshToken: refreshToken)
            await OAuthTokenService.shared.adopt(tokens, for: account.id)
            return true
        } catch OAuthError.cancelled {
            return false
        } catch {
            testResult = .failure(error.localizedDescription)
            return false
        }
    }

    /// Baut das Postfach aus den Eingaben (Art IMAP/SMTP).
    ///
    /// - Returns: Neues Postfach mit E-Mail-Adresse und tatsächlichem
    ///   Anmeldenamen; ungültige Ports fallen auf 993 bzw. 587 zurück.
    func makeAccount() -> MailAccount {
        MailAccount(
            displayName: displayName,
            senderName: senderName,
            username: loginName,
            emailAddress: emailAddress,
            imapHost: imapHost,
            imapPort: Int(imapPort) ?? 993,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 587,
            colorHex: selectedColor?.rawValue,
            storesSentCopy: savesSentCopy
        )
    }

    /// Baut das Postfach für die Anmeldung bei einem Anbieter.
    ///
    /// Verarbeitung: Server und Ports kommen aus der Anbieter-Konfiguration;
    /// Anmeldename ist der Benutzername, sonst die E-Mail-Adresse. Eine Kopie in „Gesendet“ wird
    /// zunächst abgelegt; legt der Anbieter selbst ab, lässt sich das unter
    /// „Postfach bearbeiten“ ausschalten.
    ///
    /// - Parameter provider: Anbieter.
    /// - Returns: Neues Postfach mit Anmeldung per OAuth 2.
    func makeAccount(provider: OAuthProvider) -> MailAccount {
        MailAccount(
            displayName: displayName,
            senderName: senderName,
            username: loginName,
            emailAddress: emailAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            imapHost: provider.imapHost,
            imapPort: provider.imapPort,
            smtpHost: provider.smtpHost,
            smtpPort: provider.smtpPort,
            colorHex: selectedColor?.rawValue,
            storesSentCopy: true,
            oauthProvider: provider.id
        )
    }
}
