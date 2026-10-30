//
//  FetchPlanningTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die reine Logik des Abrufs, die in v0.3.1b aus dem
//  MailFetchService herausgelöst wurde: Einordnung gegen den Cache
//  (FetchClassifier), Stand eines Ordners (ServerReconciliation.folderState),
//  Auswahl der Serversuche (ServerSearchPlan) und Cache-Einträge von
//  Anhängen (FetchedMessageMapping).
//

import Foundation
import SwiftMail
import Testing
@testable import Mailwerk

/// Tests für FetchClassifier, folderState, ServerSearchPlan und FetchedMessageMapping.
@MainActor
struct FetchPlanningTests {

    /// Testhilfe: Postfach der Cache-IDs.
    private let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Testhilfe: Cache-ID einer UID im Posteingang.
    private func id(_ uid: UInt32) -> String {
        CachedMessage.makeID(accountID: accountID, folder: "INBOX", uid: uid)
    }

    /// Testhilfe: gespeicherter Flag-Stand.
    private func cached(_ uid: UInt32, unread: Bool) -> CachedFlagState {
        CachedFlagState(id: id(uid), uid: uid, isUnread: unread, isFlagged: false, isAnswered: false, isForwarded: false)
    }

    /// Testhilfe: Listeneintrag mit Datum.
    private func hit(_ uid: UInt32, daysAgo: Double?) -> MessageListItem {
        MessageListItem(
            id: id(uid), accountID: accountID, folder: "INBOX", uid: uid,
            subject: "Betreff", from: "a@example.com", recipients: [],
            date: daysAgo.map { Date(timeIntervalSinceNow: -$0 * 86_400) },
            isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
            hasAttachments: false, sizeBytes: 0, spamVerdict: nil
        )
    }

    // MARK: - FetchClassifier

    /// Neu, Flags geändert, Kopfdaten nachtragen und ohne UID werden getrennt erkannt.
    @Test("Einordnung gegen den Cache")
    func classify() {
        let read = FlagState([.seen])
        let unread = FlagState([])
        let entries = [
            FetchClassifier.Entry(uid: 1, flags: read),     // bekannt, unverändert
            FetchClassifier.Entry(uid: 2, flags: read),     // bekannt, war ungelesen
            FetchClassifier.Entry(uid: 3, flags: unread),   // neu
            FetchClassifier.Entry(uid: nil, flags: read),   // ohne UID
            FetchClassifier.Entry(uid: 4, flags: read)      // bekannt, ohne Flag-Stand, Kopfdaten fehlen
        ]
        let cache = FetchClassifier.CacheSnapshot(
            messageIDs: [id(1), id(2), id(4)],
            flags: [id(1): cached(1, unread: false), id(2): cached(2, unread: true)],
            needsHeaders: [id(4)]
        )
        let result = FetchClassifier.classify(entries, cache: cache, accountID: accountID, folder: "INBOX")
        #expect(result.newMessages == [.init(index: 2, uid: 3, messageID: id(3))])
        #expect(result.flagUpdates.map(\.uid) == [2, 4])
        #expect(result.headerBackfills == [.init(index: 4, uid: 4, messageID: id(4))])
        #expect(result.skippedCount == 1)
    }

    // MARK: - ServerReconciliation.folderState

    /// Jede UID landet in `all` und je nach Flags in den passenden Mengen.
    @Test("Stand des Ordners aus den Flags")
    func folderState() {
        let state = ServerReconciliation.folderState(from: [
            (uid: 1, flags: FlagState([.seen])),
            (uid: 2, flags: FlagState([.flagged, .answered])),
            (uid: 3, flags: FlagState([.seen, .custom(FlagState.forwardedKeyword)]))
        ])
        #expect(state.all == [1, 2, 3])
        #expect(state.unseen == [2])
        #expect(state.flagged == [2])
        #expect(state.answered == [2])
        #expect(state.forwarded == [3])
    }

    // MARK: - ServerSearchPlan

    /// Ohne suchbare Eingabe und ohne Person gibt es keine Kriterien.
    @Test("Keine Kriterien ohne Eingabe")
    func noCriteria() {
        #expect(ServerSearchPlan.criteria(query: "ab", address: nil).isEmpty)
        #expect(ServerSearchPlan.criteria(query: "", address: "").isEmpty)
        #expect(ServerSearchPlan.criteria(query: "Rechnung", address: "a@example.com").count == 2)
    }

    /// Gecachte Treffer entfallen; die Grenze gilt für die übrigen.
    @Test("Treffer außerhalb des Caches bis zur Grenze")
    func candidates() {
        let selection = ServerSearchPlan.candidates([9, 8, 7, 6, 5], cached: [8, 6], limit: 2)
        #expect(selection.uids == [9, 7])
        #expect(selection.missingCount == 3)
    }

    /// Neueste zuerst, ohne Datum zuletzt; `hasMore` bei mehr Treffern als Grenze.
    @Test("Gezeigte Treffer: neueste zuerst, hasMore")
    func result() {
        let hits = [hit(1, daysAgo: 5), hit(2, daysAgo: nil), hit(3, daysAgo: 1)]
        let limited = ServerSearchPlan.result(hits: hits, missingCount: 3, limit: 2)
        #expect(limited.hits.map(\.uid) == [3, 1])
        #expect(limited.hasMore)
        let all = ServerSearchPlan.result(hits: hits, missingCount: 3, limit: 3)
        #expect(all.hits.map(\.uid) == [3, 1, 2])
        #expect(!all.hasMore)
    }

    // MARK: - FetchedMessageMapping

    /// Ersatznamen, Größe aus Daten bzw. Struktur und Content-ID je Art.
    @Test("Cache-Eintrag eines Anhangs bzw. Bildes")
    func attachmentMapping() {
        let attachment = FetchedMessageMapping.attachment(
            for: MessageContentPlan.part(section: "2", contentType: "application/pdf", size: 500),
            data: nil, isInline: false, messageID: "m"
        )
        #expect(attachment.filename == FetchedMessageMapping.unnamedAttachment)
        #expect(attachment.sizeBytes == 500)
        #expect(attachment.contentID == nil)
        #expect(attachment.id == "m-2")

        let image = FetchedMessageMapping.attachment(
            for: MessageContentPlan.part(section: "1.2", contentType: "image/png", contentId: "<logo@x>"),
            data: Data([1, 2, 3]), isInline: true, messageID: "m"
        )
        #expect(image.filename == FetchedMessageMapping.unnamedInlineImage)
        #expect(image.sizeBytes == 3)
        #expect(image.contentID == "logo@x")
        #expect(image.isInline)
    }
}
