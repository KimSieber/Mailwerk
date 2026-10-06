//
//  SyncStatePlannerTests.swift
//  MailwerkTests
//
//  Zweck: Tests für SyncStatePlanner – Entscheidung über das Vorgehen
//  eines Abrufs (Fälle A/B/C) und Planung der Neuankünfte inklusive
//  Obergrenze. Die Fallnummern verweisen auf das Konzept
//  „Sync-Zustand je Ordner“.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SyncStatePlannerTests {

    // MARK: - Entscheidung

    /// Meldet der Server keine UIDVALIDITY, wird kein Zustand verwendet.
    @Test func missingValidityIsUnsupported() {
        let decision = SyncStatePlanner.decide(
            stored: FolderSyncState(uidValidity: 1, uidNext: 10),
            serverUIDValidity: 0, serverUIDNext: 20
        )
        #expect(decision == .unsupported)
    }

    /// Meldet der Server kein UIDNEXT, wird kein Zustand verwendet.
    @Test func missingUIDNextIsUnsupported() {
        #expect(SyncStatePlanner.decide(stored: nil, serverUIDValidity: 5, serverUIDNext: 0) == .unsupported)
    }

    /// Fall 1: ohne gespeicherten Zustand → erster Abruf.
    @Test func noStoredStateIsInitial() {
        #expect(SyncStatePlanner.decide(stored: nil, serverUIDValidity: 5, serverUIDNext: 20) == .initial)
    }

    /// Fall 8: geänderte UIDVALIDITY → Ordner-Cache verwerfen.
    @Test func changedValidityIsReset() {
        let decision = SyncStatePlanner.decide(
            stored: FolderSyncState(uidValidity: 5, uidNext: 10),
            serverUIDValidity: 6, serverUIDNext: 20
        )
        #expect(decision == .reset)
    }

    /// Gleiche UIDVALIDITY → Neuankünfte ab dem gespeicherten UIDNEXT.
    @Test func sameValidityIsIncremental() {
        let decision = SyncStatePlanner.decide(
            stored: FolderSyncState(uidValidity: 5, uidNext: 10),
            serverUIDValidity: 5, serverUIDNext: 20
        )
        #expect(decision == .incremental(fromUID: 10))
    }

    // MARK: - Neuankünfte

    /// Fall 3: hineinkopierte, alt datierte Mail (neue UID) wird geladen.
    @Test func copiedOldMailIsLoaded() {
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: [1, 2, 3, 10], fromUID: 10, serverUIDNext: 11, known: [1, 2, 3]
        )
        #expect(plan.toLoad == [10])
        #expect(plan.deferredCount == 0)
        #expect(plan.nextUIDNext == 11)
    }

    /// Fall 4: kopierte Mail und danach eine neue Mail – die neue fand schon die Datumssuche, die kopierte wird geladen.
    @Test func copiedMailFollowedByNewMailIsNotLost() {
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: [5, 10, 11], fromUID: 10, serverUIDNext: 12, known: [5, 11]
        )
        #expect(plan.toLoad == [10])
        #expect(plan.nextUIDNext == 12)
    }

    /// Fall 11: alte, nie geladene Historie unterhalb des gespeicherten UIDNEXT bleibt unberührt.
    @Test func historyBelowStoredUIDNextIsIgnored() {
        let history = Set<UInt32>(1...8_000)
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: history.union([8_001]), fromUID: 8_001, serverUIDNext: 8_002, known: []
        )
        #expect(plan.toLoad == [8_001])
    }

    /// Mails, die nach dem SELECT eintrafen (UID ≥ UIDNEXT des Servers), gehören zum nächsten Abruf.
    @Test func arrivalsAfterSelectAreLeftForNextRun() {
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: [10, 11, 12], fromUID: 10, serverUIDNext: 11, known: []
        )
        #expect(plan.toLoad == [10])
        #expect(plan.nextUIDNext == 11)
    }

    /// Fall 5: in Mailwerk verschobene Mail liegt schon im Cache und wird nicht erneut geladen.
    @Test func alreadyCachedArrivalIsSkipped() {
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: [10], fromUID: 10, serverUIDNext: 11, known: [10]
        )
        #expect(plan.toLoad.isEmpty)
        #expect(plan.nextUIDNext == 11)
    }

    /// Nichts Neues → nichts laden, UIDNEXT übernehmen.
    @Test func noArrivalsAdvancesToServerUIDNext() {
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: [1, 2], fromUID: 3, serverUIDNext: 3, known: [1, 2]
        )
        #expect(plan.toLoad.isEmpty)
        #expect(plan.deferredCount == 0)
        #expect(plan.nextUIDNext == 3)
    }

    /// Fall 9: über der Obergrenze werden die ältesten Ankünfte geladen, der Rest folgt.
    @Test func limitDefersRemainingArrivals() {
        let arrivals = Set<UInt32>(100..<350)          // 250 Neuankünfte
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: arrivals, fromUID: 100, serverUIDNext: 350, known: [], limit: 200
        )
        #expect(plan.toLoad.count == 200)
        #expect(plan.toLoad.first == 100)
        #expect(plan.toLoad.last == 299)
        #expect(plan.deferredCount == 50)
        #expect(plan.nextUIDNext == 300)
    }

    /// Fall 9, zweiter Abruf: der Rest wird geladen, danach steht UIDNEXT auf dem Serverwert.
    @Test func secondRunLoadsTheRest() {
        let arrivals = Set<UInt32>(100..<350)
        let alreadyLoaded = Set<UInt32>(100..<300)
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: arrivals, fromUID: 300, serverUIDNext: 350, known: alreadyLoaded, limit: 200
        )
        #expect(plan.toLoad.count == 50)
        #expect(plan.deferredCount == 0)
        #expect(plan.nextUIDNext == 350)
    }

    /// Die Standard-Obergrenze beträgt 200.
    @Test func defaultLimitIs200() {
        #expect(SyncStatePlanner.arrivalLimit == 200)
    }

    /// Grenze 0 lädt nichts und lässt den Zustand unverändert.
    @Test func zeroLimitKeepsPosition() {
        let plan = SyncStatePlanner.arrivals(
            serverUIDs: [10, 11], fromUID: 10, serverUIDNext: 12, known: [], limit: 0
        )
        #expect(plan.toLoad.isEmpty)
        #expect(plan.deferredCount == 2)
        #expect(plan.nextUIDNext == 10)
    }
}
