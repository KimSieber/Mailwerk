//
//  MailConnectionTester.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//


//
//  MailConnectionTester.swift
//  Mailwerk
//

import Foundation
import SwiftMail

/// Prüft IMAP- und SMTP-Zugangsdaten, ohne dauerhaft verbunden zu bleiben.
/// Wird für den "Verbindung testen"-Button bei der Postfach-Einrichtung genutzt.
enum MailConnectionTester {

    enum TestError: LocalizedError {
        case imapFailed(String)
        case smtpFailed(String)

        var errorDescription: String? {
            switch self {
            case .imapFailed(let message):
                return "IMAP-Verbindung fehlgeschlagen: \(message)"
            case .smtpFailed(let message):
                return "SMTP-Verbindung fehlgeschlagen: \(message)"
            }
        }
    }

    static func testIMAP(host: String, port: Int, username: String, password: String) async throws {
        let server = IMAPServer(host: host, port: port)
        do {
            try await server.connect()
            try await server.login(username: username, password: password)
            _ = try await server.selectMailbox("INBOX")
            try await server.logout()
        } catch {
            throw TestError.imapFailed(error.localizedDescription)
        }
    }

    static func testSMTP(host: String, port: Int, username: String, password: String) async throws {
        let server = SMTPServer(host: host, port: port)
        do {
            try await server.connect()
            try await server.login(username: username, password: password)
            try await server.disconnect()
        } catch {
            throw TestError.smtpFailed(error.localizedDescription)
        }
    }
}
