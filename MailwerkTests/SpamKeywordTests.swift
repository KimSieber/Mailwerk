//
//  SpamKeywordTests.swift
//  Mailwerk
//
//  Created by Kim Sieber on 23.09.26.
//


//
//  SpamKeywordTests.swift
//  MailwerkTests
//
//  Absicherung der IMAP-Keywords: SwiftMail ersetzt ungültige Keywords
//  ohne Fehlermeldung durch `CUSTOM`.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SpamKeywordTests {

    @Test("Die Keywords des Filters sind gültige IMAP-Atome",
          arguments: [SpamKeyword.checked, SpamKeyword.blacklisted])
    func keywordsAreValidAtoms(keyword: String) {
        #expect(SpamKeyword.isValidAtom(keyword))
    }

    @Test("Die Keywords sind eindeutig benannt")
    func keywordsAreDistinct() {
        #expect(SpamKeyword.checked.hasPrefix("$Mailwerk"))
        #expect(SpamKeyword.blacklisted.hasPrefix("$Mailwerk"))
        #expect(SpamKeyword.checked.lowercased() != SpamKeyword.blacklisted.lowercased())
    }

    @Test("Gültige Atome werden erkannt",
          arguments: ["$Forwarded", "Junk", "$MailFlagBit0", "a"])
    func acceptsValidAtoms(keyword: String) {
        #expect(SpamKeyword.isValidAtom(keyword))
    }

    @Test("Ungültige Atome werden erkannt",
          arguments: ["", "$Mailwerk Checked", "$Mailwerk(", "$Mailwerk)", "$Mailwerk{",
                      "$Mailwerk\"", "$Mailwerk%", "$Mailwerk*", "$Mailwerk\\", "$Mailwerk]",
                      "$Mailwärk", "$Mailwerk\t"])
    func rejectsInvalidAtoms(keyword: String) {
        #expect(!SpamKeyword.isValidAtom(keyword))
    }
}