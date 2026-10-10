//
//  MailConnectionTester.swift
//  Mailwerk
//
//  Zweck: Prüft IMAP- und SMTP-Zugangsdaten, ohne dauerhaft verbunden zu
//  bleiben – für „Verbindung testen“ bei der Postfach-Einrichtung.
//
//  Die Verbindung wird in jedem Fall wieder geschlossen, auch bei Fehlern.
//  Verbindungen entstehen ausschließlich verschlüsselt über
//  MailServerFactory.
//
//  Abgrenzung: Verbindungen für Abruf und Aktionen → MailSession.
//
//  Abhängigkeiten: SwiftMail, MailServerFactory, MailFolder (Posteingang).
//

import Foundation
import SwiftMail

/// Test der Zugangsdaten eines Postfachs.
enum MailConnectionTester {

    /// Fehler des Verbindungstests.
    enum TestError: LocalizedError {
        /// IMAP-Anmeldung oder Auswahl des Posteingangs gescheitert.
        case imapFailed(String)
        /// SMTP-Anmeldung gescheitert.
        case smtpFailed(String)

        /// Liefert die deutsche Meldung für den Nutzer.
        ///
        /// - Returns: Meldungstext für die Anzeige.
        var errorDescription: String? {
            switch self {
            case .imapFailed(let message):
                return "IMAP-Verbindung fehlgeschlagen: \(message)"
            case .smtpFailed(let message):
                return "SMTP-Verbindung fehlgeschlagen: \(message)"
            }
        }
    }

    /// Prüft die IMAP-Zugangsdaten.
    ///
    /// Verarbeitung: Verbinden, anmelden, Posteingang auswählen, abmelden.
    /// Bei einem Fehler wird die Verbindung getrennt.
    ///
    /// - Parameters:
    ///   - host: IMAP-Server.
    ///   - port: Port.
    ///   - username: Benutzername.
    ///   - password: Passwort.
    /// - Throws: `TestError.imapFailed`.
    static func testIMAP(host: String, port: Int, username: String, password: String) async throws {
        let server = MailServerFactory.imapServer(host: host, port: port)
        do {
            try await server.connect()
            try await server.login(username: username, password: password)
            _ = try await server.selectMailbox(MailFolder.inboxPath)
            try await server.logout()
        } catch {
            // Verbindung nicht offen lassen (z. B. nach fehlgeschlagenem Login)
            try? await server.disconnect()
            throw TestError.imapFailed(error.localizedDescription)
        }
    }

    /// Prüft die SMTP-Zugangsdaten.
    ///
    /// Verarbeitung: Verbinden, anmelden, trennen. Bei einem Fehler wird
    /// die Verbindung ebenfalls getrennt.
    ///
    /// - Parameters:
    ///   - host: SMTP-Server.
    ///   - port: Port.
    ///   - username: Benutzername.
    ///   - password: Passwort.
    /// - Throws: `TestError.smtpFailed`.
    static func testSMTP(host: String, port: Int, username: String, password: String) async throws {
        let server = MailServerFactory.smtpServer(host: host, port: port)
        do {
            try await server.connect()
            try await server.login(username: username, password: password)
            try await server.disconnect()
        } catch {
            // Verbindung nicht offen lassen (z. B. nach fehlgeschlagenem Login)
            try? await server.disconnect()
            throw TestError.smtpFailed(error.localizedDescription)
        }
    }
}
