//
//  ParallelRefreshPlannerTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Verteilung des parallelen Abrufs
//  (ParallelRefreshPlanner, Prüfbericht P-21): Grenzen insgesamt und je
//  Server, Reihenfolge, nachträglich hinzugekommene Postfächer, Abbruch.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für ParallelRefreshPlanner.
@MainActor
struct ParallelRefreshPlannerTests {

    /// Testhilfe: Postfach auf einem Server.
    private func item(_ host: String) -> ParallelRefreshPlanner.Item {
        ParallelRefreshPlanner.Item(accountID: UUID(), host: host)
    }

    /// Insgesamt starten höchstens drei Abrufe.
    @Test("Insgesamt höchstens drei gleichzeitig")
    func respectsTotalLimit() {
        var planner = ParallelRefreshPlanner(maxConcurrent: 3, maxPerHost: 2)
        planner.add([item("a"), item("b"), item("c"), item("d"), item("e")])
        #expect(planner.startableItems().count == 3)
        #expect(planner.pending.count == 2)
    }

    /// Je Server starten höchstens zwei; andere Server rücken vor.
    @Test("Je Server höchstens zwei, andere Server rücken vor")
    func respectsPerHostLimit() {
        var planner = ParallelRefreshPlanner(maxConcurrent: 3, maxPerHost: 2)
        let first = item("imap.manitu.de")
        let second = item("IMAP.manitu.de")
        let third = item("imap.manitu.de")
        let other = item("imap.gmail.com")
        planner.add([first, second, third, other])
        let started = planner.startableItems()
        #expect(started == [first, second, other])
        #expect(planner.pending == [third])
    }

    /// Wird ein Platz frei, startet das nächste Postfach desselben Servers.
    @Test("Freier Platz lässt das nächste Postfach starten")
    func finishingFreesSlot() {
        var planner = ParallelRefreshPlanner(maxConcurrent: 3, maxPerHost: 2)
        let a1 = item("h"), a2 = item("h"), a3 = item("h")
        planner.add([a1, a2, a3])
        #expect(planner.startableItems() == [a1, a2])
        planner.finish(a1)
        #expect(planner.startableItems() == [a3])
    }

    /// Ein Postfach wird je Runde nur einmal eingeplant.
    @Test("Ein Postfach wird je Runde nur einmal eingeplant")
    func addsEachAccountOnce() {
        var planner = ParallelRefreshPlanner()
        let a = item("h")
        planner.add([a])
        planner.add([a])
        #expect(planner.pending.count == 1)
        _ = planner.startableItems()
        planner.add([a])
        #expect(planner.pending.isEmpty)
    }

    /// Nachträglich hinzugekommene Postfächer laufen in derselben Runde.
    @Test("Hinzugekommene Postfächer laufen mit")
    func lateAccountsJoin() {
        var planner = ParallelRefreshPlanner()
        let a = item("x")
        planner.add([a])
        _ = planner.startableItems()
        let late = item("y")
        planner.add([late])
        #expect(planner.startableItems() == [late])
    }

    /// Abbruch verwirft Wartende; die Runde endet, wenn die laufenden fertig sind.
    @Test("Abbruch verwirft wartende Postfächer")
    func dropPendingEndsRound() {
        var planner = ParallelRefreshPlanner(maxConcurrent: 1, maxPerHost: 1)
        let a = item("x"), b = item("y")
        planner.add([a, b])
        _ = planner.startableItems()
        planner.dropPending()
        #expect(!planner.isFinished)
        planner.finish(a)
        #expect(planner.isFinished)
    }
}

/// Testhilfe: Ende einer Abrufrunde.
extension ParallelRefreshPlanner {
    /// `true`, wenn nichts mehr wartet und nichts mehr läuft.
    nonisolated var isFinished: Bool { pending.isEmpty && runningCount == 0 }
}
