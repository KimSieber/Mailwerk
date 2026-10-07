//
//  MessageStoreSyncTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den gespeicherten Stand je Ordner (Tabelle
//  folder_sync): Zeitpunkt des letzten Abrufs und Sync-Zustand
//  (UIDVALIDITY, UIDNEXT) inklusive Migration auf Schema-Stufe 2.
//
//  Jeder Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreSyncTests {

    private let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private let other = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3302")!

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
    }

    /// Testhilfe: neue Ablage auf eigener Datei.
    private func makeStore() -> MessageStore {
        MessageStore(path: temporaryPath())
    }

    /// Testhilfe: gecachte Nachricht mit wählbarem Ordner und UID.
    private func message(folder: String, uid: UInt32) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: account, folder: folder, uid: uid),
            accountID: account, accountDisplayName: "Test", folder: folder, uid: uid,
            subject: "Betreff", from: "anna@example.org", to: "kim@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
            totalSizeBytes: 100, hasAttachments: false, textBody: "Text", htmlBody: nil,
            fetchedAt: Date(), headers: CachedMessageHeaders()
        )
    }

    // MARK: - Zeitpunkt des letzten Abrufs

    /// Ein nie abgerufener Ordner hat keinen Zeitstempel.
    @Test func neverFetchedFolderHasNoStamp() {
        let store = makeStore()
        #expect(store.lastSync(accountID: account, folder: "INBOX") == nil)
    }

    /// Ein gespeicherter Abruf wird zurückgeliefert.
    @Test func recordedSyncIsReturned() {
        let store = makeStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordSync(accountID: account, folder: "INBOX", at: date)
        #expect(store.lastSync(accountID: account, folder: "INBOX") == date)
    }

    /// Ein späterer Abruf ersetzt den früheren.
    @Test func laterSyncReplacesEarlier() {
        let store = makeStore()
        store.recordSync(accountID: account, folder: "INBOX", at: Date(timeIntervalSince1970: 1_000))
        store.recordSync(accountID: account, folder: "INBOX", at: Date(timeIntervalSince1970: 2_000))
        #expect(store.lastSync(accountID: account, folder: "INBOX") == Date(timeIntervalSince1970: 2_000))
    }

    /// Stände sind je Ordner und Postfach getrennt.
    @Test func stampsAreSeparatePerFolderAndAccount() {
        let store = makeStore()
        store.recordSync(accountID: account, folder: "INBOX", at: Date(timeIntervalSince1970: 1_000))
        #expect(store.lastSync(accountID: account, folder: "INBOX.Trash") == nil)
        #expect(store.lastSync(accountID: other, folder: "INBOX") == nil)
    }

    /// Der Stand übersteht ein erneutes Öffnen der Ablage.
    @Test func stampSurvivesReopeningTheStore() {
        let path = temporaryPath()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        MessageStore(path: path).recordSync(accountID: account, folder: "INBOX", at: date)
        #expect(MessageStore(path: path).lastSync(accountID: account, folder: "INBOX") == date)
    }

    // MARK: - Sync-Zustand

    /// Ohne gespeicherten Zustand liefert die Ablage nil, auch nach einem Abruf ohne Zustand.
    @Test func noStateUntilOneIsRecorded() {
        let store = makeStore()
        #expect(store.syncState(accountID: account, folder: "INBOX") == nil)
        store.recordSync(accountID: account, folder: "INBOX")
        #expect(store.syncState(accountID: account, folder: "INBOX") == nil)
    }

    /// Ein gespeicherter Zustand wird zurückgeliefert und übersteht erneutes Öffnen.
    @Test func recordedStateIsReturned() {
        let path = temporaryPath()
        let state = FolderSyncState(uidValidity: 1_234, uidNext: 8_801)
        MessageStore(path: path).recordSync(accountID: account, folder: "INBOX", state: state)
        #expect(MessageStore(path: path).syncState(accountID: account, folder: "INBOX") == state)
    }

    /// Ein Abruf ohne Zustand lässt den gespeicherten Zustand stehen.
    @Test func recordWithoutStateKeepsExistingState() {
        let store = makeStore()
        let state = FolderSyncState(uidValidity: 1, uidNext: 50)
        store.recordSync(accountID: account, folder: "INBOX", state: state)
        store.recordSync(accountID: account, folder: "INBOX")
        #expect(store.syncState(accountID: account, folder: "INBOX") == state)
    }

    /// Ein neuer Zustand ersetzt den alten.
    @Test func newerStateReplacesOlder() {
        let store = makeStore()
        store.recordSync(accountID: account, folder: "INBOX", state: FolderSyncState(uidValidity: 1, uidNext: 50))
        store.recordSync(accountID: account, folder: "INBOX", state: FolderSyncState(uidValidity: 1, uidNext: 60))
        #expect(store.syncState(accountID: account, folder: "INBOX")?.uidNext == 60)
    }

    /// Ordner verwerfen (z. B. bei geänderter UIDVALIDITY) entfernt auch den Zustand – nur für diesen Ordner.
    @Test func deleteFolderRemovesStateOfThatFolderOnly() {
        let store = makeStore()
        store.recordSync(accountID: account, folder: "INBOX", state: FolderSyncState(uidValidity: 1, uidNext: 50))
        store.recordSync(accountID: account, folder: "Junk", state: FolderSyncState(uidValidity: 2, uidNext: 9))
        store.deleteFolder(accountID: account, folder: "INBOX")
        #expect(store.syncState(accountID: account, folder: "INBOX") == nil)
        #expect(store.syncState(accountID: account, folder: "Junk") != nil)
    }

    /// cachedUIDs liefert die UIDs genau eines Ordners.
    @Test func cachedUIDsAreFolderSpecific() {
        let store = makeStore()
        store.saveMessage(message(folder: "INBOX", uid: 7))
        store.saveMessage(message(folder: "INBOX", uid: 9))
        store.saveMessage(message(folder: "Junk", uid: 7))
        #expect(store.cachedUIDs(accountID: account, folder: "INBOX") == [7, 9])
        #expect(store.cachedUIDs(accountID: account, folder: "Junk") == [7])
    }

    // MARK: - Migration auf Stufe 2

    /// Eine Datenbank der Stufe 1 erhält die neuen Spalten (und durchläuft alle späteren Stufen); bestehende Stände haben noch keinen Zustand.
    @Test func migratesVersion1Database() throws {
        let path = temporaryPath()
        try createVersion1Database(at: path)

        let store = MessageStore(path: path)

        #expect(store.lastSync(accountID: account, folder: "INBOX") == Date(timeIntervalSince1970: 1_000))
        #expect(store.syncState(accountID: account, folder: "INBOX") == nil)
        let state = FolderSyncState(uidValidity: 3, uidNext: 4)
        store.recordSync(accountID: account, folder: "INBOX", state: state)
        #expect(store.syncState(accountID: account, folder: "INBOX") == state)
        #expect(userVersion(at: path) == 3)
    }

    /// Testhilfe: legt eine Datenbank im Zustand der Schema-Stufe 1 an
    /// (folder_sync ohne Zustandsspalten, user_version = 1).
    private func createVersion1Database(at path: String) throws {
        // Erst eine vollständige Ablage anlegen, dann folder_sync auf den
        // Stand von Stufe 1 zurückbauen.
        _ = MessageStore(path: path)
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let statements = [
            "DROP TABLE folder_sync",
            """
            CREATE TABLE folder_sync (
                accountID TEXT NOT NULL, folder TEXT NOT NULL, lastSyncAt REAL NOT NULL,
                PRIMARY KEY (accountID, folder)
            )
            """,
            "INSERT INTO folder_sync VALUES ('\(account.uuidString)', 'INBOX', 1000.0)",
            "PRAGMA user_version = 1"
        ]
        for sql in statements {
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)")
        }
    }

    /// Testhilfe: liest `PRAGMA user_version` direkt aus der Datei.
    private func userVersion(at path: String) -> Int32 {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int(stmt, 0) : -1
    }
}
