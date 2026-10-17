//
//  KeywordSupportTests.swift
//  MailwerkTests
//
//  Zweck: Tests für KeywordSupport – ob ein Server eigene Schlüsselwörter
//  dauerhaft speichert (PERMANENTFLAGS).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct KeywordSupportTests {

    /// Ohne gemeldete PERMANENTFLAGS bleibt das bisherige Verhalten (erlaubt).
    @Test func missingPermanentFlagsAllowKeywords() {
        #expect(KeywordSupport.allows("$MailwerkChecked", permanentFlags: []))
    }

    /// `\*` erlaubt eigene Schlüsselwörter – in beiden Schreibweisen.
    @Test func wildcardAllowsKeywords() {
        #expect(KeywordSupport.allows("$MailwerkChecked", permanentFlags: ["\\Seen", "wildcard"]))
        #expect(KeywordSupport.allows("$MailwerkChecked", permanentFlags: ["\\Seen", "\\*"]))
    }

    /// Outlook (Exchange Online): nur feste Kennzeichen – keine eigenen Schlüsselwörter.
    @Test func outlookFlagsRejectKeywords() {
        let outlook = ["\\Seen", "\\Answered", "\\Flagged", "\\Deleted", "\\Draft", "$MDNSent"]
        #expect(!KeywordSupport.allows("$MailwerkChecked", permanentFlags: outlook))
        #expect(KeywordSupport.allows("$mdnsent", permanentFlags: outlook))
    }
}
