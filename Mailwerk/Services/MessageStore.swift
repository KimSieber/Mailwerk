//
//  MessageStore.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Lokale SQLite-Ablage für Nachrichten, Anhänge und den Stand
//  je Ordner (letzter Abruf mit Sync-Zustand, Zeitfenster, Ordnerliste).
//
//  Nutzt das auf jeder Apple-Plattform mitgelieferte System-SQLite im
//  WAL-Modus.
//
//  Nebenläufigkeit (v0.2.3b): Die Ablage ist `nonisolated` und aus jedem
//  Thread nutzbar. Sie hält zwei Verbindungen:
//  - die Schreibverbindung auf einer eigenen seriellen Queue – alle
//    Schreibvorgänge und zusammengehörigen Folgen (BEGIN … COMMIT) laufen
//    dort ungeteilt nacheinander (`onWrite`);
//  - eine nur lesende Zweitverbindung auf einer zweiten Queue für Abfragen
//    (`onRead`). WAL erlaubt ihr, parallel zu einem laufenden Schreibvorgang
//    einen festgeschriebenen Stand zu lesen – die Liste muss nicht warten,
//    bis der Abruf ein Paket gespeichert hat.
//  Verschachtelte Aufrufe (z. B. Speichern innerhalb von `batch`) laufen
//  direkt im bereits aktiven Kontext und verklemmen nicht. Abfragen
//  innerhalb einer Schreibfolge lesen über die Schreibverbindung und sehen
//  so auch deren noch offene Änderungen. Arbeitet die Ablage im
//  Arbeitsspeicher, gibt es nur die Schreibverbindung.
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
//  Listen: Die Abfragen für die Nachrichtenliste liefern
//  `MessageListItem` ohne Text- und HTML-Inhalt. Die vollständige
//  Nachricht liefert `message(id:)`. Sammelsichten über mehrere Ordner
//  (Spam-Ordner aller Postfächer) fragen Paare aus Postfach und Ordner ab
//  (`FolderKey`).
//
//  Suchindex: Die FTS5-Tabelle `message_search` (Verfahren „trigram“:
//  Teilzeichenfolgen ab drei Zeichen, ohne Groß-/Kleinschreibung) hält je
//  Nachricht Betreff, Personen (Von, An, Cc), Text und Anhangnamen. Ihre
//  Zeilennummer ist die der Nachricht. Beim Speichern einer Nachricht und
//  beim Nachtragen der Kopfdaten wird ihr Eintrag neu geschrieben; ein
//  Trigger löscht ihn mit der Nachricht. Verschieben ändert die
//  Zeilennummer nicht. Fehlende Einträge (Bestand vor Schema-Stufe 7 oder
//  ein gescheitertes Schreiben) trägt `indexMissingSearchEntries` nach.
//
//  Schema: `createTablesIfNeeded()` legt nur das Basisschema an, alle
//  späteren Spalten und Tabellen kommen über `migrateIfNeeded()`.
//  `PRAGMA user_version` hält die erreichte Schema-Version; jede
//  Migrationsstufe läuft genau einmal.
//
//  Schreiben: Alle Schreibzugriffe laufen über `execute(_:context:bind:)`,
//  das das Ergebnis von `sqlite3_step` prüft und bei einem Fehler wirft.
//  Die vorbereiteten Anweisungen von `execute` werden je SQL-Text
//  zwischengespeichert und wiederverwendet (`statementCache`), statt sie
//  bei jedem Aufruf neu zu übersetzen.
//  Mehrteilige Schreibvorgänge laufen in `transaction(_:)` und werden
//  bei einem Fehler vollständig zurückgerollt. Transaktionen lassen sich
//  verschachteln: Die äußerste beginnt mit BEGIN, jede innere ist ein
//  SAVEPOINT. Scheitert eine innere, wird nur sie zurückgerollt. So kann
//  der Abruf viele Mails in einem gemeinsamen Commit speichern
//  (`batch(_:_:)`), ohne dass eine fehlerhafte Mail die übrigen mitreißt.
//  Die öffentlichen Schreibfunktionen werfen nicht; sie protokollieren
//  Fehler und melden – wo der Aufrufer es braucht – Erfolg über den
//  Rückgabewert.
//
//  Einstellungen der Verbindung: WAL mit `synchronous = NORMAL` – ein
//  Sync auf den Speicher nur beim Checkpoint statt bei jedem Commit. Ein
//  Absturz der App verliert nichts; bei Stromausfall können die letzten
//  Commits fehlen, die Datenbank bleibt aber unbeschädigt. Weil der Server
//  führend ist, holt der nächste Abruf Fehlendes nach. Dazu Zwischen-
//  ergebnisse im Arbeitsspeicher und ein Seiten-Cache von rund 8 MB.
//
//  Abgrenzung: Der Store kennt weder IMAP noch Oberfläche. Abruf und
//  Darstellung liegen im MailFetchService bzw. in den ViewModels.
//
//  Absenderlogos: Tabelle `sender_icon` hält je Domain das geladene Logo
//  (oder den erfolglosen Versuch) mit Prüfzeitpunkt. Sie gehört keinem
//  Postfach und bleibt beim Entfernen eines Postfachs erhalten.
//
//  Spam-Angabe: Je Nachricht speichert die Ablage die Einstufung des
//  Servers (Spalten `spamFlag`, `spamScore`). `spamFlag` NULL heißt
//  „unbekannt“ – die Nachricht wurde vor Schema-Stufe 4 gespeichert und
//  noch nicht nachgefüllt. Unbekannt ist etwas anderes als „kein Spam“.
//
//  Anzeige-Hinweise (Stufe 9): externe Inhalte, eigene Farben und fremde
//  Sprache je Nachricht (MessageDisplayHints), beim Abruf vorberechnet.
//  `hintsVersion` NULL oder veraltet heißt „nicht berechnet“ – die
//  Mailansicht rechnet dann beim Öffnen nach und speichert.
//
//  Abhängigkeiten: SQLite3 (System-Framework), CachedMessage, MessageDisplayHints,
//  CachedAttachment, SpamHeaderVerdict, FolderListing, MailFolder (Name des Posteingangs),
//  ServerReconciliation (Plan-Typ), FolderSyncState, MessageListItem,
//  SenderIconRecord, SearchText (Inhalt des Suchindex), SearchScope,
//  FolderKey (Ordner je Postfach), Log.
//

import Foundation
import SQLite3
import os

/// SQLite soll übergebene Texte/Blobs selbst kopieren (SQLITE_TRANSIENT = -1).
/// Das C-Makro ist in Swift nicht verfügbar, daher hier nachgebildet.
nonisolated private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
nonisolated final class MessageStore: @unchecked Sendable {
    /// Gemeinsame Ablage der App.
    static let shared = MessageStore()

    /// Version der gespeicherten Kopfdaten (Adressen, Threading,
    /// Spam-Angabe). Nachrichten mit kleinerer Version werden beim nächsten
    /// Abruf ihres Ordners nachgefüllt, ohne sie neu zu laden.
    /// Version 3: Spam-Angabe berücksichtigt auch `X-Spam-Flag`.
    static let currentHeadersVersion = 3

    /// Schema-Version, die diese App-Version erwartet. Wird nach den
    /// Migrationen in `PRAGMA user_version` geschrieben.
    private static let schemaVersion: Int32 = 9

    /// Explizite Spaltenliste – Reihenfolge entspricht den Indizes in readMessage().
    private static let messageColumns = """
        id, accountID, accountDisplayName, uid, subject, "from", "to", date, \
        isUnread, isFlagged, isAnswered, isForwarded, totalSizeBytes, hasAttachments, \
        textBody, htmlBody, fetchedAt, \
        toJSON, ccJSON, replyToJSON, rfcMessageID, rfcInReplyTo, rfcReferences, \
        folder, spamFlag, spamScore
        """

    /// Spaltenliste der Listeneinträge – ohne Text und HTML.
    /// Reihenfolge entspricht readListItem().
    private static let listColumns = """
        id, accountID, folder, uid, subject, "from", date, \
        isUnread, isFlagged, isAnswered, isForwarded, hasAttachments, totalSizeBytes, \
        toJSON, spamFlag, spamScore
        """

    /// Spaltenliste der Anhänge – Reihenfolge entspricht readAttachment().
    private static let attachmentColumns =
        "id, messageID, filename, contentType, sizeBytes, data, contentID, isInline"

    /// Name des Unterordners für die Ablage im Application-Support-Verzeichnis.
    static let cacheDirectoryName = "Cache"

    /// Dateiname der Datenbank.
    static let databaseFileName = "Mailwerk.sqlite"

    /// Schreibverbindung. Alle Schreibvorgänge und Lesezugriffe innerhalb
    /// einer Schreibfolge laufen über sie, serialisiert auf `writeQueue`.
    private var writeHandle: OpaquePointer?

    /// Nur lesende Zweitverbindung für Abfragen (WAL erlaubt Lesen parallel
    /// zum Schreiben), serialisiert auf `readQueue`. `nil`, wenn die Ablage
    /// im Arbeitsspeicher arbeitet – dann laufen Lesezugriffe über die
    /// Schreibverbindung.
    private var readHandle: OpaquePointer?

    /// Serielle Queue der Schreibverbindung.
    private let writeQueue = DispatchQueue(label: "de.sieber-bw.Mailwerk.store.write", qos: .userInitiated)
    /// Serielle Queue der Leseverbindung.
    private let readQueue = DispatchQueue(label: "de.sieber-bw.Mailwerk.store.read", qos: .userInitiated)
    /// Kennzeichen „läuft gerade auf `writeQueue`“ (je Ablage eigenes Objekt).
    private let writeQueueKey = DispatchSpecificKey<Bool>()
    /// Kennzeichen „läuft gerade auf `readQueue`“ (je Ablage eigenes Objekt).
    private let readQueueKey = DispatchSpecificKey<Bool>()

    /// Verbindung für den aktuellen Ausführungskontext: auf `readQueue` die
    /// Leseverbindung, sonst die Schreibverbindung (auch während `init`,
    /// das vor jedem anderen Zugriff läuft).
    private var db: OpaquePointer? {
        if DispatchQueue.getSpecific(key: readQueueKey) == true, let readHandle {
            return readHandle
        }
        return writeHandle
    }

    /// Hinweis für die Oberfläche, solange er nicht abgeholt wurde.
    private var startupNotice: StoreStartupNotice?

    /// Vorbereitete Schreibanweisungen je SQL-Text (siehe `execute`).
    private var statementCache: [String: OpaquePointer] = [:]

    /// Tiefe der laufenden Transaktionen: 0 = keine, 1 = BEGIN, ab 2 Savepoints.
    private var transactionDepth = 0

    /// Gemeinsamer Kodierer für Adresslisten (statt eines neuen je Aufruf).
    private static let listEncoder = JSONEncoder()
    /// Gemeinsamer Dekodierer für Adresslisten (statt eines neuen je Zeile).
    private static let listDecoder = JSONDecoder()

    /// `true`, wenn die Tabelle des Suchindex besteht. Fehlt sie (SQLite
    /// ohne FTS5), wird nicht indiziert und die Suche findet nichts – das
    /// Speichern von Mails darf daran nie scheitern.
    private var hasSearchIndex = false

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
            Log.store.error("🗄️ Verzeichnis für die Ablage nicht verfügbar: \(String(describing: error), privacy: .public)")
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
    /// Danach werden WAL-Modus, Sync-Stufe, Cache-Größe und Fremdschlüssel
    /// eingestellt, das Basisschema angelegt und ausstehende Migrationen
    /// ausgeführt. Zuletzt wird bei einer Datei die nur lesende
    /// Zweitverbindung geöffnet (`openReadOnly`); misslingt das, lesen die
    /// Abfragen über die Schreibverbindung.
    /// Neben `shared` nutzen das die Tests mit eigenen Dateien.
    ///
    /// - Parameter path: Dateipfad der SQLite-Datenbank; `nil` = nur im
    ///   Arbeitsspeicher (Hinweis `unavailable`).
    init(path: String?) {
        writeQueue.setSpecific(key: writeQueueKey, value: true)
        readQueue.setSpecific(key: readQueueKey, value: true)

        // Pfad der Datei, sofern die Ablage dateibasiert läuft (für die
        // Leseverbindung); `nil` im Arbeitsspeicher.
        var filePath: String?
        if let path {
            switch Self.open(path) {
            case .opened(let handle):
                writeHandle = handle
                filePath = path

            case .corrupt(let code, let message):
                Log.store.error("🗄️ Datenbank beschädigt (\(code): \(message, privacy: .public)) → wird gelöscht und neu angelegt")
                Self.removeDatabaseFiles(at: path)
                if case .opened(let handle) = Self.open(path) {
                    writeHandle = handle
                    filePath = path
                    startupNotice = .rebuiltAfterCorruption
                } else {
                    Log.store.error("🗄️ Neuanlage fehlgeschlagen → Ablage im Arbeitsspeicher")
                    writeHandle = Self.openInMemory()
                    startupNotice = .unavailable
                }

            case .failed(let code, let message):
                Log.store.error("🗄️ Datenbank nicht zu öffnen (\(code): \(message, privacy: .public)) → Ablage im Arbeitsspeicher, nichts gelöscht")
                writeHandle = Self.openInMemory()
                startupNotice = .unavailable
            }
        } else {
            writeHandle = Self.openInMemory()
            startupNotice = .unavailable
        }

        exec("PRAGMA journal_mode = WAL")
        // Im WAL-Modus genügt NORMAL: Sync nur beim Checkpoint (siehe Kopf).
        exec("PRAGMA synchronous = NORMAL")
        exec("PRAGMA temp_store = MEMORY")
        // Negativer Wert = Größe in KiB, also rund 8 MB Seiten-Cache.
        exec("PRAGMA cache_size = -8000")
        exec("PRAGMA foreign_keys = ON")
        createTablesIfNeeded()
        migrateIfNeeded()
        hasSearchIndex = tableExists("message_search")

        // Leseverbindung erst nach Schema und Migration öffnen.
        if let filePath {
            readHandle = Self.openReadOnly(filePath)
        }
    }

    /// Liefert den Hinweis für die Oberfläche genau einmal.
    ///
    /// Verarbeitung: Gibt einen anstehenden Hinweis zurück und löscht ihn,
    /// damit die Meldung nur einmal erscheint.
    ///
    /// - Returns: Der Hinweis oder `nil`, wenn das Öffnen normal verlief.
    func consumeStartupNotice() -> StoreStartupNotice? {
        return onWrite {
            defer { startupNotice = nil }
            return startupNotice
        }
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
                Log.store.error("🗄️ Löschen fehlgeschlagen (\(file, privacy: .public)): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Öffnet die nur lesende Zweitverbindung zu einer bestehenden Datei.
    ///
    /// Verarbeitung: `SQLITE_OPEN_READONLY`; die Einstellungen der Datei
    /// (WAL) gelten auch hier. Misslingt das Öffnen, wird nur protokolliert –
    /// die Ablage liest dann über die Schreibverbindung.
    ///
    /// - Parameter path: Dateipfad der Datenbank.
    /// - Returns: Handle oder `nil`.
    private static func openReadOnly(_ path: String) -> OpaquePointer? {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            Log.store.error("🗄️ Leseverbindung nicht zu öffnen → Lesen über die Schreibverbindung")
            sqlite3_close(handle)
            return nil
        }
        sqlite3_exec(handle, "PRAGMA temp_store = MEMORY", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA cache_size = -8000", nil, nil, nil)
        return handle
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
            Log.store.error("🗄️ Ablage im Arbeitsspeicher nicht möglich")
            sqlite3_close(handle)
            return nil
        }
        return handle
    }

    /// Gibt die zwischengespeicherten Anweisungen frei und schließt beide
    /// Verbindungen.
    deinit {
        for stmt in statementCache.values { sqlite3_finalize(stmt) }
        sqlite3_close(readHandle)
        sqlite3_close(writeHandle)
    }

    // MARK: - Ausführungskontext

    /// Führt einen Block auf der Schreibverbindung aus.
    ///
    /// Verarbeitung: Läuft der Aufruf schon auf `writeQueue` (verschachtelt,
    /// z. B. innerhalb von `batch`), wird der Block direkt ausgeführt –
    /// sonst synchron auf `writeQueue`. So bleiben zusammengehörige Folgen
    /// (BEGIN … COMMIT) ungeteilt und verschachtelte Aufrufe verklemmen nicht.
    ///
    /// - Parameter body: Arbeit auf der Datenbank.
    /// - Returns: Ergebnis von `body`.
    @discardableResult
    private func onWrite<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: writeQueueKey) == true {
            return try body()
        }
        return try writeQueue.sync(execute: body)
    }

    /// Führt eine Abfrage auf der Leseverbindung aus.
    ///
    /// Verarbeitung: Innerhalb einer Schreibfolge (auf `writeQueue`) läuft
    /// die Abfrage direkt auf der Schreibverbindung – sie sieht dann auch
    /// noch nicht festgeschriebene Änderungen dieser Folge. Ohne
    /// Leseverbindung (Ablage im Arbeitsspeicher) geht sie über
    /// `onWrite`. Sonst synchron auf `readQueue`; dort wählt `db` die
    /// Leseverbindung.
    ///
    /// - Parameter body: Abfrage.
    /// - Returns: Ergebnis von `body`.
    @discardableResult
    private func onRead<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: writeQueueKey) == true
            || DispatchQueue.getSpecific(key: readQueueKey) == true {
            return try body()
        }
        guard readHandle != nil else { return try onWrite(body) }
        return try readQueue.sync(execute: body)
    }

    /// Letzte Fehlermeldung der Datenbank.
    private var errorMessage: String {
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
        if current < 3 {
            migrateToVersion3()
        }
        if current < 4 {
            migrateToVersion4()
        }
        if current < 5 {
            migrateToVersion5()
        }
        if current < 6 {
            migrateToVersion6()
        }
        if current < 7 {
            migrateToVersion7()
        }
        if current < 8 {
            migrateToVersion8()
        }
        if current < 9 {
            migrateToVersion9()
        }

        setUserVersion(Self.schemaVersion)
    }

    /// Stufe 1: alle Erweiterungen aus der Zeit vor `user_version`.
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

    /// Stufe 3: Index für die Nachrichtenliste.
    ///
    /// Verarbeitung: Legt den Index auf Postfach, Ordner und Datum an,
    /// damit die Liste ohne Umweg nach Datum sortiert; der bisherige Index
    /// auf Postfach und Ordner ist darin enthalten und entfällt. (Die
    /// früher hier angelegte Vorschau-Spalte entfernt Stufe 7.)
    private func migrateToVersion3() {
        exec("""
            CREATE INDEX IF NOT EXISTS idx_message_account_folder_date
            ON message(accountID, folder, date DESC)
            """)
        exec("DROP INDEX IF EXISTS idx_message_account_folder")
    }

    /// Stufe 4: Spam-Angabe des Servers je Nachricht.
    ///
    /// Verarbeitung: Ergänzt `spamFlag` und `spamScore`. Bestehende Zeilen
    /// erhalten NULL („unbekannt“); der nächste Abruf ihres Ordners füllt
    /// sie über die Header-Version nach.
    private func migrateToVersion4() {
        addColumnIfMissing("spamFlag", "INTEGER")
        addColumnIfMissing("spamScore", "REAL")
    }

    /// Stufe 5: Absenderlogos je Domain.
    ///
    /// Verarbeitung: Legt die Tabelle `sender_icon` an. `image` NULL heißt
    /// „kein Logo gefunden“; `checkedAt` steuert, wann erneut geladen wird.
    private func migrateToVersion5() {
        exec("""
            CREATE TABLE IF NOT EXISTS sender_icon (
                domain TEXT PRIMARY KEY,
                image BLOB,
                checkedAt REAL NOT NULL
            )
            """)
    }

    /// Stufe 6: eingebettete Bilder in der Anhang-Tabelle.
    ///
    /// Verarbeitung: Ergänzt `contentID` und `isInline`. Bestehende Zeilen
    /// sind echte Anhänge (`isInline` 0, ohne Content-ID); eingebettete
    /// Bilder wurden bis dahin nicht gespeichert. Fehlen sie beim Öffnen
    /// einer Mail, lädt die Mailansicht sie nach (InlineImageLoader).
    private func migrateToVersion6() {
        addColumnIfMissing("contentID", "TEXT", in: "attachment")
        addColumnIfMissing("isInline", "INTEGER NOT NULL DEFAULT 0", in: "attachment")
    }

    /// Stufe 7: Suchindex; die Vorschau-Spalte entfällt.
    ///
    /// Verarbeitung: Legt die FTS5-Tabelle `message_search` (Verfahren
    /// „trigram“) und den Trigger an, der den Eintrag mit der Nachricht
    /// löscht. Gefüllt wird der Index nicht hier, sondern schrittweise über
    /// `indexMissingSearchEntries` – so bleibt der Start nach dem Update
    /// kurz. Die nicht mehr genutzte Spalte `preview` wird entfernt.
    private func migrateToVersion7() {
        // Der Trigger nur mit Tabelle – sonst scheiterte jedes Löschen.
        let created = exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS message_search
            USING fts5(subject, people, body, attachments, tokenize = 'trigram')
            """)
        if created {
            exec("""
                CREATE TRIGGER IF NOT EXISTS message_search_delete
                AFTER DELETE ON message BEGIN
                    DELETE FROM message_search WHERE rowid = old.rowid;
                END
                """)
        }
        if columnExists("preview", in: "message") {
            exec("ALTER TABLE message DROP COLUMN preview")
        }
    }

    /// Stufe 8: Index der Anhänge nach Nachricht.
    ///
    /// Verarbeitung: Ohne diesen Index durchsuchten das Lesen der Anhänge
    /// einer Mail, die Anhangnamen im Suchindex und das Löschen einer Mail
    /// (ON DELETE CASCADE) jedes Mal die ganze Anhang-Tabelle.
    private func migrateToVersion8() {
        exec("CREATE INDEX IF NOT EXISTS idx_attachment_message ON attachment(messageID)")
    }

    /// Stufe 9: vorberechnete Anzeige-Hinweise je Nachricht.
    ///
    /// Verarbeitung: Ergänzt `hintsVersion`, `hasRemoteContent`,
    /// `usesOwnColors` und `language` (MessageDisplayHints). Bestehende
    /// Zeilen erhalten NULL („nicht berechnet“); berechnet wird beim
    /// nächsten Öffnen der Mail (MessageOpenPreparation) – kein langer
    /// Lauf beim Start.
    private func migrateToVersion9() {
        addColumnIfMissing("hintsVersion", "INTEGER")
        addColumnIfMissing("hasRemoteContent", "INTEGER")
        addColumnIfMissing("usesOwnColors", "INTEGER")
        addColumnIfMissing("language", "TEXT")
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

    /// Prüft, ob eine Tabelle (auch eine virtuelle) existiert.
    ///
    /// - Parameter table: Tabellenname.
    /// - Returns: `true`, wenn die Tabelle vorhanden ist.
    private func tableExists(_ table: String) -> Bool {
        guard let stmt = prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?") else { return false }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, table)
        return sqlite3_step(stmt) == SQLITE_ROW
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
            if columnText(stmt, 1) == column { return true }
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
        onWrite {
            logged("saveMessage \(m.id)") {
                try transaction {
                    try insertMessage(m)
                    try writeSearchEntry(messageID: m.id)
                }
            }
        }
    }

    /// Speichert eine Nachricht und ihre Anhänge in einer Transaktion.
    ///
    /// Verarbeitung: Nachricht, alle Anhänge und der Eintrag im Suchindex
    /// werden gemeinsam geschrieben. Schlägt ein Teil fehl, wird alles
    /// zurückgerollt – es entsteht weder eine Nachricht ohne ihre Anhänge
    /// noch ein verwaister Anhang.
    ///
    /// - Parameters:
    ///   - message: Zu speichernde Nachricht.
    ///   - attachments: Zugehörige Anhänge (mit oder ohne Daten).
    ///   - hints: Vorberechnete Anzeige-Hinweise; `nil` = später beim
    ///     Öffnen berechnen.
    /// - Returns: `true`, wenn alles gespeichert wurde; `false` nach Rollback.
    @discardableResult
    func saveMessageWithAttachments(
        _ message: CachedMessage,
        attachments: [CachedAttachment],
        hints: MessageDisplayHints? = nil
    ) -> Bool {
        return onWrite {
            logged("saveMessageWithAttachments \(message.id)") {
                try transaction {
                    try insertMessage(message)
                    for attachment in attachments {
                        try insertAttachment(attachment)
                    }
                    if let hints {
                        try writeDisplayHints(hints, messageID: message.id)
                    }
                    try writeSearchEntry(messageID: message.id)
                }
            }
        }
    }

    // MARK: - Anzeige-Hinweise

    /// Liest die vorberechneten Anzeige-Hinweise einer Nachricht.
    ///
    /// Verarbeitung: Gilt nur, wenn die gespeicherte Version der aktuellen
    /// entspricht (`MessageDisplayHints.currentVersion`); sonst `nil`, und
    /// der Aufrufer berechnet neu.
    ///
    /// - Parameter messageID: Cache-ID der Nachricht.
    /// - Returns: Hinweise; `nil`, wenn nicht berechnet oder veraltet.
    func displayHints(messageID: String) -> MessageDisplayHints? {
        return onRead {
            let sql = "SELECT hintsVersion, hasRemoteContent, usesOwnColors, language FROM message WHERE id = ? LIMIT 1"
            guard let stmt = prepare(sql) else { return nil }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, messageID)
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  sqlite3_column_type(stmt, 0) != SQLITE_NULL,
                  Int(sqlite3_column_int(stmt, 0)) == MessageDisplayHints.currentVersion
            else { return nil }
            return MessageDisplayHints(
                hasRemoteContent: sqlite3_column_int(stmt, 1) != 0,
                usesOwnColors: sqlite3_column_int(stmt, 2) != 0,
                languageCode: optionalColumnText(stmt, 3)
            )
        }
    }

    /// Speichert die Anzeige-Hinweise einer bereits gespeicherten Nachricht
    /// (Rückfall beim Öffnen). Ein Fehler wird nur protokolliert.
    ///
    /// - Parameters:
    ///   - hints: Berechnete Hinweise.
    ///   - messageID: Cache-ID der Nachricht.
    func saveDisplayHints(_ hints: MessageDisplayHints, messageID: String) {
        onWrite {
            logged("saveDisplayHints \(messageID)") {
                try writeDisplayHints(hints, messageID: messageID)
            }
        }
    }

    /// Schreibt die Anzeige-Hinweise samt aktueller Version.
    ///
    /// - Parameters:
    ///   - hints: Berechnete Hinweise.
    ///   - messageID: Cache-ID der Nachricht.
    /// - Throws: `StoreError`, wenn das Schreiben fehlschlägt.
    private func writeDisplayHints(_ hints: MessageDisplayHints, messageID: String) throws {
        try execute(
            "UPDATE message SET hintsVersion = ?, hasRemoteContent = ?, usesOwnColors = ?, language = ? WHERE id = ?",
            context: "writeDisplayHints \(messageID)"
        ) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(MessageDisplayHints.currentVersion))
            sqlite3_bind_int(stmt, 2, hints.hasRemoteContent ? 1 : 0)
            sqlite3_bind_int(stmt, 3, hints.usesOwnColors ? 1 : 0)
            bind(stmt, 4, hints.languageCode)
            bind(stmt, 5, messageID)
        }
    }

    /// Schreibt eine Nachricht per UPSERT.
    ///
    /// Verarbeitung: `ON CONFLICT … DO UPDATE` statt `INSERT OR REPLACE`,
    /// weil letzteres intern DELETE + INSERT ist und damit über
    /// ON DELETE CASCADE die Anhänge löschen würde. Den Suchindex schreibt
    /// der Aufrufer (`writeSearchEntry`), wenn auch die Anhänge stehen.
    /// Platzhalter: 1–24 Spalten bis `folder`, 25–26 Spam-Angabe,
    /// 27 Header-Version.
    ///
    /// - Parameter m: Zu speichernde Nachricht.
    /// - Throws: `StoreError`, wenn das Schreiben fehlschlägt.
    private func insertMessage(_ m: CachedMessage) throws {
        let sql = """
            INSERT INTO message
            (\(Self.messageColumns), headersVersion)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
                spamFlag = excluded.spamFlag,
                spamScore = excluded.spamScore,
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
            bindSpamVerdict(stmt, startingAt: 25, m.headers.spamVerdict)  // 25–26
            sqlite3_bind_int(stmt, 27, Int32(Self.currentHeadersVersion))
        }
    }

    // MARK: - Flags aktualisieren

    /// Aktualisiert nur den Gelesen-Status einer gecachten Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isUnread: `true` = ungelesen.
    func updateUnread(messageID: String, isUnread: Bool) {
        onWrite {
            updateIntColumn("isUnread", value: isUnread, messageID: messageID)
        }
    }

    /// Aktualisiert nur die Kennzeichnung (\Flagged) einer gecachten Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isFlagged: `true` = gekennzeichnet.
    func updateFlagged(messageID: String, isFlagged: Bool) {
        onWrite {
            updateIntColumn("isFlagged", value: isFlagged, messageID: messageID)
        }
    }

    /// Aktualisiert nur den Beantwortet-Status (\Answered) einer gecachten Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isAnswered: `true` = beantwortet.
    func updateAnswered(messageID: String, isAnswered: Bool) {
        onWrite {
            updateIntColumn("isAnswered", value: isAnswered, messageID: messageID)
        }
    }

    /// Aktualisiert nur den Weitergeleitet-Status ($Forwarded) einer gecachten Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - isForwarded: `true` = weitergeleitet.
    func updateForwarded(messageID: String, isForwarded: Bool) {
        onWrite {
            updateIntColumn("isForwarded", value: isForwarded, messageID: messageID)
        }
    }

    /// Übernimmt alle Server-Flags einer Nachricht in einem Statement.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - flags: Ausgewertete Flags des Servers.
    func updateServerFlags(messageID: String, flags: FlagState) {
        onWrite {
            logged("updateServerFlags \(messageID)") {
                try writeServerFlags(messageID: messageID, flags: flags)
            }
        }
    }

    /// Schreibt alle Server-Flags einer Nachricht.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - flags: Ungelesen, gekennzeichnet, beantwortet, weitergeleitet.
    /// - Throws: `StoreError`, wenn das Schreiben fehlschlägt.
    private func writeServerFlags(messageID: String, flags: FlagState) throws {
        let sql = """
            UPDATE message
            SET isUnread = ?, isFlagged = ?, isAnswered = ?, isForwarded = ?
            WHERE id = ?
            """
        try execute(sql, context: "writeServerFlags \(messageID)") { stmt in
            sqlite3_bind_int(stmt, 1, flags.isUnread ? 1 : 0)
            sqlite3_bind_int(stmt, 2, flags.isFlagged ? 1 : 0)
            sqlite3_bind_int(stmt, 3, flags.isAnswered ? 1 : 0)
            sqlite3_bind_int(stmt, 4, flags.isForwarded ? 1 : 0)
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
        return onRead {
            flagStates(
                sql: """
                    SELECT id, uid, isUnread, isFlagged, isAnswered, isForwarded FROM message
                    WHERE accountID = ? AND folder = ? AND date >= ?
                    """,
                accountID: accountID, folder: folder, date: since
            )
        }
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
        return query(sql, bind: { stmt in
            bind(stmt, 1, accountID.uuidString)
            bind(stmt, 2, folder)
            sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
        }) { stmt in
            CachedFlagState(
                id: columnText(stmt, 0),
                uid: UInt32(sqlite3_column_int64(stmt, 1)),
                isUnread: sqlite3_column_int(stmt, 2) == 1,
                isFlagged: sqlite3_column_int(stmt, 3) == 1,
                isAnswered: sqlite3_column_int(stmt, 4) == 1,
                isForwarded: sqlite3_column_int(stmt, 5) == 1
            )
        }
    }

    /// Wendet einen Abgleichsplan an.
    ///
    /// Verarbeitung: Entfernt gelöschte Mails und schreibt geänderte Flags
    /// in einer Transaktion. Schlägt ein Teil fehl, bleibt der Cache
    /// unverändert; der nächste Abgleich versucht es erneut.
    ///
    /// - Parameter plan: Änderungsplan aus `ServerReconciliation`.
    func apply(_ plan: ServerReconciliation.Plan) {
        onWrite {
            guard !plan.isEmpty else { return }
            logged("apply Abgleichsplan") {
                try transaction {
                    for id in plan.removedIDs {
                        try removeMessage(id: id)
                    }
                    for state in plan.flagUpdates {
                        try writeServerFlags(messageID: state.id, flags: state.flags)
                    }
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
        return onRead {
            let sql = """
                SELECT id FROM message
                WHERE accountID = ? AND folder = ? AND headersVersion < ?
                """
            return Set(query(sql, bind: { stmt in
                bind(stmt, 1, accountID.uuidString)
                bind(stmt, 2, folder)
                sqlite3_bind_int(stmt, 3, Int32(Self.currentHeadersVersion))
            }) { stmt in
                columnText(stmt, 0)
            })
        }
    }

    /// Schreibt Adress-, Threading- und Spam-Kopfdaten und setzt die
    /// Header-Version.
    ///
    /// Verarbeitung: Im Suchindex ändert sich dadurch nur die Spalte der
    /// Personen (An, Cc); nur sie wird neu geschrieben
    /// (`writeSearchPeople`). Text und Anhangnamen bleiben unverändert –
    /// das erspart die Aufbereitung des Mailtextes.
    ///
    /// - Parameters:
    ///   - messageID: Cache-ID der Nachricht.
    ///   - headers: Aufbereitete Header.
    func updateHeaders(messageID: String, headers: CachedMessageHeaders) {
        onWrite {
            let sql = """
                UPDATE message SET
                    toJSON = ?, ccJSON = ?, replyToJSON = ?,
                    rfcMessageID = ?, rfcInReplyTo = ?, rfcReferences = ?,
                    spamFlag = ?, spamScore = ?,
                    headersVersion = ?
                WHERE id = ?
                """
            logged("updateHeaders \(messageID)") {
                try transaction {
                    try execute(sql, context: "updateHeaders \(messageID)") { stmt in
                        bindHeaders(stmt, startingAt: 1, headers)                    // 1–6
                        bindSpamVerdict(stmt, startingAt: 7, headers.spamVerdict)  // 7–8
                        sqlite3_bind_int(stmt, 9, Int32(Self.currentHeadersVersion))
                        bind(stmt, 10, messageID)
                    }
                    // An und Cc gehören zum Suchindex – nur die Personen neu.
                    try writeSearchPeople(messageID: messageID)
                }
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
        onWrite {
            logged("saveAttachment \(a.id)") { try insertAttachment(a) }
        }
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
            VALUES (?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                filename = excluded.filename,
                contentType = excluded.contentType,
                sizeBytes = excluded.sizeBytes,
                data = excluded.data,
                contentID = excluded.contentID,
                isInline = excluded.isInline
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
            if let contentID = a.contentID {
                bind(stmt, 7, contentID)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_int(stmt, 8, a.isInline ? 1 : 0)
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
        onWrite {
            logged("deleteAttachmentData \(id)") {
                try execute("UPDATE attachment SET data = NULL WHERE id = ?",
                            context: "deleteAttachmentData \(id)") { stmt in
                    bind(stmt, 1, id)
                }
            }
        }
    }

    // MARK: - Lesen

    /// Liest eine einzelne Nachricht.
    ///
    /// - Parameter id: Cache-ID der Nachricht.
    /// - Returns: Die Nachricht oder `nil`, wenn sie nicht im Cache liegt.
    func message(id: String) -> CachedMessage? {
        return onRead {
            let sql = "SELECT \(Self.messageColumns) FROM message WHERE id = ? LIMIT 1"
            guard let stmt = prepare(sql) else { return nil }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readMessage(stmt)
        }
    }

    /// Listeneinträge mehrerer Postfächer in einem Ordner.
    ///
    /// - Parameters:
    ///   - accountIDs: Postfächer.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Listeneinträge ohne Mailinhalt, absteigend nach Datum.
    func allMessages(accountIDs: [UUID], folder: String) -> [MessageListItem] {
        return onRead {
            guard !accountIDs.isEmpty else { return [] }
            let sql = """
                SELECT \(Self.listColumns) FROM message
                WHERE accountID IN (\(Self.placeholders(accountIDs.count))) AND folder = ?
                ORDER BY date DESC
                """
            return query(sql, bind: { stmt in
                let next = bind(stmt, accountIDs: accountIDs)
                bind(stmt, next, folder)
            }) { stmt in
                readListItem(stmt)
            }
        }
    }

    /// Listeneinträge eines einzelnen Ordners eines Postfachs.
    ///
    /// Verarbeitung: Kurzform von `allMessages` mit einem Postfach.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Listeneinträge ohne Mailinhalt, absteigend nach Datum.
    func folderMessages(accountID: UUID, folder: String) -> [MessageListItem] {
        allMessages(accountIDs: [accountID], folder: folder)
    }

    /// Listeneinträge mehrerer Ordner, je Postfach ein eigener Ordner
    /// (z. B. die Spam-Ordner aller Postfächer).
    ///
    /// - Parameter folders: Ordner je Postfach.
    /// - Returns: Listeneinträge ohne Mailinhalt, absteigend nach Datum.
    func messages(in folders: [FolderKey]) -> [MessageListItem] {
        return onRead {
            guard !folders.isEmpty else { return [] }
            let sql = """
                SELECT \(Self.listColumns) FROM message
                WHERE \(Self.folderCondition(folders.count))
                ORDER BY date DESC
                """
            return query(sql, bind: { stmt in
                _ = bind(stmt, folders: folders, from: 1)
            }) { stmt in
                readListItem(stmt)
            }
        }
    }

    /// Ungelesene Listeneinträge aus den Posteingängen mehrerer Postfächer,
    /// dazu die übergebenen Mails, auch wenn sie inzwischen gelesen sind.
    ///
    /// Verarbeitung: Die Sicht „Ungelesen“ behält Mails, die während ihres
    /// Besuchs gelesen wurden, bis sie verlassen wird – deshalb die Liste
    /// `keeping`. Mails, die nicht mehr im Posteingang liegen (gelöscht,
    /// verschoben), entfallen trotzdem.
    ///
    /// - Parameters:
    ///   - accountIDs: Postfächer.
    ///   - keeping: Cache-IDs, die unabhängig vom Gelesen-Status bleiben.
    /// - Returns: Listeneinträge ohne Mailinhalt, absteigend nach Datum.
    func unreadInboxMessages(accountIDs: [UUID], keeping: Set<String> = []) -> [MessageListItem] {
        return onRead {
            guard !accountIDs.isEmpty else { return [] }
            let kept = Array(keeping)
            let keepCondition = kept.isEmpty ? "" : " OR id IN (\(Self.placeholders(kept.count)))"
            let sql = """
                SELECT \(Self.listColumns) FROM message
                WHERE accountID IN (\(Self.placeholders(accountIDs.count))) AND folder = ?
                AND (isUnread = 1\(keepCondition))
                ORDER BY date DESC
                """
            return query(sql, bind: { stmt in
                let next = bind(stmt, accountIDs: accountIDs)
                bind(stmt, next, MailFolder.inboxPath)
                for (offset, id) in kept.enumerated() {
                    bind(stmt, next + 1 + Int32(offset), id)
                }
            }) { stmt in
                readListItem(stmt)
            }
        }
    }

    /// Anzahl ungelesener Nachrichten in den Posteingängen.
    ///
    /// - Parameter accountIDs: Postfächer.
    /// - Returns: Anzahl.
    func unreadInboxCount(accountIDs: [UUID]) -> Int {
        return onRead {
            guard !accountIDs.isEmpty else { return 0 }
            let sql = """
                SELECT COUNT(*) FROM message
                WHERE accountID IN (\(Self.placeholders(accountIDs.count))) AND folder = ? AND isUnread = 1
                """
            return queryFirst(sql, bind: { stmt in
                let next = bind(stmt, accountIDs: accountIDs)
                bind(stmt, next, MailFolder.inboxPath)
            }) { stmt in
                Int(sqlite3_column_int(stmt, 0))
            } ?? 0
        }
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
        onWrite {
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
    }

    /// Gespeicherter Sync-Zustand eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Der Zustand oder `nil`, wenn noch keiner gespeichert ist.
    func syncState(accountID: UUID, folder: String) -> FolderSyncState? {
        return onRead {
            let sql = "SELECT uidValidity, uidNext FROM folder_sync WHERE accountID = ? AND folder = ?"
            return queryFirst(sql, bind: { stmt in
                bindFolder(stmt, accountID: accountID, folder: folder)
            }) { stmt -> FolderSyncState? in
                guard sqlite3_column_type(stmt, 0) != SQLITE_NULL,
                      sqlite3_column_type(stmt, 1) != SQLITE_NULL else { return nil }
                return FolderSyncState(
                    uidValidity: UInt32(truncatingIfNeeded: sqlite3_column_int64(stmt, 0)),
                    uidNext: UInt32(truncatingIfNeeded: sqlite3_column_int64(stmt, 1))
                )
            }
        }
    }

    /// Letzter erfolgreicher Abruf eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Zeitpunkt oder `nil`, wenn noch nie abgerufen.
    func lastSync(accountID: UUID, folder: String) -> Date? {
        return onRead {
            let sql = "SELECT lastSyncAt FROM folder_sync WHERE accountID = ? AND folder = ?"
            return queryFirst(sql, bind: { stmt in
                bindFolder(stmt, accountID: accountID, folder: folder)
            }) { stmt in
                Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
            }
        }
    }

    // MARK: - Zeitfenster je Ordner

    /// Beginn des erweiterten Zeitfensters eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Fensterbeginn oder `nil` (= Standardfenster).
    func windowStart(accountID: UUID, folder: String) -> Date? {
        return onRead {
            let sql = "SELECT windowStart FROM folder_window WHERE accountID = ? AND folder = ?"
            return queryFirst(sql, bind: { stmt in
                bindFolder(stmt, accountID: accountID, folder: folder)
            }) { stmt in
                Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
            }
        }
    }

    /// Speichert den Beginn des erweiterten Zeitfensters eines Ordners.
    ///
    /// - Parameters:
    ///   - date: Neuer Fensterbeginn.
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    func setWindowStart(_ date: Date, accountID: UUID, folder: String) {
        onWrite {
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
    }

    /// Gekennzeichnete Listeneinträge aus den Posteingängen mehrerer Postfächer.
    ///
    /// - Parameter accountIDs: Postfächer.
    /// - Returns: Listeneinträge ohne Mailinhalt, absteigend nach Datum.
    func flaggedInboxMessages(accountIDs: [UUID]) -> [MessageListItem] {
        return onRead {
            guard !accountIDs.isEmpty else { return [] }
            let sql = """
                SELECT \(Self.listColumns) FROM message
                WHERE accountID IN (\(Self.placeholders(accountIDs.count))) AND folder = ? AND isFlagged = 1
                ORDER BY date DESC
                """
            return query(sql, bind: { stmt in
                let next = bind(stmt, accountIDs: accountIDs)
                bind(stmt, next, MailFolder.inboxPath)
            }) { stmt in
                readListItem(stmt)
            }
        }
    }

    /// Anzahl gekennzeichneter Nachrichten in den Posteingängen.
    ///
    /// - Parameter accountIDs: Postfächer.
    /// - Returns: Anzahl.
    func flaggedInboxCount(accountIDs: [UUID]) -> Int {
        return onRead {
            guard !accountIDs.isEmpty else { return 0 }
            let sql = """
                SELECT COUNT(*) FROM message
                WHERE accountID IN (\(Self.placeholders(accountIDs.count))) AND folder = ? AND isFlagged = 1
                """
            return queryFirst(sql, bind: { stmt in
                let next = bind(stmt, accountIDs: accountIDs)
                bind(stmt, next, MailFolder.inboxPath)
            }) { stmt in
                Int(sqlite3_column_int(stmt, 0))
            } ?? 0
        }
    }

    /// Cache-IDs aller Nachrichten eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Menge der Cache-IDs.
    func cachedMessageIDs(forAccount accountID: UUID, folder: String) -> Set<String> {
        return onRead {
            let sql = "SELECT id FROM message WHERE accountID = ? AND folder = ?"
            return Set(query(sql, bind: { stmt in
                bind(stmt, 1, accountID.uuidString)
                bind(stmt, 2, folder)
            }) { stmt in
                columnText(stmt, 0)
            })
        }
    }

    /// UIDs aller gecachten Nachrichten eines Ordners.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Menge der UIDs.
    func cachedUIDs(accountID: UUID, folder: String) -> Set<UInt32> {
        return onRead {
            let sql = "SELECT uid FROM message WHERE accountID = ? AND folder = ?"
            return Set(query(sql, bind: { stmt in
                bind(stmt, 1, accountID.uuidString)
                bind(stmt, 2, folder)
            }) { stmt in
                UInt32(truncatingIfNeeded: sqlite3_column_int64(stmt, 0))
            })
        }
    }

    /// Anhänge einer Nachricht.
    ///
    /// - Parameter messageID: Cache-ID der Nachricht.
    /// - Returns: Alle zugehörigen Anhänge.
    func attachments(forMessage messageID: String) -> [CachedAttachment] {
        return onRead {
            let sql = "SELECT \(Self.attachmentColumns) FROM attachment WHERE messageID = ?"
            return query(sql, bind: { stmt in
                bind(stmt, 1, messageID)
            }) { stmt in
                readAttachment(stmt)
            }
        }
    }

    // MARK: - Ordnerliste

    /// Speichert die Ordnerliste eines Postfachs und ersetzt die bisherige.
    ///
    /// - Parameters:
    ///   - listing: Ordnerstruktur.
    ///   - accountID: Postfach.
    func saveFolderListing(_ listing: FolderListing, accountID: UUID) {
        onWrite {
            let json: String
            do {
                json = String(decoding: try JSONEncoder().encode(listing), as: UTF8.self)
            } catch {
                Log.store.error("⚠️ Ordnerliste nicht kodierbar, nicht gespeichert: \(error.localizedDescription, privacy: .public)")
                return
            }
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
    }

    /// Gespeicherte Ordnerliste eines Postfachs.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: Ordnerliste oder `nil`, wenn keine vorliegt oder sie
    ///   nicht mehr lesbar ist.
    func folderListing(accountID: UUID) -> FolderListing? {
        return onRead {
            guard let stmt = prepare("SELECT json FROM folder_listing WHERE accountID = ?") else { return nil }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, accountID.uuidString)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return try? JSONDecoder().decode(FolderListing.self, from: Data(columnText(stmt, 0).utf8))
        }
    }

    // MARK: - Absenderlogos

    /// Speichert das Logo einer Domain bzw. den erfolglosen Versuch und
    /// ersetzt einen vorhandenen Eintrag.
    ///
    /// - Parameter record: Logo mit Prüfzeitpunkt; `imageData` `nil` = kein Logo.
    func saveSenderIcon(_ record: SenderIconRecord) {
        onWrite {
            let sql = """
                INSERT INTO sender_icon (domain, image, checkedAt) VALUES (?, ?, ?)
                ON CONFLICT(domain) DO UPDATE SET image = excluded.image, checkedAt = excluded.checkedAt
                """
            logged("saveSenderIcon") {
                try execute(sql, context: "saveSenderIcon") { stmt in
                    bind(stmt, 1, record.domain)
                    if let data = record.imageData, !data.isEmpty {
                        _ = data.withUnsafeBytes { ptr in
                            sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                        }
                    } else {
                        sqlite3_bind_null(stmt, 2)
                    }
                    sqlite3_bind_double(stmt, 3, record.checkedAt.timeIntervalSince1970)
                }
            }
        }
    }

    /// Gespeichertes Logo einer Domain.
    ///
    /// - Parameter domain: Hauptdomain.
    /// - Returns: Eintrag oder `nil`, wenn die Domain noch nie geprüft wurde.
    func senderIcon(domain: String) -> SenderIconRecord? {
        return onRead {
            guard let stmt = prepare("SELECT image, checkedAt FROM sender_icon WHERE domain = ?") else { return nil }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, domain)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            var data: Data?
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL, let bytes = sqlite3_column_blob(stmt, 0) {
                data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
            }
            return SenderIconRecord(
                domain: domain,
                imageData: data,
                checkedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            )
        }
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
        return onWrite {
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
        onWrite {
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
    }

    /// Entfernt eine einzelne Nachricht samt Anhängen aus dem Cache.
    ///
    /// Verarbeitung: Wird nach erfolgreichem Löschen oder Verschieben auf
    /// dem Server aufgerufen. Anhänge folgen über ON DELETE CASCADE.
    ///
    /// - Parameter id: Cache-ID der Nachricht.
    func deleteMessage(id: String) {
        onWrite {
            logged("deleteMessage \(id)") { try removeMessage(id: id) }
        }
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
        return onWrite {
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
    }

    // MARK: - Suchindex

    /// Schreibt den Eintrag einer Nachricht im Suchindex neu.
    ///
    /// Verarbeitung: Liest Betreff, Absender, An, Cc, Text und HTML der
    /// Nachricht sowie die Namen ihrer echten Anhänge (ohne eingebettete
    /// Bilder) aus der Ablage, bereitet sie über `SearchText` auf und
    /// ersetzt den Eintrag mit der Zeilennummer der Nachricht. Fehlt die
    /// Nachricht, passiert nichts.
    ///
    /// - Parameter messageID: Cache-ID der Nachricht.
    /// - Throws: `StoreError`, wenn Lesen oder Schreiben fehlschlägt.
    private func writeSearchEntry(messageID: String) throws {
        guard hasSearchIndex else { return }
        let readSQL = """
            SELECT rowid, subject, "from", toJSON, ccJSON, textBody, htmlBody,
                   (SELECT group_concat(filename, char(10)) FROM attachment
                    WHERE messageID = message.id AND isInline = 0)
            FROM message WHERE id = ?
            """
        guard let stmt = prepare(readSQL) else {
            throw StoreError.prepare(context: "writeSearchEntry \(messageID)", message: errorMessage)
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, messageID)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return }

        let rowID = sqlite3_column_int64(stmt, 0)
        let entry = SearchText.Entry(
            subject: columnText(stmt, 1),
            people: SearchText.people(
                from: columnText(stmt, 2),
                to: decodeList(optionalColumnText(stmt, 3)),
                cc: decodeList(optionalColumnText(stmt, 4))
            ),
            body: SearchText.body(text: optionalColumnText(stmt, 5), html: optionalColumnText(stmt, 6)),
            attachments: optionalColumnText(stmt, 7) ?? ""
        )

        try execute("DELETE FROM message_search WHERE rowid = ?",
                    context: "writeSearchEntry/delete \(messageID)") { s in
            sqlite3_bind_int64(s, 1, rowID)
        }
        try execute("""
            INSERT INTO message_search (rowid, subject, people, body, attachments)
            VALUES (?, ?, ?, ?, ?)
            """, context: "writeSearchEntry/insert \(messageID)") { s in
            sqlite3_bind_int64(s, 1, rowID)
            bind(s, 2, entry.subject)
            bind(s, 3, entry.people)
            bind(s, 4, entry.body)
            bind(s, 5, entry.attachments)
        }
    }

    /// Schreibt nur die Personen (Von, An, Cc) im Suchindex neu.
    ///
    /// Verarbeitung: Liest Absender und Adresslisten der Nachricht und
    /// aktualisiert die Spalte `people` ihres Eintrags. Hat die Nachricht
    /// noch keinen Eintrag, wird er vollständig geschrieben
    /// (`writeSearchEntry`). Fehlt die Nachricht, passiert nichts.
    ///
    /// - Parameter messageID: Cache-ID der Nachricht.
    /// - Throws: `StoreError`, wenn Lesen oder Schreiben fehlschlägt.
    private func writeSearchPeople(messageID: String) throws {
        guard hasSearchIndex else { return }
        guard let stmt = prepare("""
            SELECT rowid, "from", toJSON, ccJSON FROM message WHERE id = ?
            """) else {
            throw StoreError.prepare(context: "writeSearchPeople \(messageID)", message: errorMessage)
        }
        bind(stmt, 1, messageID)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            sqlite3_finalize(stmt)
            return
        }
        let rowID = sqlite3_column_int64(stmt, 0)
        let people = SearchText.people(
            from: columnText(stmt, 1),
            to: decodeList(optionalColumnText(stmt, 2)),
            cc: decodeList(optionalColumnText(stmt, 3))
        )
        sqlite3_finalize(stmt)

        try execute("UPDATE message_search SET people = ? WHERE rowid = ?",
                    context: "writeSearchPeople \(messageID)") { s in
            bind(s, 1, people)
            sqlite3_bind_int64(s, 2, rowID)
        }
        if sqlite3_changes(db) == 0 {
            // Noch kein Eintrag (z. B. vor dem Nachtragen): vollständig schreiben.
            try writeSearchEntry(messageID: messageID)
        }
    }

    /// Trägt fehlende Einträge im Suchindex nach.
    ///
    /// Verarbeitung: Sucht bis zu `limit` Nachrichten ohne Eintrag (die
    /// neuesten zuerst, damit aktuelle Mails schnell auffindbar sind) und
    /// schreibt ihre Einträge in einer Transaktion. Der Aufrufer wiederholt,
    /// bis 0 zurückkommt (`SearchIndexBuilder`). Scheitert ein Paket, wird
    /// es zurückgerollt und 0 gemeldet, damit keine Endlosschleife entsteht.
    ///
    /// - Parameter limit: Höchstzahl der Nachrichten je Aufruf.
    /// - Returns: Anzahl der nachgetragenen Nachrichten.
    @discardableResult
    func indexMissingSearchEntries(limit: Int) -> Int {
        return onWrite {
            guard hasSearchIndex else { return 0 }
            let sql = """
                SELECT id FROM message
                WHERE rowid NOT IN (SELECT rowid FROM message_search)
                ORDER BY date DESC LIMIT ?
                """
            guard let stmt = prepare(sql) else { return 0 }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var ids: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.append(columnText(stmt, 0))
            }
            sqlite3_finalize(stmt)
            guard !ids.isEmpty else { return 0 }

            let ok = logged("indexMissingSearchEntries") {
                try transaction {
                    for id in ids {
                        try writeSearchEntry(messageID: id)
                    }
                }
            }
            return ok ? ids.count : 0
        }
    }

    // MARK: - Suche

    /// Cache-IDs der Mails im Suchbereich, die einen Suchausdruck erfüllen.
    ///
    /// Verarbeitung: Fragt den Suchindex mit `MATCH` und schränkt auf
    /// Postfächer, Ordner und ggf. Kennzeichnung ein. Ohne Suchindex ist
    /// das Ergebnis leer.
    ///
    /// - Parameters:
    ///   - scope: Suchbereich.
    ///   - match: FTS5-Ausdruck (`SearchText.matchExpression`).
    /// - Returns: Cache-IDs der Treffer.
    func searchMessageIDs(in scope: SearchScope, match: String) -> Set<String> {
        return onRead {
            guard hasSearchIndex, !scope.folders.isEmpty else { return [] }
            let sql = """
                SELECT id FROM message
                WHERE \(Self.folderCondition(scope.folders.count))
                \(scope.flaggedOnly ? "AND isFlagged = 1" : "")
                AND rowid IN (SELECT rowid FROM message_search WHERE message_search MATCH ?)
                """
            return Set(query(sql, bind: { stmt in
                let next = bind(stmt, folders: scope.folders, from: 1)
                bind(stmt, next, match)
            }) { stmt in
                columnText(stmt, 0)
            })
        }
    }

    /// Alle Adressen (Von, An, Cc) der Mails im Suchbereich – Quelle der
    /// Namensvorschläge.
    ///
    /// - Parameter scope: Suchbereich.
    /// - Returns: Formatierte Adressen ohne Doppelte, ungeordnet.
    func participantAddresses(in scope: SearchScope) -> [String] {
        return onRead {
            guard !scope.folders.isEmpty else { return [] }
            let sql = """
                SELECT "from", toJSON, ccJSON FROM message
                WHERE \(Self.folderCondition(scope.folders.count))
                \(scope.flaggedOnly ? "AND isFlagged = 1" : "")
                """
            guard let stmt = prepare(sql) else { return [] }
            defer { sqlite3_finalize(stmt) }
            _ = bind(stmt, folders: scope.folders, from: 1)
            var addresses = Set<String>()
            // Gleiche JSON-Listen kommen oft vor (z. B. immer „An: ich“) –
            // jede nur einmal entschlüsseln.
            var decoded = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                addresses.insert(columnText(stmt, 0))
                for json in [optionalColumnText(stmt, 1), optionalColumnText(stmt, 2)].compactMap({ $0 }) where decoded.insert(json).inserted {
                    addresses.formUnion(decodeList(json))
                }
            }
            return Array(addresses)
        }
    }

    // MARK: - Transaktionen und Schreib-Helfer

    /// Führt einen Block in einer Transaktion aus; lässt sich verschachteln.
    ///
    /// Verarbeitung: Die äußerste Ebene beginnt mit `BEGIN` und endet mit
    /// `COMMIT`; wirft der Block oder scheitert das COMMIT, folgt
    /// `ROLLBACK`. Jede innere Ebene ist ein `SAVEPOINT`: Erfolg gibt ihn
    /// frei (`RELEASE`), ein Fehler rollt nur bis zu ihm zurück
    /// (`ROLLBACK TO`) und gibt ihn danach frei. Der Fehler wird in jedem
    /// Fall weitergegeben – die umgebende Ebene entscheidet, ob sie ihn
    /// abfängt.
    ///
    /// - Parameter body: Schreibschritte der Transaktion.
    /// - Returns: Ergebnis von `body`.
    /// - Throws: Fehler aus `body` oder `StoreError.exec`.
    @discardableResult
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        let depth = transactionDepth
        let savepoint = "mw_sp\(depth)"
        if depth == 0 {
            try execOrThrow("BEGIN TRANSACTION")
        } else {
            try execOrThrow("SAVEPOINT \(savepoint)")
        }
        transactionDepth += 1
        defer { transactionDepth -= 1 }
        do {
            let result = try body()
            if depth == 0 {
                try execOrThrow("COMMIT")
            } else {
                try execOrThrow("RELEASE \(savepoint)")
            }
            return result
        } catch {
            if depth == 0 {
                exec("ROLLBACK")
            } else {
                exec("ROLLBACK TO \(savepoint)")
                exec("RELEASE \(savepoint)")
            }
            throw error
        }
    }

    /// Führt mehrere Schreibvorgänge in einem gemeinsamen Commit aus.
    ///
    /// Verarbeitung: Öffnet eine Transaktion, in der die öffentlichen
    /// Schreibfunktionen des Blocks als Savepoints laufen. Scheitert ein
    /// einzelner Schreibvorgang, rollt nur er zurück und meldet das wie
    /// gewohnt über seinen Rückgabewert bzw. das Protokoll; die übrigen
    /// bleiben erhalten. Am Ende steht ein einziges COMMIT statt eines je
    /// Vorgang. Scheitert dieses COMMIT, ist nichts aus dem Block
    /// gespeichert – das meldet der Rückgabewert.
    /// Nicht für `relocateMessage` verwenden: Das Abschalten der
    /// Fremdschlüssel wirkt innerhalb einer Transaktion nicht.
    ///
    /// - Parameters:
    ///   - context: Kurzbeschreibung für das Protokoll.
    ///   - body: Schreibvorgänge.
    /// - Returns: `true`, wenn das gemeinsame COMMIT gelang.
    @discardableResult
    func batch(_ context: String, _ body: () -> Void) -> Bool {
        return onWrite {
            logged("batch \(context)") {
                try transaction { body() }
            }
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
        // Innerhalb einer Transaktion wäre das Umschalten wirkungslos.
        assert(transactionDepth == 0, "withForeignKeysDisabled innerhalb einer Transaktion")
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
            Log.store.error("🗄️ Schreiben fehlgeschlagen (\(context, privacy: .public)): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Führt einen Schreibbefehl mit Parametern aus.
    ///
    /// Verarbeitung: Holt die vorbereitete Anweisung aus dem Cache oder
    /// bereitet sie einmal vor (`cachedStatement`), bindet die Parameter und
    /// erwartet `SQLITE_DONE`; jedes andere Ergebnis gilt als Fehler. Danach
    /// wird die Anweisung in jedem Fall zurückgesetzt und ihre Bindungen
    /// gelöscht – so hält sie keine Sperre und keine Werte fest.
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
        guard let stmt = cachedStatement(sql) else {
            throw StoreError.prepare(context: context, message: errorMessage)
        }
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        bindValues(stmt)
        let code = sqlite3_step(stmt)
        guard code == SQLITE_DONE else {
            throw StoreError.step(context: context, code: code, message: errorMessage)
        }
    }

    /// Vorbereitete Anweisung zu einem SQL-Text, bei Bedarf neu angelegt.
    ///
    /// Verarbeitung: Die Anzahl verschiedener Texte ist begrenzt (feste
    /// Befehle, wenige Tabellen- bzw. Spaltennamen), der Cache wächst daher
    /// nicht unbegrenzt. SQLite übersetzt eine Anweisung nach einer
    /// Schemaänderung selbst neu (`sqlite3_prepare_v2`).
    ///
    /// - Parameter sql: SQL-Text.
    /// - Returns: Anweisung oder `nil`, wenn sie sich nicht vorbereiten lässt.
    private func cachedStatement(_ sql: String) -> OpaquePointer? {
        if let stmt = statementCache[sql] { return stmt }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_finalize(stmt)
            return nil
        }
        statementCache[sql] = stmt
        return stmt
    }

    /// Führt einen Befehl ohne Parameter aus und wirft bei einem Fehler.
    ///
    /// - Parameter sql: SQL-Befehl (z. B. BEGIN, COMMIT).
    /// - Throws: `StoreError.exec`.
    private func execOrThrow(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.exec(sql: sql, message: errorMessage)
        }
    }

    // MARK: - Interne Helfer

    /// Liest eine Zeile gemäß `messageColumns` (Indizes 0–25).
    ///
    /// - Parameter s: Statement, das auf einer Ergebniszeile steht.
    /// - Returns: Die gelesene Nachricht.
    private func readMessage(_ s: OpaquePointer?) -> CachedMessage {
        let dateVal = sqlite3_column_type(s, 7) != SQLITE_NULL
            ? sqlite3_column_double(s, 7) : nil
        let headers = CachedMessageHeaders(
            toList: decodeList(optionalColumnText(s, 17)),
            ccList: decodeList(optionalColumnText(s, 18)),
            replyToList: decodeList(optionalColumnText(s, 19)),
            rfcMessageID: optionalColumnText(s, 20),
            rfcInReplyTo: optionalColumnText(s, 21),
            rfcReferences: optionalColumnText(s, 22),
            spamVerdict: readSpamVerdict(s, startingAt: 24)
        )
        return CachedMessage(
            id: columnText(s, 0),
            accountID: UUID(uuidString: columnText(s, 1)) ?? UUID(),
            accountDisplayName: columnText(s, 2),
            folder: columnText(s, 23),
            uid: UInt32(truncatingIfNeeded: sqlite3_column_int64(s, 3)),
            subject: columnText(s, 4),
            from: columnText(s, 5),
            to: columnText(s, 6),
            date: dateVal.map { Date(timeIntervalSince1970: $0) },
            isUnread: sqlite3_column_int(s, 8) != 0,
            isFlagged: sqlite3_column_int(s, 9) != 0,
            isAnswered: sqlite3_column_int(s, 10) != 0,
            isForwarded: sqlite3_column_int(s, 11) != 0,
            totalSizeBytes: Int(sqlite3_column_int64(s, 12)),
            hasAttachments: sqlite3_column_int(s, 13) != 0,
            textBody: optionalColumnText(s, 14),
            htmlBody: optionalColumnText(s, 15),
            fetchedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 16)),
            headers: headers
        )
    }

    /// Liest eine Zeile gemäß `listColumns` (Indizes 0–15).
    ///
    /// - Parameter s: Statement, das auf einer Ergebniszeile steht.
    /// - Returns: Der gelesene Listeneintrag.
    private func readListItem(_ s: OpaquePointer?) -> MessageListItem {
        let dateVal = sqlite3_column_type(s, 6) != SQLITE_NULL
            ? sqlite3_column_double(s, 6) : nil
        return MessageListItem(
            id: columnText(s, 0),
            accountID: UUID(uuidString: columnText(s, 1)) ?? UUID(),
            folder: columnText(s, 2),
            uid: UInt32(truncatingIfNeeded: sqlite3_column_int64(s, 3)),
            subject: columnText(s, 4),
            from: columnText(s, 5),
            recipients: decodeList(optionalColumnText(s, 13)),
            date: dateVal.map { Date(timeIntervalSince1970: $0) },
            isUnread: sqlite3_column_int(s, 7) != 0,
            isFlagged: sqlite3_column_int(s, 8) != 0,
            isAnswered: sqlite3_column_int(s, 9) != 0,
            isForwarded: sqlite3_column_int(s, 10) != 0,
            hasAttachments: sqlite3_column_int(s, 11) != 0,
            sizeBytes: Int(sqlite3_column_int64(s, 12)),
            spamVerdict: readSpamVerdict(s, startingAt: 14)
        )
    }

    /// Liest eine Zeile gemäß `attachmentColumns` (Indizes 0–7).
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
            id: columnText(s, 0),
            messageID: columnText(s, 1),
            filename: columnText(s, 2),
            contentType: columnText(s, 3),
            sizeBytes: Int(sqlite3_column_int64(s, 4)),
            data: data,
            contentID: optionalColumnText(s, 6),
            isInline: sqlite3_column_int(s, 7) != 0
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

    /// Bindet die Spam-Angabe an zwei Platzhalter (`spamFlag`, `spamScore`).
    ///
    /// Verarbeitung: Ohne Angabe („unbekannt“) bleiben beide NULL; sonst
    /// steht im ersten 1 oder 0, im zweiten der Score oder NULL.
    ///
    /// - Parameters:
    ///   - s: Vorbereitetes Statement.
    ///   - i: Position des ersten Platzhalters.
    ///   - verdict: Spam-Angabe oder `nil`.
    private func bindSpamVerdict(_ s: OpaquePointer?, startingAt i: Int32, _ verdict: SpamHeaderVerdict?) {
        guard let verdict else {
            sqlite3_bind_null(s, i)
            sqlite3_bind_null(s, i + 1)
            return
        }
        sqlite3_bind_int(s, i, verdict.isSpam ? 1 : 0)
        if let score = verdict.score { sqlite3_bind_double(s, i + 1, score) }
        else { sqlite3_bind_null(s, i + 1) }
    }

    /// Liest die Spam-Angabe aus zwei Spalten (`spamFlag`, `spamScore`).
    ///
    /// - Parameters:
    ///   - s: Statement, das auf einer Ergebniszeile steht.
    ///   - i: Index der Spalte `spamFlag`.
    /// - Returns: Spam-Angabe oder `nil`, wenn sie unbekannt ist.
    private func readSpamVerdict(_ s: OpaquePointer?, startingAt i: Int32) -> SpamHeaderVerdict? {
        guard sqlite3_column_type(s, i) != SQLITE_NULL else { return nil }
        let score = sqlite3_column_type(s, i + 1) != SQLITE_NULL
            ? sqlite3_column_double(s, i + 1) : nil
        return SpamHeaderVerdict(isSpam: sqlite3_column_int(s, i) != 0, score: score)
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
              let data = try? Self.listEncoder.encode(list) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Dekodiert eine als JSON gespeicherte Adressliste.
    ///
    /// - Parameter json: JSON-Text oder `nil`.
    /// - Returns: Adressen; leer bei fehlendem oder unlesbarem Wert.
    private func decodeList(_ json: String?) -> [String] {
        guard let json,
              let data = json.data(using: .utf8),
              let list = try? Self.listDecoder.decode([String].self, from: data) else { return [] }
        return list
    }

    /// Liest eine Textspalte.
    ///
    /// - Parameters:
    ///   - s: Statement auf einer Ergebniszeile.
    ///   - col: Spaltenindex.
    /// - Returns: Text; leer bei NULL.
    private func columnText(_ s: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(s, col) else { return "" }
        return String(cString: c)
    }

    /// Liest eine optionale Textspalte.
    ///
    /// - Parameters:
    ///   - s: Statement auf einer Ergebniszeile.
    ///   - col: Spaltenindex.
    /// - Returns: Text oder `nil` bei NULL.
    private func optionalColumnText(_ s: OpaquePointer?, _ col: Int32) -> String? {
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

    /// Platzhalterliste für `IN (…)`.
    ///
    /// - Parameter count: Anzahl der Werte (mindestens 1).
    /// - Returns: z. B. „?,?,?“ für drei Werte.
    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    /// Bedingung „Mail liegt in einem dieser Ordner“ für mehrere Paare aus
    /// Postfach und Ordner.
    ///
    /// - Parameter count: Anzahl der Paare (mindestens 1).
    /// - Returns: z. B. „((accountID = ? AND folder = ?) OR (…))“.
    private static func folderCondition(_ count: Int) -> String {
        "(" + Array(repeating: "(accountID = ? AND folder = ?)", count: count).joined(separator: " OR ") + ")"
    }

    /// Bindet Paare aus Postfach und Ordner an die Platzhalter von
    /// `folderCondition`.
    ///
    /// - Parameters:
    ///   - s: Vorbereitetes Statement.
    ///   - folders: Ordner je Postfach in Platzhalter-Reihenfolge.
    ///   - start: Position des ersten Platzhalters.
    /// - Returns: Nächste freie Platzhalter-Position.
    private func bind(_ s: OpaquePointer?, folders: [FolderKey], from start: Int32) -> Int32 {
        var index = start
        for key in folders {
            bind(s, index, key.accountID.uuidString)
            bind(s, index + 1, key.folder)
            index += 2
        }
        return index
    }

    /// Bindet Postfach-IDs ab Position 1 an die Platzhalter einer
    /// `IN (…)`-Liste.
    ///
    /// - Parameters:
    ///   - s: Vorbereitetes Statement.
    ///   - accountIDs: Postfach-IDs in Platzhalter-Reihenfolge.
    /// - Returns: Nächste freie Platzhalter-Position.
    private func bind(_ s: OpaquePointer?, accountIDs: [UUID]) -> Int32 {
        for (offset, id) in accountIDs.enumerated() {
            bind(s, Int32(offset + 1), id.uuidString)
        }
        return Int32(accountIDs.count + 1)
    }

    /// Bindet Postfach und Ordner an die Platzhalter 1 und 2 – die häufigste
    /// Bedingung „accountID = ? AND folder = ?“.
    ///
    /// - Parameters:
    ///   - s: Vorbereitetes Statement.
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    private func bindFolder(_ s: OpaquePointer?, accountID: UUID, folder: String) {
        bind(s, 1, accountID.uuidString)
        bind(s, 2, folder)
    }

    /// Führt eine lesende Abfrage aus und bildet jede Ergebniszeile ab.
    ///
    /// Verarbeitung: Vorbereiten, Werte binden, alle Zeilen lesen, die
    /// Anweisung freigeben – an einer Stelle statt in jeder Abfrage. Lässt
    /// sich die Abfrage nicht vorbereiten, ist das Ergebnis leer (der
    /// Fehler ist dann protokolliert, siehe `prepare`).
    ///
    /// - Parameters:
    ///   - sql: Abfrage.
    ///   - bind: Bindet die Werte an die Platzhalter.
    ///   - row: Bildet die aktuelle Zeile ab.
    /// - Returns: Abgebildete Zeilen in der Reihenfolge des Ergebnisses.
    private func query<T>(
        _ sql: String,
        bind: (OpaquePointer) -> Void = { _ in },
        row: (OpaquePointer) -> T
    ) -> [T] {
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        var rows: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(row(stmt))
        }
        return rows
    }

    /// Führt eine lesende Abfrage aus und bildet nur die erste Zeile ab.
    ///
    /// Verarbeitung: Wie `query`, liest aber höchstens eine Zeile – für
    /// Einzelwerte (Anzahl, Zeitpunkt, Zustand).
    ///
    /// - Parameters:
    ///   - sql: Abfrage.
    ///   - bind: Bindet die Werte an die Platzhalter.
    ///   - row: Bildet die Zeile ab; `nil` = Zeile unbrauchbar.
    /// - Returns: Abgebildete erste Zeile; `nil` ohne Ergebnis.
    private func queryFirst<T>(
        _ sql: String,
        bind: (OpaquePointer) -> Void = { _ in },
        row: (OpaquePointer) -> T?
    ) -> T? {
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return row(stmt)
    }

    /// Bereitet eine Leseabfrage vor.
    ///
    /// - Parameter sql: SQL-Abfrage.
    /// - Returns: Statement oder `nil` bei einem Fehler (wird protokolliert).
    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.store.error("🗄️ SQL-Fehler: \(self.errorMessage, privacy: .public) – \(String(sql.prefix(80)), privacy: .public)")
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
        if !ok { Log.store.error("🗄️ SQL-Fehler: \(self.errorMessage, privacy: .public) – \(String(sql.prefix(80)), privacy: .public)") }
        return ok
    }
}
