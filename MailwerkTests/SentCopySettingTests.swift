//
//  SentCopySettingTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Einstellung „Kopie in Gesendet ablegen“ eines
//  Postfachs (`MailAccount.savesSentCopy`).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SentCopySettingTests {

    /// Ein älteres gespeichertes Postfach ohne das Feld legt weiter eine Kopie ab.
    @Test func olderAccountSavesSentCopy() throws {
        let json = """
            {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","displayName":"Alt",
             "username":"kim@example.org","imapHost":"imap.example.org","imapPort":993,
             "smtpHost":"smtp.example.org","smtpPort":465}
            """
        let decoded = try JSONDecoder().decode(MailAccount.self, from: Data(json.utf8))
        #expect(decoded.storesSentCopy == nil)
        #expect(decoded.savesSentCopy)
    }

    /// Ausgeschaltet bleibt die Einstellung über Speichern und Laden erhalten.
    @Test func disabledSettingSurvivesCoding() throws {
        let account = MailAccount(
            displayName: "Gmail", username: "kim@example.org",
            imapHost: "imap.example.org", smtpHost: "smtp.example.org",
            storesSentCopy: false
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(MailAccount.self, from: data)
        #expect(!decoded.savesSentCopy)
        #expect(MailAccount(displayName: "Neu", username: "a@example.org",
                            imapHost: "i", smtpHost: "s").savesSentCopy)
    }
}
