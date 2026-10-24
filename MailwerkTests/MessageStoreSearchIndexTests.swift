//
//  MessageStoreSearchIndexTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Suchindex des MessageStore (Schema-Stufe 7) –
//  Eintrag beim Speichern, Neuschreiben, Löschen per Trigger, Verschieben,
//  Kopfdaten, Anhangnamen, Nachtragen und Migration.
//
//  Gesucht wird hier direkt per SQL auf der Datei; die Suchabfragen der
//  Oberfläche prüfen eigene Tests.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreSearchIndexTests {

    private static let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
    }

    /// Testhilfe: Nachricht mit wählbarem Betreff, Text und HTML.
    private func message(
        uid: UInt32,
        subject: String = "Betreff",
        text: String? = nil,
        html: String? = nil,
        headers: CachedMessageHeaders? = nil
    ) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: Self.account, folder: "INBOX", uid: uid),
            accountID: Self.account, accountDisplayName: "Test", folder: "INBOX", uid: uid,
            subject: subject, from: "Anna Muster <anna@example.org>", to: "kim@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(uid)),
            isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
            totalSizeBytes: 100, hasAttachments: false, textBody: text, htmlBody: html,
            fetchedAt: Date(), headers: headers ?? CachedMessageHeaders()
        )
    }

    /// Testhilfe: Anzahl der Treffer eines FTS5-Ausdrucks direkt aus der Datei.
    private func hits(_ expression: String, at path: String) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT count(*) FROM message_search WHERE message_search MATCH ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, expression, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Testhilfe: führt SQL direkt auf der Datei aus.
    private func exec(_ statements: [String], at path: String) {
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in statements {
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)")
        }
    }

    /// Betreff, Text, Absender und Teilwörter sind nach dem Speichern auffindbar.
    @Test func savedMessageIsFound() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        store.saveMessage(message(uid: 1, subject: "Ihre Stromrechnung", text: "Abt. IS meldet Ärger"))
        #expect(hits("\"rechnung\"", at: path) == 1)
        #expect(hits("\"ärger\"", at: path) == 1)
        #expect(hits("\"is \"", at: path) == 1)
        #expect(hits("people : \"<anna@example.org>\"", at: path) == 1)
        #expect(hits("\"nichtda\"", at: path) == 0)
    }

    /// Reine HTML-Mails werden ohne Tags indiziert.
    @Test func htmlOnlyMessageIsIndexedWithoutTags() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        store.saveMessage(message(uid: 1, html: "<p style=\"color:red\">Ver<b>trag</b>sende</p>"))
        #expect(hits("\"vertragsende\"", at: path) == 1)
        #expect(hits("\"color\"", at: path) == 0)
    }

    /// Erneutes Speichern ersetzt den Eintrag statt einen zweiten anzulegen.
    @Test func resavingReplacesEntry() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        store.saveMessage(message(uid: 1, text: "alter Text"))
        store.saveMessage(message(uid: 1, text: "neuer Text"))
        #expect(hits("\"alter\"", at: path) == 0)
        #expect(hits("\"neuer\"", at: path) == 1)
    }

    /// Gelöschte Nachrichten verschwinden aus dem Index (auch ganze Ordner).
    @Test func deletionRemovesEntry() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        let first = message(uid: 1, text: "eins zwei")
        store.saveMessage(first)
        store.saveMessage(message(uid: 2, text: "eins drei"))
        store.deleteMessage(id: first.id)
        #expect(hits("\"eins\"", at: path) == 1)
        store.deleteFolder(accountID: Self.account, folder: "INBOX")
        #expect(hits("\"eins\"", at: path) == 0)
    }

    /// Verschieben behält den Eintrag.
    @Test func relocationKeepsEntry() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        let saved = message(uid: 1, text: "Kündigung")
        store.saveMessage(saved)
        #expect(store.relocateMessage(id: saved.id, toFolder: "Archiv", newUID: 9) != nil)
        #expect(hits("\"kündigung\"", at: path) == 1)
    }

    /// Nachgetragene Kopfdaten (An, Cc) kommen in den Index.
    @Test func updatedHeadersAreIndexed() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        let saved = message(uid: 1, text: "x")
        store.saveMessage(saved)
        var headers = CachedMessageHeaders()
        headers.ccList = ["Chef <chef@firma.de>"]
        store.updateHeaders(messageID: saved.id, headers: headers)
        #expect(hits("people : \"<chef@firma.de>\"", at: path) == 1)
    }

    /// Nachgetragene Kopfdaten lassen Text und Anhangnamen im Index unverändert.
    @Test func updatedHeadersKeepBodyAndAttachments() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        let saved = message(uid: 1, text: "Kündigungsbestätigung")
        let pdf = CachedAttachment(
            id: "\(saved.id)-2", messageID: saved.id, filename: "Vertrag.pdf",
            contentType: "application/pdf", sizeBytes: 1, data: nil
        )
        store.saveMessageWithAttachments(saved, attachments: [pdf])
        var headers = CachedMessageHeaders()
        headers.toList = ["Max Müller <max@example.org>"]
        store.updateHeaders(messageID: saved.id, headers: headers)
        #expect(hits("\"kündigung\"", at: path) == 1)
        #expect(hits("attachments : \"vertrag\"", at: path) == 1)
        #expect(hits("people : \"<max@example.org>\"", at: path) == 1)
    }

    /// Fehlt der Eintrag noch, schreiben nachgetragene Kopfdaten ihn vollständig.
    @Test func updatedHeadersCreateMissingEntry() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        let saved = message(uid: 1, text: "Rechnung")
        store.saveMessage(saved)
        exec(["DELETE FROM message_search"], at: path)
        var headers = CachedMessageHeaders()
        headers.ccList = ["chef@firma.de"]
        store.updateHeaders(messageID: saved.id, headers: headers)
        #expect(hits("\"rechnung\"", at: path) == 1)
        #expect(hits("people : \"<chef@firma.de>\"", at: path) == 1)
    }

    /// Namen echter Anhänge sind auffindbar, eingebettete Bilder nicht.
    @Test func attachmentNamesAreIndexed() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        let saved = message(uid: 1, text: "x")
        let pdf = CachedAttachment(
            id: "\(saved.id)-2", messageID: saved.id, filename: "Angebot_2026.pdf",
            contentType: "application/pdf", sizeBytes: 1, data: nil
        )
        let logo = CachedAttachment(
            id: "\(saved.id)-3", messageID: saved.id, filename: "logo.png",
            contentType: "image/png", sizeBytes: 1, data: nil, contentID: "logo", isInline: true
        )
        #expect(store.saveMessageWithAttachments(saved, attachments: [pdf, logo]))
        #expect(hits("attachments : \"angebot\"", at: path) == 1)
        #expect(hits("\"logo.png\"", at: path) == 0)
    }

    /// Fehlende Einträge werden in Paketen nachgetragen, bis keiner mehr fehlt.
    @Test func missingEntriesAreBackfilled() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        for uid in 1...5 {
            store.saveMessage(message(uid: UInt32(uid), text: "Bestand \(uid)"))
        }
        exec(["DELETE FROM message_search"], at: path)
        #expect(store.indexMissingSearchEntries(limit: 3) == 3)
        #expect(store.indexMissingSearchEntries(limit: 3) == 2)
        #expect(store.indexMissingSearchEntries(limit: 3) == 0)
        #expect(hits("\"bestand\"", at: path) == 5)
    }

    /// Migration 6 → 7: Index angelegt (zunächst leer), Vorschau-Spalte entfernt, Nachtragen füllt ihn.
    @Test func migrationToVersion7CreatesIndex() {
        let path = temporaryPath()
        do {
            let store = MessageStore(path: path)
            store.saveMessage(message(uid: 1, text: "Altbestand"))
        }
        exec([
            "DROP TRIGGER message_search_delete",
            "DROP TABLE message_search",
            "ALTER TABLE message ADD COLUMN preview TEXT",
            "PRAGMA user_version = 6",
        ], at: path)

        let store = MessageStore(path: path)
        #expect(hits("\"altbestand\"", at: path) == 0)
        #expect(store.indexMissingSearchEntries(limit: 10) == 1)
        #expect(hits("\"altbestand\"", at: path) == 1)
        #expect(store.folderMessages(accountID: Self.account, folder: "INBOX").count == 1)
    }
}
