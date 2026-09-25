//
//  FilterAddressTests.swift
//  Mailwerk
//
//  Created by Kim Sieber on 23.09.26.
//


//
//  FilterAddressTests.swift
//  MailwerkTests
//
//  Tests für die Normalisierung von Absendern und Listeneinträgen.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FilterAddressTests {

    // MARK: - Absender aus dem From-Header

    @Test("Absender ohne Anzeigename")
    func plainSender() throws {
        let sender = try #require(FilterAddress.sender(fromHeader: "anna@example.org"))
        #expect(sender.address == "anna@example.org")
        #expect(sender.domain == "example.org")
    }

    @Test("Anzeigename, Anführungszeichen, spitze Klammern und Großbuchstaben",
          arguments: [
            "Anna Muster <Anna@Example.ORG>",
            "\"Muster, Anna\" <anna@example.org>",
            "\"Anna <Chefin>\" <ANNA@EXAMPLE.ORG>",
            "  <anna@example.org>  ",
            "=?UTF-8?Q?Anna_M=C3=BCller?= <anna@example.org>"
          ])
    func formattedSender(raw: String) throws {
        let sender = try #require(FilterAddress.sender(fromHeader: raw))
        #expect(sender.address == "anna@example.org")
        #expect(sender.domain == "example.org")
    }

    @Test("Bei mehreren Absendern zählt der erste")
    func firstOfSeveral() throws {
        let sender = try #require(
            FilterAddress.sender(fromHeader: "\"Muster, Anna\" <anna@example.org>, bob@example.net")
        )
        #expect(sender.address == "anna@example.org")
    }

    @Test("Die Domain ist exakt der Teil nach dem @")
    func subdomainStaysExact() throws {
        let sender = try #require(FilterAddress.sender(fromHeader: "News <x@mail.firma.de>"))
        #expect(sender.domain == "mail.firma.de")
    }

    @Test("Ungewöhnliche, aber zulässige Absender bleiben filterbar",
          arguments: ["bounce=123@news.example.org", "_info@example.org", "a@example.org"])
    func unusualSenders(raw: String) throws {
        let sender = try #require(FilterAddress.sender(fromHeader: raw))
        #expect(sender.address == raw)
    }

    @Test("Unbrauchbare From-Angaben liefern nil",
          arguments: ["", "   ", "Undisclosed recipients:;", "kein-at-zeichen",
                      "Anna <>", "@example.org", "anna@", "anna@example"])
    func unusableSender(raw: String) {
        #expect(FilterAddress.sender(fromHeader: raw) == nil)
    }

    // MARK: - Listeneingabe: Adresse

    @Test("Adresseingabe wird normalisiert")
    func normalizesAddress() throws {
        let entry = try #require(FilterAddress(normalizing: "  Rechnung@Firma.DE "))
        #expect(entry.address == "rechnung@firma.de")
        #expect(entry.domain == "firma.de")
    }

    @Test("Unbrauchbare Adresseingaben liefern nil",
          arguments: ["", "   ", "firma.de", "a b@firma.de", "Anna <anna@firma.de>",
                      "anna@firma", "anna@@firma.de", "anna@firma..de", "@firma.de", "anna@"])
    func rejectsAddress(raw: String) {
        #expect(FilterAddress(normalizing: raw) == nil)
    }

    // MARK: - Listeneingabe: Domain

    @Test("Domain-Eingaben werden normalisiert",
          arguments: [
            ("firma.de", "firma.de"),
            ("  Firma.DE ", "firma.de"),
            ("*@firma.de", "firma.de"),
            ("@firma.de", "firma.de"),
            ("firma.de.", "firma.de"),
            ("mail.firma.de", "mail.firma.de")
          ])
    func normalizesDomain(input: String, expected: String) {
        #expect(FilterAddress.normalizedDomain(input) == expected)
    }

    @Test("Unbrauchbare Domain-Eingaben liefern nil",
          arguments: ["", "  ", "firma", "anna@firma.de", "fir ma.de",
                      "*.firma.de", "firma..de", ".firma.de", "*@"])
    func rejectsDomain(raw: String) {
        #expect(FilterAddress.normalizedDomain(raw) == nil)
    }
}