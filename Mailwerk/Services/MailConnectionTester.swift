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
//  Eine gescheiterte SMTP-Anmeldung wird verständlich gemeldet
//  (SMTPLoginFailure), der gescheiterte Schritt protokolliert.
//
//  Abhängigkeiten: SwiftMail, MailServerFactory, MailFolder (Posteingang),
//  SMTPLoginFailure, Log.
//

import Foundation
import SwiftMail
import os

/// Test der Zugangsdaten eines Postfachs.
enum MailConnectionTester {

    /// Fehler des Verbindungstests.
    enum TestError: LocalizedError {
        /// IMAP-Anmeldung oder Auswahl des Posteingangs gescheitert.
        case imapFailed(String)
        /// SMTP-Verbindung gescheitert.
        case smtpFailed(String)
        /// SMTP-Anmeldung gescheitert; Antwort des Servers, falls bekannt.
        case smtpLoginRejected(String?)

        /// Liefert die deutsche Meldung für den Nutzer.
        ///
        /// - Returns: Meldungstext für die Anzeige.
        var errorDescription: String? {
            switch self {
            case .imapFailed(let message):
                return "IMAP-Verbindung fehlgeschlagen: \(message)"
            case .smtpFailed(let message):
                return "SMTP-Verbindung fehlgeschlagen: \(message)"
            case .smtpLoginRejected(let reply):
                return "SMTP: " + SMTPLoginFailure.message(serverReply: reply)
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
    /// die Verbindung ebenfalls getrennt. Scheitert erst die Anmeldung,
    /// meldet der Test das verständlich (`smtpLoginRejected`) – auch wenn
    /// der Server die Verbindung sofort beendet und SwiftMail nur einen
    /// NIO-Fehler liefert.
    ///
    /// - Parameters:
    ///   - host: SMTP-Server.
    ///   - port: Port.
    ///   - username: Benutzername.
    ///   - password: Passwort.
    /// - Throws: `TestError.smtpFailed` oder `TestError.smtpLoginRejected`.
    static func testSMTP(host: String, port: Int, username: String, password: String) async throws {
        let server = MailServerFactory.smtpServer(host: host, port: port)
        var step = SMTPStep.connect
        do {
            try await server.connect()
            step = .login
            try await server.login(username: username, password: password)
            try await server.disconnect()
        } catch {
            // Verbindung nicht offen lassen (z. B. nach fehlgeschlagenem Login)
            try? await server.disconnect()
            Log.send.error("❌ Verbindungstest SMTP \(host, privacy: .public):\(port, privacy: .public) gescheitert beim Schritt \(step.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            guard step == .login else {
                throw TestError.smtpFailed(error.localizedDescription)
            }
            if case SMTPError.authenticationFailed(let reply) = error {
                throw TestError.smtpLoginRejected(reply)
            }
            throw TestError.smtpLoginRejected(nil)
        }
    }
}
