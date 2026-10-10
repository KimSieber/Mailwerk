//
//  MailSessionTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Bestimmen der Zugangsdaten in MailSession –
//  Postfach gefunden, Postfach fehlt, Passwort fehlt, Lesefehler des
//  Schlüsselbunds wird unverändert weitergegeben.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MailSessionTests {

    /// Testhilfe: ein Postfach mit Namen.
    private func account(_ name: String) -> MailAccount {
        MailAccount(displayName: name, username: "\(name)@example.org",
                    imapHost: "imap.example.org", smtpHost: "smtp.example.org")
    }

    /// Testhilfe: Lesefehler des Schlüsselbunds.
    private struct KeychainFailure: Error, Equatable {}

    /// Postfach und Passwort vorhanden: beides wird geliefert.
    @Test func resolvesAccountAndPassword() throws {
        let a = account("a"), b = account("b")
        let credentials = try MailSession.resolve(accountID: b.id, in: [a, b]) { $0.id == b.id ? "geheim" : nil }
        #expect(credentials.account.id == b.id)
        #expect(credentials.password == "geheim")
    }

    /// Unbekannte Postfach-ID: Postfach nicht gefunden.
    @Test func unknownAccountThrowsAccountNotFound() {
        #expect(throws: MailCredentialError.accountNotFound) {
            try MailSession.resolve(accountID: UUID(), in: [account("a")]) { _ in "geheim" }
        }
    }

    /// Kein Passwort gespeichert: kein Passwort.
    @Test func missingPasswordThrowsNoPassword() {
        let a = account("a")
        #expect(throws: MailCredentialError.noPassword) {
            try MailSession.resolve(accountID: a.id, in: [a]) { _ in nil }
        }
    }

    /// Lesefehler des Schlüsselbunds: wird unverändert weitergegeben.
    @Test func keychainErrorPassesThrough() {
        let a = account("a")
        #expect(throws: KeychainFailure()) {
            try MailSession.resolve(account: a) { _ in throw KeychainFailure() }
        }
    }
}
