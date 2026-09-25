//
//  SpamClassifierTests.swift
//  Mailwerk
//
//  Created by Kim Sieber on 23.09.26.
//


//
//  SpamClassifierTests.swift
//  MailwerkTests
//
//  Tests für die Entscheidungsregel: Adresse vor Domain, Whitelist vor
//  Blacklist, beides vor der Server-Einstufung – mit Score-Obergrenze.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SpamClassifierTests {

    // MARK: - Hilfen

    private let clean = SpamHeaderVerdict.clean

    private func serverSpam(_ score: Double?) -> SpamHeaderVerdict {
        SpamHeaderVerdict(isSpam: true, score: score)
    }

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

    @Test("Standard-Obergrenze ist 15")
    func defaultLimit() {
        #expect(SpamClassifier.defaultScoreLimit == 15)
    }

    @Test("Kein Treffer, kein Server-Spam → behalten")
    func keepsCleanMail() throws {
        #expect(try classify("x@firma.de", clean) == .keep)
    }

    @Test("Kein Treffer, Server-Spam → Spam (Server)")
    func serverSpamWithoutLists() throws {
        #expect(try classify("x@firma.de", serverSpam(6)) == .junkServer)
    }

    // MARK: - Blacklist

    @Test("Adresse auf der Blacklist → Spam (Blacklist), auch ohne Server-Einstufung")
    func blacklistedAddress() throws {
        let lists = FilterLists(blackAddresses: ["x@firma.de"])
        #expect(try classify("x@firma.de", clean, lists) == .junkBlacklist)
    }

    @Test("Domain auf der Blacklist → Spam (Blacklist)")
    func blacklistedDomain() throws {
        let lists = FilterLists(blackDomains: ["firma.de"])
        #expect(try classify("x@firma.de", clean, lists) == .junkBlacklist)
    }

    @Test("Blacklist gewinnt vor der Server-Einstufung")
    func blacklistBeforeServer() throws {
        let lists = FilterLists(blackDomains: ["firma.de"])
        #expect(try classify("x@firma.de", serverSpam(30), lists) == .junkBlacklist)
    }

    // MARK: - Vorrang Adresse vor Domain

    @Test("Adresse auf der Whitelist schlägt Domain auf der Blacklist")
    func addressWhiteBeatsDomainBlack() throws {
        let lists = FilterLists(whiteAddresses: ["rechnung@firma.de"], blackDomains: ["firma.de"])
        #expect(try classify("rechnung@firma.de", clean, lists) == .keep)
        #expect(try classify("werbung@firma.de", clean, lists) == .junkBlacklist)
    }

    @Test("Adresse auf der Blacklist schlägt Domain auf der Whitelist")
    func addressBlackBeatsDomainWhite() throws {
        let lists = FilterLists(whiteDomains: ["firma.de"], blackAddresses: ["werbung@firma.de"])
        #expect(try classify("werbung@firma.de", clean, lists) == .junkBlacklist)
        #expect(try classify("rechnung@firma.de", clean, lists) == .keep)
    }

    @Test("Steht dieselbe Adresse (Sync-Konflikt) auf beiden Listen, gewinnt die Whitelist")
    func sameAddressOnBothLists() throws {
        let lists = FilterLists(whiteAddresses: ["x@firma.de"], blackAddresses: ["x@firma.de"])
        #expect(try classify("x@firma.de", clean, lists) == .keep)
    }

    // MARK: - Whitelist und Score-Obergrenze

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

    @Test("Server-Spam ohne lesbaren Score gilt als unendlich")
    func whitelistWithoutScore() throws {
        let lists = FilterLists(whiteAddresses: ["x@firma.de"])
        #expect(try classify("x@firma.de", serverSpam(nil), lists) == .junkServer)
    }

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

    @Test("Ohne verwertbaren Absender entscheidet nur der Server")
    func withoutSender() throws {
        let lists = FilterLists(whiteDomains: ["firma.de"], blackDomains: ["andere.de"])
        #expect(try classify(nil, clean, lists) == .keep)
        #expect(try classify(nil, serverSpam(6), lists) == .junkServer)
    }
}