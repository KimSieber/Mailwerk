//
//  MessageStoreFolderTests.swift
//  Mailwerk
//
//  Created by Kim Sieber on 24.09.26.
//


//
//  MessageStoreFolderTests.swift
//  MailwerkTests
//
//  Tests für die ordnerfähige Ablage: Trennung gleicher UIDs in
//  verschiedenen Ordnern, Umzug einer Nachricht und die einmalige
//  Migration der Kennungen von v0.1.4 auf v0.1.5.
//
//  Jeder Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis,
//  damit die Ablage der App unberührt bleibt.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreFolderTests {

    // MARK: - Hilfen

    private static let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite")
            .path
    }

    private func message(
        folder: String,
        uid: UInt32,
        subject: String = "Betreff",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: Self.account, folder: folder, uid: uid),
            accountID: Self.account,
            accountDisplayName: "Test",
            folder: folder,
            uid: uid,
            subject: subject,
            from: "anna@example.org",
            to: "kim@example.org",
            date: date,
            isUnread: true,
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

    // MARK: - Kennung

    @Test("Die Kennung enthält Konto, Ordner und UID")
    func idContainsFolder() {
        let id = CachedMessage.makeID(accountID: Self.account, folder: "INBOX", uid: 42)
        #expect(id == "\(Self.account.uuidString)-INBOX-42")
    }

    @Test("Ordner mit Bindestrich oder Pfadtrenner ergeben eigene Kennungen")
    func idStaysUniqueForUnusualFolders() {
        let a = CachedMessage.makeID(accountID: Self.account, folder: "Junk-E-Mail", uid: 1)
        let b = CachedMessage.makeID(accountID: Self.account, folder: "INBOX/Junk", uid: 1)
        #expect(a != b)
    }

    // MARK: - Trennung der Ordner

    @Test("Gleiche UID in zwei Ordnern sind zwei Nachrichten")
    func sameUIDInTwoFolders() {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(folder: "INBOX", uid: 7, subject: "Aus dem Posteingang"))
        store.saveMessage(message(folder: "Junk", uid: 7, subject: "Aus dem Spam"))

        let inbox = store.allMessages(accountIDs: [Self.account], folder: "INBOX")
        let junk = store.allMessages(accountIDs: [Self.account], folder: "Junk")

        #expect(inbox.map(\.subject) == ["Aus dem Posteingang"])
        #expect(junk.map(\.subject) == ["Aus dem Spam"])
        #expect(inbox.first?.folder == "INBOX")
    }

    @Test("Die bekannten Kennungen kommen je Ordner zurück")
    func cachedIDsPerFolder() {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(folder: "INBOX", uid: 1))
        store.saveMessage(message(folder: "INBOX", uid: 2))
        store.saveMessage(message(folder: "Junk", uid: 1))

        #expect(store.cachedMessageIDs(forAccount: Self.account, folder: "INBOX").count == 2)
        #expect(store.cachedMessageIDs(forAccount: Self.account, folder: "Junk").count == 1)
    }

    @Test("Die Bereinigung alter Mails trifft nur den angegebenen Ordner")
    func cleanupPerFolder() {
        let store = MessageStore(path: temporaryPath())
        let old = Date(timeIntervalSince1970: 1_000_000)
        store.saveMessage(message(folder: "INBOX", uid: 1, date: old))
        store.saveMessage(message(folder: "Junk", uid: 1, date: old))

        store.deleteMessagesOlderThan(
            Date(timeIntervalSince1970: 2_000_000), forAccount: Self.account, folder: "INBOX"
        )

        #expect(store.allMessages(accountIDs: [Self.account], folder: "INBOX").isEmpty)
        #expect(store.allMessages(accountIDs: [Self.account], folder: "Junk").count == 1)
    }

    // MARK: - Umzug

    @Test("Eine Nachricht zieht mitsamt Anhang in einen anderen Ordner um")
    func relocateMovesAttachments() throws {
        let store = MessageStore(path: temporaryPath())
        let original = message(folder: "INBOX", uid: 7)
        store.saveMessage(original)
        store.saveAttachment(CachedAttachment(
            id: "\(original.id)-1.2",
            messageID: original.id,
            filename: "Rechnung.pdf",
            contentType: "application/pdf",
            sizeBytes: 3,
            data: Data([1, 2, 3])
        ))

        let newID = try #require(
            store.relocateMessage(id: original.id, toFolder: "Junk", newUID: 99)
        )

        #expect(newID == CachedMessage.makeID(accountID: Self.account, folder: "Junk", uid: 99))
        #expect(store.message(id: original.id) == nil)

        let moved = try #require(store.message(id: newID))
        #expect(moved.folder == "Junk")
        #expect(moved.uid == 99)
        #expect(moved.subject == original.subject)

        let attachments = store.attachments(forMessage: newID)
        #expect(attachments.count == 1)
        #expect(attachments.first?.id == "\(newID)-1.2")
        #expect(attachments.first?.data == Data([1, 2, 3]))
        #expect(store.attachments(forMessage: original.id).isEmpty)
    }

    @Test("Eine unbekannte Kennung lässt die Ablage unverändert")
    func relocateUnknownMessage() {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(folder: "INBOX", uid: 1))
        #expect(store.relocateMessage(id: "gibt-es-nicht", toFolder: "Junk", newUID: 5) == nil)
        #expect(store.allMessages(accountIDs: [Self.account], folder: "INBOX").count == 1)
    }

    // MARK: - Migration von v0.1.4

    @Test("Bestandsdaten werden auf das Ordner-Schema umgeschrieben")
    func migratesOldDatabase() throws {
        let path = temporaryPath()
        let oldMessageID = "\(Self.account.uuidString)-4711"
        try createLegacyDatabase(at: path, messageID: oldMessageID)

        // Öffnen löst die Migration aus.
        let store = MessageStore(path: path)

        let expectedID = CachedMessage.makeID(
            accountID: Self.account, folder: "INBOX", uid: 4711
        )
        #expect(store.message(id: oldMessageID) == nil)

        let migrated = try #require(store.message(id: expectedID))
        #expect(migrated.folder == "INBOX")
        #expect(migrated.uid == 4711)
        #expect(migrated.subject == "Alter Bestand")

        let attachments = store.attachments(forMessage: expectedID)
        #expect(attachments.count == 1, "Der Anhang muss mitwandern statt verwaist zu bleiben")
        #expect(attachments.first?.id == "\(expectedID)-2")
        #expect(attachments.first?.filename == "Alt.pdf")
    }

    @Test("Eine zweite Öffnung ändert die Kennungen nicht erneut")
    func migrationRunsOnlyOnce() throws {
        let path = temporaryPath()
        try createLegacyDatabase(at: path, messageID: "\(Self.account.uuidString)-4711")

        _ = MessageStore(path: path)
        let store = MessageStore(path: path)

        let expectedID = CachedMessage.makeID(
            accountID: Self.account, folder: "INBOX", uid: 4711
        )
        #expect(store.message(id: expectedID) != nil)
        #expect(store.allMessages(accountIDs: [Self.account], folder: "INBOX").count == 1)
    }

    /// Legt eine Datenbank im Zustand von v0.1.4 an: Kennung ohne Ordner,
    /// keine Spalte `folder`.
    private func createLegacyDatabase(at path: String, messageID: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        let statements = [
            """
            CREATE TABLE message (
                id TEXT PRIMARY KEY, accountID TEXT NOT NULL,
                accountDisplayName TEXT NOT NULL, uid INTEGER NOT NULL,
                subject TEXT NOT NULL, "from" TEXT NOT NULL, "to" TEXT NOT NULL,
                date REAL, isUnread INTEGER NOT NULL, totalSizeBytes INTEGER NOT NULL,
                textBody TEXT, htmlBody TEXT, fetchedAt REAL NOT NULL,
                hasAttachments INTEGER NOT NULL DEFAULT 0,
                isFlagged INTEGER NOT NULL DEFAULT 0,
                isAnswered INTEGER NOT NULL DEFAULT 0,
                isForwarded INTEGER NOT NULL DEFAULT 0,
                toJSON TEXT, ccJSON TEXT, replyToJSON TEXT,
                rfcMessageID TEXT, rfcInReplyTo TEXT, rfcReferences TEXT,
                headersVersion INTEGER NOT NULL DEFAULT 0
            )
            """,
            """
            CREATE TABLE attachment (
                id TEXT PRIMARY KEY, messageID TEXT NOT NULL, filename TEXT NOT NULL,
                contentType TEXT NOT NULL, sizeBytes INTEGER NOT NULL, data BLOB,
                FOREIGN KEY (messageID) REFERENCES message(id) ON DELETE CASCADE
            )
            """,
            """
            INSERT INTO message
            (id, accountID, accountDisplayName, uid, subject, "from", "to", date,
             isUnread, totalSizeBytes, textBody, htmlBody, fetchedAt, hasAttachments,
             headersVersion)
            VALUES ('\(messageID)', '\(Self.account.uuidString)', 'Test', 4711,
                    'Alter Bestand', 'anna@example.org', 'kim@example.org',
                    1700000000.0, 1, 1024, 'Text', NULL, 1700000000.0, 1, 1)
            """,
            """
            INSERT INTO attachment (id, messageID, filename, contentType, sizeBytes, data)
            VALUES ('\(messageID)-2', '\(messageID)', 'Alt.pdf', 'application/pdf', 3, NULL)
            """
        ]

        for sql in statements {
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK,
                    "Aufbau der Alt-Datenbank fehlgeschlagen: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
}