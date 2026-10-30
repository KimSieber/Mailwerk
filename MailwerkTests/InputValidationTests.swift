//
//  InputValidationTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Prüfung von Eingaben an der Systemgrenze
//  (Code-Review v0.3.1, Regel 12): Port-Eingaben in den Postfach-Formularen
//  (MailAccount.port) und das Größenlimit beim Anhängen von Dateien
//  (AttachmentManager.exceedsImportLimit).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für Port-Prüfung und Größenlimit beim Anhängen.
@MainActor
struct InputValidationTests {

    /// Gültige Ports werden übernommen, auch mit Leerraum.
    @Test("Gültige Ports", arguments: [("993", 993), ("1", 1), ("65535", 65535), (" 587 ", 587)])
    func validPorts(text: String, expected: Int) {
        #expect(MailAccount.port(from: text) == expected)
    }

    /// Ports außerhalb 1–65535 und Nicht-Zahlen werden abgelehnt.
    @Test("Ungültige Ports", arguments: ["0", "65536", "70000", "-1", "", "abc", "99.5"])
    func invalidPorts(text: String) {
        #expect(MailAccount.port(from: text) == nil)
    }

    /// Bis zum Limit wird angehängt, darüber abgelehnt; unbekannte Größe passiert.
    @Test("Größenlimit beim Anhängen")
    func importLimit() {
        let limit = AttachmentManager.maxImportBytes
        #expect(!AttachmentManager.exceedsImportLimit(sizeBytes: limit))
        #expect(AttachmentManager.exceedsImportLimit(sizeBytes: limit + 1))
        #expect(!AttachmentManager.exceedsImportLimit(sizeBytes: nil))
    }
}
