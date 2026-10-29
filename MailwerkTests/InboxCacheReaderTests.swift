//
//  InboxCacheReaderTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Momentaufnahme der Mailliste (InboxCacheReader,
//  v0.2.3b): Einträge je Quelle, Abrufzeitpunkte, Zähler und Fensterbeginn.
//
//  Jeder Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für `InboxCacheReader`.
@MainActor
struct InboxCacheReaderTests {

    private static let accountA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let accountB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
    }

    /// Testhilfe: Nachricht mit wählbarem Postfach, Ordner und Flags.
    private func message(
        account: UUID, folder: String = "INBOX", uid: UInt32,
        unread: Bool = false, flagged: Bool = false
    ) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: account, folder: folder, uid: uid),
            accountID: account, accountDisplayName: "Test", folder: folder, uid: uid,
            subject: "Betreff \(uid)", from: "anna@example.org", to: "max@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(uid)),
            isUnread: unread, isFlagged: flagged, isAnswered: false, isForwarded: false,
            totalSizeBytes: 100, hasAttachments: false, textBody: "Text", htmlBody: nil,
            fetchedAt: Date(), headers: CachedMessageHeaders()
        )
    }

    /// Testhilfe: Ablage mit Mails in zwei Postfächern und einem Archiv-Ordner.
    private func filledStore() -> MessageStore {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(account: Self.accountA, uid: 1, unread: true))
        store.saveMessage(message(account: Self.accountA, uid: 2, flagged: true))
        store.saveMessage(message(account: Self.accountB, uid: 3, unread: true, flagged: true))
        store.saveMessage(message(account: Self.accountB, folder: "Archiv", uid: 4))
        return store
    }

    /// Alle Eingänge: Einträge beider Posteingänge, neueste zuerst, dazu Zähler.
    @Test("Alle Eingänge mit Zählern")
    func inboxesWithCounts() {
        let store = filledStore()
        let request = InboxCacheReader.Request(
            source: .inboxes([Self.accountA, Self.accountB]),
            syncFolders: [],
            countAccountIDs: [Self.accountA, Self.accountB],
            windowFolders: []
        )
        let snapshot = InboxCacheReader.readSync(request, store: store)
        #expect(snapshot.items.map(\.uid) == [3, 2, 1])
        #expect(snapshot.unreadCount == 2)
        #expect(snapshot.flaggedCount == 2)
    }

    /// Ungelesen behält die übergebenen Mails, auch wenn sie gelesen sind.
    @Test("Ungelesen behält schon gezeigte Mails")
    func unreadKeepsShown() {
        let store = filledStore()
        let kept = CachedMessage.makeID(accountID: Self.accountA, folder: "INBOX", uid: 2)
        let request = InboxCacheReader.Request(
            source: .unread([Self.accountA, Self.accountB], keeping: [kept]),
            syncFolders: [], countAccountIDs: [], windowFolders: []
        )
        #expect(InboxCacheReader.readSync(request, store: store).items.map(\.uid) == [3, 2, 1])
    }

    /// Ein Ordner: nur seine Einträge; Abrufzeitpunkt und Fensterbeginn werden mitgelesen.
    @Test("Ordner mit Abrufzeitpunkt und Fensterbeginn")
    func folderWithSyncAndWindow() {
        let store = filledStore()
        let archive = FolderKey(accountID: Self.accountB, folder: "Archiv")
        let synced = Date(timeIntervalSince1970: 1_800_000_000)
        let window = Date(timeIntervalSince1970: 1_600_000_000)
        store.recordSync(accountID: Self.accountB, folder: "Archiv", at: synced)
        store.setWindowStart(window, accountID: Self.accountB, folder: "Archiv")

        let request = InboxCacheReader.Request(
            source: .folder(accountID: Self.accountB, path: "Archiv"),
            syncFolders: [archive, FolderKey(accountID: Self.accountA, folder: "INBOX")],
            countAccountIDs: [],
            windowFolders: [archive, FolderKey(accountID: Self.accountA, folder: "INBOX")]
        )
        let snapshot = InboxCacheReader.readSync(request, store: store)
        #expect(snapshot.items.map(\.uid) == [4])
        #expect(snapshot.syncDates == [synced, nil])
        #expect(snapshot.windowStarts == [archive: window])
    }

    /// Die asynchrone Variante liefert dasselbe wie die synchrone.
    @Test("read liefert dasselbe wie readSync")
    func asyncMatchesSync() async {
        let store = filledStore()
        let request = InboxCacheReader.Request(
            source: .flagged([Self.accountA, Self.accountB]),
            syncFolders: [], countAccountIDs: [Self.accountA], windowFolders: []
        )
        let snapshot = await InboxCacheReader.read(request, store: store)
        #expect(snapshot.items.map(\.uid) == [3, 2])
        #expect(snapshot.unreadCount == 1)
        #expect(snapshot.flaggedCount == 1)
    }
}
