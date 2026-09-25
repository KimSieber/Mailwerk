//
//  FilterListInputTests.swift
//  MailwerkTests
//
//  Tests für das Zerlegen einer Sammeleingabe in Listeneinträge.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FilterListInputTests {

    private func address(_ value: String) -> FilterListInputEntry {
        FilterListInputEntry(value: value, kind: .address)
    }

    private func domain(_ value: String) -> FilterListInputEntry {
        FilterListInputEntry(value: value, kind: .domain)
    }

    // MARK: - Einzelne Eingaben

    @Test("Leere Eingabe ergibt nichts")
    func emptyInput() {
        #expect(FilterListInput.parse("") == .empty)
        #expect(FilterListInput.parse("   \n  ") == .empty)
    }

    @Test("Eine Adresse wird als Adresse erkannt")
    func singleAddress() {
        let result = FilterListInput.parse("Anna@Firma.DE")
        #expect(result.entries == [address("anna@firma.de")])
        #expect(result.invalid.isEmpty)
    }

    @Test("Eine Domain wird als Domain erkannt", arguments: ["firma.de", "*@firma.de", "@firma.de"])
    func singleDomain(input: String) {
        #expect(FilterListInput.parse(input).entries == [domain("firma.de")])
    }

    @Test("Ein Anzeigename wird entfernt")
    func formattedAddress() {
        let result = FilterListInput.parse("Anna Muster <anna@firma.de>")
        #expect(result.entries == [address("anna@firma.de")])
        #expect(result.invalid.isEmpty)
    }

    // MARK: - Sammeleingaben

    @Test("Mehrere Angaben, getrennt durch Komma, Semikolon, Zeilenumbruch und Leerzeichen")
    func multipleSeparators() {
        let result = FilterListInput.parse("""
            anna@firma.de, bob@firma.de; firma.de
            *@werbung.tld  chef@kunde.de
            """)
        #expect(result.entries == [
            address("anna@firma.de"),
            address("bob@firma.de"),
            domain("firma.de"),
            domain("werbung.tld"),
            address("chef@kunde.de")
        ])
        #expect(result.invalid.isEmpty)
    }

    @Test("Ein Anzeigename mit Leerzeichen bleibt zusammen")
    func formattedAddressesInList() {
        let result = FilterListInput.parse("\"Muster, Anna\" <anna@firma.de>\nBob <bob@firma.de>")
        #expect(result.entries == [address("anna@firma.de"), address("bob@firma.de")])
    }

    @Test("Doppelte Angaben erscheinen einmal")
    func deduplicates() {
        let result = FilterListInput.parse("anna@firma.de, ANNA@firma.de, firma.de, firma.de")
        #expect(result.entries == [address("anna@firma.de"), domain("firma.de")])
    }

    @Test("Adresse und Domain derselben Firma sind zwei Einträge")
    func addressAndDomainAreDistinct() {
        let result = FilterListInput.parse("anna@firma.de firma.de")
        #expect(result.entries.count == 2)
    }

    // MARK: - Unbrauchbares

    @Test("Unbrauchbare Abschnitte werden gemeldet, der Rest bleibt erhalten")
    func reportsInvalid() {
        let result = FilterListInput.parse("anna@firma.de, quatsch, anna@firma")
        #expect(result.entries == [address("anna@firma.de")])
        #expect(result.invalid == ["quatsch", "anna@firma"])
    }
}
