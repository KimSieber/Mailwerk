//
//  SpamMarkTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Anzeigetext der Spam-Einschätzung (SpamMark) in
//  Mailliste und Mailansicht.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SpamMarkTests {

    /// Testhilfe: Absender aus einer Adresse.
    private func sender(_ address: String) throws -> FilterAddress {
        try #require(FilterAddress(normalizing: address))
    }

    /// Testhilfe: Text für einen Absender mit Befund und Listen.
    private func mark(
        _ address: String,
        _ verdict: SpamHeaderVerdict?,
        _ lists: FilterLists = .empty,
        _ style: SpamMark.Style = .detail
    ) throws -> String? {
        SpamMark.text(
            sender: try sender(address), verdict: verdict,
            rules: SpamRules(lists: lists, scoreLimit: 15), style: style
        )
    }

    // MARK: - Mailliste

    /// Die Liste zeigt nur [SPAM], nie einen Score und nie NoSpam.
    @Test func listShowsOnlySpam() {
        #expect(SpamMark.text(isSpam: true, score: 7.2, keptByWhitelist: false, style: .list) == "[SPAM]")
        #expect(SpamMark.text(isSpam: true, score: nil, keptByWhitelist: false, style: .list) == "[SPAM]")
        #expect(SpamMark.text(isSpam: false, score: 2.1, keptByWhitelist: false, style: .list) == nil)
        #expect(SpamMark.text(isSpam: false, score: nil, keptByWhitelist: true, style: .list) == nil)
    }

    // MARK: - Mailansicht

    /// Die fünf Fälle der Mailansicht.
    @Test func detailTextsForAllCases() {
        #expect(SpamMark.text(isSpam: true, score: 7.24, keptByWhitelist: false, style: .detail) == "[SPAM score=7.2]")
        #expect(SpamMark.text(isSpam: true, score: nil, keptByWhitelist: false, style: .detail) == "[SPAM]")
        #expect(SpamMark.text(isSpam: false, score: 2.1, keptByWhitelist: false, style: .detail) == "[NoSpam score=2.1]")
        #expect(SpamMark.text(isSpam: false, score: nil, keptByWhitelist: true, style: .detail) == "[NoSpam]")
        #expect(SpamMark.text(isSpam: false, score: nil, keptByWhitelist: false, style: .detail) == nil)
    }

    /// Negative und ganzzahlige Scores mit einer Nachkommastelle und Punkt.
    @Test func scoreFormatting() {
        #expect(SpamMark.text(isSpam: false, score: -1.5, keptByWhitelist: false, style: .detail) == "[NoSpam score=-1.5]")
        #expect(SpamMark.text(isSpam: true, score: 10, keptByWhitelist: false, style: .detail) == "[SPAM score=10.0]")
    }

    // MARK: - Gesamtergebnis

    /// Ohne gespeicherten Befund und ohne Whitelist erscheint nichts.
    @Test func unknownVerdictShowsNothing() throws {
        #expect(try mark("x@firma.de", nil) == nil)
        #expect(try mark("x@firma.de", nil, .empty, .list) == nil)
    }

    /// Ohne gespeicherten Befund, aber auf der Whitelist → [NoSpam] (nur Mailansicht).
    @Test func unknownVerdictWithWhitelistShowsNoSpam() throws {
        let lists = FilterLists(whiteDomains: ["firma.de"])
        #expect(try mark("x@firma.de", nil, lists) == "[NoSpam]")
        #expect(try mark("x@firma.de", nil, lists, .list) == nil)
    }

    /// Server-Spam ohne Listeneintrag.
    @Test func serverSpamIsMarked() throws {
        let verdict = SpamHeaderVerdict(isSpam: true, score: 8)
        #expect(try mark("x@firma.de", verdict) == "[SPAM score=8.0]")
        #expect(try mark("x@firma.de", verdict, .empty, .list) == "[SPAM]")
    }

    /// Whitelist hebt Server-Spam auf → NoSpam mit Score.
    @Test func whitelistShowsNoSpamWithScore() throws {
        let verdict = SpamHeaderVerdict(isSpam: true, score: 8)
        let lists = FilterLists(whiteDomains: ["firma.de"])
        #expect(try mark("x@firma.de", verdict, lists) == "[NoSpam score=8.0]")
        #expect(try mark("x@firma.de", verdict, lists, .list) == nil)
    }

    /// Whitelist hebt Server-Spam ohne Score auf (z. B. X-Spam-Flag) → [NoSpam].
    @Test func whitelistShowsNoSpamWithoutScore() throws {
        let verdict = SpamHeaderVerdict(isSpam: true, score: nil)
        let lists = FilterLists(whiteAddresses: ["x@firma.de"])
        #expect(try mark("x@firma.de", verdict, lists) == "[NoSpam]")
    }

    /// Whitelist bei unverdächtiger Mail ohne Score (z. B. Gmail) → [NoSpam].
    @Test func whitelistOnCleanMailShowsNoSpam() throws {
        let lists = FilterLists(whiteDomains: ["firma.de"])
        #expect(try mark("x@firma.de", .clean, lists) == "[NoSpam]")
    }

    /// Score ab der Obergrenze übersteuert die Whitelist → SPAM, kein NoSpam.
    @Test func scoreAboveLimitBeatsWhitelist() throws {
        let verdict = SpamHeaderVerdict(isSpam: true, score: 20)
        let lists = FilterLists(whiteDomains: ["firma.de"])
        #expect(try mark("x@firma.de", verdict, lists) == "[SPAM score=20.0]")
    }

    /// Blacklist ohne Server-Spam → [SPAM].
    @Test func blacklistIsMarked() throws {
        let lists = FilterLists(blackAddresses: ["x@firma.de"])
        #expect(try mark("x@firma.de", .clean, lists) == "[SPAM]")
        #expect(try mark("x@firma.de", .clean, lists, .list) == "[SPAM]")
    }

    /// Ohne Whitelist und ohne Score bleibt eine unverdächtige Mail leer.
    @Test func cleanMailWithoutWhitelistShowsNothing() throws {
        #expect(try mark("x@firma.de", .clean) == nil)
    }
}
