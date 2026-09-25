//
//  MessageStore.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//

import Foundation
import SQLite3

/// SQLite soll übergebene Texte/Blobs selbst kopieren (SQLITE_TRANSIENT = -1).
/// Das C-Makro ist in Swift nicht verfügbar, daher hier nachgebildet.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Lokale SQLite-Ablage für Nachrichten und Anhänge.
/// Nutzt das auf jeder Apple-Plattform mitgelieferte System-SQLite.
/// Dient später auch als Basis für den FTS5-Volltextindex (Stufe 2).
///
/// Schema-Prinzip: `createTablesIfNeeded()` legt nur das Basisschema (v0.1.0) an,
/// alle späteren Spalten kommen ausschließlich über `migrateIfNeeded()`.
/// Damit ist die Struktur auf Neu- und Bestandsinstallationen identisch.
final class MessageStore: @unchecked Sendable {
    static let shared = MessageStore()

    /// Version der gespeicherten Adress-/Threading-Header. Nachrichten mit
    /// kleinerer Version werden beim nächsten Refresh nachgefüllt.
    static let currentHeadersVersion = 1

    /// Explizite Spaltenliste – Reihenfolge entspricht den Indizes in readMessage().
    private static let messageColumns = """
        id, accountID, accountDisplayName, uid, subject, "from", "to", date, \
        isUnread, isFlagged, isAnswered, isForwarded, totalSizeBytes, hasAttachments, \
        textBody, htmlBody, fetchedAt, \
        toJSON, ccJSON, replyToJSON, rfcMessageID, rfcInReplyTo, rfcReferences, \
        folder
        """

    private static let attachmentColumns =
        "id, messageID, filename, contentType, sizeBytes, data"

    private var db: OpaquePointer?

    private convenience init() {
        let directory: URL
        do {
            directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
        } catch {
            fatalError("App-Support-Verzeichnis nicht verfügbar: \(error)")
        }
        self.init(path: directory.appendingPathComponent("Mailwerk.sqlite").path)
    }

    /// Öffnet eine Ablage an einem bestimmten Pfad. Neben `shared` nutzen das
    /// die Tests, die mit einer eigenen Datei im Temp-Verzeichnis arbeiten.
    init(path: String) {
        // FULLMUTEX: Verbindung wird aus mehreren async-Kontexten genutzt –
        // SQLite serialisiert die Zugriffe intern.
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            fatalError("SQLite öffnen fehlgeschlagen: \(errMsg)")
        }
        exec("PRAGMA foreign_keys = ON")
        createTablesIfNeeded()
        migrateIfNeeded()
    }

    deinit { sqlite3_close(db) }

    private var errMsg: String {
        String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Schema

    private func createTablesIfNeeded() {
        // Basisschema v0.1.0 – Erweiterungen nur über migrateIfNeeded()
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
                fetchedAt REAL NOT NULL
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
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        // v0.1.1: hasAttachments
        if addColumnIfMissing("hasAttachments", "INTEGER NOT NULL DEFAULT 0") {
            // Backfill anhand der Attachment-Tabelle
            exec("""
                UPDATE message SET hasAttachments = 1
                WHERE id IN (SELECT DISTINCT messageID FROM attachment)
                """)
        }

        // v0.1.2: isFlagged
        addColumnIfMissing("isFlagged", "INTEGER NOT NULL DEFAULT 0")

        // v0.1.4: Beantwortet-/Weitergeleitet-Status, Adresslisten, Threading-Header
        addColumnIfMissing("isAnswered", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("isForwarded", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("toJSON", "TEXT")
        addColumnIfMissing("ccJSON", "TEXT")
        addColumnIfMissing("replyToJSON", "TEXT")
        addColumnIfMissing("rfcMessageID", "TEXT")
        addColumnIfMissing("rfcInReplyTo", "TEXT")
        addColumnIfMissing("rfcReferences", "TEXT")
        addColumnIfMissing("headersVersion", "INTEGER NOT NULL DEFAULT 0")

        // v0.1.5: Ordner. UIDs sind nur innerhalb eines Ordners eindeutig,
        // deshalb wandert der Ordner in die Kennung. Bestehende Zeilen
        // stammen ausnahmslos aus der INBOX.
        if addColumnIfMissing("folder", "TEXT NOT NULL DEFAULT 'INBOX'") {
            migrateIDsToFolderScheme()
        }
        exec("""
            CREATE INDEX IF NOT EXISTS idx_message_account_folder
            ON message(accountID, folder)
            """)
    }

    /// Schreibt die Kennungen von "<account>-<uid>" auf "<account>-INBOX-<uid>" um.
    /// Die Anhänge zuerst, weil ihre Fremdschlüssel sonst ins Leere zeigen.
    private func migrateIDsToFolderScheme() {
        withForeignKeysDisabled {
            exec("BEGIN TRANSACTION")
            exec("""
                UPDATE attachment SET
                    id = (SELECT m.accountID || '-INBOX-' || m.uid
                          FROM message m WHERE m.id = attachment.messageID)
                         || substr(attachment.id, length(attachment.messageID) + 1),
                    messageID = (SELECT m.accountID || '-INBOX-' || m.uid
                                 FROM message m WHERE m.id = attachment.messageID)
                WHERE EXISTS (SELECT 1 FROM message m WHERE m.id = attachment.messageID)
                """)
            exec("UPDATE message SET id = accountID || '-INBOX-' || uid")
            exec("COMMIT")
        }
    }

    /// Führt einen Block ohne Fremdschlüsselprüfung aus. Nötig, wenn sich
    /// Primärschlüssel ändern – SQLite kennt kein ON UPDATE CASCADE hier.
    /// Das Umschalten wirkt nur außerhalb einer Transaktion.
    private func withForeignKeysDisabled(_ body: () -> Void) {
        exec("PRAGMA foreign_keys = OFF")
        body()
        exec("PRAGMA foreign_keys = ON")
    }

    /// Fügt eine Spalte zur message-Tabelle hinzu, falls sie fehlt.
    /// - Returns: `true`, wenn die Spalte neu angelegt wurde.
    @discardableResult
    private func addColumnIfMissing(_ column: String, _ definition: String) -> Bool {
        guard !columnExists(column, in: "message") else { return false }
        return exec("ALTER TABLE message ADD COLUMN \(column) \(definition)")
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
            (\(Self.messageColumns), headersVersion)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                isUnread = excluded.isUnread,
                isFlagged = excluded.isFlagged,
                isAnswered = excluded.isAnswered,
                isForwarded = excluded.isForwarded,
                totalSizeBytes = excluded.totalSizeBytes,
                hasAttachments = excluded.hasAttachments,
                textBody = excluded.textBody,
                htmlBody = excluded.htmlBody,
                fetchedAt = excluded.fetchedAt,
                toJSON = excluded.toJSON,
                ccJSON = excluded.ccJSON,
                replyToJSON = excluded.replyToJSON,
                rfcMessageID = excluded.rfcMessageID,
                rfcInReplyTo = excluded.rfcInReplyTo,
                rfcReferences = excluded.rfcReferences,
                headersVersion = excluded.headersVersion
            """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, m.id)
        bind(stmt, 2, m.accountID.uuidString)
        bind(stmt, 3, m.accountDisplayName)
        sqlite3_bind_int64(stmt, 4, Int64(m.uid))
        bind(stmt, 5, m.subject)
        bind(stmt, 6, m.from)
        bind(stmt, 7, m.to)
        if let d = m.date { sqlite3_bind_double(stmt, 8, d.timeIntervalSince1970) }
        else { sqlite3_bind_null(stmt, 8) }
        sqlite3_bind_int(stmt, 9, m.isUnread ? 1 : 0)
        sqlite3_bind_int(stmt, 10, m.isFlagged ? 1 : 0)
        sqlite3_bind_int(stmt, 11, m.isAnswered ? 1 : 0)
        sqlite3_bind_int(stmt, 12, m.isForwarded ? 1 : 0)
        sqlite3_bind_int64(stmt, 13, Int64(m.totalSizeBytes))
        sqlite3_bind_int(stmt, 14, m.hasAttachments ? 1 : 0)
        bind(stmt, 15, m.textBody)
        bind(stmt, 16, m.htmlBody)
        sqlite3_bind_double(stmt, 17, m.fetchedAt.timeIntervalSince1970)
        bindHeaders(stmt, startingAt: 18, m.headers)          // 18–23
        bind(stmt, 24, m.folder)
        sqlite3_bind_int(stmt, 25, Int32(Self.currentHeadersVersion))

        sqlite3_step(stmt)
    }

    func saveMessages(_ messages: [CachedMessage]) {
        exec("BEGIN TRANSACTION")
        for m in messages { saveMessage(m) }
        exec("COMMIT")
    }

    // MARK: - Flags aktualisieren

    /// Aktualisiert nur den Gelesen-Status einer bereits gecachten Nachricht.
    /// Leichtgewichtig, ohne Risiko für Cascade-Deletes.
    func updateFlags(messageID: String, isUnread: Bool) {
        updateIntColumn("isUnread", value: isUnread, messageID: messageID)
    }

    /// Aktualisiert nur die Kennzeichnung (\Flagged) einer bereits gecachten Nachricht.
    func updateFlagged(messageID: String, isFlagged: Bool) {
        updateIntColumn("isFlagged", value: isFlagged, messageID: messageID)
    }

    /// Aktualisiert nur den Beantwortet-Status (\Answered) einer bereits gecachten Nachricht.
    func updateAnswered(messageID: String, isAnswered: Bool) {
        updateIntColumn("isAnswered", value: isAnswered, messageID: messageID)
    }

    /// Aktualisiert nur den Weitergeleitet-Status ($Forwarded) einer bereits gecachten Nachricht.
    func updateForwarded(messageID: String, isForwarded: Bool) {
        updateIntColumn("isForwarded", value: isForwarded, messageID: messageID)
    }

    /// Übernimmt alle Server-Flags in einem Statement (für den Refresh).
    func updateServerFlags(
        messageID: String,
        isUnread: Bool,
        isFlagged: Bool,
        isAnswered: Bool,
        isForwarded: Bool
    ) {
        let sql = """
            UPDATE message
            SET isUnread = ?, isFlagged = ?, isAnswered = ?, isForwarded = ?
            WHERE id = ?
            """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, isUnread ? 1 : 0)
        sqlite3_bind_int(stmt, 2, isFlagged ? 1 : 0)
        sqlite3_bind_int(stmt, 3, isAnswered ? 1 : 0)
        sqlite3_bind_int(stmt, 4, isForwarded ? 1 : 0)
        bind(stmt, 5, messageID)
        sqlite3_step(stmt)
    }

    // MARK: - Header nachfüllen

    /// IDs der Nachrichten eines Kontos, deren Header noch nicht dem
    /// aktuellen Stand (`currentHeadersVersion`) entsprechen.
    func messageIDsNeedingHeaders(forAccount accountID: UUID, folder: String) -> Set<String> {
        let sql = """
            SELECT id FROM message
            WHERE accountID = ? AND folder = ? AND headersVersion < ?
            """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        sqlite3_bind_int(stmt, 3, Int32(Self.currentHeadersVersion))
        var ids = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.insert(str(stmt, 0))
        }
        return ids
    }

    /// Schreibt Adress-/Threading-Header und setzt die Header-Version.
    func updateHeaders(messageID: String, headers: CachedMessageHeaders) {
        let sql = """
            UPDATE message SET
                toJSON = ?, ccJSON = ?, replyToJSON = ?,
                rfcMessageID = ?, rfcInReplyTo = ?, rfcReferences = ?,
                headersVersion = ?
            WHERE id = ?
            """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bindHeaders(stmt, startingAt: 1, headers)             // 1–6
        sqlite3_bind_int(stmt, 7, Int32(Self.currentHeadersVersion))
        bind(stmt, 8, messageID)
        sqlite3_step(stmt)
    }

    // MARK: - Anhänge speichern

    func saveAttachment(_ a: CachedAttachment) {
        let sql = """
            INSERT INTO attachment
            (\(Self.attachmentColumns))
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
        sqlite3_bind_int64(stmt, 5, Int64(a.sizeBytes))
        if let data = a.data {
            _ = data.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 6, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
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
        let sql = "SELECT \(Self.messageColumns) FROM message WHERE id = ? LIMIT 1"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readMessage(stmt)
    }

    func allMessages(accountIDs: [UUID], folder: String) -> [CachedMessage] {
        guard !accountIDs.isEmpty else { return [] }
        let ph = accountIDs.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT \(Self.messageColumns) FROM message
            WHERE accountID IN (\(ph)) AND folder = ? ORDER BY date DESC
            """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in accountIDs.enumerated() {
            bind(stmt, Int32(i + 1), id.uuidString)
        }
        bind(stmt, Int32(accountIDs.count + 1), folder)
        var result: [CachedMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(readMessage(stmt))
        }
        return result
    }

    func cachedMessageIDs(forAccount accountID: UUID, folder: String) -> Set<String> {
        let sql = "SELECT id FROM message WHERE accountID = ? AND folder = ?"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        var ids = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.insert(str(stmt, 0))
        }
        return ids
    }

    func attachments(forMessage messageID: String) -> [CachedAttachment] {
        let sql = "SELECT \(Self.attachmentColumns) FROM attachment WHERE messageID = ?"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, messageID)
        var result: [CachedAttachment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(readAttachment(stmt))
        }
        return result
    }

    // MARK: - Löschen (für Cache-Bereinigung)

    func deleteMessagesOlderThan(_ date: Date, forAccount accountID: UUID, folder: String) {
        let sql = "DELETE FROM message WHERE accountID = ? AND folder = ? AND date < ?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    /// Entfernt eine einzelne Nachricht (und über ON DELETE CASCADE
    /// automatisch ihre Anhänge) aus dem Cache. Wird nach erfolgreichem
    /// serverseitigem Löschen/Verschieben aufgerufen.
    func deleteMessage(id: String) {
        let sql = "DELETE FROM message WHERE id = ?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        sqlite3_step(stmt)
    }

    // MARK: - Verschieben

    /// Zieht eine gecachte Nachricht in einen anderen Ordner um, nachdem der
    /// Server sie verschoben hat. Kennung und UID ändern sich dabei, die
    /// Anhänge ziehen mit – deshalb läuft alles in einer Transaktion.
    ///
    /// - Parameter newUID: die vom Server gemeldete UID im Zielordner.
    /// - Returns: die neue Kennung, oder nil wenn die Nachricht nicht im Cache lag.
    @discardableResult
    func relocateMessage(id: String, toFolder folder: String, newUID: UInt32) -> String? {
        guard let existing = message(id: id) else { return nil }
        let newID = CachedMessage.makeID(
            accountID: existing.accountID, folder: folder, uid: newUID
        )
        guard newID != id else { return newID }

        withForeignKeysDisabled {
            exec("BEGIN TRANSACTION")

            // Anhänge zuerst: ihre Kennung beginnt mit der Nachrichten-Kennung.
            if let stmt = prepare("""
                UPDATE attachment
                SET id = ? || substr(id, length(messageID) + 1), messageID = ?
                WHERE messageID = ?
                """) {
                bind(stmt, 1, newID)
                bind(stmt, 2, newID)
                bind(stmt, 3, id)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            if let stmt = prepare("UPDATE message SET id = ?, folder = ?, uid = ? WHERE id = ?") {
                bind(stmt, 1, newID)
                bind(stmt, 2, folder)
                sqlite3_bind_int64(stmt, 3, Int64(newUID))
                bind(stmt, 4, id)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            exec("COMMIT")
        }
        return newID
    }

    // MARK: - Interne Helfer

    /// Liest eine Zeile gemäß `messageColumns` (Indizes 0–23).
    private func readMessage(_ s: OpaquePointer?) -> CachedMessage {
        let dateVal = sqlite3_column_type(s, 7) != SQLITE_NULL
            ? sqlite3_column_double(s, 7) : nil
        let headers = CachedMessageHeaders(
            toList: decodeList(optStr(s, 17)),
            ccList: decodeList(optStr(s, 18)),
            replyToList: decodeList(optStr(s, 19)),
            rfcMessageID: optStr(s, 20),
            rfcInReplyTo: optStr(s, 21),
            rfcReferences: optStr(s, 22)
        )
        return CachedMessage(
            id: str(s, 0),
            accountID: UUID(uuidString: str(s, 1)) ?? UUID(),
            accountDisplayName: str(s, 2),
            folder: str(s, 23),
            uid: UInt32(truncatingIfNeeded: sqlite3_column_int64(s, 3)),
            subject: str(s, 4),
            from: str(s, 5),
            to: str(s, 6),
            date: dateVal.map { Date(timeIntervalSince1970: $0) },
            isUnread: sqlite3_column_int(s, 8) != 0,
            isFlagged: sqlite3_column_int(s, 9) != 0,
            isAnswered: sqlite3_column_int(s, 10) != 0,
            isForwarded: sqlite3_column_int(s, 11) != 0,
            totalSizeBytes: Int(sqlite3_column_int64(s, 12)),
            hasAttachments: sqlite3_column_int(s, 13) != 0,
            textBody: optStr(s, 14),
            htmlBody: optStr(s, 15),
            fetchedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 16)),
            headers: headers
        )
    }

    /// Liest eine Zeile gemäß `attachmentColumns` (Indizes 0–5).
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
            sizeBytes: Int(sqlite3_column_int64(s, 4)),
            data: data
        )
    }

    /// Bindet die sechs Header-Felder ab `startingAt` in der Reihenfolge:
    /// toJSON, ccJSON, replyToJSON, rfcMessageID, rfcInReplyTo, rfcReferences.
    private func bindHeaders(_ s: OpaquePointer?, startingAt i: Int32, _ h: CachedMessageHeaders) {
        bind(s, i,     encodeList(h.toList))
        bind(s, i + 1, encodeList(h.ccList))
        bind(s, i + 2, encodeList(h.replyToList))
        bind(s, i + 3, h.rfcMessageID)
        bind(s, i + 4, h.rfcInReplyTo)
        bind(s, i + 5, h.rfcReferences)
    }

    private func updateIntColumn(_ column: String, value: Bool, messageID: String) {
        let sql = "UPDATE message SET \(column) = ? WHERE id = ?"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, value ? 1 : 0)
        bind(stmt, 2, messageID)
        sqlite3_step(stmt)
    }

    private func encodeList(_ list: [String]) -> String? {
        guard !list.isEmpty,
              let data = try? JSONEncoder().encode(list) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeList(_ json: String?) -> [String] {
        guard let json,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
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
        if let v { sqlite3_bind_text(s, i, v, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(s, i) }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("🗄️ SQL-Fehler: \(errMsg) – \(sql.prefix(80))")
            return nil
        }
        return stmt
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        let ok = sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
        if !ok { print("🗄️ SQL-Fehler: \(errMsg) – \(sql.prefix(80))") }
        return ok
    }
}
