//
//  MessageStoreTransactionTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Schreibsicherheit des MessageStore – atomares
//  Speichern von Nachricht und Anhängen, Rollback bei Fehlern,
//  WAL-Modus und Schema-Version.
//
//  Jeder Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreTransactionTests {

    private static let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite")
            .path
    }

    /// Testhilfe: gecachte Nachricht im Posteingang.
    private func message(uid: UInt32 = 1, hasAttachments: Bool = true) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: Self.account, folder: "INBOX", uid: uid),
            accountID: Self.account,
            accountDisplayName: "Test",
            folder: "INBOX",
            uid: uid,
            subject: "Betreff",
            from: "anna@example.org",
            to: "kim@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isUnread: true,
            isFlagged: false,
            isAnswered: false,
            isForwarded: false,
            totalSizeBytes: 1_024,
            hasAttachments: hasAttachments,
            textBody: "Text",
            htmlBody: nil,
            fetchedAt: Date(),
            headers: CachedMessageHeaders()
        )
    }

    /// Testhilfe: Anhang mit Daten zu einer Nachrichten-ID.
    private func attachment(messageID: String, index: Int) -> CachedAttachment {
        CachedAttachment(
            id: "\(messageID)-\(index + 1)",
            messageID: messageID,
            filename: "datei\(index).pdf",
            contentType: "application/pdf",
            sizeBytes: 3,
            data: Data([1, 2, 3])
        )
    }

    /// Testhilfe: liest ein PRAGMA direkt aus der Datei.
    private func pragma(_ name: String, at path: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA \(name)", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }

    /// Nachricht und Anhänge werden gemeinsam gespeichert.
    @Test func saveMessageWithAttachmentsStoresBoth() {
        let store = MessageStore(path: temporaryPath())
        let msg = message()

        let ok = store.saveMessageWithAttachments(
            msg, attachments: [attachment(messageID: msg.id, index: 1), attachment(messageID: msg.id, index: 2)]
        )

        #expect(ok)
        #expect(store.message(id: msg.id) != nil)
        #expect(store.attachments(forMessage: msg.id).count == 2)
    }

    /// Nachricht ohne Anhänge wird ebenfalls gespeichert.
    @Test func saveMessageWithAttachmentsWorksWithoutAttachments() {
        let store = MessageStore(path: temporaryPath())
        let msg = message(hasAttachments: false)

        #expect(store.saveMessageWithAttachments(msg, attachments: []))
        #expect(store.message(id: msg.id) != nil)
    }

    /// Scheitert ein Anhang (verweist auf fremde Nachricht), wird auch die Nachricht nicht gespeichert.
    @Test func failingAttachmentRollsBackTheMessage() {
        let store = MessageStore(path: temporaryPath())
        let msg = message()
        let orphan = attachment(messageID: "gibt-es-nicht", index: 1)

        let ok = store.saveMessageWithAttachments(
            msg, attachments: [attachment(messageID: msg.id, index: 1), orphan]
        )

        #expect(!ok)
        #expect(store.message(id: msg.id) == nil)
        #expect(store.attachments(forMessage: msg.id).isEmpty)
    }

    /// Nach einem Rollback ist die Ablage weiter beschreibbar.
    @Test func storeStaysUsableAfterRollback() {
        let store = MessageStore(path: temporaryPath())
        let first = message(uid: 1)
        _ = store.saveMessageWithAttachments(first, attachments: [attachment(messageID: "gibt-es-nicht", index: 1)])

        let second = message(uid: 2)
        #expect(store.saveMessageWithAttachments(second, attachments: [attachment(messageID: second.id, index: 1)]))
        #expect(store.message(id: second.id) != nil)
    }

    /// Die Datenbank läuft im WAL-Modus.
    @Test func walModeIsEnabled() {
        let path = temporaryPath()
        _ = MessageStore(path: path)
        #expect(pragma("journal_mode", at: path) == "wal")
    }

    /// Nach dem Öffnen steht die Schema-Version auf 2, auch nach erneutem Öffnen.
    @Test func schemaVersionIsStored() {
        let path = temporaryPath()
        _ = MessageStore(path: path)
        #expect(pragma("user_version", at: path) == "2")
        _ = MessageStore(path: path)
        #expect(pragma("user_version", at: path) == "2")
    }
}
