//
//  FlagStateTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Vergleich des Cache-Stands mit den Server-Flags
//  (`CachedFlagState.matches`), Grundlage für „Flags nur bei Änderung
//  schreiben“ im Abruf (v0.2.3a).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für `CachedFlagState.matches`.
struct FlagStateTests {

    /// Testhilfe: Cache-Stand mit wählbaren Flags.
    private func cached(
        unread: Bool = false, flagged: Bool = false,
        answered: Bool = false, forwarded: Bool = false
    ) -> CachedFlagState {
        CachedFlagState(
            id: "a-INBOX-1", uid: 1,
            isUnread: unread, isFlagged: flagged,
            isAnswered: answered, isForwarded: forwarded
        )
    }

    /// Gleiche Flags gelten als übereinstimmend.
    @Test("Gleiche Flags stimmen überein")
    func equalFlagsMatch() {
        let state = cached(unread: true, flagged: true, answered: true, forwarded: true)
        #expect(state.matches(isUnread: true, isFlagged: true, isAnswered: true, isForwarded: true))
    }

    /// Jedes einzelne abweichende Flag wird erkannt.
    @Test("Jedes abweichende Flag wird erkannt")
    func eachDifferenceIsDetected() {
        let state = cached()
        #expect(state.matches(isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false))
        #expect(!state.matches(isUnread: true, isFlagged: false, isAnswered: false, isForwarded: false))
        #expect(!state.matches(isUnread: false, isFlagged: true, isAnswered: false, isForwarded: false))
        #expect(!state.matches(isUnread: false, isFlagged: false, isAnswered: true, isForwarded: false))
        #expect(!state.matches(isUnread: false, isFlagged: false, isAnswered: false, isForwarded: true))
    }
}
