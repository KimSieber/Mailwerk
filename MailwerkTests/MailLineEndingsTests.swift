//
//  MailLineEndingsTests.swift
//  MailwerkTests
//
//  Zweck: Tests für `MailLineEndings.crlf` – ausgehende Texte dürfen kein
//  einzelnes LF oder CR enthalten (Posteo: „bare <LF> received“).
//

import Foundation
import Testing
@testable import Mailwerk

struct MailLineEndingsTests {

    /// Einzelne LF werden zu CRLF.
    @Test func convertsBareLineFeeds() {
        #expect(MailLineEndings.crlf("Zeile 1\nZeile 2\n") == "Zeile 1\r\nZeile 2\r\n")
    }

    /// Gemischte Zeilenenden (LF, CR, CRLF) werden einheitlich CRLF.
    @Test func normalizesMixedLineEndings() {
        #expect(MailLineEndings.crlf("a\nb\rc\r\nd") == "a\r\nb\r\nc\r\nd")
    }

    /// Text mit CRLF oder ohne Umbruch bleibt unverändert.
    @Test func keepsExistingCRLF() {
        #expect(MailLineEndings.crlf("a\r\nb\r\n") == "a\r\nb\r\n")
        #expect(MailLineEndings.crlf("ohne Umbruch") == "ohne Umbruch")
    }
}
