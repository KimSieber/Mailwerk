//
//  MessageStoreListTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Listenabfragen des MessageStore – Listeneinträge
//  ohne Mailinhalt, Vorschau aus dem Textteil, Sortierung, Migration auf
//  Schema-Stufe 3 (Vorschau nachgetragen, Index angelegt).
//
//  Jeder Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreListTests {

    private static let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
    }

    /// Testhilfe: Nachricht mit wählbarem Text, Datum und Kennzeichen.
    private func message(
        uid: UInt32,
        folder: String = "INBOX",
        text: String? = "Text",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        flagged: Bool = false
    ) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: Self.account, folder: folder, uid: uid),
            accountID: Self.account, accountDisplayName: "Test", folder: folder, uid: uid,
            subject: "Betreff \(uid)", from: "anna@example.org", to: "kim@example.org",
            date: date,
            isUnread: true, isFlagged: flagged, isAnswered: false, isForwarded: true,
            totalSizeBytes: 100, hasAttachments: true, textBody: text, htmlBody: "<p>HTML</p>",
            fetchedAt: Date(), headers: CachedMessageHeaders()
        )
    }

    /// Der Listeneintrag übernimmt alle Felder der Zeile.
    @Test func listItemCarriesRowFields() throws {
        let store = MessageStore(path: temporaryPath())
        let saved = message(uid: 7)
        store.saveMessage(saved)

        let item = try #require(store.folderMessages(accountID: Self.account, folder: "INBOX").first)
        #expect(item.id == saved.id)
        #expect(item.accountID == Self.account)
        #expect(item.folder == "INBOX")
        #expect(item.uid == 7)
        #expect(item.subject == "Betreff 7")
        #expect(item.from == "anna@example.org")
        #expect(item.date == saved.date)
        #expect(item.isUnread && !item.isFlagged && !item.isAnswered && item.isForwarded)
        #expect(item.hasAttachments)
        #expect(item.preview == "Text")
    }

    /// Die Vorschau besteht aus den ersten 200 Zeichen des Textteils (Zeichen, nicht Bytes).
    @Test func previewIsFirst200Characters() throws {
        let store = MessageStore(path: temporaryPath())
        let long = String(repeating: "ä", count: 250)
        store.saveMessage(message(uid: 1, text: long))

        let item = try #require(store.folderMessages(accountID: Self.account, folder: "INBOX").first)
        #expect(item.preview == String(repeating: "ä", count: MessageStore.previewLength))
    }

    /// Ohne Textteil gibt es keine Vorschau.
    @Test func noTextMeansNoPreview() throws {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(uid: 1, text: nil))
        let item = try #require(store.folderMessages(accountID: Self.account, folder: "INBOX").first)
        #expect(item.preview == nil)
    }

    /// Wird eine Mail erneut gespeichert, wird auch die Vorschau aktualisiert.
    @Test func resavingUpdatesPreview() throws {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(uid: 1, text: "alt"))
        store.saveMessage(message(uid: 1, text: "neu"))
        let item = try #require(store.folderMessages(accountID: Self.account, folder: "INBOX").first)
        #expect(item.preview == "neu")
    }

    /// Alle drei Listenabfragen liefern absteigend nach Datum.
    @Test func listsAreSortedNewestFirst() {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(uid: 1, date: Date(timeIntervalSince1970: 1_000), flagged: true))
        store.saveMessage(message(uid: 2, date: Date(timeIntervalSince1970: 3_000), flagged: true))
        store.saveMessage(message(uid: 3, date: Date(timeIntervalSince1970: 2_000), flagged: true))

        #expect(store.folderMessages(accountID: Self.account, folder: "INBOX").map(\.uid) == [2, 3, 1])
        #expect(store.allMessages(accountIDs: [Self.account], folder: "INBOX").map(\.uid) == [2, 3, 1])
        #expect(store.flaggedInboxMessages(accountIDs: [Self.account]).map(\.uid) == [2, 3, 1])
    }

    /// Die vollständige Mail ist weiterhin über message(id:) mit Text und HTML erreichbar.
    @Test func fullMessageStillHasBodies() throws {
        let store = MessageStore(path: temporaryPath())
        let saved = message(uid: 1, text: "Volltext")
        store.saveMessage(saved)
        let full = try #require(store.message(id: saved.id))
        #expect(full.textBody == "Volltext")
        #expect(full.htmlBody == "<p>HTML</p>")
    }

    /// Migration 2 → 3: Vorschau wird für vorhandene Mails nachgetragen, Index angelegt, alter Index entfernt.
    @Test func migrationToVersion3FillsPreviewAndCreatesIndex() throws {
        let path = temporaryPath()
        do {
            let store = MessageStore(path: path)
            store.saveMessage(message(uid: 1, text: "Bestand"))
            store.saveMessage(message(uid: 2, text: nil))
        }
        try downgradeToVersion2(at: path)

        let store = MessageStore(path: path)

        let items = store.folderMessages(accountID: Self.account, folder: "INBOX")
        #expect(items.first { $0.uid == 1 }?.preview == "Bestand")
        #expect(items.first { $0.uid == 2 }?.preview == nil)
        #expect(sqlite(at: path, "SELECT count(*) FROM sqlite_master WHERE name = 'idx_message_account_folder_date'") == "1")
        #expect(sqlite(at: path, "SELECT count(*) FROM sqlite_master WHERE name = 'idx_message_account_folder'") == "0")
        #expect(sqlite(at: path, "PRAGMA user_version") == "3")
    }

    /// Testhilfe: versetzt eine Datenbank in den Zustand von Schema-Stufe 2
    /// (ohne Spalte `preview`, alter Index, user_version = 2).
    private func downgradeToVersion2(at path: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in [
            "DROP INDEX IF EXISTS idx_message_account_folder_date",
            "ALTER TABLE message DROP COLUMN preview",
            "CREATE INDEX IF NOT EXISTS idx_message_account_folder ON message(accountID, folder)",
            "PRAGMA user_version = 2"
        ] {
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)")
        }
    }

    /// Testhilfe: liest den ersten Wert einer Abfrage direkt aus der Datei.
    private func sqlite(at path: String, _ sql: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }
}
