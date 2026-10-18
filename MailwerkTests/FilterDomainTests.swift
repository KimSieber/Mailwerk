//
//  FilterDomainTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Domain-Regeln der Filterlisten (FilterDomain):
//  Schreibweise, Länderendungen, Kandidaten für den Abgleich, Hauptdomain
//  und Listenwert aus dem Spam-Menü.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FilterDomainTests {

    /// Testhilfe: Absender aus einer Adresse.
    private func sender(_ address: String) throws -> FilterAddress {
        try #require(FilterAddress(normalizing: address))
    }

    // MARK: - Schreibweise

    /// Domains erscheinen als `*domain`, Adressen unverändert.
    @Test func displayUsesAsterisk() {
        #expect(FilterDomain.display("apple.com") == "*apple.com")
        #expect(FilterDomain.display("apple.com", kind: .domain) == "*apple.com")
        #expect(FilterDomain.display("a@apple.com", kind: .address) == "a@apple.com")
    }

    // MARK: - Länderendungen

    /// Länderendungen sind keine eintragbare Domain.
    @Test(arguments: ["de", "com", "co.uk", "com.au"])
    func suffixIsNotListable(value: String) {
        #expect(FilterDomain.isSuffixOnly(value))
        #expect(FilterDomain.listable(value) == nil)
        #expect(FilterDomain.listable("*\(value)") == nil)
    }

    /// Echte Domains sind eintragbar, in allen Schreibweisen.
    @Test(arguments: ["apple.com", "*apple.com", "*.apple.com", "*@apple.com", "@apple.com", " *Apple.COM "])
    func domainIsListable(value: String) {
        #expect(FilterDomain.listable(value) == "apple.com")
    }

    /// Domains unter zweiteiligen Länderendungen sind eintragbar.
    @Test func domainUnderTwoPartSuffixIsListable() {
        #expect(FilterDomain.listable("*firma.co.uk") == "firma.co.uk")
    }

    /// Doppelte oder falsch gesetzte Platzhalter sind unbrauchbar.
    @Test(arguments: ["**apple.com", "*.*.apple.com", "*", "*@", "apple.*"])
    func malformedWildcardIsRejected(value: String) {
        #expect(FilterDomain.listable(value) == nil)
    }

    // MARK: - Abgleich

    /// Kandidaten vom genauesten zum allgemeinsten, bis zur Hauptdomain.
    @Test func candidatesWalkUpToMainDomain() {
        #expect(FilterDomain.matchCandidates(for: "a.mail.apple.com") == ["a.mail.apple.com", "mail.apple.com", "apple.com"])
        #expect(FilterDomain.matchCandidates(for: "apple.com") == ["apple.com"])
    }

    /// Zweiteilige Länderendungen gehören nie zu den Kandidaten.
    @Test func candidatesStopBeforeTwoPartSuffix() {
        #expect(FilterDomain.matchCandidates(for: "shop.firma.co.uk") == ["shop.firma.co.uk", "firma.co.uk"])
    }

    // MARK: - Hauptdomain

    /// Hauptdomain nur, wenn es eine Subdomain gibt.
    @Test func mainDomainOnlyForSubdomains() {
        #expect(FilterDomain.mainDomainIfDifferent(from: "mail.apple.com") == "apple.com")
        #expect(FilterDomain.mainDomainIfDifferent(from: "apple.com") == nil)
        #expect(FilterDomain.mainDomainIfDifferent(from: "firma.co.uk") == nil)
        #expect(FilterDomain.mainDomainIfDifferent(from: "shop.firma.co.uk") == "firma.co.uk")
    }

    // MARK: - Listenwert aus dem Menü

    /// Ohne Wunsch: Adresse bzw. Domain des Absenders.
    @Test func entryValueDefaults() throws {
        let from = try sender("x@mail.apple.com")
        #expect(FilterDomain.entryValue(for: from, kind: .address, requested: nil) == "x@mail.apple.com")
        #expect(FilterDomain.entryValue(for: from, kind: .domain, requested: nil) == "mail.apple.com")
    }

    /// Die Hauptdomain des Absenders ist erlaubt.
    @Test func entryValueAcceptsMainDomain() throws {
        let from = try sender("x@mail.apple.com")
        #expect(FilterDomain.entryValue(for: from, kind: .domain, requested: "apple.com") == "apple.com")
    }

    /// Fremde Werte und Länderendungen werden abgelehnt.
    @Test func entryValueRejectsForeignValues() throws {
        let from = try sender("x@mail.apple.com")
        #expect(FilterDomain.entryValue(for: from, kind: .domain, requested: "com") == nil)
        #expect(FilterDomain.entryValue(for: from, kind: .domain, requested: "badapple.com") == nil)
        #expect(FilterDomain.entryValue(for: from, kind: .address, requested: "y@mail.apple.com") == nil)
    }
}
