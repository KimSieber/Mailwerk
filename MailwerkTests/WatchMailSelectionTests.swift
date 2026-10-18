//
//  WatchMailSelectionTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Auswahl der Mails auf der Apple Watch
//  (WatchMailSelection) – die 50 neuesten, dazu ungelesene und
//  gekennzeichnete, höchstens 100 (neueste gewinnen), dazu die 20 neuesten
//  Spam-Mails.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct WatchMailSelectionTests {

    /// Testhilfe: Kandidat mit Datum `index` Minuten vor einem festen Zeitpunkt
    /// (kleinerer Index = neuer).
    private func candidate(_ index: Int, unread: Bool = false, flagged: Bool = false) -> WatchMailSelection.Candidate {
        WatchMailSelection.Candidate(
            id: "m\(index)",
            date: Date(timeIntervalSince1970: 1_000_000 - Double(index) * 60),
            isUnread: unread,
            isFlagged: flagged
        )
    }

    /// Wenige Mails: alle, neueste zuerst – auch bei ungeordneter Eingabe.
    @Test func fewMailsAreAllSelectedNewestFirst() {
        let ids = WatchMailSelection.inbox([candidate(2), candidate(0), candidate(1)])
        #expect(ids == ["m0", "m1", "m2"])
    }

    /// Die 50 neuesten immer, ältere nur ungelesen oder gekennzeichnet.
    @Test func olderMailsOnlyWhenUnreadOrFlagged() {
        var candidates = (0..<60).map { candidate($0) }
        candidates[55] = candidate(55, unread: true)
        candidates[58] = candidate(58, flagged: true)
        let ids = WatchMailSelection.inbox(candidates)
        #expect(ids.count == 52)
        #expect(ids.prefix(50) == ArraySlice((0..<50).map { "m\($0)" }))
        #expect(ids.suffix(2) == ["m55", "m58"])
    }

    /// Mehr als 100: die neuesten gewinnen.
    @Test func limitKeepsNewest() {
        let candidates = (0..<150).map { candidate($0, unread: true) }
        let ids = WatchMailSelection.inbox(candidates)
        #expect(ids.count == 100)
        #expect(ids.first == "m0")
        #expect(ids.last == "m99")
    }

    /// Mails ohne Datum zählen als älteste.
    @Test func mailsWithoutDateComeLast() {
        let undated = WatchMailSelection.Candidate(id: "x", date: nil, isUnread: false, isFlagged: false)
        #expect(WatchMailSelection.inbox([undated, candidate(5)]) == ["m5", "x"])
    }

    /// Spam: die 20 neuesten, unabhängig vom Zustand.
    @Test func spamKeepsTwentyNewest() {
        let ids = WatchMailSelection.spam((0..<30).map { candidate($0) })
        #expect(ids.count == 20)
        #expect(ids.first == "m0")
        #expect(ids.last == "m19")
    }
}
