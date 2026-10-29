//
//  SpamKeywordTests.swift
//  MailwerkTests
//
//  Zweck: Absicherung der IMAP-Keywords des Spamfilters: SwiftMail ersetzt
//  ungültige Keywords ohne Fehlermeldung durch `CUSTOM`.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für SpamKeyword.
@MainActor
struct SpamKeywordTests {

    /// Die Keywords des Filters sind gültige IMAP-Atome.
    @Test("Die Keywords des Filters sind gültige IMAP-Atome",
          arguments: [SpamKeyword.checked, SpamKeyword.blacklisted])
    func keywordsAreValidAtoms(keyword: String) {
        #expect(SpamKeyword.isValidAtom(keyword))
    }

    /// Die Keywords sind eindeutig benannt.
    @Test("Die Keywords sind eindeutig benannt")
    func keywordsAreDistinct() {
        #expect(SpamKeyword.checked.hasPrefix("$Mailwerk"))
        #expect(SpamKeyword.blacklisted.hasPrefix("$Mailwerk"))
        #expect(SpamKeyword.checked.lowercased() != SpamKeyword.blacklisted.lowercased())
    }

    /// Gültige Atome werden erkannt.
    @Test("Gültige Atome werden erkannt",
          arguments: ["$Forwarded", "Junk", "$MailFlagBit0", "a"])
    func acceptsValidAtoms(keyword: String) {
        #expect(SpamKeyword.isValidAtom(keyword))
    }

    /// Ungültige Atome werden erkannt.
    @Test("Ungültige Atome werden erkannt",
          arguments: ["", "$Mailwerk Checked", "$Mailwerk(", "$Mailwerk)", "$Mailwerk{",
                      "$Mailwerk\"", "$Mailwerk%", "$Mailwerk*", "$Mailwerk\\", "$Mailwerk]",
                      "$Mailwärk", "$Mailwerk\t"])
    func rejectsInvalidAtoms(keyword: String) {
        #expect(!SpamKeyword.isValidAtom(keyword))
    }
}
