//
//  MessageStoreSpamVerdictTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Spam-Angabe im MessageStore – Speichern und Lesen,
//  Unterschied zwischen „unbekannt“ und „kein Spam“, Nachfüllen über die
//  Header-Version und Migration auf Schema-Stufe 4.
//
//  Jeder Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreSpamVerdictTests {

    private static let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
    }

    /// Testhilfe: Nachricht im Posteingang mit wählbarer Spam-Angabe.
    private func message(uid: UInt32, verdict: SpamHeaderVerdict?) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: Self.account, folder: "INBOX", uid: uid),
            accountID: Self.account, accountDisplayName: "Test", folder: "INBOX", uid: uid,
            subject: "Betreff", from: "anna@example.org", to: "kim@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isUnread: true, isFlagged: false, isAnswered: false, isForwarded: false,
            totalSizeBytes: 100, hasAttachments: false, textBody: "Text", htmlBody: nil,
            fetchedAt: Date(), headers: CachedMessageHeaders(spamVerdict: verdict)
        )
    }

    /// Spam-Kennzeichen und Score kommen unverändert zurück.
    @Test func storesSpamVerdict() throws {
        let store = MessageStore(path: temporaryPath())
        let saved = message(uid: 1, verdict: SpamHeaderVerdict(isSpam: true, score: 7.5))
        store.saveMessage(saved)

        let loaded = try #require(store.message(id: saved.id))
        #expect(loaded.headers.spamVerdict == SpamHeaderVerdict(isSpam: true, score: 7.5))
    }

    /// „Unbekannt“ bleibt unbekannt, „kein Spam ohne Score“ bleibt eine bekannte Angabe.
    @Test func distinguishesUnknownFromClean() throws {
        let store = MessageStore(path: temporaryPath())
        let unknown = message(uid: 1, verdict: nil)
        let clean = message(uid: 2, verdict: .clean)
        store.saveMessage(unknown)
        store.saveMessage(clean)

        #expect(try #require(store.message(id: unknown.id)).headers.spamVerdict == nil)
        #expect(try #require(store.message(id: clean.id)).headers.spamVerdict == .clean)
    }

    /// Nachfüllen schreibt die Spam-Angabe und gilt danach als aktuell.
    @Test func updateHeadersWritesVerdict() throws {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        let saved = message(uid: 1, verdict: nil)
        store.saveMessage(saved)
        try setHeadersVersion(0, at: path)
        #expect(store.messageIDsNeedingHeaders(forAccount: Self.account, folder: "INBOX") == [saved.id])

        store.updateHeaders(
            messageID: saved.id,
            headers: CachedMessageHeaders(spamVerdict: SpamHeaderVerdict(isSpam: false, score: 1.2))
        )

        #expect(try #require(store.message(id: saved.id)).headers.spamVerdict
                == SpamHeaderVerdict(isSpam: false, score: 1.2))
        #expect(store.messageIDsNeedingHeaders(forAccount: Self.account, folder: "INBOX").isEmpty)
    }

    /// Eine Datenbank der Stufe 3 erhält die Spalten; Bestand gilt als unbekannt.
    @Test func migratesVersion3Database() throws {
        let path = temporaryPath()
        let saved = message(uid: 1, verdict: .clean)
        do {
            let store = MessageStore(path: path)
            store.saveMessage(saved)
        }
        try downgradeToVersion3(at: path)

        let store = MessageStore(path: path)

        let loaded = try #require(store.message(id: saved.id))
        #expect(loaded.subject == "Betreff")
        #expect(loaded.headers.spamVerdict == nil)
    }

    /// Testhilfe: setzt die Header-Version aller Nachrichten direkt in der Datei.
    private func setHeadersVersion(_ version: Int, at path: String) throws {
        try exec(["UPDATE message SET headersVersion = \(version)"], at: path)
    }

    /// Testhilfe: versetzt eine Datenbank in den Zustand von Schema-Stufe 3
    /// (ohne Spalten `spamFlag` und `spamScore`, user_version = 3).
    private func downgradeToVersion3(at path: String) throws {
        try exec([
            "ALTER TABLE message DROP COLUMN spamFlag",
            "ALTER TABLE message DROP COLUMN spamScore",
            "PRAGMA user_version = 3"
        ], at: path)
    }

    /// Testhilfe: führt SQL-Befehle direkt auf der Datei aus.
    private func exec(_ statements: [String], at path: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in statements {
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)")
        }
    }
}
