//
//  AccountAddressTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die E-Mail-Adresse eines Postfachs – Rückfall auf den
//  Benutzernamen, abweichende Adresse, Lesen älterer gespeicherter
//  Postfächer ohne das Feld, Anmeldename und die Prüfung im Formular
//  „Postfach hinzufügen“.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für `MailAccount.senderAddress` und die Adressprüfung beim Anlegen.
@MainActor
struct AccountAddressTests {

    /// Testhilfe: Postfach mit Benutzername und optionaler Adresse.
    private func account(username: String, emailAddress: String? = nil) -> MailAccount {
        MailAccount(
            displayName: "Test",
            username: username,
            emailAddress: emailAddress,
            imapHost: "imap.example.org",
            smtpHost: "smtp.example.org"
        )
    }

    /// Ohne E-Mail-Adresse ist der Benutzername die Absenderadresse.
    @Test func senderAddressFallsBackToUsername() {
        let mailbox = account(username: " kim@example.org ")
        #expect(mailbox.emailAddress == nil)
        #expect(mailbox.senderAddress == "kim@example.org")
    }

    /// Eine abweichende Adresse geht vor; eine leere wird nicht gespeichert.
    @Test func emailAddressOverridesUsername() {
        #expect(account(username: "m0123456", emailAddress: "info@example.org").senderAddress
                == "info@example.org")
        #expect(account(username: "kim@example.org", emailAddress: "  ").emailAddress == nil)
    }

    /// Ein älteres gespeichertes Postfach ohne das Feld wird gelesen.
    @Test func decodesAccountWithoutEmailAddress() throws {
        let json = """
            {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","displayName":"Alt",
             "username":"kim@example.org","imapHost":"imap.example.org","imapPort":993,
             "smtpHost":"smtp.example.org","smtpPort":465}
            """
        let decoded = try JSONDecoder().decode(MailAccount.self, from: Data(json.utf8))
        #expect(decoded.emailAddress == nil)
        #expect(decoded.senderAddress == "kim@example.org")
    }

    /// Der Anmeldename ist der Benutzername, sonst die E-Mail-Adresse.
    @Test func loginNameFallsBackToEmailAddress() {
        #expect(MailAccount.loginName(username: "  ", emailAddress: " kim@example.org ")
                == "kim@example.org")
        #expect(MailAccount.loginName(username: "m0123456", emailAddress: "kim@example.org")
                == "m0123456")
    }

    /// Testhilfe: Formular mit allen Pflichtfeldern außer der E-Mail-Adresse.
    private func filledForm() -> AddAccountViewModel {
        let model = AddAccountViewModel()
        model.displayName = "Test"
        model.password = "geheim"
        model.imapHost = "imap.example.org"
        model.smtpHost = "smtp.example.org"
        return model
    }

    /// Gespeichert werden kann nur mit gültiger E-Mail-Adresse; ohne
    /// Benutzername meldet sich das Postfach mit der Adresse an.
    @Test func formNeedsValidEmailAddress() {
        let model = filledForm()
        model.emailAddress = "kim"
        #expect(!model.isValid)

        model.emailAddress = "kim@example.org"
        #expect(model.isValid)
        let account = model.makeAccount()
        #expect(account.username == "kim@example.org")
        #expect(account.senderAddress == "kim@example.org")
    }

    /// Ein abweichender Benutzername wird zur Anmeldung, die Adresse bleibt Absender.
    @Test func formKeepsSeparateUsername() {
        let model = filledForm()
        model.emailAddress = "info@example.org"
        model.username = "m0123456"
        #expect(model.isValid)
        let account = model.makeAccount()
        #expect(account.username == "m0123456")
        #expect(account.senderAddress == "info@example.org")
    }
}
