//
//  LoadCompletenessTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Regel „nur bei vollständigem Laden vorrücken“:
//  UIDNEXT nach den Neuankünften (SyncStatePlanner) und Fensterbeginn
//  nach „Ältere laden“ (SyncWindow). Fehlt auch nur eine Mail, bleibt der
//  bisherige Stand stehen, damit der nächste Abruf sie erneut versucht.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct LoadCompletenessTests {

    /// Testhilfe: Planung mit drei Neuankünften ab UID 10, UIDNEXT 20.
    private var plan: SyncStatePlanner.ArrivalPlan {
        SyncStatePlanner.arrivals(
            serverUIDs: [10, 11, 12], fromUID: 10, serverUIDNext: 20, known: []
        )
    }

    /// Alle Neuankünfte gespeichert → UIDNEXT rückt auf den geplanten Wert.
    @Test func uidNextAdvancesWhenAllArrivalsStored() {
        #expect(SyncStatePlanner.uidNextAfterLoading(plan: plan, fromUID: 10, failedCount: 0) == 20)
    }

    /// Eine Neuankunft fehlt → UIDNEXT bleibt beim bisherigen Stand.
    @Test func uidNextStaysWhenAnArrivalFailed() {
        #expect(SyncStatePlanner.uidNextAfterLoading(plan: plan, fromUID: 10, failedCount: 1) == 10)
    }

    /// Zeitraum vollständig geladen → Fensterbeginn rückt auf dessen Anfang.
    @Test func windowAdvancesWhenBlockComplete() {
        let previous = Date(timeIntervalSince1970: 2_000_000)
        let loaded = Date(timeIntervalSince1970: 1_000_000)
        #expect(SyncWindow.startAfterLoading(previous: previous, loaded: loaded, failedCount: 0) == loaded)
    }

    /// Eine Mail des Zeitraums fehlt → Fensterbeginn bleibt stehen.
    @Test func windowStaysWhenBlockIncomplete() {
        let previous = Date(timeIntervalSince1970: 2_000_000)
        let loaded = Date(timeIntervalSince1970: 1_000_000)
        #expect(SyncWindow.startAfterLoading(previous: previous, loaded: loaded, failedCount: 2) == previous)
    }
}
