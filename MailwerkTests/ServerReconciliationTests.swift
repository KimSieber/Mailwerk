//
//  ServerReconciliationTests.swift
//  MailwerkTests
//
//  Tests für den Vergleich von Cache und Server-Stand (v0.1.8d).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct ServerReconciliationTests {

    // MARK: - Hilfen

    private func cached(
        _ uid: UInt32,
        unread: Bool = false,
        flagged: Bool = false,
        answered: Bool = false,
        forwarded: Bool = false
    ) -> CachedFlagState {
        CachedFlagState(
            id: "msg-\(uid)", uid: uid,
            isUnread: unread, isFlagged: flagged,
            isAnswered: answered, isForwarded: forwarded
        )
    }

    private func server(
        all: Set<UInt32>,
        unseen: Set<UInt32> = [],
        flagged: Set<UInt32> = [],
        answered: Set<UInt32> = [],
        forwarded: Set<UInt32>? = []
    ) -> ServerFolderState {
        ServerFolderState(all: all, unseen: unseen, flagged: flagged,
                          answered: answered, forwarded: forwarded)
    }

    private func plan(
        _ cachedMessages: [CachedFlagState],
        _ state: ServerFolderState
    ) -> ServerReconciliation.Plan {
        ServerReconciliation.plan(
            cached: cachedMessages,
            server: state,
            keepUIDsAbove: ServerReconciliation.highestUID(in: state)
        )
    }

    // MARK: - Nichts zu tun

    @Test func identicalStateChangesNothing() {
        let result = plan(
            [cached(1, unread: true), cached(2, flagged: true)],
            server(all: [1, 2], unseen: [1], flagged: [2])
        )
        #expect(result.isEmpty)
    }

    @Test func newServerMessagesAreNotPartOfThePlan() {
        // UID 3 ist noch nicht gecacht – darum kümmert sich der Abruf.
        let result = plan([cached(1)], server(all: [1, 2, 3]))
        #expect(result.isEmpty)
    }

    // MARK: - Entfernte Mails

    @Test func messagesGoneFromServerAreRemoved() {
        let result = plan(
            [cached(1), cached(2), cached(3)],
            server(all: [1, 3])
        )
        #expect(result.removedIDs == ["msg-2"])
    }

    @Test func flaggedMessageDeletedElsewhereIsAlsoRemoved() {
        let result = plan([cached(7, flagged: true)], server(all: [8]))
        #expect(result.removedIDs == ["msg-7"])
        #expect(result.flagUpdates.isEmpty)
    }

    @Test func emptiedFolderClearsTheCache() {
        let result = plan([cached(1), cached(2)], server(all: []))
        #expect(result.removedIDs == ["msg-1", "msg-2"])
    }

    /// Mails, die nach der Server-Abfrage eintreffen und schon gecacht
    /// sind, dürfen nicht als gelöscht gelten.
    @Test func newerUIDsThanTheServerAnswerAreKept() {
        let state = server(all: [1, 2])
        let result = ServerReconciliation.plan(
            cached: [cached(1), cached(2), cached(99)],
            server: state,
            keepUIDsAbove: ServerReconciliation.highestUID(in: state)
        )
        #expect(result.removedIDs.isEmpty)
    }

    @Test func highestUIDIsMaxForEmptyFolder() {
        #expect(ServerReconciliation.highestUID(in: server(all: [])) == .max)
        #expect(ServerReconciliation.highestUID(in: server(all: [4, 9, 2])) == 9)
    }

    // MARK: - Flags

    @Test func readElsewhereBecomesRead() {
        let result = plan([cached(1, unread: true)], server(all: [1]))
        #expect(result.flagUpdates.count == 1)
        #expect(result.flagUpdates.first?.isUnread == false)
    }

    @Test func unreadAgainElsewhereBecomesUnread() {
        let result = plan([cached(1)], server(all: [1], unseen: [1]))
        #expect(result.flagUpdates.first?.isUnread == true)
    }

    @Test func flagRemovedElsewhereIsRemovedLocally() {
        let result = plan([cached(1, flagged: true)], server(all: [1]))
        #expect(result.flagUpdates.first?.isFlagged == false)
    }

    @Test func answeredAndForwardedAreTakenOver() {
        let result = plan(
            [cached(1)],
            server(all: [1], answered: [1], forwarded: [1])
        )
        let updated = result.flagUpdates.first
        #expect(updated?.isAnswered == true)
        #expect(updated?.isForwarded == true)
    }

    /// Meldet der Server kein `$Forwarded`, bleibt das Kennzeichen stehen.
    @Test func forwardedIsKeptWhenServerDoesNotSupportIt() {
        let result = plan(
            [cached(1, forwarded: true)],
            server(all: [1], forwarded: nil)
        )
        #expect(result.isEmpty)
    }

    @Test func severalChangesAtOnce() {
        let result = plan(
            [cached(1, unread: true), cached(2, flagged: true), cached(3)],
            server(all: [1, 3], unseen: [], flagged: [3])
        )
        #expect(result.removedIDs == ["msg-2"])
        #expect(result.flagUpdates.map(\.id) == ["msg-1", "msg-3"])
        #expect(result.flagUpdates.first?.isUnread == false)
        #expect(result.flagUpdates.last?.isFlagged == true)
    }
}
