//
//  ServerReconciliationTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Vergleich von Cache und Server-Stand. Prüft
//  Entfernungen, Flag-Änderungen und das Erkennen fehlender Mails.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct ServerReconciliationTests {

    // MARK: - Hilfen

    /// Erzeugt einen gecachten Flag-Zustand mit frei wählbaren Flags.
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

    /// Erzeugt einen Server-Ordner-Stand mit frei wählbaren UID-Mengen.
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

    /// Berechnet den Abgleichsplan mit Standard-keepUIDsAbove.
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

    /// Cache und Server identisch → keine Änderungen.
    @Test func identicalStateChangesNothing() {
        let result = plan(
            [cached(1, unread: true), cached(2, flagged: true)],
            server(all: [1, 2], unseen: [1], flagged: [2])
        )
        #expect(result.isEmpty)
    }

    // MARK: - Entfernte Mails

    /// Mail nur noch auf dem Server → wird aus dem Cache entfernt.
    @Test func messagesGoneFromServerAreRemoved() {
        let result = plan(
            [cached(1), cached(2), cached(3)],
            server(all: [1, 3])
        )
        #expect(result.removedIDs == ["msg-2"])
    }

    /// Gekennzeichnete Mail, anderswo gelöscht → wird trotzdem entfernt.
    @Test func flaggedMessageDeletedElsewhereIsAlsoRemoved() {
        let result = plan([cached(7, flagged: true)], server(all: [8]))
        #expect(result.removedIDs == ["msg-7"])
        #expect(result.flagUpdates.isEmpty)
    }

    /// Leerer Ordner auf dem Server → Cache komplett leeren.
    @Test func emptiedFolderClearsTheCache() {
        let result = plan([cached(1), cached(2)], server(all: []))
        #expect(result.removedIDs == ["msg-1", "msg-2"])
    }

    /// Mails mit UIDs oberhalb der Server-Antwort bleiben erhalten.
    @Test func newerUIDsThanTheServerAnswerAreKept() {
        let state = server(all: [1, 2])
        let result = ServerReconciliation.plan(
            cached: [cached(1), cached(2), cached(99)],
            server: state,
            keepUIDsAbove: ServerReconciliation.highestUID(in: state)
        )
        #expect(result.removedIDs.isEmpty)
    }

    /// highestUID: Maximum der Menge, bei leerem Ordner .max.
    @Test func highestUIDIsMaxForEmptyFolder() {
        #expect(ServerReconciliation.highestUID(in: server(all: [])) == .max)
        #expect(ServerReconciliation.highestUID(in: server(all: [4, 9, 2])) == 9)
    }

    // MARK: - Flags

    /// Im Webmail gelesen → wird auch lokal als gelesen markiert.
    @Test func readElsewhereBecomesRead() {
        let result = plan([cached(1, unread: true)], server(all: [1]))
        #expect(result.flagUpdates.count == 1)
        #expect(result.flagUpdates.first?.isUnread == false)
    }

    /// Im Webmail als ungelesen markiert → wird auch lokal ungelesen.
    @Test func unreadAgainElsewhereBecomesUnread() {
        let result = plan([cached(1)], server(all: [1], unseen: [1]))
        #expect(result.flagUpdates.first?.isUnread == true)
    }

    /// Kennzeichnung im Webmail entfernt → wird auch lokal entfernt.
    @Test func flagRemovedElsewhereIsRemovedLocally() {
        let result = plan([cached(1, flagged: true)], server(all: [1]))
        #expect(result.flagUpdates.first?.isFlagged == false)
    }

    /// Beantwortet und Weitergeleitet werden übernommen.
    @Test func answeredAndForwardedAreTakenOver() {
        let result = plan(
            [cached(1)],
            server(all: [1], answered: [1], forwarded: [1])
        )
        let updated = result.flagUpdates.first
        #expect(updated?.isAnswered == true)
        #expect(updated?.isForwarded == true)
    }

    /// Server meldet kein $Forwarded → bestehendes Kennzeichen bleibt.
    @Test func forwardedIsKeptWhenServerDoesNotSupportIt() {
        let result = plan(
            [cached(1, forwarded: true)],
            server(all: [1], forwarded: nil)
        )
        #expect(result.isEmpty)
    }

    /// Mehrere Änderungen gleichzeitig: Entfernung, Flag-Updates und fehlende UIDs.
    @Test func severalChangesAtOnce() {
        let result = plan(
            [cached(1, unread: true), cached(2, flagged: true), cached(3)],
            server(all: [1, 3, 5], unseen: [], flagged: [3])
        )
        #expect(result.removedIDs == ["msg-2"])
        #expect(result.flagUpdates.map(\.id) == ["msg-1", "msg-3"])
        #expect(result.flagUpdates.first?.isUnread == false)
        #expect(result.flagUpdates.last?.isFlagged == true)
        #expect(result.missingUIDs == [5])
    }

    // MARK: - Fehlende Mails (a1b)

    /// Server hat Mails, die nicht im Cache liegen → missingUIDs.
    @Test func missingUIDsAreDetected() {
        let result = plan(
            [cached(1), cached(3)],
            server(all: [1, 2, 3, 5])
        )
        #expect(result.removedIDs.isEmpty)
        #expect(result.flagUpdates.isEmpty)
        #expect(result.missingUIDs == [2, 5])
    }

    /// Leerer Cache bei gefülltem Ordner → alle UIDs fehlen.
    @Test func emptyCache_allUIDs_areMissing() {
        let result = plan([], server(all: [10, 20, 30]))
        #expect(result.missingUIDs == [10, 20, 30])
    }

    /// Cache und Server deckungsgleich → keine fehlenden UIDs.
    @Test func fullyCachedFolder_noMissing() {
        let result = plan(
            [cached(1), cached(2), cached(3)],
            server(all: [1, 2, 3])
        )
        #expect(result.missingUIDs.isEmpty)
        #expect(result.isEmpty)
    }

    /// UIDs oberhalb von keepUIDsAbove erscheinen nicht als fehlend
    /// (sie wurden möglicherweise gerade erst vom regulären Abruf gecacht).
    @Test func missingUIDs_aboveKeepThreshold_areExcluded() {
        let state = server(all: [1, 2, 5])
        // keepUIDsAbove = 5 (höchste UID im Server)
        // UID 99 ist nicht in server.all, daher irrelevant
        let result = ServerReconciliation.plan(
            cached: [cached(1)],
            server: state,
            keepUIDsAbove: 3   // Grenze bewusst niedriger
        )
        // UID 2 ≤ 3 → fehlt; UID 5 > 3 → wird nicht gemeldet
        #expect(result.missingUIDs == [2])
    }

    /// Sortierung: missingUIDs kommen aufsteigend zurück.
    @Test func missingUIDs_areSortedAscending() {
        let result = plan(
            [cached(5)],
            server(all: [1, 3, 5, 7, 9])
        )
        #expect(result.missingUIDs == [1, 3, 7, 9])
    }
}
