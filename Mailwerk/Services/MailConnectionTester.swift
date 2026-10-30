//
//  MailConnectionTester.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Prüft IMAP- und SMTP-Zugang, ohne dauerhaft verbunden zu
//  bleiben – für „Verbindung testen“ bei der Postfach-Einrichtung und nach
//  der Anmeldung bei Microsoft.
//
//  Geprüft wird mit Passwort oder mit einem Access-Token (XOAUTH2). Das
//  Token kommt beim Einrichten direkt aus dem Anmeldefenster – das
//  Postfach ist dann noch nicht gespeichert.
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
//  SMTPLoginFailure, MailSession (Zugang), OAuthTokenService, Log.
//

import Foundation
import SwiftMail
import os

/// Zugang für einen Verbindungstest.
nonisolated enum MailLogin: Equatable, Sendable {
    /// Anmeldung mit Passwort.
    case password(String)
    /// Anmeldung per OAuth 2 mit einem Access-Token (XOAUTH2).
    case accessToken(String)
}

/// Test der Zugangsdaten eines Postfachs.
enum MailConnectionTester {

    /// Fehler des Verbindungstests.
    enum TestError: LocalizedError, Equatable {
        /// IMAP-Anmeldung oder Auswahl des Posteingangs gescheitert.
        case imapFailed(String)
        /// SMTP-Verbindung gescheitert.
        case smtpFailed(String)
        /// SMTP-Anmeldung mit Passwort gescheitert; Antwort des Servers,
        /// falls bekannt.
        case smtpLoginRejected(String?)
        /// SMTP-Anmeldung per OAuth 2 gescheitert; Antwort des Servers,
        /// falls bekannt.
        case smtpTokenRejected(String?)

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
            case .smtpTokenRejected(let reply):
                let detail = reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return detail.isEmpty
                    ? "SMTP: Der Versandserver hat die Anmeldung nicht angenommen."
                    : "SMTP: Der Versandserver hat die Anmeldung nicht angenommen (\(detail))."
            }
        }
    }

    /// Prüft den IMAP-Zugang.
    ///
    /// Verarbeitung: Verbinden, anmelden (Passwort oder XOAUTH2),
    /// Posteingang auswählen, abmelden. Bei einem Fehler wird die
    /// Verbindung getrennt.
    ///
    /// - Parameters:
    ///   - host: IMAP-Server.
    ///   - port: Port.
    ///   - username: Benutzername bzw. E-Mail-Adresse.
    ///   - login: Passwort oder Access-Token.
    /// - Throws: `TestError.imapFailed`.
    static func testIMAP(host: String, port: Int, username: String, login: MailLogin) async throws {
        let server = MailServerFactory.imapServer(host: host, port: port)
        do {
            try await server.connect()
            switch login {
            case .password(let password):
                try await server.login(username: username, password: password)
            case .accessToken(let token):
                try await server.authenticateXOAUTH2(email: username, accessToken: token)
            }
            _ = try await server.selectMailbox(MailFolder.inboxPath)
            try await server.logout()
        } catch {
            // Verbindung nicht offen lassen (z. B. nach fehlgeschlagenem Login)
            await MailSession.disconnectQuietly(Log.fetch, host: host) {
                try await server.disconnect()
            }
            Log.fetch.error("❌ Verbindungstest IMAP \(host, privacy: .public):\(port, privacy: .public) gescheitert: \(error.localizedDescription, privacy: .public)")
            throw TestError.imapFailed(error.localizedDescription)
        }
    }

    /// Prüft den SMTP-Zugang.
    ///
    /// Verarbeitung: Verbinden, anmelden (Passwort oder XOAUTH2), trennen.
    /// Bei einem Fehler wird die Verbindung ebenfalls getrennt. Scheitert
    /// erst die Anmeldung, meldet der Test das verständlich – auch wenn
    /// der Server die Verbindung sofort beendet und SwiftMail nur einen
    /// NIO-Fehler liefert.
    ///
    /// - Parameters:
    ///   - host: SMTP-Server.
    ///   - port: Port.
    ///   - username: Benutzername bzw. E-Mail-Adresse.
    ///   - login: Passwort oder Access-Token.
    /// - Throws: `TestError.smtpFailed`, `.smtpLoginRejected` oder
    ///   `.smtpTokenRejected`.
    static func testSMTP(host: String, port: Int, username: String, login: MailLogin) async throws {
        let server = MailServerFactory.smtpServer(host: host, port: port)
        var step = SMTPStep.connect
        do {
            try await server.connect()
            step = .login
            switch login {
            case .password(let password):
                try await server.login(username: username, password: password)
            case .accessToken(let token):
                try await server.authenticateXOAUTH2(email: username, accessToken: token)
            }
            try await server.disconnect()
        } catch {
            // Verbindung nicht offen lassen (z. B. nach fehlgeschlagenem Login)
            await MailSession.disconnectQuietly(Log.send, host: host) {
                try await server.disconnect()
            }
            Log.send.error("❌ Verbindungstest SMTP \(host, privacy: .public):\(port, privacy: .public) gescheitert beim Schritt \(step.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw smtpTestError(for: error, step: step, login: login)
        }
    }

    /// Ordnet einen Fehler des SMTP-Tests einer Meldung zu.
    ///
    /// Verarbeitung: Scheitert die Verbindung, gilt `smtpFailed`. Scheitert
    /// erst die Anmeldung, gilt je nach Zugang `smtpLoginRejected` bzw.
    /// `smtpTokenRejected` – mit der Antwort des Servers, sofern SwiftMail
    /// sie liefert. Auch ein NIO-Fehler in diesem Schritt zählt als
    /// abgelehnte Anmeldung: Manche Server beenden die Verbindung sofort.
    ///
    /// - Parameters:
    ///   - error: Aufgetretener Fehler.
    ///   - step: Schritt, in dem er auftrat.
    ///   - login: Verwendeter Zugang.
    /// - Returns: Fehler für den Nutzer.
    static func smtpTestError(for error: Error, step: SMTPStep, login: MailLogin) -> TestError {
        guard step == .login else {
            return .smtpFailed(error.localizedDescription)
        }
        var reply: String?
        if case SMTPError.authenticationFailed(let text) = error { reply = text }
        switch login {
        case .password: return .smtpLoginRejected(reply)
        case .accessToken: return .smtpTokenRejected(reply)
        }
    }

    /// Prüft IMAP und SMTP eines gespeicherten Postfachs mit seinem Zugang.
    ///
    /// Verarbeitung: Mit Passwort wird es direkt verwendet; per OAuth 2
    /// holt der OAuthTokenService ein gültiges Access-Token (erneuert bei
    /// Bedarf).
    ///
    /// - Parameter credentials: Postfach und Zugang.
    /// - Throws: `TestError` oder `OAuthError`.
    static func test(_ credentials: MailCredentials) async throws {
        let account = credentials.account
        let login: MailLogin
        switch credentials.secret {
        case .password(let password):
            login = .password(password)
        case .oauth(let provider):
            login = .accessToken(
                try await OAuthTokenService.shared.accessToken(accountID: account.id, provider: provider)
            )
        }
        try await testIMAP(host: account.imapHost, port: account.imapPort, username: account.username, login: login)
        try await testSMTP(host: account.smtpHost, port: account.smtpPort, username: account.username, login: login)
    }
}
