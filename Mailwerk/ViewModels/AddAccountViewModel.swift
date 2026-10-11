//
//  AddAccountViewModel.swift
//  Mailwerk
//
//  Zweck: Eingaben, Prüfung und Verbindungstest des Formulars „Postfach
//  hinzufügen“ sowie der Aufbau des neuen Postfachs.
//
//  Abgrenzung: Formular → AddAccountView; Speichern → AccountStore;
//  Verbindungstest → MailConnectionTester.
//
//  Abhängigkeiten: Foundation, Observation, MailConnectionTester, MailAccount.
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
    /// Anmeldename, zugleich Absenderadresse.
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

    /// `true`, solange der Verbindungstest läuft.
    var isTesting = false
    /// Ergebnis des letzten Verbindungstests.
    var testResult: TestResult?

    /// Ergebnis eines Verbindungstests.
    enum TestResult: Equatable {
        case success
        case failure(String)
    }

    /// `true`, wenn alle Pflichtfelder gefüllt und die Ports Zahlen sind.
    var isValid: Bool {
        !displayName.isEmpty && !username.isEmpty && !password.isEmpty
            && !imapHost.isEmpty && !smtpHost.isEmpty
            && Int(imapPort) != nil && Int(smtpPort) != nil
    }

    /// Prüft Anmeldung bei IMAP und SMTP mit den Eingaben.
    ///
    /// Verarbeitung: Ungültige Ports werden ohne Verbindungsversuch gemeldet;
    /// das Ergebnis steht danach in `testResult`.
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
                host: imapHost, port: imapPortInt, username: username, password: password
            )
            try await MailConnectionTester.testSMTP(
                host: smtpHost, port: smtpPortInt, username: username, password: password
            )
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    /// Baut das Postfach aus den Eingaben.
    ///
    /// - Returns: Neues Postfach; ungültige Ports fallen auf 993 bzw. 587 zurück.
    func makeAccount() -> MailAccount {
        MailAccount(
            displayName: displayName,
            senderName: senderName,
            username: username,
            imapHost: imapHost,
            imapPort: Int(imapPort) ?? 993,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 587
        )
    }
}
