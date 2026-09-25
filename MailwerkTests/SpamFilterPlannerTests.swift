//
//  SpamFilterPlannerTests.swift
//  MailwerkTests
//
//  Tests für den Arbeitsplan eines Filterlaufs.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SpamFilterPlannerTests {

    // MARK: - Hilfen

    private func candidate(
        _ uid: UInt32,
        from address: String?,
        spam: Bool = false,
        score: Double? = nil
    ) -> SpamCandidate {
        SpamCandidate(
            uid: uid,
            sender: address.flatMap { FilterAddress(normalizing: $0) },
            verdict: SpamHeaderVerdict(isSpam: spam, score: score)
        )
    }

    private func plan(
        _ candidates: [SpamCandidate],
        lists: FilterLists = .empty,
        scoreLimit: Double = SpamClassifier.defaultScoreLimit
    ) -> SpamFilterPlan {
        SpamFilterPlanner.plan(for: candidates, lists: lists, scoreLimit: scoreLimit)
    }

    // MARK: - Grundfälle

    @Test("Ohne Kandidaten bleibt der Plan leer")
    func emptyPlan() {
        let result = plan([])
        #expect(result == .empty)
        #expect(result.isEmpty)
    }

    @Test("Saubere Mails bleiben im Posteingang, werden aber als geprüft vermerkt")
    func cleanMailsStay() {
        let result = plan([
            candidate(1, from: "anna@firma.de"),
            candidate(2, from: "bob@firma.de")
        ])
        #expect(result.keep == [1, 2])
        #expect(result.checked == [1, 2])
        #expect(result.moveToSpam.isEmpty)
        #expect(result.blacklisted.isEmpty)
        #expect(!result.isEmpty)
    }

    @Test("Vom Server erkannter Spam wandert, ohne Blacklist-Keyword")
    func serverSpamMoves() {
        let result = plan([candidate(5, from: "werbung@firma.de", spam: true, score: 9)])
        #expect(result.moveToSpam == [5])
        #expect(result.checked == [5])
        #expect(result.blacklisted.isEmpty)
        #expect(result.keep.isEmpty)
    }

    @Test("Ein Blacklist-Treffer wandert und wird als solcher gekennzeichnet")
    func blacklistMovesAndMarks() {
        let lists = FilterLists(blackDomains: ["firma.de"])
        let result = plan([candidate(7, from: "werbung@firma.de")], lists: lists)
        #expect(result.moveToSpam == [7])
        #expect(result.blacklisted == [7])
        #expect(result.checked == [7])
    }

    @Test("Ein Whitelist-Treffer unterhalb der Obergrenze bleibt trotz Server-Spam")
    func whitelistKeeps() {
        let lists = FilterLists(whiteAddresses: ["anna@firma.de"])
        let result = plan([candidate(9, from: "anna@firma.de", spam: true, score: 6)], lists: lists)
        #expect(result.keep == [9])
        #expect(result.moveToSpam.isEmpty)
        #expect(result.checked == [9])
    }

    @Test("Die Score-Obergrenze wird durchgereicht")
    func scoreLimitIsPassedThrough() {
        let lists = FilterLists(whiteAddresses: ["anna@firma.de"])
        let candidates = [candidate(9, from: "anna@firma.de", spam: true, score: 6)]
        #expect(plan(candidates, lists: lists, scoreLimit: 5).moveToSpam == [9])
        #expect(plan(candidates, lists: lists, scoreLimit: 7).keep == [9])
    }

    @Test("Ohne verwertbaren Absender entscheidet allein der Server")
    func withoutSender() {
        let lists = FilterLists(blackDomains: ["firma.de"])
        let result = plan([
            candidate(1, from: nil, spam: true, score: 8),
            candidate(2, from: nil)
        ], lists: lists)
        #expect(result.moveToSpam == [1])
        #expect(result.keep == [2])
        #expect(result.blacklisted.isEmpty)
    }

    // MARK: - Bündelung

    @Test("Gemischter Lauf: jede Nachricht landet in genau einer Gruppe")
    func mixedRun() {
        let lists = FilterLists(
            whiteDomains: ["kunde.de"],
            blackAddresses: ["werbung@firma.de"]
        )
        let result = plan([
            candidate(10, from: "anna@kunde.de", spam: true, score: 7),   // gerettet
            candidate(11, from: "werbung@firma.de"),                      // Blacklist
            candidate(12, from: "spam@irgendwo.tld", spam: true, score: 20), // Server
            candidate(13, from: "bob@firma.de")                           // sauber
        ], lists: lists)

        #expect(result.keep == [10, 13])
        #expect(result.moveToSpam == [11, 12])
        #expect(result.blacklisted == [11])
        #expect(result.checked == [10, 11, 12, 13])
    }

    @Test("Die Listen sind aufsteigend sortiert, unabhängig von der Eingabereihenfolge")
    func sortedOutput() {
        let lists = FilterLists(blackDomains: ["firma.de"])
        let result = plan([
            candidate(30, from: "a@firma.de"),
            candidate(10, from: "b@firma.de"),
            candidate(20, from: "c@example.org")
        ], lists: lists)

        #expect(result.checked == [10, 20, 30])
        #expect(result.moveToSpam == [10, 30])
        #expect(result.blacklisted == [10, 30])
        #expect(result.keep == [20])
    }

    @Test("Eine doppelt gelieferte UID erscheint nur einmal")
    func deduplicatesUIDs() {
        let result = plan([
            candidate(4, from: "anna@firma.de"),
            candidate(4, from: "anna@firma.de")
        ])
        #expect(result.checked == [4])
        #expect(result.keep == [4])
    }
}
