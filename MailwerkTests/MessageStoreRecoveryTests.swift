//
//  MessageStoreRecoveryTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Öffnen des MessageStore ohne Absturz –
//  beschädigte Datei wird gelöscht und neu angelegt, andere Fehler
//  löschen nichts und führen zur Ablage im Arbeitsspeicher – sowie für
//  den Backup-Ausschluss des Ablageordners.
//
//  Jeder Test arbeitet auf eigenen Dateien im Temp-Verzeichnis.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreRecoveryTests {

    private static let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    /// Testhilfe: Pfad einer neuen Datenbankdatei im Temp-Verzeichnis.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
    }

    /// Testhilfe: gecachte Nachricht im Posteingang.
    private func message(uid: UInt32 = 1) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: Self.account, folder: "INBOX", uid: uid),
            accountID: Self.account, accountDisplayName: "Test", folder: "INBOX", uid: uid,
            subject: "Betreff", from: "anna@example.org", to: "kim@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
            totalSizeBytes: 100, hasAttachments: false, textBody: "Text", htmlBody: nil,
            fetchedAt: Date(), headers: CachedMessageHeaders()
        )
    }

    /// Testhilfe: Inhalt, der sicher keine SQLite-Datenbank ist.
    private let garbage = Data(repeating: 0xAB, count: 8_192)

    /// Eine gesunde Datenbank wird normal geöffnet, ohne Hinweis, und behält ihre Daten.
    @Test func healthyDatabaseOpensWithoutNotice() {
        let path = temporaryPath()
        let first = MessageStore(path: path)
        first.saveMessage(message())
        #expect(first.consumeStartupNotice() == nil)

        let reopened = MessageStore(path: path)
        #expect(reopened.consumeStartupNotice() == nil)
        #expect(reopened.message(id: message().id) != nil)
    }

    /// Eine beschädigte Datei wird gelöscht und neu angelegt; Hinweis „neu angelegt“.
    @Test func corruptDatabaseIsRebuilt() throws {
        let path = temporaryPath()
        try garbage.write(to: URL(fileURLWithPath: path))

        let store = MessageStore(path: path)

        #expect(store.consumeStartupNotice() == .rebuiltAfterCorruption)
        store.saveMessage(message())
        #expect(store.message(id: message().id) != nil)
        // Neu angelegt: die Datei beginnt jetzt mit der SQLite-Kennung.
        let header = try Data(contentsOf: URL(fileURLWithPath: path)).prefix(15)
        #expect(String(data: header, encoding: .ascii) == "SQLite format 3")
    }

    /// Beim Neuanlegen werden auch alte WAL-Begleitdateien entfernt.
    @Test func corruptDatabaseRemovesCompanionFiles() throws {
        let path = temporaryPath()
        try garbage.write(to: URL(fileURLWithPath: path))
        try garbage.write(to: URL(fileURLWithPath: path + "-wal"))
        try garbage.write(to: URL(fileURLWithPath: path + "-shm"))

        let store = MessageStore(path: path)

        #expect(store.consumeStartupNotice() == .rebuiltAfterCorruption)
        for suffix in ["-wal", "-shm"] {
            let url = URL(fileURLWithPath: path + suffix)
            // Entweder entfernt oder von SQLite neu angelegt – nie der alte Inhalt.
            if FileManager.default.fileExists(atPath: url.path) {
                #expect(try Data(contentsOf: url) != garbage)
            }
        }
        #expect(store.saveMessageWithAttachments(message(), attachments: []))
    }

    /// Kann nicht geöffnet werden (Verzeichnis fehlt): nichts löschen, im Arbeitsspeicher weiterarbeiten.
    @Test func unopenableDatabaseFallsBackToMemory() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("gibt-es-nicht-\(UUID().uuidString)/Mailwerk.sqlite").path

        let store = MessageStore(path: path)

        #expect(store.consumeStartupNotice() == .unavailable)
        store.saveMessage(message())
        #expect(store.message(id: message().id) != nil)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    /// Ohne Pfad arbeitet die Ablage im Arbeitsspeicher und meldet das.
    @Test func noPathMeansMemoryWithNotice() {
        let store = MessageStore(path: nil)
        #expect(store.consumeStartupNotice() == .unavailable)
        store.saveMessage(message())
        #expect(store.message(id: message().id) != nil)
    }

    /// Der Hinweis wird genau einmal geliefert.
    @Test func noticeIsDeliveredOnlyOnce() throws {
        let path = temporaryPath()
        try garbage.write(to: URL(fileURLWithPath: path))
        let store = MessageStore(path: path)
        #expect(store.consumeStartupNotice() == .rebuiltAfterCorruption)
        #expect(store.consumeStartupNotice() == nil)
    }

    /// Der Ablageordner wird angelegt und vom Backup ausgeschlossen.
    @Test func cacheDirectoryIsExcludedFromBackup() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let directory = try MessageStore.prepareCacheDirectory(in: base)

        #expect(directory.lastPathComponent == MessageStore.cacheDirectoryName)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
