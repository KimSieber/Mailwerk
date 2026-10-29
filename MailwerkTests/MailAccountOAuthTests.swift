//
//  MailAccountOAuthTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Anmeldeart am Postfach (MailAccount.oauthProvider) –
//  ältere gespeicherte Postfächer bleiben lesbar und melden sich mit
//  Passwort an, ein Microsoft-Postfach übersteht Speichern und Lesen und
//  meldet sich mit dem Benutzernamen an (Alias als Absender).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MailAccountOAuthTests {

    /// Gespeichertes Postfach ohne Feld: lesbar, Anmeldung mit Passwort.
    @Test func olderAccountWithoutFieldUsesPassword() throws {
        let json = #"""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","displayName":"Privat","username":"kim@example.org",
         "imapHost":"imap.example.org","imapPort":993,"smtpHost":"smtp.example.org","smtpPort":465}
        """#
        let account = try JSONDecoder().decode(MailAccount.self, from: Data(json.utf8))
        #expect(account.oauthProvider == nil)
        #expect(!account.usesOAuth)
        #expect(account.oauthConfiguration == nil)
    }

    /// Postfach ohne Anmeldung per OAuth 2 schreibt kein Feld dafür.
    @Test func passwordAccountWritesNoProviderField() throws {
        let account = MailAccount(displayName: "Privat", username: "kim@example.org",
                                  imapHost: "imap.example.org", smtpHost: "smtp.example.org")
        let text = String(data: try JSONEncoder().encode(account), encoding: .utf8) ?? ""
        #expect(!text.contains("oauthProvider"))
    }

    /// Microsoft-Postfach: Anbieter und Konfiguration überstehen Speichern und Lesen.
    @Test func microsoftAccountRoundTrips() throws {
        let provider = OAuthProvider.microsoft
        let account = MailAccount(
            displayName: "Outlook", username: "kim@outlook.com", emailAddress: "kim@outlook.com",
            imapHost: provider.imapHost, imapPort: provider.imapPort,
            smtpHost: provider.smtpHost, smtpPort: provider.smtpPort,
            oauthProvider: .microsoft
        )
        let decoded = try JSONDecoder().decode(MailAccount.self, from: JSONEncoder().encode(account))
        #expect(decoded == account)
        #expect(decoded.usesOAuth)
        #expect(decoded.oauthConfiguration == .microsoft)
    }

    /// Microsoft-Postfach aus dem Formular: Server fest, Anmeldung mit dem Benutzernamen, Absender bleibt die Adresse.
    @Test func microsoftAccountFromFormUsesUsernameForLogin() {
        let model = AddAccountViewModel()
        model.kind = .oauth(.microsoft)
        model.displayName = "Outlook"
        model.emailAddress = " kim@outlook.de "
        model.username = "kim@example.com"
        let account = model.makeAccount(provider: .microsoft)
        #expect(account.username == "kim@example.com")
        #expect(account.senderAddress == "kim@outlook.de")
        #expect(account.imapHost == "outlook.office365.com")
        #expect(account.smtpPort == 587)
        #expect(account.oauthProvider == .microsoft)

        model.username = ""
        #expect(model.makeAccount(provider: .microsoft).username == "kim@outlook.de")
    }
}
