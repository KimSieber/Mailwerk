//
//  MessageStoreListTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Listenabfragen des MessageStore – Listeneinträge
//  ohne Mailinhalt (samt Empfängern, Größe und Spam-Angabe), Sortierung,
//  die Sammelansichten „Ungelesen“ (samt Zähler und behaltenen Mails) und
//  „Spam“ (mehrere Ordner), Migration auf Schema-Stufe 3 (Index angelegt)
//  und weiter bis zur aktuellen Stufe (Vorschau-Spalte entfernt).
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

    /// Zweites Postfach für Sammelansichten.
    private static let other = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3302")!

    /// Testhilfe: Nachricht mit wählbarem Postfach, Text, Datum, Kennzeichen und Gelesen-Status.
    private func message(
        uid: UInt32,
        account: UUID? = nil,
        folder: String = "INBOX",
        text: String? = "Text",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        flagged: Bool = false,
        unread: Bool = true
    ) -> CachedMessage {
        let account = account ?? Self.account
        return CachedMessage(
            id: CachedMessage.makeID(accountID: account, folder: folder, uid: uid),
            accountID: account, accountDisplayName: "Test", folder: folder, uid: uid,
            subject: "Betreff \(uid)", from: "anna@example.org", to: "kim@example.org",
            date: date,
            isUnread: unread, isFlagged: flagged, isAnswered: false, isForwarded: true,
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
        #expect(item.sizeBytes == 100)
    }

    /// Der Listeneintrag übernimmt Empfänger und Spam-Angabe.
    @Test func listItemCarriesRecipientsAndSpamVerdict() throws {
        let store = MessageStore(path: temporaryPath())
        let base = message(uid: 3)
        var headers = CachedMessageHeaders()
        headers.toList = ["Anna Muster <anna@example.org>", "ben@example.org"]
        headers.spamVerdict = SpamHeaderVerdict(isSpam: true, score: 7.5)
        store.saveMessage(CachedMessage(
            id: base.id, accountID: base.accountID, accountDisplayName: base.accountDisplayName,
            folder: base.folder, uid: base.uid, subject: base.subject, from: base.from, to: base.to,
            date: base.date, isUnread: base.isUnread, isFlagged: base.isFlagged,
            isAnswered: base.isAnswered, isForwarded: base.isForwarded,
            totalSizeBytes: base.totalSizeBytes, hasAttachments: base.hasAttachments,
            textBody: base.textBody, htmlBody: base.htmlBody, fetchedAt: base.fetchedAt,
            headers: headers
        ))

        let item = try #require(store.folderMessages(accountID: Self.account, folder: "INBOX").first)
        #expect(item.recipients == ["Anna Muster <anna@example.org>", "ben@example.org"])
        #expect(item.spamVerdict == SpamHeaderVerdict(isSpam: true, score: 7.5))
    }

    /// Ohne gespeicherte Spam-Angabe bleibt sie im Listeneintrag unbekannt.
    @Test func listItemWithoutVerdictIsUnknown() throws {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(uid: 4))

        let item = try #require(store.folderMessages(accountID: Self.account, folder: "INBOX").first)
        #expect(item.spamVerdict == nil)
        #expect(item.recipients.isEmpty)
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

    /// Ungelesen: nur ungelesene Mails der Posteingänge; Zähler passend.
    @Test func unreadListAndCountCoverInboxesOnly() {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(uid: 1, date: Date(timeIntervalSince1970: 1_000)))
        store.saveMessage(message(uid: 2, date: Date(timeIntervalSince1970: 2_000), unread: false))
        store.saveMessage(message(uid: 3, account: Self.other, date: Date(timeIntervalSince1970: 3_000)))
        store.saveMessage(message(uid: 4, folder: "Archiv"))

        let ids = [Self.account, Self.other]
        #expect(store.unreadInboxMessages(accountIDs: ids).map(\.uid) == [3, 1])
        #expect(store.unreadInboxCount(accountIDs: ids) == 2)
        #expect(store.unreadInboxCount(accountIDs: [Self.account]) == 1)
    }

    /// Ungelesen: bereits gezeigte Mails bleiben, auch wenn sie inzwischen gelesen sind.
    @Test func unreadListKeepsShownMails() {
        let store = MessageStore(path: temporaryPath())
        let read = message(uid: 2, date: Date(timeIntervalSince1970: 2_000), unread: false)
        store.saveMessage(message(uid: 1, date: Date(timeIntervalSince1970: 1_000)))
        store.saveMessage(read)
        store.saveMessage(message(uid: 3, date: Date(timeIntervalSince1970: 3_000), unread: false))

        let list = store.unreadInboxMessages(accountIDs: [Self.account], keeping: [read.id])
        #expect(list.map(\.uid) == [2, 1])
        #expect(store.unreadInboxCount(accountIDs: [Self.account]) == 1)
    }

    /// Spam-Sicht: je Postfach der eigene Ordner, gemeinsam nach Datum.
    @Test func messagesFromSeveralFolders() {
        let store = MessageStore(path: temporaryPath())
        store.saveMessage(message(uid: 1, folder: "Spam", date: Date(timeIntervalSince1970: 1_000)))
        store.saveMessage(message(uid: 2, account: Self.other, folder: "Junk", date: Date(timeIntervalSince1970: 2_000)))
        store.saveMessage(message(uid: 3, folder: "Junk"))
        store.saveMessage(message(uid: 4))

        let folders = [FolderKey(accountID: Self.account, folder: "Spam"), FolderKey(accountID: Self.other, folder: "Junk")]
        #expect(store.messages(in: folders).map(\.uid) == [2, 1])
        #expect(store.messages(in: []).isEmpty)
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

    /// Migration ab Stufe 2: Index angelegt, alter Index und Vorschau-Spalte entfernt, Mails bleiben.
    @Test func migrationFromVersion2CreatesIndexAndDropsPreview() throws {
        let path = temporaryPath()
        do {
            let store = MessageStore(path: path)
            store.saveMessage(message(uid: 1, text: "Bestand"))
            store.saveMessage(message(uid: 2, text: nil))
        }
        try downgradeToVersion2(at: path)

        let store = MessageStore(path: path)

        let items = store.folderMessages(accountID: Self.account, folder: "INBOX")
        #expect(Set(items.map(\.uid)) == [1, 2])
        #expect(sqlite(at: path, "SELECT count(*) FROM pragma_table_info('message') WHERE name = 'preview'") == "0")
        #expect(sqlite(at: path, "SELECT count(*) FROM sqlite_master WHERE name = 'idx_message_account_folder_date'") == "1")
        #expect(sqlite(at: path, "SELECT count(*) FROM sqlite_master WHERE name = 'idx_message_account_folder'") == "0")
        #expect(sqlite(at: path, "PRAGMA user_version") == "8")
    }

    /// Testhilfe: versetzt eine Datenbank in den Zustand von Schema-Stufe 2
    /// (alter Index, user_version = 2) – mit der Vorschau-Spalte, die
    /// frühere Stände ab Stufe 3 hatten.
    private func downgradeToVersion2(at path: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in [
            "DROP INDEX IF EXISTS idx_message_account_folder_date",
            "ALTER TABLE message ADD COLUMN preview TEXT",
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
