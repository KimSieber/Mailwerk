//
//  RecipientInputTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Zerlegen von Eingaben in Empfängeradressen
//  (RecipientInput).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für RecipientInput.
@MainActor
struct RecipientInputTests {

    /// Komma und Semikolon schließen Adressen ab.
    @Test("Komma und Semikolon schließen Adressen ab")
    func splitsOnSeparators() {
        let result = RecipientInput.split("anna@example.org, bob@example.org; ")
        #expect(result.addresses.map(\.address) == ["anna@example.org", "bob@example.org"])
        #expect(result.remainder.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Komma im Namen trennt nicht.
    @Test("Komma im Namen trennt nicht")
    func keepsQuotedName() {
        let result = RecipientInput.split("\"Sieber, Kim\" <kim@example.org>,")
        #expect(result.addresses.count == 1)
        #expect(result.addresses.first?.name == "Sieber, Kim")
        #expect(result.addresses.first?.address == "kim@example.org")
    }

    /// Unvollständige Eingabe bleibt als Rest stehen.
    @Test("Unvollständige Eingabe bleibt als Rest stehen")
    func keepsRemainder() {
        let result = RecipientInput.split("anna@example.org, bo")
        #expect(result.addresses.map(\.address) == ["anna@example.org"])
        #expect(result.remainder == " bo")
    }

    /// Ungültige Eingabe wird als ungültige Adresse übernommen.
    @Test("Ungültige Eingabe wird als ungültige Adresse übernommen")
    func keepsInvalidInput() {
        let result = RecipientInput.split("keine-adresse,")
        #expect(result.addresses.count == 1)
        #expect(result.addresses.first?.isValid == false)
    }

    /// Leere Abschnitte werden übersprungen.
    @Test("Leere Abschnitte werden übersprungen")
    func ignoresEmptyTokens() {
        let result = RecipientInput.split(",  ,anna@example.org,")
        #expect(result.addresses.map(\.address) == ["anna@example.org"])
    }

    /// Doppelte Adressen werden nicht erneut hinzugefügt.
    @Test("Doppelte Adressen werden nicht erneut hinzugefügt")
    func removesDuplicates() {
        let existing = [MailAddress(address: "anna@example.org")]
        let additions = [
            MailAddress(address: "ANNA@example.org"),
            MailAddress(address: "bob@example.org"),
            MailAddress(address: "bob@example.org")
        ]
        let result = RecipientInput.appending(additions, to: existing)
        #expect(result.map(\.normalizedAddress) == ["anna@example.org", "bob@example.org"])
    }
}
