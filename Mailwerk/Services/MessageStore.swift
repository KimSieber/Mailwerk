//
//  MessageStore.swift
//  Mailwerk
//
//  Zweck: Lokale SQLite-Ablage für Nachrichten, Anhänge und den Stand
//  je Ordner (letzter Abruf mit Sync-Zustand, Zeitfenster, Ordnerliste).
//
//  Nutzt das auf jeder Apple-Plattform mitgelieferte System-SQLite.
//  Die Verbindung arbeitet im WAL-Modus und wird mit
//  `SQLITE_OPEN_FULLMUTEX` geöffnet; SQLite serialisiert die Zugriffe
//  damit intern.
//
//  Speicherort: Unterordner `Cache` im Application-Support-Verzeichnis.
//  Der Ordner ist vom Geräte-Backup ausgeschlossen – sein Inhalt lässt
//  sich jederzeit vom Server neu laden.
//
//  Start ohne Absturz: Meldet SQLite die Datei ausdrücklich als
//  beschädigt oder als keine Datenbank, werden Datei und Begleitdateien
//  gelöscht und neu angelegt. Andere Fehler beim Öffnen (z. B. Speicher
//  voll) löschen nichts; die App arbeitet dann in dieser Sitzung mit
//  einer Ablage im Arbeitsspeicher. In beiden Fällen liegt für die
//  Oberfläche ein Hinweis bereit (`consumeStartupNotice()`).
//
//  Schema: `createTablesIfNeeded()` legt nur das Basisschema an, alle
//  späteren Spalten und Tabellen kommen über `migrateIfNeeded()`.
//  `PRAGMA user_version` hält die erreichte Schema-Version; jede
//  Migrationsstufe läuft genau einmal.
//
//  Schreiben: Alle Schreibzugriffe laufen über `execute(_:context:bind:)`,
//  das das Ergebnis von `sqlite3_step` prüft und bei einem Fehler wirft.
//  Mehrteilige Schreibvorgänge laufen in `transaction(_:)` und werden
//  bei einem Fehler vollständig zurückgerollt. Die öffentlichen
//  Schreibfunktionen werfen nicht; sie protokollieren Fehler und melden
//  – wo der Aufrufer es braucht – Erfolg über den Rückgabewert.
//
//  Abgrenzung: Der Store kennt weder IMAP noch Oberfläche. Abruf und
//  Darstellung liegen im MailFetchService bzw. in den ViewModels.
//
//  Abhängigkeiten: SQLite3 (System-Framework), CachedMessage,
//  CachedAttachment, FolderListing, ServerReconciliation (Plan-Typ),
//  FolderSyncState.
//

import Foundation
import SQLite3

/// SQLite soll übergebene Texte/Blobs selbst kopieren (SQLITE_TRANSIENT = -1).
/// Das C-Makro ist in Swift nicht verfügbar, daher hier nachgebildet.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Fehler beim Schreiben in die Ablage.
nonisolated enum StoreError: Error, CustomStringConvertible {
    /// Ein SQL-Befehl ließ sich nicht vorbereiten.
    case prepare(context: String, message: String)
    /// Ein vorbereiteter Befehl lieferte nicht `SQLITE_DONE`.
    case step(context: String, code: Int32, message: String)
    /// Ein direkt ausgeführter Befehl (z. B. BEGIN, COMMIT) schlug fehl.
    case exec(sql: String, message: String)

    /// Lesbare Beschreibung für die Protokollausgabe.
    ///
    /// - Returns: Fehlerart, Kontext und Meldung von SQLite.
    var description: String {
        switch self {
        case .prepare(let context, let message):
            return "prepare fehlgeschlagen (\(context)): \(message)"
        case .step(let context, let code, let message):
            return "step fehlgeschlagen (\(context)): \(code) – \(message)"
        case .exec(let sql, let message):
            return "exec fehlgeschlagen (\(sql)): \(message)"
        }
    }
}

/// Hinweis an die Oberfläche über Besonderheiten beim Öffnen der Ablage.
nonisolated enum StoreStartupNotice: Equatable {
    /// Die Datenbank war beschädigt und wurde gelöscht und neu angelegt.
    case rebuiltAfterCorruption
    /// Die Datenbank konnte nicht geöffnet werden; die App arbeitet in
    /// dieser Sitzung mit einer Ablage im Arbeitsspeicher.
    case unavailable

    /// Titel der Meldung.
    var title: String {
        switch self {
        case .rebuiltAfterCorruption: return "Lokaler Mail-Speicher neu angelegt"
        case .unavailable: return "Lokaler Mail-Speicher nicht verfügbar"
        }
    }

    /// Text der Meldung.
    var message: String {
        switch self {
        case .rebuiltAfterCorruption:
            return "Der lokale Speicher von Mailwerk war beschädigt und wurde neu angelegt. Deine Mails liegen weiterhin vollständig auf dem Server. Sie werden jetzt neu geladen; das kann beim ersten Abruf etwas länger dauern."
        case .unavailable:
            return "Mailwerk konnte seinen lokalen Speicher nicht öffnen, zum Beispiel weil der Gerätespeicher voll ist. Deine Mails liegen weiterhin vollständig auf dem Server. In dieser Sitzung werden sie nur vorübergehend gehalten; beim nächsten Start wird es erneut versucht."
        }
    }
}

/// Lokale SQLite-Ablage für Nachrichten und Anhänge.
final class MessageStore: @unchecked Sendable {
    /// Gemeinsame Ablage der App.
    static let shared = MessageStore()

    /// Version der gespeicherten Adress-/Threading-Header. Nachrichten mit
    /// kleinerer Version werden beim nächsten Refresh nachgefüllt.
    static let currentHeadersVersion = 1

    /// Schema-Version, die diese App-Version erwartet. Wird nach den
    /// Migrationen in `PRAGMA user_version` geschrieben.
    private static let schemaVersion: Int32 = 2

    /// Explizite Spaltenliste – Reihenfolge entspricht den Indizes in readMessage().
    private static let messageColumns = """
        id, accountID, accountDisplayName, uid, subject, "from", "to", date, \
        isUnread, isFlagged, isAnswered, isForwarded, totalSizeBytes, hasAttachments, \
        textBody, htmlBody, fetchedAt, \
        toJSON, ccJSON, replyToJSON, rfcMessageID, rfcInReplyTo, rfcReferences, \
        folder
        """

    /// Spaltenliste der Anhänge – Reihenfolge entspricht readAttachment().
    private static let attachmentColumns =
        "id, messageID, filename, contentType, sizeBytes, data"

    /// Name des Unterordners für die Ablage im Application-Support-Verzeichnis.
    static let cacheDirectoryName = "Cache"

    /// Dateiname der Datenbank.
    static let databaseFileName = "Mailwerk.sqlite"

    /// Handle der geöffneten Datenbank.
    private var db: OpaquePointer?

    /// Hinweis für die Oberfläche, solange er nicht abgeholt wurde.
    private var startupNotice: StoreStartupNotice?

    /// Ergebnis eines Öffnungsversuchs.
    private enum OpenResult {
        /// Geöffnet und lesbar.
        case opened(OpaquePointer)
        /// SQLite meldet die Datei als beschädigt oder als keine Datenbank.
        case corrupt(code: Int32, message: String)
        /// Anderer Fehler (z. B. Speicher voll, keine Berechtigung).
        case failed(code: Int32, message: String)
    }

    /// Öffnet die Ablage der App.
    ///
    /// Verarbeitung: Legt den Unterordner `Cache` im Application-Support-
    /// Verzeichnis an, schließt ihn vom Backup aus und öffnet dort die
    /// Datenbank. Steht das Verzeichnis nicht zur Verfügung, arbeitet die
    /// Ablage im Arbeitsspeicher und meldet `unavailable`.
    private convenience init() {
        let path: String?
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let directory = try Self.prepareCacheDirectory(in: base)
            path = directory.appendingPathComponent(Self.databaseFileName).path
        } catch {
            print("🗄️ Verzeichnis für die Ablage nicht verfügbar: \(error)")
            path = nil
        }
        self.init(path: path)
    }

    /// Öffnet eine Ablage an einem bestimmten Pfad.
    ///
    /// Verarbeitung: Öffnet die Datenbank und prüft mit einem ersten
    /// Lesezugriff, ob sie lesbar ist.
    /// - Beschädigt oder keine Datenbank: Datei und Begleitdateien werden
    ///   gelöscht und neu angelegt; Hinweis `rebuiltAfterCorruption`.
    /// - Anderer Fehler: Es wird nichts gelöscht; die Ablage arbeitet im
    ///   Arbeitsspeicher; Hinweis `unavailable`.
    /// Danach werden WAL-Modus und Fremdschlüssel eingeschaltet, das
    /// Basisschema angelegt und ausstehende Migrationen ausgeführt.
    /// Neben `shared` nutzen das die Tests mit eigenen Dateien.
    ///
    /// - Parameter path: Dateipfad der SQLite-Datenbank; `nil` = nur im
    ///   Arbeitsspeicher (Hinweis `unavailable`).
    init(path: String?) {
        if let path {
            switch Self.open(path) {
            case .opened(let handle):
                db = handle

            case .corrupt(let code, let message):
                print("🗄️ Datenbank beschädigt (\(code): \(message)) → wird gelöscht und neu angelegt")
                Self.removeDatabaseFiles(at: path)
                if case .opened(let handle) = Self.open(path) {
                    db = handle
                    startupNotice = .rebuiltAfterCorruption
                } else {
                    print("🗄️ Neuanlage fehlgeschlagen → Ablage im Arbeitsspeicher")
                    db = Self.openInMemory()
                    startupNotice = .unavailable
                }

            case .failed(let code, let message):
                print("🗄️ Datenbank nicht zu öffnen (\(code): \(message)) → Ablage im Arbeitsspeicher, nichts gelöscht")
                db = Self.openInMemory()
                startupNotice = .unavailable
            }
        } else {
            db = Self.openInMemory()
            startupNotice = .unavailable
        }

        exec("PRAGMA journal_mode = WAL")
        exec("PRAGMA foreign_keys = ON")
        createTablesIfNeeded()
        migrateIfNeeded()
    }

    /// Liefert den Hinweis für die Oberfläche genau einmal.
    ///
    /// Verarbeitung: Gibt einen anstehenden Hinweis zurück und löscht ihn,
    /// damit die Meldung nur einmal erscheint.
    ///
    /// - Returns: Der Hinweis oder `nil`, wenn das Öffnen normal verlief.
    func consumeStartupNotice() -> StoreStartupNotice? {
        defer { startupNotice = nil }
        return startupNotice
    }

    // MARK: - Öffnen und Wiederherstellen

    /// Legt den Unterordner der Ablage an und schließt ihn vom Backup aus.
    ///
    /// Verarbeitung: Der Ausschluss gilt für den ganzen Ordner und damit
    /// auch für die WAL-Begleitdateien, die SQLite selbst anlegt.
    ///
    /// - Parameter base: Übergeordnetes Verzeichnis (Application Support).
    /// - Returns: URL des Unterordners.
    /// - Throws: Fehler des Dateisystems.
    static func prepareCacheDirectory(in base: URL) throws -> URL {
        var directory = base.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }

    /// Öffnet eine Datenbankdatei und prüft, ob sie lesbar ist.
    ///
    /// Verarbeitung: SQLite öffnet auch defekte Dateien zunächst ohne
    /// Fehler; der Defekt zeigt sich erst beim ersten Lesen. Deshalb wird
    /// nach dem Öffnen `sqlite_master` gelesen. Als beschädigt gilt die
    /// Datei nur bei `SQLITE_CORRUPT` oder `SQLITE_NOTADB`; jeder andere
    /// Fehler gilt als `failed`. Bei einem Fehler wird das Handle
    /// geschlossen.
    ///
    /// - Parameter path: Dateipfad der Datenbank.
    /// - Returns: Ergebnis des Versuchs.
    private static func open(_ path: String) -> OpenResult {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openCode = sqlite3_open_v2(path, &handle, flags, nil)
        guard openCode == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "kein Handle"
            sqlite3_close(handle)
            return classify(openCode, message: message)
        }

        // Erster Lesezugriff deckt einen Defekt auf.
        var stmt: OpaquePointer?
        var code = sqlite3_prepare_v2(handle, "SELECT count(*) FROM sqlite_master", -1, &stmt, nil)
        if code == SQLITE_OK {
            code = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        guard code == SQLITE_OK || code == SQLITE_ROW || code == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            return classify(code, message: message)
        }
        return .opened(handle)
    }

    /// Ordnet einen SQLite-Fehlercode ein.
    ///
    /// - Parameters:
    ///   - code: Fehlercode (auch erweiterte Codes; ausgewertet wird der
    ///     primäre Teil).
    ///   - message: Meldung von SQLite.
    /// - Returns: `corrupt` bei `SQLITE_CORRUPT`/`SQLITE_NOTADB`, sonst `failed`.
    private static func classify(_ code: Int32, message: String) -> OpenResult {
        switch code & 0xFF {
        case SQLITE_CORRUPT, SQLITE_NOTADB:
            return .corrupt(code: code, message: message)
        default:
            return .failed(code: code, message: message)
        }
    }

    /// Löscht die Datenbank samt WAL-Begleitdateien.
    ///
    /// Verarbeitung: Entfernt `<pfad>`, `<pfad>-wal` und `<pfad>-shm`.
    /// Eine liegengebliebene WAL-Datei würde SQLite sonst auf die neue
    /// Datenbank anzuwenden versuchen. Fehlende Dateien sind kein Fehler.
    ///
    /// - Parameter path: Dateipfad der Datenbank.
    static func removeDatabaseFiles(at path: String) {
        for suffix in ["", "-wal", "-shm"] {
            let file = path + suffix
            guard FileManager.default.fileExists(atPath: file) else { continue }
            do {
                try FileManager.default.removeItem(atPath: file)
            } catch {
                print("🗄️ Löschen fehlgeschlagen (\(file)): \(error)")
            }
        }
    }

    /// Öffnet eine Datenbank nur im Arbeitsspeicher.
    ///
    /// Verarbeitung: Rückfallebene, damit die App ohne Datei weiterläuft.
    /// Der Inhalt geht beim Beenden verloren.
    ///
    /// - Returns: Handle oder `nil`, falls selbst das scheitert (dann
    ///   protokollieren alle Zugriffe nur Fehler).
    private static func openInMemory() -> OpaquePointer? {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_MEMORY
        guard sqlite3_open_v2(":memory:", &handle, flags, nil) == SQLITE_OK else {
            print("🗄️ Ablage im Arbeitsspeicher nicht möglich")
            sqlite3_close(handle)
            return nil
        }
        return handle
    }

    /// Schließt die Datenbank.
    deinit { sqlite3_close(db) }

    /// Letzte Fehlermeldung der Datenbank.
    private var errMsg: String {
        String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Schema

    /// Legt das Basisschema an, falls es fehlt.
    ///
    /// Verarbeitung: Nur die Tabellen des ersten Standes. Alle späteren
    /// Ergänzungen kommen ausschließlich über `migrateIfNeeded()`, damit
    /// die Struktur auf Neu- und Bestandsinstallationen identisch ist.
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

    /// Führt die ausstehenden Migrationsstufen aus.
    ///
    /// Verarbeitung: Liest `PRAGMA user_version`. Jede Stufe läuft nur,
    /// wenn die gespeicherte Version darunter liegt. Stufe 1 fasst alle
    /// bisherigen Erweiterungen zusammen; sie ist idempotent, weil
    /// Bestandsdatenbanken vor Einführung von `user_version` bereits
    /// einzelne Teile enthalten können. Am Ende wird die erreichte
    /// Version gespeichert. Neue Stufen werden als weiterer
    /// `if current < n`-Block ergänzt.
    private func migrateIfNeeded() {
        let current = userVersion()
        guard current < Self.schemaVersion else { return }

        if current < 1 {
            migrateToVersion1()
        }
        if current < 2 {
            migrateToVersion2()
        }

        setUserVersion(Self.schemaVersion)
    }

    /// Stufe 1: alle Erweiterungen bis einschließlich v0.1.9a.
    ///
    /// Verarbeitung: Ergänzt fehlende Spalten, schreibt bei Bedarf die
    /// Kennungen auf das Ordner-Schema um und legt Index und Zusatz-
    /// tabellen an. Jeder Teil prüft selbst, ob er schon vorhanden ist.
    private func migrateToVersion1() {
        // hasAttachments – mit Nachtrag aus der Anhang-Tabelle
        if addColumnIfMissing("hasAttachments", "INTEGER NOT NULL DEFAULT 0") {
            exec("""
                UPDATE message SET hasAttachments = 1
                WHERE id IN (SELECT DISTINCT messageID FROM attachment)
                """)
        }

        // Kennzeichnung
        addColumnIfMissing("isFlagged", "INTEGER NOT NULL DEFAULT 0")

        // Beantwortet-/Weitergeleitet-Status, Adresslisten, Threading-Header
        addColumnIfMissing("isAnswered", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("isForwarded", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("toJSON", "TEXT")
        addColumnIfMissing("ccJSON", "TEXT")
        addColumnIfMissing("replyToJSON", "TEXT")
        addColumnIfMissing("rfcMessageID", "TEXT")
        addColumnIfMissing("rfcInReplyTo", "TEXT")
        addColumnIfMissing("rfcReferences", "TEXT")
        addColumnIfMissing("headersVersion", "INTEGER NOT NULL DEFAULT 0")

        // Ordner. UIDs sind nur innerhalb eines Ordners eindeutig, deshalb
        // wandert der Ordner in die Kennung. Bestehende Zeilen stammen
        // ausnahmslos aus der INBOX.
        if addColumnIfMissing("folder", "TEXT NOT NULL DEFAULT 'INBOX'") {
            migrateIDsToFolderScheme()
        }
        exec("""
            CREATE INDEX IF NOT EXISTS idx_message_account_folder
            ON message(accountID, folder)
            """)

        // Stand je Ordner. Eigene Tabelle, weil auch leere Ordner einen
        // Stand haben.
        exec("""
            CREATE TABLE IF NOT EXISTS folder_sync (
                accountID TEXT NOT NULL,
                folder TEXT NOT NULL,
                lastSyncAt REAL NOT NULL,
                PRIMARY KEY (accountID, folder)
            )
            """)

        // Erweitertes Zeitfenster je Ordner („Ältere laden“).
        exec("""
            CREATE TABLE IF NOT EXISTS folder_window (
                accountID TEXT NOT NULL,
                folder TEXT NOT NULL,
                windowStart REAL NOT NULL,
                PRIMARY KEY (accountID, folder)
            )
            """)

        // Ordnerliste je Postfach (JSON), damit die Seitenleiste auch
        // offline ihre Ordner zeigt.
        exec("""
            CREATE TABLE IF NOT EXISTS folder_listing (
                accountID TEXT PRIMARY KEY,
                json TEXT NOT NULL,
                savedAt REAL NOT NULL
            )
            """)
    }

    /// Stufe 2: Sync-Zustand je Ordner (UIDVALIDITY und UIDNEXT).
    ///
    /// Verarbeitung: Ergänzt `folder_sync` um zwei Spalten. Bestehende
    /// Zeilen erhalten NULL; das gilt als „noch kein Zustand“, der nächste
    /// Abruf des Ordners legt ihn an.
    private func migrateToVersion2() {
        addColumnIfMissing("uidValidity", "INTEGER", in: "folder_sync")
        addColumnIfMissing("uidNext", "INTEGER", in: "folder_sync")
    }

    /// Schreibt die Kennungen von "<account>-<uid>" auf "<account>-INBOX-<uid>" um.
    ///
    /// Verarbeitung: Die Anhänge zuerst, weil ihre Fremdschlüssel sonst
    /// ins Leere zeigen. Läuft ohne Fremdschlüsselprüfung in einer
    /// Transaktion; bei einem Fehler bleibt der alte Stand erhalten.
    private func migrateIDsToFolderScheme() {
        withForeignKeysDisabled {
            logged("Migration Ordner-Schema") {
                try transaction {
                    try execute("""
                        UPDATE attachment SET
                            id = (SELECT m.accountID || '-INBOX-' || m.uid
                                  FROM message m WHERE m.id = attachment.messageID)
                                 || substr(attachment.id, length(attachment.messageID) + 1),
                            messageID = (SELECT m.accountID || '-INBOX-' || m.uid
                                         FROM message m WHERE m.id = attachment.messageID)
                        WHERE EXISTS (SELECT 1 FROM message m WHERE m.id = attachment.messageID)
                        """, context: "Migration Anhänge")
                    try execute(
                        "UPDATE message SET id = accountID || '-INBOX-' || uid",
                        context: "Migration Nachrichten"
                    )
                }
            }
        }
    }

    /// Liest die gespeicherte Schema-Version.
    ///
    /// - Returns: Wert von `PRAGMA user_version` (0 bei neuer oder alter Datenbank).
    private func userVersion() -> Int32 {
        guard let stmt = prepare("PRAGMA user_version") else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int(stmt, 0) : 0
    }

    /// Speichert die erreichte Schema-Version.
    ///
    /// - Parameter version: Neue Schema-Version.
    private func setUserVersion(_ version: Int32) {
        exec("PRAGMA user_version = \(version)")
    }

    /// Fügt einer Tabelle eine Spalte hinzu, falls sie fehlt.
    ///
    /// - Parameters:
    ///   - column: Spaltenname.
    ///   - definition: Typ und Einschränkungen der Spalte.
    ///   - table: Tabellenname (Standard: `message`).
    /// - Returns: `true`, wenn die Spalte neu angelegt wurde.
    @discardableResult
    private func addColumnIfMissing(_ column: String, _ definition: String, in table: String = "message") -> Bool {
        guard !columnExists(column, in: table) else { return false }
        return exec("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    /// Prüft, ob eine Spalte in einer Tabelle existiert.
    ///
    /// - Parameters:
    ///   - column: Spaltenname.
    ///   - table: Tabellenname.
    /// - Returns: `true`, wenn die Spalte vorhanden ist.
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
    ///
    /// Verarbeitung: Schreibt über `insertMessage`. Ein Fehler wird
    /// protokolliert, nicht geworfen. Für Nachricht samt Anhängen
    /// `saveMessageWithAttachments` verwenden.
    ///
    /// - Parameter m: Zu speichernde Nachricht.
    func saveMessage(_ m: CachedMessage) {
        logged("saveMessage \(m.id)") { try insertMessage(m) }
    }

    /// Speichert eine Nachricht und ihre Anhänge in einer Transaktion.
    ///
    /// Verarbeitung: Nachricht und alle Anhänge werden gemeinsam
    /// geschrieben. Schlägt ein Teil fehl, wird alles zurückgerollt –
    /// es entsteht weder eine Nachricht ohne ihre Anhänge noch ein
    /// verwaister Anhang.
    ///
    /// - Parameters:
    ///   - message: Zu speichernde Nachricht.
    ///   - attachments: Zugehörige Anhänge (mit oder ohne Daten).
    /// - Returns: `true`, wenn alles gespeichert wurde; `false` nach Rollback.
    @discardableResult
    func saveMessageWithAttachments(_ message: CachedMessage, attachments: [CachedAttachment]) -> Bool {
        logged("saveMessageWithAttachments \(message.id)") {
            try transaction {
                try insertMessage(message)
                for attachment in attachments {
                    try insertAttachment(attachment)
                }
            }
        }
    }

    /// Schreibt eine Nachricht per UPSERT.
    ///
    /// Verarbeitung: `ON CONFLICT … DO UPDATE` statt `INSERT OR REPLACE`,
    /// weil letzteres intern DELETE + INSERT ist und damit über
    /// ON DELETE CASCADE die Anhänge löschen würde.
    ///
    /// - Parameter m: Zu speichernde Nachricht.
    /// - Throws: `StoreError`, wenn das Schreiben fehlschlägt.
    private func insertMessage(_ m: CachedMessage) throws {
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
        try execute(sql, context: "insertMessage \(m.id)") { stmt in
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
        }
    }

    // MARK: - Flags aktualisieren

    /// Aktualisiert nur den Gelesen-Status einer gecachten Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isUnread: `true` = ungelesen.
    func updateFlags(messageID: String, isUnread: Bool) {
        updateIntColumn("isUnread", value: isUnread, messageID: messageID)
    }

    /// Aktualisiert nur die Kennzeichnung (\Flagged) einer gecachten Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isFlagged: `true` = gekennzeichnet.
    func updateFlagged(messageID: String, isFlagged: Bool) {
        updateIntColumn("isFlagged", value: isFlagged, messageID: messageID)
    }

    /// Aktualisiert nur den Beantwortet-Status (\Answered) einer gecachten Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isAnswered: `true` = beantwortet.
    func updateAnswered(messageID: String, isAnswered: Bool) {
        updateIntColumn("isAnswered", value: isAnswered, messageID: messageID)
    }

    /// Aktualisiert nur den Weitergeleitet-Status ($Forwarded) einer gecachten Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isForwarded: `true` = weitergeleitet.
    func updateForwarded(messageID: String, isForwarded: Bool) {
        updateIntColumn("isForwarded", value: isForwarded, messageID: messageID)
    }

    /// Übernimmt alle Server-Flags einer Nachricht in einem Statement.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isUnread: `true` = ungelesen.
    ///   - isFlagged: `true` = gekennzeichnet.
    ///   - isAnswered: `true` = beantwortet.
    ///   - isForwarded: `true` = weitergeleitet.
    func updateServerFlags(
        messageID: String,
        isUnread: Bool,
        isFlagged: Bool,
        isAnswered: Bool,
        isForwarded: Bool
    ) {
        logged("updateServerFlags \(messageID)") {
            try writeServerFlags(
                messageID: messageID, isUnread: isUnread, isFlagged: isFlagged,
                isAnswered: isAnswered, isForwarded: isForwarded
            )
        }
    }

    /// Schreibt alle Server-Flags einer Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isUnread: `true` = ungelesen.
    ///   - isFlagged: `true` = gekennzeichnet.
    ///   - isAnswered: `true` = beantwortet.
    ///   - isForwarded: `true` = weitergeleitet.
    /// - Throws: `StoreError`, wenn das Schreiben fehlschlägt.
    private func writeServerFlags(
        messageID: String,
        isUnread: Bool,
        isFlagged: Bool,
        isAnswered: Bool,
        isForwarded: Bool
    ) throws {
        let sql = """
            UPDATE message
            SET isUnread = ?, isFlagged = ?, isAnswered = ?, isForwarded = ?
            WHERE id = ?
            """
        try execute(sql, context: "writeServerFlags \(messageID)") { stmt in
            sqlite3_bind_int(stmt, 1, isUnread ? 1 : 0)
            sqlite3_bind_int(stmt, 2, isFlagged ? 1 : 0)
            sqlite3_bind_int(stmt, 3, isAnswered ? 1 : 0)
            sqlite3_bind_int(stmt, 4, isForwarded ? 1 : 0)
            bind(stmt, 5, messageID)
        }
    }

    // MARK: - Server-Abgleich

    /// Flags der gecachten Mails eines Ordners ab einem Datum.
    ///
    /// Verarbeitung: Grundlage für den Vergleich mit dem Server.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    ///   - since: Untergrenze für das Nachrichtendatum.
    /// - Returns: Flag-Zustände der gecachten Mails.
    func cachedFlagStates(accountID: UUID, folder: String, since: Date) -> [CachedFlagState] {
        flagStates(
            sql: """
                SELECT id, uid, isUnread, isFlagged, isAnswered, isForwarded FROM message
                WHERE accountID = ? AND folder = ? AND date >= ?
                """,
            accountID: accountID, folder: folder, date: since
        )
    }

    /// Liest Flag-Zustände mit einer Abfrage, die Postfach, Ordner und
    /// Datum (in dieser Reihenfolge) als Parameter erwartet.
    ///
    /// - Parameters:
    ///   - sql: Abfrage mit drei Platzhaltern.
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    ///   - date: Datumsgrenze.
    /// - Returns: Gelesene Flag-Zustände.
    private func flagStates(sql: String, accountID: UUID, folder: String, date: Date) -> [CachedFlagState] {
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
        var result: [CachedFlagState] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(CachedFlagState(
                id: str(stmt, 0),
                uid: UInt32(sqlite3_column_int64(stmt, 1)),
                isUnread: sqlite3_column_int(stmt, 2) == 1,
                isFlagged: sqlite3_column_int(stmt, 3) == 1,
                isAnswered: sqlite3_column_int(stmt, 4) == 1,
                isForwarded: sqlite3_column_int(stmt, 5) == 1
            ))
        }
        return result
    }

    /// Wendet einen Abgleichsplan an.
    ///
    /// Verarbeitung: Entfernt gelöschte Mails und schreibt geänderte Flags
    /// in einer Transaktion. Schlägt ein Teil fehl, bleibt der Cache
    /// unverändert; der nächste Abgleich versucht es erneut.
    ///
    /// - Parameter plan: Änderungsplan aus `ServerReconciliation`.
    func apply(_ plan: ServerReconciliation.Plan) {
        guard !plan.isEmpty else { return }
        logged("apply Abgleichsplan") {
            try transaction {
                for id in plan.removedIDs {
                    try removeMessage(id: id)
                }
                for state in plan.flagUpdates {
                    try writeServerFlags(
                        messageID: state.id,
                        isUnread: state.isUnread,
                        isFlagged: state.isFlagged,
                        isAnswered: state.isAnswered,
                        isForwarded: state.isForwarded
                    )
                }
            }
        }
    }

    // MARK: - Header nachfüllen

    /// IDs der Nachrichten eines Ordners, deren Header nicht aktuell sind.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Cache-IDs mit `headersVersion` unter `currentHeadersVersion`.
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
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - headers: Aufbereitete Header.
    func updateHeaders(messageID: String, headers: CachedMessageHeaders) {
        let sql = """
            UPDATE message SET
                toJSON = ?, ccJSON = ?, replyToJSON = ?,
                rfcMessageID = ?, rfcInReplyTo = ?, rfcReferences = ?,
                headersVersion = ?
            WHERE id = ?
            """
        logged("updateHeaders \(messageID)") {
            try execute(sql, context: "updateHeaders \(messageID)") { stmt in
                bindHeaders(stmt, startingAt: 1, headers)             // 1–6
                sqlite3_bind_int(stmt, 7, Int32(Self.currentHeadersVersion))
                bind(stmt, 8, messageID)
            }
        }
    }

    // MARK: - Anhänge speichern

    /// Speichert oder aktualisiert einen Anhang.
    ///
    /// Verarbeitung: Schreibt über `insertAttachment`. Ein Fehler wird
    /// protokolliert, nicht geworfen. Für Nachricht samt Anhängen
    /// `saveMessageWithAttachments` verwenden.
    ///
    /// - Parameter a: Zu speichernder Anhang.
    func saveAttachment(_ a: CachedAttachment) {
        logged("saveAttachment \(a.id)") { try insertAttachment(a) }
    }

    /// Schreibt einen Anhang per UPSERT.
    ///
    /// - Parameter a: Zu speichernder Anhang.
    /// - Throws: `StoreError`, wenn das Schreiben fehlschlägt (z. B. weil
    ///   die zugehörige Nachricht fehlt).
    private func insertAttachment(_ a: CachedAttachment) throws {
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
        try execute(sql, context: "insertAttachment \(a.id)") { stmt in
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
        }
    }

    // MARK: - Anhänge löschen (nur lokales BLOB)

    /// Löscht nur die lokalen Binärdaten eines Anhangs.
    ///
    /// Verarbeitung: Dateiname, Größe und Typ bleiben erhalten; der
    /// Anhang kann bei Bedarf erneut vom Server geladen werden.
    ///
    /// - Parameter id: ID des Anhangs.
    func deleteAttachmentData(id: String) {
        logged("deleteAttachmentData \(id)") {
            try execute("UPDATE attachment SET data = NULL WHERE id = ?",
                        context: "deleteAttachmentData \(id)") { stmt in
                bind(stmt, 1, id)
            }
        }
    }

    // MARK: - Lesen

    /// Liest eine einzelne Nachricht.
    ///
    /// - Parameter id: Cache-ID der Nachricht.
    /// - Returns: Die Nachricht oder `nil`, wenn sie nicht im Cache liegt.
    func message(id: String) -> CachedMessage? {
        let sql = "SELECT \(Self.messageColumns) FROM message WHERE id = ? LIMIT 1"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readMessage(stmt)
    }

    /// Nachrichten mehrerer Postfächer in einem Ordner.
    ///
    /// - Parameters:
    ///   - accountIDs: Postfächer.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Nachrichten, absteigend nach Datum.
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

    /// Nachrichten eines einzelnen Ordners eines Postfachs.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Nachrichten, absteigend nach Datum.
    func folderMessages(accountID: UUID, folder: String) -> [CachedMessage] {
        let sql = """
            SELECT \(Self.messageColumns) FROM message
            WHERE accountID = ? AND folder = ? ORDER BY date DESC
            """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        var result: [CachedMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(readMessage(stmt))
        }
        return result
    }

    // MARK: - Stand je Ordner

    /// Vermerkt einen erfolgreichen Abruf eines Ordners.
    ///
    /// Verarbeitung: Speichert den Zeitpunkt und – falls übergeben – den
    /// Sync-Zustand. Ohne Zustand bleibt ein bereits gespeicherter
    /// erhalten (z. B. wenn der Server UIDVALIDITY nicht meldet).
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    ///   - date: Zeitpunkt des Abrufs (Standard: jetzt).
    ///   - state: Sync-Zustand nach dem Abruf; `nil` = unverändert lassen.
    func recordSync(accountID: UUID, folder: String, at date: Date = Date(), state: FolderSyncState? = nil) {
        let sql = """
            INSERT INTO folder_sync (accountID, folder, lastSyncAt, uidValidity, uidNext)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(accountID, folder) DO UPDATE SET
                lastSyncAt = excluded.lastSyncAt,
                uidValidity = COALESCE(excluded.uidValidity, folder_sync.uidValidity),
                uidNext = COALESCE(excluded.uidNext, folder_sync.uidNext)
            """
        logged("recordSync") {
            try execute(sql, context: "recordSync") { stmt in
                bind(stmt, 1, accountID.uuidString)
                bind(stmt, 2, folder)
                sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
                if let state {
                    sqlite3_bind_int64(stmt, 4, Int64(state.uidValidity))
                    sqlite3_bind_int64(stmt, 5, Int64(state.uidNext))
                } else {
                    sqlite3_bind_null(stmt, 4)
                    sqlite3_bind_null(stmt, 5)
                }
            }
        }
    }

    /// Gespeicherter Sync-Zustand eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Der Zustand oder `nil`, wenn noch keiner gespeichert ist.
    func syncState(accountID: UUID, folder: String) -> FolderSyncState? {
        let sql = "SELECT uidValidity, uidNext FROM folder_sync WHERE accountID = ? AND folder = ?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_type(stmt, 0) != SQLITE_NULL,
              sqlite3_column_type(stmt, 1) != SQLITE_NULL else { return nil }
        return FolderSyncState(
            uidValidity: UInt32(truncatingIfNeeded: sqlite3_column_int64(stmt, 0)),
            uidNext: UInt32(truncatingIfNeeded: sqlite3_column_int64(stmt, 1))
        )
    }

    /// Letzter erfolgreicher Abruf eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Zeitpunkt oder `nil`, wenn noch nie abgerufen.
    func lastSync(accountID: UUID, folder: String) -> Date? {
        let sql = "SELECT lastSyncAt FROM folder_sync WHERE accountID = ? AND folder = ?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
    }

    // MARK: - Zeitfenster je Ordner

    /// Beginn des erweiterten Zeitfensters eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Fensterbeginn oder `nil` (= Standardfenster).
    func windowStart(accountID: UUID, folder: String) -> Date? {
        let sql = "SELECT windowStart FROM folder_window WHERE accountID = ? AND folder = ?"
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
    }

    /// Speichert den Beginn des erweiterten Zeitfensters eines Ordners.
    ///
    /// - Parameters:
    ///   - date: Neuer Fensterbeginn.
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    func setWindowStart(_ date: Date, accountID: UUID, folder: String) {
        let sql = """
            INSERT INTO folder_window (accountID, folder, windowStart) VALUES (?, ?, ?)
            ON CONFLICT(accountID, folder) DO UPDATE SET windowStart = excluded.windowStart
            """
        logged("setWindowStart") {
            try execute(sql, context: "setWindowStart") { stmt in
                bind(stmt, 1, accountID.uuidString)
                bind(stmt, 2, folder)
                sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
            }
        }
    }

    /// Gekennzeichnete Nachrichten aus den Posteingängen mehrerer Postfächer.
    ///
    /// - Parameter accountIDs: Postfächer.
    /// - Returns: Nachrichten, absteigend nach Datum.
    func flaggedInboxMessages(accountIDs: [UUID]) -> [CachedMessage] {
        guard !accountIDs.isEmpty else { return [] }
        let ph = accountIDs.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT \(Self.messageColumns) FROM message
            WHERE accountID IN (\(ph)) AND folder = ? AND isFlagged = 1
            ORDER BY date DESC
            """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in accountIDs.enumerated() {
            bind(stmt, Int32(i + 1), id.uuidString)
        }
        bind(stmt, Int32(accountIDs.count + 1), MailFetchService.inboxFolder)
        var result: [CachedMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(readMessage(stmt))
        }
        return result
    }

    /// Anzahl gekennzeichneter Nachrichten in den Posteingängen.
    ///
    /// - Parameter accountIDs: Postfächer.
    /// - Returns: Anzahl.
    func flaggedInboxCount(accountIDs: [UUID]) -> Int {
        guard !accountIDs.isEmpty else { return 0 }
        let ph = accountIDs.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT COUNT(*) FROM message
            WHERE accountID IN (\(ph)) AND folder = ? AND isFlagged = 1
            """
        guard let stmt = prepare(sql) else { return 0 }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in accountIDs.enumerated() {
            bind(stmt, Int32(i + 1), id.uuidString)
        }
        bind(stmt, Int32(accountIDs.count + 1), MailFetchService.inboxFolder)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    /// Cache-IDs aller Nachrichten eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Menge der Cache-IDs.
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

    /// UIDs aller gecachten Nachrichten eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Menge der UIDs.
    func cachedUIDs(accountID: UUID, folder: String) -> Set<UInt32> {
        let sql = "SELECT uid FROM message WHERE accountID = ? AND folder = ?"
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        bind(stmt, 2, folder)
        var uids = Set<UInt32>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            uids.insert(UInt32(truncatingIfNeeded: sqlite3_column_int64(stmt, 0)))
        }
        return uids
    }

    /// Anhänge einer Nachricht.
    ///
    /// - Parameter messageID: Cache-ID der Nachricht.
    /// - Returns: Alle zugehörigen Anhänge.
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

    // MARK: - Ordnerliste

    /// Speichert die Ordnerliste eines Postfachs und ersetzt die bisherige.
    ///
    /// - Parameters:
    ///   - listing: Ordnerstruktur.
    ///   - accountID: Postfach.
    func saveFolderListing(_ listing: FolderListing, accountID: UUID) {
        guard let data = try? JSONEncoder().encode(listing),
              let json = String(data: data, encoding: .utf8) else { return }
        let sql = """
            INSERT INTO folder_listing (accountID, json, savedAt) VALUES (?, ?, ?)
            ON CONFLICT(accountID) DO UPDATE SET json = excluded.json, savedAt = excluded.savedAt
            """
        logged("saveFolderListing") {
            try execute(sql, context: "saveFolderListing") { stmt in
                bind(stmt, 1, accountID.uuidString)
                bind(stmt, 2, json)
                sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            }
        }
    }

    /// Gespeicherte Ordnerliste eines Postfachs.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: Ordnerliste oder `nil`, wenn keine vorliegt oder sie
    ///   nicht mehr lesbar ist.
    func folderListing(accountID: UUID) -> FolderListing? {
        guard let stmt = prepare("SELECT json FROM folder_listing WHERE accountID = ?") else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return try? JSONDecoder().decode(FolderListing.self, from: Data(str(stmt, 0).utf8))
    }

    // MARK: - Löschen

    // Mails verlassen den Cache nur, wenn sie in Mailwerk gelöscht oder
    // verschoben werden, der Abgleich sie auf dem Server nicht mehr findet
    // oder ihr Ordner bzw. Postfach entfernt wird. Ein Löschen nach Alter
    // gibt es nicht.

    /// Entfernt alles, was der Cache zu einem Postfach hält.
    ///
    /// Verarbeitung: Löscht Nachrichten (über ON DELETE CASCADE samt
    /// Anhängen), Stände, Zeitfenster und Ordnerliste in einer
    /// Transaktion. Bei einem Fehler bleibt alles erhalten.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: Anzahl der gelöschten Nachrichten; 0 bei einem Fehler.
    @discardableResult
    func deleteAccount(accountID: UUID) -> Int {
        let removed = messageCount(accountID: accountID)
        let ok = logged("deleteAccount") {
            try transaction {
                for table in ["message", "folder_sync", "folder_window", "folder_listing"] {
                    try execute("DELETE FROM \(table) WHERE accountID = ?",
                                context: "deleteAccount/\(table)") { stmt in
                        bind(stmt, 1, accountID.uuidString)
                    }
                }
            }
        }
        return ok ? removed : 0
    }

    /// Anzahl der gecachten Nachrichten eines Postfachs.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: Anzahl.
    private func messageCount(accountID: UUID) -> Int {
        guard let stmt = prepare("SELECT COUNT(*) FROM message WHERE accountID = ?") else { return 0 }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, accountID.uuidString)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    /// Entfernt alles, was der Cache zu einem Ordner hält.
    ///
    /// Verarbeitung: Löscht Nachrichten (samt Anhängen), Stand mit
    /// Sync-Zustand und Zeitfenster in einer Transaktion. Wird nach dem
    /// Löschen des Ordners auf dem Server aufgerufen und wenn sich die
    /// UIDVALIDITY des Ordners geändert hat. Unterordner bleiben unberührt.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    func deleteFolder(accountID: UUID, folder: String) {
        logged("deleteFolder") {
            try transaction {
                for table in ["message", "folder_sync", "folder_window"] {
                    try execute("DELETE FROM \(table) WHERE accountID = ? AND folder = ?",
                                context: "deleteFolder/\(table)") { stmt in
                        bind(stmt, 1, accountID.uuidString)
                        bind(stmt, 2, folder)
                    }
                }
            }
        }
    }

    /// Entfernt eine einzelne Nachricht samt Anhängen aus dem Cache.
    ///
    /// Verarbeitung: Wird nach erfolgreichem Löschen oder Verschieben auf
    /// dem Server aufgerufen. Anhänge folgen über ON DELETE CASCADE.
    ///
    /// - Parameter id: Cache-ID der Nachricht.
    func deleteMessage(id: String) {
        logged("deleteMessage \(id)") { try removeMessage(id: id) }
    }

    /// Löscht eine Nachricht.
    ///
    /// - Parameter id: Cache-ID der Nachricht.
    /// - Throws: `StoreError`, wenn das Löschen fehlschlägt.
    private func removeMessage(id: String) throws {
        try execute("DELETE FROM message WHERE id = ?", context: "removeMessage \(id)") { stmt in
            bind(stmt, 1, id)
        }
    }

    // MARK: - Verschieben

    /// Zieht eine gecachte Nachricht in einen anderen Ordner um.
    ///
    /// Verarbeitung: Kennung und UID ändern sich, die Anhänge ziehen mit.
    /// Weil sich der Primärschlüssel ändert, laufen beide Schritte ohne
    /// Fremdschlüsselprüfung in einer Transaktion. Bei einem Fehler wird
    /// zurückgerollt und die Nachricht bleibt unter der alten Kennung.
    ///
    /// - Parameters:
    ///   - id: Bisherige Cache-ID.
    ///   - folder: Zielordner.
    ///   - newUID: Vom Server gemeldete UID im Zielordner.
    /// - Returns: Neue Kennung; `nil`, wenn die Nachricht nicht im Cache
    ///   lag oder das Umschreiben fehlschlug.
    @discardableResult
    func relocateMessage(id: String, toFolder folder: String, newUID: UInt32) -> String? {
        guard let existing = message(id: id) else { return nil }
        let newID = CachedMessage.makeID(
            accountID: existing.accountID, folder: folder, uid: newUID
        )
        guard newID != id else { return newID }

        let ok = withForeignKeysDisabled {
            logged("relocateMessage \(id)") {
                try transaction {
                    // Anhänge zuerst: ihre Kennung beginnt mit der Nachrichten-Kennung.
                    try execute("""
                        UPDATE attachment
                        SET id = ? || substr(id, length(messageID) + 1), messageID = ?
                        WHERE messageID = ?
                        """, context: "relocateMessage/attachment") { stmt in
                        bind(stmt, 1, newID)
                        bind(stmt, 2, newID)
                        bind(stmt, 3, id)
                    }
                    try execute(
                        "UPDATE message SET id = ?, folder = ?, uid = ? WHERE id = ?",
                        context: "relocateMessage/message"
                    ) { stmt in
                        bind(stmt, 1, newID)
                        bind(stmt, 2, folder)
                        sqlite3_bind_int64(stmt, 3, Int64(newUID))
                        bind(stmt, 4, id)
                    }
                }
            }
        }
        return ok ? newID : nil
    }

    // MARK: - Transaktionen und Schreib-Helfer

    /// Führt einen Block in einer Transaktion aus.
    ///
    /// Verarbeitung: `BEGIN` vor dem Block, `COMMIT` danach. Wirft der
    /// Block oder schlägt das COMMIT fehl, wird `ROLLBACK` ausgeführt und
    /// der Fehler weitergegeben. Nicht verschachteln – SQLite kennt keine
    /// verschachtelten Transaktionen.
    ///
    /// - Parameter body: Schreibschritte der Transaktion.
    /// - Returns: Ergebnis von `body`.
    /// - Throws: Fehler aus `body` oder `StoreError.exec`.
    @discardableResult
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execOrThrow("BEGIN TRANSACTION")
        do {
            let result = try body()
            try execOrThrow("COMMIT")
            return result
        } catch {
            exec("ROLLBACK")
            throw error
        }
    }

    /// Führt einen Block ohne Fremdschlüsselprüfung aus.
    ///
    /// Verarbeitung: Schaltet `PRAGMA foreign_keys` ab und per `defer`
    /// in jedem Fall wieder ein. Nötig, wenn sich Primärschlüssel ändern
    /// (SQLite kennt hier kein ON UPDATE CASCADE). Das Umschalten wirkt
    /// nur außerhalb einer Transaktion.
    ///
    /// - Parameter body: Auszuführender Block.
    /// - Returns: Ergebnis von `body`.
    @discardableResult
    private func withForeignKeysDisabled<T>(_ body: () -> T) -> T {
        exec("PRAGMA foreign_keys = OFF")
        defer { exec("PRAGMA foreign_keys = ON") }
        return body()
    }

    /// Führt einen werfenden Schreibblock aus und protokolliert Fehler.
    ///
    /// Verarbeitung: Brücke zwischen den werfenden internen Schreib-
    /// schritten und der nicht werfenden öffentlichen Schnittstelle.
    ///
    /// - Parameters:
    ///   - context: Kurzbeschreibung für die Protokollausgabe.
    ///   - body: Schreibblock.
    /// - Returns: `true` bei Erfolg, `false` nach einem Fehler.
    @discardableResult
    private func logged(_ context: String, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            return true
        } catch {
            print("🗄️ Schreiben fehlgeschlagen (\(context)): \(error)")
            return false
        }
    }

    /// Bereitet einen Schreibbefehl vor, bindet Parameter und führt ihn aus.
    ///
    /// Verarbeitung: Erwartet `SQLITE_DONE`. Jedes andere Ergebnis gilt
    /// als Fehler. Das Statement wird in jedem Fall freigegeben.
    ///
    /// - Parameters:
    ///   - sql: SQL-Befehl mit Platzhaltern.
    ///   - context: Kurzbeschreibung für Fehlermeldungen.
    ///   - bindValues: Bindet die Parameter an das Statement.
    /// - Throws: `StoreError.prepare` oder `StoreError.step`.
    private func execute(
        _ sql: String,
        context: String,
        bind bindValues: (OpaquePointer?) -> Void = { _ in }
    ) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.prepare(context: context, message: errMsg)
        }
        defer { sqlite3_finalize(stmt) }
        bindValues(stmt)
        let code = sqlite3_step(stmt)
        guard code == SQLITE_DONE else {
            throw StoreError.step(context: context, code: code, message: errMsg)
        }
    }

    /// Führt einen Befehl ohne Parameter aus und wirft bei einem Fehler.
    ///
    /// - Parameter sql: SQL-Befehl (z. B. BEGIN, COMMIT).
    /// - Throws: `StoreError.exec`.
    private func execOrThrow(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.exec(sql: sql, message: errMsg)
        }
    }

    // MARK: - Interne Helfer

    /// Liest eine Zeile gemäß `messageColumns` (Indizes 0–23).
    ///
    /// - Parameter s: Statement, das auf einer Ergebniszeile steht.
    /// - Returns: Die gelesene Nachricht.
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
    ///
    /// - Parameter s: Statement, das auf einer Ergebniszeile steht.
    /// - Returns: Der gelesene Anhang.
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

    /// Bindet die sechs Header-Felder ab einer Position.
    ///
    /// Verarbeitung: Reihenfolge toJSON, ccJSON, replyToJSON,
    /// rfcMessageID, rfcInReplyTo, rfcReferences.
    ///
    /// - Parameters:
    ///   - s: Vorbereitetes Statement.
    ///   - i: Position des ersten Platzhalters.
    ///   - h: Zu bindende Header.
    private func bindHeaders(_ s: OpaquePointer?, startingAt i: Int32, _ h: CachedMessageHeaders) {
        bind(s, i,     encodeList(h.toList))
        bind(s, i + 1, encodeList(h.ccList))
        bind(s, i + 2, encodeList(h.replyToList))
        bind(s, i + 3, h.rfcMessageID)
        bind(s, i + 4, h.rfcInReplyTo)
        bind(s, i + 5, h.rfcReferences)
    }

    /// Setzt eine boolesche Spalte einer Nachricht.
    ///
    /// - Parameters:
    ///   - column: Spaltenname (nur interne Konstanten, keine Nutzereingaben).
    ///   - value: Neuer Wert.
    ///   - messageID: Cache-ID der Nachricht.
    private func updateIntColumn(_ column: String, value: Bool, messageID: String) {
        logged("update \(column) \(messageID)") {
            try execute("UPDATE message SET \(column) = ? WHERE id = ?",
                        context: "update \(column)") { stmt in
                sqlite3_bind_int(stmt, 1, value ? 1 : 0)
                bind(stmt, 2, messageID)
            }
        }
    }

    /// Kodiert eine Adressliste als JSON.
    ///
    /// - Parameter list: Adressen.
    /// - Returns: JSON-Text oder `nil` bei leerer Liste.
    private func encodeList(_ list: [String]) -> String? {
        guard !list.isEmpty,
              let data = try? JSONEncoder().encode(list) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Dekodiert eine als JSON gespeicherte Adressliste.
    ///
    /// - Parameter json: JSON-Text oder `nil`.
    /// - Returns: Adressen; leer bei fehlendem oder unlesbarem Wert.
    private func decodeList(_ json: String?) -> [String] {
        guard let json,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    /// Liest eine Textspalte.
    ///
    /// - Parameters:
    ///   - s: Statement auf einer Ergebniszeile.
    ///   - col: Spaltenindex.
    /// - Returns: Text; leer bei NULL.
    private func str(_ s: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(s, col) else { return "" }
        return String(cString: c)
    }

    /// Liest eine optionale Textspalte.
    ///
    /// - Parameters:
    ///   - s: Statement auf einer Ergebniszeile.
    ///   - col: Spaltenindex.
    /// - Returns: Text oder `nil` bei NULL.
    private func optStr(_ s: OpaquePointer?, _ col: Int32) -> String? {
        guard sqlite3_column_type(s, col) != SQLITE_NULL,
              let c = sqlite3_column_text(s, col) else { return nil }
        return String(cString: c)
    }

    /// Bindet einen optionalen Text an einen Platzhalter.
    ///
    /// - Parameters:
    ///   - s: Vorbereitetes Statement.
    ///   - i: Position des Platzhalters (1-basiert).
    ///   - v: Wert; `nil` wird als NULL gebunden.
    private func bind(_ s: OpaquePointer?, _ i: Int32, _ v: String?) {
        if let v { sqlite3_bind_text(s, i, v, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(s, i) }
    }

    /// Bereitet eine Leseabfrage vor.
    ///
    /// - Parameter sql: SQL-Abfrage.
    /// - Returns: Statement oder `nil` bei einem Fehler (wird protokolliert).
    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("🗄️ SQL-Fehler: \(errMsg) – \(sql.prefix(80))")
            return nil
        }
        return stmt
    }

    /// Führt einen Befehl ohne Parameter aus und protokolliert Fehler.
    ///
    /// Verarbeitung: Für Schema, Migration und PRAGMAs, bei denen ein
    /// Fehler nur protokolliert wird.
    ///
    /// - Parameter sql: SQL-Befehl.
    /// - Returns: `true` bei Erfolg.
    @discardableResult
    private func exec(_ sql: String) -> Bool {
        let ok = sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
        if !ok { print("🗄️ SQL-Fehler: \(errMsg) – \(sql.prefix(80))") }
        return ok
    }
}
