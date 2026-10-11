//
//  SenderIconStoreTests.swift
//  MailwerkTests
//
//  Zweck: Tests für gespeicherte Absenderlogos – Ablaufregeln
//  (SenderIconRecord) sowie Speichern, Ersetzen und Migration auf
//  Schema-Stufe 5 im MessageStore.
//
//  Jeder Store-Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

@MainActor
struct SenderIconStoreTests {

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
    }

    /// Testhilfe: Bezugszeitpunkt.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Testhilfe: Zeitpunkt vor einer Anzahl Tagen.
    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 24 * 60 * 60)
    }

    // MARK: - Ablaufregeln

    /// Ohne Logo wird nach 30 Tagen erneut versucht.
    @Test func missIsRetriedAfter30Days() {
        #expect(!SenderIconRecord(domain: "a.de", imageData: nil, checkedAt: daysAgo(29)).isDue(now: now))
        #expect(SenderIconRecord(domain: "a.de", imageData: nil, checkedAt: daysAgo(30)).isDue(now: now))
    }

    /// Vorhandene Logos werden nach 90 Tagen aufgefrischt.
    @Test func hitIsRefreshedAfter90Days() {
        let data = Data([1])
        #expect(!SenderIconRecord(domain: "a.de", imageData: data, checkedAt: daysAgo(89)).isDue(now: now))
        #expect(SenderIconRecord(domain: "a.de", imageData: data, checkedAt: daysAgo(90)).isDue(now: now))
    }

    /// Ein Prüfzeitpunkt in der Zukunft gilt als abgelaufen.
    @Test func futureCheckIsDue() {
        #expect(SenderIconRecord(domain: "a.de", imageData: Data([1]), checkedAt: daysAgo(-1)).isDue(now: now))
    }

    // MARK: - Ablage

    /// Logo und erfolgloser Versuch werden gespeichert und gelesen.
    @Test func iconAndMissAreStored() {
        let store = MessageStore(path: temporaryPath())
        let hit = SenderIconRecord(domain: "firma.de", imageData: Data([1, 2, 3]), checkedAt: now)
        let miss = SenderIconRecord(domain: "leer.de", imageData: nil, checkedAt: now)
        store.saveSenderIcon(hit)
        store.saveSenderIcon(miss)
        #expect(store.senderIcon(domain: "firma.de") == hit)
        #expect(store.senderIcon(domain: "leer.de") == miss)
        #expect(store.senderIcon(domain: "unbekannt.de") == nil)
    }

    /// Ein neuer Eintrag ersetzt den bisherigen derselben Domain.
    @Test func newRecordReplacesOld() {
        let store = MessageStore(path: temporaryPath())
        store.saveSenderIcon(SenderIconRecord(domain: "firma.de", imageData: Data([1]), checkedAt: daysAgo(100)))
        let newer = SenderIconRecord(domain: "firma.de", imageData: nil, checkedAt: now)
        store.saveSenderIcon(newer)
        #expect(store.senderIcon(domain: "firma.de") == newer)
    }

    /// Eine Datenbank der Stufe 4 erhält beim Öffnen die Logo-Tabelle.
    @Test func migrationFromVersion4AddsTable() throws {
        let path = temporaryPath()
        do { _ = MessageStore(path: path) }
        try exec(["DROP TABLE sender_icon", "PRAGMA user_version = 4"], at: path)

        let store = MessageStore(path: path)
        let record = SenderIconRecord(domain: "firma.de", imageData: Data([7]), checkedAt: now)
        store.saveSenderIcon(record)
        #expect(store.senderIcon(domain: "firma.de") == record)
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
