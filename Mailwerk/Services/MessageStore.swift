//
//  MessageStore.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//


//
//  MessageStore.swift
//  Mailwerk
//

import Foundation
import SQLite3

/// Lokale SQLite-Ablage für Nachrichten und Anhänge.
/// Nutzt das auf jeder Apple-Plattform mitgelieferte System-SQLite.
/// Dient später auch als Basis für den FTS5-Volltextindex (Stufe 2).
final class MessageStore: @unchecked Sendable {
    static let shared = MessageStore()

    private var db: OpaquePointer?

    private init() {
        do {
            let folder = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let path = folder.appendingPathComponent("Mailwerk.sqlite").path
            guard sqlite3_open(path, &db) == SQLITE_OK else {
                fatalError("SQLite öffnen fehlgeschlagen: \(errMsg)")
            }
            createTablesIfNeeded()
            migrateIfNeeded()
        } catch {
            fatalError("App-Support-Verzeichnis nicht verfügbar: \(error)")
        }
    }

    deinit { sqlite3_close(db) }

    private var errMsg: String {
        String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Schema

    private func createTablesIfNeeded() {
        exec("""
            CREATE TABLE IF NOT EXISTS message (
                id TEXT PRIMARY KEY,
                accountID TEXT NOT NULL,
                accountDisplayName TEXT NOT NULL,
                uid INTEGER NOT NULL,
                subject TEXT NOT NULL,
                "from" TEXT NOT NULL,
                "to" TEXT NOT NULL,
                date REAL,
                isUnread INTEGER NOT NULL,
                totalSizeBytes INTEGER NOT NULL,
                textBody TEXT,
                htmlBody TEXT,
                fetchedAt REAL NOT NULL,
                hasAttachments INTEGER NOT NULL DEFAULT 0
            )
            """)
        exec("""
            CREATE TABLE IF NOT EXISTS attachment (
                id TEXT PRIMARY KEY,
                messageID TEXT NOT NULL,
                filename TEXT NOT NULL,
                contentType TEXT NOT NULL,
                sizeBytes INTEGER NOT NULL,
                data BLOB,
                FOREIGN KEY (messageID) REFERENCES message(id) ON DELETE CASCADE
            )
            """)
        exec("PRAGMA foreign_keys = ON")
    }

    // MARK: - Migration

    /// Fügt neue Spalten hinzu, falls die DB aus v0.1.0 stammt.
    /// Prüft vorher per PRAGMA table_info, ob die Spalte schon existiert.
    private func migrateIfNeeded() {
        // v0.1.1: hasAttachments-Spalte
        if !columnExists("hasAttachments", in: "message") {
            exec("ALTER TABLE message ADD COLUMN hasAttachments INTEGER NOT NULL DEFAULT 0")

            // Backfill: bestehende Nachrichten anhand der Attachment-Tabelle aktualisieren
            exec("""
                UPDATE message SET hasAttachments = 1
                WHERE id IN (SELECT DISTINCT messageID FROM attachment)
                """)
        }
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        guard let stmt = prepare("PRAGMA table_info(\(table))") else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            // Spalte 1 von PRAGMA table_info ist der Spaltenname
            if str(stmt, 1) == column { return true }
        }
        return false
    }

    // MARK: - Nachrichten speichern

    /// Speichert eine neue Nachricht oder aktualisiert eine bestehende.
    /// Nutzt UPSERT (ON CONFLICT … DO UPDATE) statt INSERT OR REPLACE,
    /// da letzteres intern DELETE + INSERT ist und damit ON DELETE CASCADE
    /// auf der Attachment-Tabelle auslösen würde.
    func saveMessage(_ m: CachedMessage) {
        let sql = """
            INSERT INTO message
            (id, accountID, accountDisplayName, uid, subject,
             "from", "to", date, isUnread, totalSizeBytes,
             textBody, htmlBody, fetchedAt, hasAttachments)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                isUnread = excluded.isUnread,
                totalSizeBytes = excluded.totalSizeBytes,
                textBody = excluded.textBody,
                htmlBody = excluded.htmlBody,
                fetchedAt = excluded.fetchedAt,
                hasAttachments = excluded.hasAttachments
            """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, m.id)
        bind(stmt, 2, m.accountID.uuidString)
        bind(stmt, 3, m.accountDisplayName)
        sqlite3_bind_int(stmt, 4, Int32(m.uid))
        bind(stmt, 5, m.subject)
        bind(stmt, 6, m.from)
        bind(stmt, 7, m.to)
        if let d = m.date { sqlite3_bind_double(stmt, 8, d.timeIntervalSince1970) }
        else { sqlite3_bind_null(stmt, 8) }
        sqlite3_bind_int(stmt, 9, m.isUnread ? 1 : 0)
        sqlite3_bind_int(stmt, 10, Int32(m.totalSizeBytes))
        bind(stmt, 11, m.textBody)
        bind(stmt, 12, m.htmlBody)
        sqlite3_bind_double(stmt, 13, m.fetchedAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 14, m.hasAttachments ? 1 : 0)

        sqlite3_step(stmt)
    }

    /// Aktualisiert nur den Gelesen-Status einer bereits gecachten Nachricht.
    /// Leichtgewichtig, ohne Risiko für Cascade-Deletes.
    func updateFlags(messageID: String, isUnread: Bool) {
        let sql = "UPDATE message SET isUnread = ? WHERE id = ?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, isUnread ? 1 : 0)
        bind(stmt, 2, messageID)
        sqlite3_step(stmt)
    }

    func saveMessages(_ messages: [CachedMessage]) {
        exec("BEGIN TRANSACTION")
        for m in messages { saveMessage(m) }
        exec("COMMIT")
    }

    // MARK: - Anhänge speichern

    func saveAttachment(_ a: CachedAttachment) {
        let sql = """
            INSERT INTO attachment
            (id, messageID, filename, contentType, sizeBytes, data)
            VALUES (?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                filename = excluded.filename,
                contentType = excluded.contentType,
                sizeBytes = excluded.sizeBytes,
                data = excluded.data
            """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, a.id)
        bind(stmt, 2, a.messageID)
        bind(stmt, 3, a.filename)
        bind(stmt, 4, a.contentType)
        sqlite3_bind_int(stmt, 5, Int32(a.sizeBytes))
        if let data = a.data {
            _ = data.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 6, ptr.baseAddress, Int32(data.count), nil)
            }
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_step(stmt)
    }

    // MARK: - Anhänge löschen (nur lokales BLOB)

    /// Löscht nur die lokalen Binärdaten eines Anhangs, behält aber
    /// die Metadaten (Dateiname, Größe, Typ). Der Anhang kann danach
    /// bei Bedarf erneut vom Server geladen werden.
    func deleteAttachmentData(id: String) {
        let sql = "UPDATE attachment SET data = NULL WHERE id = ?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        sqlite3_step(stmt)
    }

    // MARK: - Lesen

    func message(id: String) -> CachedMessage? {
        guard let stmt = prepare("SELECT * FROM message WHERE id = ? LIMIT 1") else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readMessage(stmt)
    }

    func allMessages(accountIDs: [UUID]) -> [CachedMessage] {
        guard !accountIDs.isEmpty else { return [] }
        let ph = accountIDs.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT * FROM message WHERE accountID IN (\(ph)) ORDER BY date DESC"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in accountIDs.enumerated() {
            bind(stmt, Int32(i + 1), id.uuidString)
        }
        var result: [CachedMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(readMessage(stmt))
        }
        return result
    }

    func cachedMessageIDs(forAccount accountID: UUID) -> Set<String> {
        guard let stmt = prepare("SELECT id FROM message WHERE accountID = ?") else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        var ids = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.insert(str(stmt, 0))
        }
        return ids
    }

    func attachments(forMessage messageID: String) -> [CachedAttachment] {
        guard let stmt = prepare("SELECT * FROM attachment WHERE messageID = ?") else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, messageID)
        var result: [CachedAttachment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(readAttachment(stmt))
        }
        return result
    }

    // MARK: - Löschen (für Cache-Bereinigung)

    func deleteMessagesOlderThan(_ date: Date, forAccount accountID: UUID) {
        let sql = "DELETE FROM message WHERE accountID = ? AND date < ?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    // MARK: - Interne Helfer

    private func readMessage(_ s: OpaquePointer?) -> CachedMessage {
        let dateVal = sqlite3_column_type(s, 7) != SQLITE_NULL
            ? sqlite3_column_double(s, 7) : nil
        return CachedMessage(
            id: str(s, 0),
            accountID: UUID(uuidString: str(s, 1)) ?? UUID(),
            accountDisplayName: str(s, 2),
            uid: UInt32(sqlite3_column_int(s, 3)),
            subject: str(s, 4),
            from: str(s, 5),
            to: str(s, 6),
            date: dateVal.map { Date(timeIntervalSince1970: $0) },
            isUnread: sqlite3_column_int(s, 8) != 0,
            totalSizeBytes: Int(sqlite3_column_int(s, 9)),
            hasAttachments: sqlite3_column_int(s, 13) != 0,
            textBody: optStr(s, 10),
            htmlBody: optStr(s, 11),
            fetchedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 12))
        )
    }

    private func readAttachment(_ s: OpaquePointer?) -> CachedAttachment {
        var data: Data?
        if sqlite3_column_type(s, 5) != SQLITE_NULL,
           let bytes = sqlite3_column_blob(s, 5) {
            let count = Int(sqlite3_column_bytes(s, 5))
            data = Data(bytes: bytes, count: count)
        }
        return CachedAttachment(
            id: str(s, 0),
            messageID: str(s, 1),
            filename: str(s, 2),
            contentType: str(s, 3),
            sizeBytes: Int(sqlite3_column_int(s, 4)),
            data: data
        )
    }

    private func str(_ s: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(s, col) else { return "" }
        return String(cString: c)
    }

    private func optStr(_ s: OpaquePointer?, _ col: Int32) -> String? {
        guard sqlite3_column_type(s, col) != SQLITE_NULL,
              let c = sqlite3_column_text(s, col) else { return nil }
        return String(cString: c)
    }

    private func bind(_ s: OpaquePointer?, _ i: Int32, _ v: String?) {
        if let v { sqlite3_bind_text(s, i, (v as NSString).utf8String, -1, nil) }
        else { sqlite3_bind_null(s, i) }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        return sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK ? stmt : nil
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }
}
