//
//  SyncWindowTests.swift
//  MailwerkTests
//
//  Tests für das Zeitfenster des Caches („Ältere Nachrichten laden"):
//  Datumslogik und die Ablage des Fensterbeginns in der Datenbank.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SyncWindowTests {

    private let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: - Datumslogik

    @Test func standardStartIsThirtyDaysBack() {
        let start = SyncWindow.standardStart(now: date(2026, 9, 30, 12), days: 30, calendar: calendar)
        #expect(start == date(2026, 8, 31, 12))
    }

    @Test func nextBlockEndsAtStartAndBeginsAtStartOfDay() {
        let block = SyncWindow.nextBlock(before: date(2026, 8, 31, 12), days: 30, calendar: calendar)
        #expect(block.before == date(2026, 8, 31, 12))
        #expect(block.since == date(2026, 8, 1))
    }

    @Test func consecutiveBlocksLeaveNoGap() {
        let first = SyncWindow.nextBlock(before: date(2026, 8, 31, 12), days: 30, calendar: calendar)
        let second = SyncWindow.nextBlock(before: first.since, days: 30, calendar: calendar)
        #expect(second.before == first.since)
        #expect(second.since < second.before)
    }

    // MARK: - Ablage

    private func makeStore() -> MessageStore {
        MessageStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path)
    }

    private func message(folder: String, uid: UInt32, date: Date) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: account, folder: folder, uid: uid),
            accountID: account,
            accountDisplayName: "Test",
            folder: folder,
            uid: uid,
            subject: "Betreff",
            from: "anna@example.org",
            to: "kim@example.org",
            date: date,
            isUnread: false,
            isFlagged: false,
            isAnswered: false,
            isForwarded: false,
            totalSizeBytes: 1_024,
            hasAttachments: false,
            textBody: "Text",
            htmlBody: nil,
            fetchedAt: Date(),
            headers: CachedMessageHeaders()
        )
    }

    @Test func noWindowByDefault() {
        #expect(makeStore().windowStart(accountID: account, folder: "INBOX") == nil)
    }

    @Test func windowStartIsStoredAndReplaced() {
        let store = makeStore()
        store.setWindowStart(date(2026, 8, 1), accountID: account, folder: "INBOX")
        store.setWindowStart(date(2026, 7, 2), accountID: account, folder: "INBOX")
        #expect(store.windowStart(accountID: account, folder: "INBOX") == date(2026, 7, 2))
        #expect(store.windowStart(accountID: account, folder: "INBOX.Trash") == nil)
    }

    /// v0.1.8b: Fensterbeginn und nachgeladene Mails überstehen einen
    /// Neustart (neu geöffnete Ablage auf derselben Datei).
    @Test func windowAndOlderMailsSurviveRestart() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
        do {
            let store = MessageStore(path: path)
            store.saveMessage(message(folder: "INBOX", uid: 1, date: date(2026, 9, 20)))
            store.saveMessage(message(folder: "INBOX", uid: 2, date: date(2025, 3, 10)))
            store.setWindowStart(date(2025, 3, 1), accountID: account, folder: "INBOX")
        }
        let reopened = MessageStore(path: path)
        #expect(reopened.windowStart(accountID: account, folder: "INBOX") == date(2025, 3, 1))
        #expect(reopened.folderMessages(accountID: account, folder: "INBOX").map(\.uid) == [1, 2])
    }
}
