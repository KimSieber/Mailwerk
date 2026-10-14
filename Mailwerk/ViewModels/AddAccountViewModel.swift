//
//  AddAccountViewModel.swift
//  Mailwerk
//
//  Zweck: Eingaben, Prüfung und Verbindungstest des Formulars „Postfach
//  hinzufügen“ sowie der Aufbau des neuen Postfachs.
//
//  Die E-Mail-Adresse ist Pflicht und muss gültig sein – sie ist der
//  Absender beim Versand. Der Benutzername ist optional: Bleibt er leer,
//  meldet sich Mailwerk mit der E-Mail-Adresse an (`loginName`).
//
//  Abgrenzung: Formular → AddAccountView; Speichern → AccountStore;
//  Verbindungstest → MailConnectionTester.
//
//  Abhängigkeiten: Foundation, Observation, MailConnectionTester,
//  MailAccount, MailAddress (Prüfung der Adresse).
//

import Foundation
import Observation

/// Zustand des Formulars „Postfach hinzufügen“.
@Observable
final class AddAccountViewModel {
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

    /// Ergebnis eines Verbindungstests.
    enum TestResult: Equatable {
        /// IMAP und SMTP erreichbar.
        case success
        /// Fehlgeschlagen (mit Meldung).
        case failure(String)
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
    /// E-Mail-Adresse gültig sind.
    var isValid: Bool {
        !displayName.isEmpty && hasValidEmailAddress && !password.isEmpty
            && !imapHost.isEmpty && !smtpHost.isEmpty
            && Int(imapPort) != nil && Int(smtpPort) != nil
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
                host: imapHost, port: imapPortInt, username: loginName, password: password
            )
            try await MailConnectionTester.testSMTP(
                host: smtpHost, port: smtpPortInt, username: loginName, password: password
            )
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    /// Baut das Postfach aus den Eingaben.
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
            storesSentCopy: savesSentCopy
        )
    }
}
