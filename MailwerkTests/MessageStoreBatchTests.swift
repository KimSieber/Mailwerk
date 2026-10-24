//
//  MessageStoreBatchTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das gemeinsame Speichern im MessageStore (v0.2.3a):
//  verschachtelte Transaktionen über `batch`, Rückrollen einer einzelnen
//  fehlerhaften Mail per Savepoint, wiederverwendete Anweisungen und der
//  Index der Anhänge (Schema-Stufe 8); dazu gleichzeitiges Schreiben und
//  Lesen aus mehreren Threads (v0.2.3b).
//
//  Jeder Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis,
//  damit die Ablage der App unberührt bleibt.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

/// Tests für gemeinsames Speichern, Savepoints und Anweisungs-Cache.
@MainActor
struct MessageStoreBatchTests {

    // MARK: - Hilfen

    private static let account = UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")!

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite")
            .path
    }

    /// Testhilfe: Nachricht im Posteingang.
    private func message(uid: UInt32) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: Self.account, folder: "INBOX", uid: uid),
            accountID: Self.account,
            accountDisplayName: "Test",
            folder: "INBOX",
            uid: uid,
            subject: "Betreff \(uid)",
            from: "anna@example.org",
            to: "max@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(uid)),
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

    /// Testhilfe: Anhang zu einer Nachrichten-Kennung.
    private func attachment(messageID: String, suffix: String = "2") -> CachedAttachment {
        CachedAttachment(
            id: "\(messageID)-\(suffix)",
            messageID: messageID,
            filename: "datei.pdf",
            contentType: "application/pdf",
            sizeBytes: 3,
            data: Data([1, 2, 3])
        )
    }

    // MARK: - batch

    /// Mehrere Mails in einem Commit sind danach alle gespeichert.
    @Test("batch speichert alle Mails des Blocks")
    func batchSavesAll() {
        let store = MessageStore(path: temporaryPath())
        let ok = store.batch("Test") {
            for uid in UInt32(1)...5 {
                store.saveMessageWithAttachments(message(uid: uid), attachments: [])
            }
        }
        #expect(ok)
        #expect(store.cachedUIDs(accountID: Self.account, folder: "INBOX") == [1, 2, 3, 4, 5])
    }

    /// Scheitert eine Mail im Block, rollt nur sie zurück; die übrigen bleiben.
    @Test("Eine fehlerhafte Mail rollt nur sich selbst zurück")
    func failedMessageRollsBackAlone() {
        let store = MessageStore(path: temporaryPath())
        let good = message(uid: 1)
        let bad = message(uid: 2)
        var badSaved = true
        let ok = store.batch("Test") {
            store.saveMessageWithAttachments(good, attachments: [])
            // Anhang verweist auf eine fehlende Nachricht → Fremdschlüssel-
            // fehler nach dem Einfügen der Nachricht; der Savepoint muss auch
            // die schon eingefügte Nachricht zurücknehmen.
            badSaved = store.saveMessageWithAttachments(
                bad, attachments: [attachment(messageID: "fehlt")]
            )
        }
        #expect(ok)
        #expect(!badSaved)
        #expect(store.message(id: good.id) != nil)
        #expect(store.message(id: bad.id) == nil)
    }

    /// Ohne umgebenden Block verhält sich das Speichern wie bisher.
    @Test("Speichern ohne batch rollt bei einem Fehler vollständig zurück")
    func saveWithoutBatchRollsBack() {
        let store = MessageStore(path: temporaryPath())
        let bad = message(uid: 7)
        let saved = store.saveMessageWithAttachments(bad, attachments: [attachment(messageID: "fehlt")])
        #expect(!saved)
        #expect(store.message(id: bad.id) == nil)
    }

    // MARK: - Anweisungs-Cache

    /// Dieselbe Schreibanweisung lässt sich mehrfach hintereinander nutzen.
    @Test("Wiederverwendete Anweisung schreibt jedes Mal den neuen Wert")
    func cachedStatementIsReusable() {
        let store = MessageStore(path: temporaryPath())
        let mail = message(uid: 3)
        store.saveMessage(mail)
        store.updateUnread(messageID: mail.id, isUnread: false)
        #expect(store.message(id: mail.id)?.isUnread == false)
        store.updateUnread(messageID: mail.id, isUnread: true)
        #expect(store.message(id: mail.id)?.isUnread == true)
        store.updateUnread(messageID: mail.id, isUnread: false)
        #expect(store.message(id: mail.id)?.isUnread == false)
    }

    // MARK: - Schema-Stufe 8

    /// Nach dem Öffnen besteht der Index der Anhänge nach Nachricht.
    @Test("Index idx_attachment_message ist angelegt")
    func attachmentIndexExists() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        store.saveMessage(message(uid: 1))  // Ablage benutzt, Datei geschrieben

        var db: OpaquePointer?
        #expect(sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT count(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_attachment_message'"
        #expect(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_int(stmt, 0) == 1)
    }

    // MARK: - Nebenläufigkeit (v0.2.3b)

    /// Gleichzeitiges Schreiben und Lesen aus vielen Threads verliert nichts und verklemmt nicht.
    @Test("Schreiben und Lesen aus mehreren Threads gleichzeitig")
    func concurrentWritesAndReads() {
        let store = MessageStore(path: temporaryPath())
        let mails = (UInt32(1)...40).map { message(uid: $0) }
        // Als lokale Konstante: Der Block läuft in vielen Threads, der
        // statische Wert gehört zum Main-Actor der Testsuite.
        let account = Self.account
        DispatchQueue.concurrentPerform(iterations: 80) { index in
            if index < 40 {
                store.saveMessageWithAttachments(mails[index], attachments: [])
            } else {
                _ = store.folderMessages(accountID: account, folder: "INBOX")
                _ = store.unreadInboxCount(accountIDs: [account])
            }
        }
        #expect(store.folderMessages(accountID: Self.account, folder: "INBOX").count == 40)
    }

    /// Ein Batch aus einem anderen Thread verklemmt nicht mit gleichzeitigen Abfragen.
    @Test("batch aus einem Hintergrund-Thread neben Abfragen")
    func batchFromBackgroundThread() async {
        let store = MessageStore(path: temporaryPath())
        let mails = (UInt32(1)...20).map { message(uid: $0) }
        let writer = Task.detached {
            store.batch("Test") {
                for mail in mails {
                    store.saveMessageWithAttachments(mail, attachments: [])
                }
            }
        }
        for _ in 0..<20 {
            _ = store.cachedUIDs(accountID: Self.account, folder: "INBOX")
        }
        #expect(await writer.value)
        #expect(store.cachedUIDs(accountID: Self.account, folder: "INBOX").count == 20)
    }

    /// Ohne Datei (Arbeitsspeicher) funktionieren Schreiben und Lesen über eine Verbindung.
    @Test("Ablage im Arbeitsspeicher liest und schreibt")
    func inMemoryStoreWorks() {
        let store = MessageStore(path: nil)
        store.saveMessage(message(uid: 9))
        #expect(store.cachedUIDs(accountID: Self.account, folder: "INBOX") == [9])
    }
}
