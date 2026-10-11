//
//  SpamClassifierTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Entscheidungsregeln des SpamClassifier – beim
//  Filterlauf (Adresse vor Domain, Whitelist vor Blacklist, beides vor der
//  Server-Einstufung, mit Score-Obergrenze) und für vertrauenswürdige
//  Absender, deren externe Inhalte sofort geladen werden.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SpamClassifierTests {

    // MARK: - Hilfen

    /// Testhilfe: Einstufung ohne Spam-Kopfzeilen.
    private let clean = SpamHeaderVerdict.clean

    /// Testhilfe: Server-Einstufung „Spam“ mit wählbarem Score.
    private func serverSpam(_ score: Double?) -> SpamHeaderVerdict {
        SpamHeaderVerdict(isSpam: true, score: score)
    }

    /// Testhilfe: Entscheidung des Filterlaufs für eine Absenderadresse.
    private func classify(
        _ sender: String?,
        _ verdict: SpamHeaderVerdict,
        _ lists: FilterLists = .empty,
        limit: Double = SpamClassifier.defaultScoreLimit
    ) throws -> SpamDecision {
        let address = try sender.map { try #require(FilterAddress(normalizing: $0)) }
        return SpamClassifier.classify(sender: address, verdict: verdict, lists: lists, scoreLimit: limit)
    }

    // MARK: - Ohne Listentreffer

    /// Standard-Obergrenze ist 15.
    @Test("Standard-Obergrenze ist 15")
    func defaultLimit() {
        #expect(SpamClassifier.defaultScoreLimit == 15)
    }

    /// Kein Treffer, kein Server-Spam → behalten.
    @Test("Kein Treffer, kein Server-Spam → behalten")
    func keepsCleanMail() throws {
        #expect(try classify("x@firma.de", clean) == .keep)
    }

    /// Kein Treffer, Server-Spam → Spam (Server).
    @Test("Kein Treffer, Server-Spam → Spam (Server)")
    func serverSpamWithoutLists() throws {
        #expect(try classify("x@firma.de", serverSpam(6)) == .junkServer)
    }

    // MARK: - Blacklist

    /// Adresse auf der Blacklist → Spam (Blacklist), auch ohne Server-Einstufung.
    @Test("Adresse auf der Blacklist → Spam (Blacklist), auch ohne Server-Einstufung")
    func blacklistedAddress() throws {
        let lists = FilterLists(blackAddresses: ["x@firma.de"])
        #expect(try classify("x@firma.de", clean, lists) == .junkBlacklist)
    }

    /// Domain auf der Blacklist → Spam (Blacklist).
    @Test("Domain auf der Blacklist → Spam (Blacklist)")
    func blacklistedDomain() throws {
        let lists = FilterLists(blackDomains: ["firma.de"])
        #expect(try classify("x@firma.de", clean, lists) == .junkBlacklist)
    }

    /// Blacklist gewinnt vor der Server-Einstufung.
    @Test("Blacklist gewinnt vor der Server-Einstufung")
    func blacklistBeforeServer() throws {
        let lists = FilterLists(blackDomains: ["firma.de"])
        #expect(try classify("x@firma.de", serverSpam(30), lists) == .junkBlacklist)
    }

    // MARK: - Vorrang Adresse vor Domain

    /// Adresse auf der Whitelist schlägt Domain auf der Blacklist.
    @Test("Adresse auf der Whitelist schlägt Domain auf der Blacklist")
    func addressWhiteBeatsDomainBlack() throws {
        let lists = FilterLists(whiteAddresses: ["rechnung@firma.de"], blackDomains: ["firma.de"])
        #expect(try classify("rechnung@firma.de", clean, lists) == .keep)
        #expect(try classify("werbung@firma.de", clean, lists) == .junkBlacklist)
    }

    /// Adresse auf der Blacklist schlägt Domain auf der Whitelist.
    @Test("Adresse auf der Blacklist schlägt Domain auf der Whitelist")
    func addressBlackBeatsDomainWhite() throws {
        let lists = FilterLists(whiteDomains: ["firma.de"], blackAddresses: ["werbung@firma.de"])
        #expect(try classify("werbung@firma.de", clean, lists) == .junkBlacklist)
        #expect(try classify("rechnung@firma.de", clean, lists) == .keep)
    }

    /// Steht dieselbe Adresse (Sync-Konflikt) auf beiden Listen, gewinnt die Whitelist.
    @Test("Steht dieselbe Adresse (Sync-Konflikt) auf beiden Listen, gewinnt die Whitelist")
    func sameAddressOnBothLists() throws {
        let lists = FilterLists(whiteAddresses: ["x@firma.de"], blackAddresses: ["x@firma.de"])
        #expect(try classify("x@firma.de", clean, lists) == .keep)
    }

    // MARK: - Whitelist und Score-Obergrenze

    /// Whitelist ohne Server-Spam → behalten.
    @Test("Whitelist ohne Server-Spam → behalten")
    func whitelistClean() throws {
        let lists = FilterLists(whiteAddresses: ["x@firma.de"])
        #expect(try classify("x@firma.de", clean, lists) == .keep)
    }

    @Test("Whitelist rettet Server-Spam unter der Obergrenze", arguments: [-2.0, 5.34, 10.0, 14.99])
    func whitelistBelowLimit(score: Double) throws {
        let lists = FilterLists(whiteDomains: ["firma.de"])
        #expect(try classify("x@firma.de", serverSpam(score), lists) == .keep)
    }

    @Test("Whitelist rettet Server-Spam ab der Obergrenze nicht", arguments: [15.0, 15.01, 20.0])
    func whitelistAtOrAboveLimit(score: Double) throws {
        let lists = FilterLists(whiteDomains: ["firma.de"])
        #expect(try classify("x@firma.de", serverSpam(score), lists) == .junkServer)
    }

    /// Server-Spam ohne lesbaren Score gilt als unendlich.
    @Test("Server-Spam ohne lesbaren Score gilt als unendlich")
    func whitelistWithoutScore() throws {
        let lists = FilterLists(whiteAddresses: ["x@firma.de"])
        #expect(try classify("x@firma.de", serverSpam(nil), lists) == .junkServer)
    }

    /// Eine eigene Obergrenze wird beachtet.
    @Test("Eine eigene Obergrenze wird beachtet")
    func customLimit() throws {
        let lists = FilterLists(whiteAddresses: ["x@firma.de"])
        #expect(try classify("x@firma.de", serverSpam(4.9), lists, limit: 5) == .keep)
        #expect(try classify("x@firma.de", serverSpam(6), lists, limit: 5) == .junkServer)
    }

    // MARK: - Exakter Domain-Vergleich

    @Test("Ähnliche Domains und Subdomains treffen nicht",
          arguments: ["x@evil-firma.de", "x@mail.firma.de", "x@firma.de.evil.com"])
    func exactDomainMatch(sender: String) throws {
        let lists = FilterLists(whiteDomains: ["firma.de"], blackDomains: ["firma.de"])
        #expect(try classify(sender, clean, lists) == .keep)
        #expect(try classify(sender, serverSpam(6), lists) == .junkServer)
    }

    // MARK: - Unbekannter Absender

    /// Ohne verwertbaren Absender entscheidet nur der Server.
    @Test("Ohne verwertbaren Absender entscheidet nur der Server")
    func withoutSender() throws {
        let lists = FilterLists(whiteDomains: ["firma.de"], blackDomains: ["andere.de"])
        #expect(try classify(nil, clean, lists) == .keep)
        #expect(try classify(nil, serverSpam(6), lists) == .junkServer)
    }

    // MARK: - Vertrauenswürdige Absender (externe Inhalte)

    /// Testhilfe: Prüfung „vertrauenswürdig“ für eine Absenderadresse.
    private func trusts(
        _ sender: String?,
        _ verdict: SpamHeaderVerdict?,
        _ lists: FilterLists,
        limit: Double = SpamClassifier.defaultScoreLimit
    ) throws -> Bool {
        let address = try sender.map { try #require(FilterAddress(normalizing: $0)) }
        return SpamClassifier.trustsSender(sender: address, verdict: verdict, lists: lists, scoreLimit: limit)
    }

    /// Whitelist-Adresse ohne Spam-Kennzeichen ist vertrauenswürdig.
    @Test func trustsWhitelistedAddress() throws {
        #expect(try trusts("news@shop.de", clean, FilterLists(whiteAddresses: ["news@shop.de"])))
    }

    /// Whitelist-Domain zählt mit.
    @Test func trustsWhitelistedDomain() throws {
        #expect(try trusts("news@shop.de", clean, FilterLists(whiteDomains: ["shop.de"])))
    }

    /// Mit Spam-Kennzeichen entscheidet die Score-Obergrenze.
    @Test func trustRespectsScoreLimit() throws {
        let lists = FilterLists(whiteAddresses: ["news@shop.de"])
        #expect(try trusts("news@shop.de", serverSpam(6), lists, limit: 15))
        #expect(try !trusts("news@shop.de", serverSpam(15), lists, limit: 15))
        #expect(try !trusts("news@shop.de", serverSpam(nil), lists, limit: 15))
    }

    /// Eine Blacklist-Adresse schlägt eine Whitelist-Domain.
    @Test func blacklistedAddressBeatsWhitelistedDomain() throws {
        let lists = FilterLists(whiteDomains: ["shop.de"], blackAddresses: ["spam@shop.de"])
        #expect(try !trusts("spam@shop.de", clean, lists))
    }

    /// Ohne bekannte Spam-Angabe wird nicht vertraut.
    @Test func unknownVerdictIsNotTrusted() throws {
        #expect(try !trusts("news@shop.de", nil, FilterLists(whiteAddresses: ["news@shop.de"])))
    }

    /// Absender ohne Listeneintrag oder nicht auswertbar: nicht vertrauenswürdig.
    @Test func unlistedOrUnknownSenderIsNotTrusted() throws {
        let lists = FilterLists(whiteAddresses: ["news@shop.de"])
        #expect(try !trusts("x@firma.de", clean, lists))
        #expect(try !trusts(nil, clean, lists))
    }
}