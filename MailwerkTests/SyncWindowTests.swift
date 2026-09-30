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

    @Test func cleanupUsesStandardStartWithoutWindow() {
        let standard = date(2026, 8, 31, 12)
        #expect(SyncWindow.cleanupCutoff(standardStart: standard, windowStart: nil) == standard)
    }

    @Test func cleanupUsesEarlierWindowStart() {
        let standard = date(2026, 8, 31, 12)
        let window = date(2026, 7, 2)
        #expect(SyncWindow.cleanupCutoff(standardStart: standard, windowStart: window) == window)
    }

    @Test func cleanupNeverGoesBeyondStandard() {
        // Ein (veralteter) Fensterbeginn nach dem Standardbeginn darf
        // das Fenster nicht verkleinern.
        let standard = date(2026, 8, 31, 12)
        let window = date(2026, 9, 10)
        #expect(SyncWindow.cleanupCutoff(standardStart: standard, windowStart: window) == standard)
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

    @Test func resetRemovesWindowsAndOlderMailsOnlyThere() {
        let store = makeStore()
        let standard = date(2026, 8, 31, 12)
        // Posteingang mit nachgeladener alter Mail
        store.saveMessage(message(folder: "INBOX", uid: 1, date: date(2026, 9, 20)))
        store.saveMessage(message(folder: "INBOX", uid: 2, date: date(2026, 8, 10)))
        store.setWindowStart(date(2026, 8, 1), accountID: account, folder: "INBOX")
        // Ordner ohne erweitertes Fenster: bleibt unangetastet
        store.saveMessage(message(folder: "Archiv", uid: 3, date: date(2026, 8, 10)))

        store.resetWindows(standardStart: standard)

        #expect(store.windowStart(accountID: account, folder: "INBOX") == nil)
        #expect(store.folderMessages(accountID: account, folder: "INBOX").map(\.uid) == [1])
        #expect(store.folderMessages(accountID: account, folder: "Archiv").map(\.uid) == [3])
    }

    @Test func resetWithoutWindowsChangesNothing() {
        let store = makeStore()
        store.saveMessage(message(folder: "INBOX", uid: 1, date: date(2026, 8, 10)))
        store.resetWindows(standardStart: date(2026, 8, 31, 12))
        #expect(store.folderMessages(accountID: account, folder: "INBOX").count == 1)
    }
}
