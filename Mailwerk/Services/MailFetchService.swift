//
//  MailFetchService.swift
//  Mailwerk
//
//  Zweck: Holt Mails von IMAP-Servern und legt sie im lokalen Cache ab.
//
//  Zugangspunkte:
//  - `refreshAndCache`: Abruf der letzten 30 Tage (plus gekennzeichnete
//    und ungelesene im Posteingang, unabhängig vom Alter) mit
//    anschließendem Abgleich.
//  - `fetchOlder`: Zeitfenster blockweise zurückschieben.
//  - `searchOnServer`: Suche in einem Ordner auf dem Server; liefert nur
//    Kopfdaten der Treffer, die nicht im Cache liegen (nichts wird
//    gespeichert).
//  - `loadMessage`: lädt eine einzelne Mail (z. B. einen Suchtreffer vom
//    Server) und speichert sie im Cache.
//  - `reconcile` (privat): Vergleicht den ganzen Ordner mit dem Cache,
//    entfernt Gelöschtes und aktualisiert Flags.
//
//  Sync-Zustand je Ordner (UIDVALIDITY und UIDNEXT, siehe
//  SyncStatePlanner): Mails, die seit dem letzten Abruf in einen Ordner
//  gekommen sind, werden unabhängig von ihrem Datum geladen – auch eine
//  im Webmail hineinkopierte, alt datierte Mail. Ändert sich die
//  UIDVALIDITY, wird der Cache des Ordners verworfen und neu aufgebaut.
//
//  Robustheit bei Verbindungsabbrüchen: SwiftMail stellt eine abgerissene
//  Verbindung still wieder her, wählt den Ordner aber nicht neu aus.
//  Schlägt eine Mail fehl, wird der Ordner deshalb neu ausgewählt und die
//  Mail einmal wiederholt. Fensterbeginn und UIDNEXT rücken nur vor, wenn
//  alle Mails eines Schritts gespeichert wurden – so entstehen keine Lücken.
//
//  Laden einer neuen Mail: Zuerst nur ihre Struktur, dann gezielt Text
//  und HTML; Anhänge einzeln und nur bei Mails bis 5 MB. Eingebettete
//  Bilder und weitergeleitete Mails werden nicht übertragen (siehe
//  MessageContentPlan). So fließt jeder Teil höchstens einmal.
//
//  Suche: Immer ohne Server-Sortierung (SORT fehlt z. B. bei Gmail); die
//  Reihenfolge ordnet `searchNewestFirst` selbst. Die Serversuche nutzt
//  TEXT (Kopf und Inhalt, damit auch Betreff und Anhangnamen) bzw. für
//  eine gewählte Person FROM/TO/CC; sie wählt den Ordner nur lesend aus
//  (EXAMINE).
//
//  Spam-Angabe: Die Kopfdaten-Abfrage holt die Spam-Kopfzeilen des
//  Servers (X-Spam, X-Spam-Flag, X-Spam-Status) gleich mit; ihre Einstufung wird mit
//  der Mail gespeichert. Mails im Cache mit älterer Header-Version
//  bekommen sie beim nächsten Abruf ihres Ordners nachgefüllt – ohne
//  zusätzliche Server-Abfrage, weil die Kopfdaten ohnehin geholt werden.
//
//  Abgrenzung: `MailActionService` setzt Flags und verschiebt Mails;
//  `MailSendService` versendet. Die Darstellung liegt im ViewModel.
//
//  Verbindung und Zugangsdaten kommen aus `MailSession`.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailSession (Verbindung),
//  MessageStore (Cache), ServerReconciliation (Abgleichslogik),
//  SyncStatePlanner (Sync-Zustand), SyncWindow (Zeitfenster),
//  MessageContentPlan (zu ladende Teile), FlagState (Flags), MailFolder,
//  SpamHeaderParser (Spam-Angabe), SearchText (Mindestlänge der Suche),
//  MessageListItem (Suchtreffer), Log.
//

import Foundation
import SwiftMail
import NIOIMAPCore
import os

/// Abruf von Mails und Abgleich des lokalen Caches.
enum MailFetchService {

    /// Maximale Nachrichtengröße (RFC822.SIZE) in Bytes, bis zu der
    /// Anhänge automatisch mitgeladen werden. Darüber: erst bei Tap.
    static let autoDownloadThreshold = 5 * 1024 * 1024  // 5 MB

    /// Zusätzlich zum ENVELOPE angeforderte Header: References (nicht Teil
    /// des ENVELOPE, für korrektes Threading) und die Spam-Kopfzeilen des
    /// Servers (für die gespeicherte Spam-Angabe).
    private static let extraHeaderFields = ["References"] + SpamHeaderParser.fieldNames

    /// Höchstzahl der Mails je Kopfdaten-Abfrage. Größere Mengen werden in
    /// mehreren Anfragen geholt, damit keine einzelne Antwort in einen
    /// Timeout läuft.
    private static let headerBatchSize = 100

    /// Ergebnis von `cacheMessages`.
    private struct CacheResult {
        /// Neu gespeicherte Mails.
        let saved: Int
        /// Neue Mails, die nicht geladen oder gespeichert werden konnten.
        let failed: Int
    }

    // MARK: - Abruf

    /// Holt neue Nachrichten eines Ordners und gleicht den Cache ab.
    ///
    /// Verarbeitung:
    /// 1. SELECT liefert UIDVALIDITY und UIDNEXT. Zusammen mit dem
    ///    gespeicherten Zustand entscheidet der SyncStatePlanner über das
    ///    Vorgehen. Bei geänderter UIDVALIDITY wird der Cache des Ordners
    ///    zuerst verworfen.
    /// 2. SEARCH SINCE der letzten 30 Tage → UIDs der aktuellen Mails
    ///    (ohne Server-Sortierung, siehe `searchNewestFirst`).
    ///    Im Posteingang zusätzlich alle gekennzeichneten Mails.
    /// 3. `cacheMessages` speichert neue Mails samt Body und Anhängen
    ///    (≤ 5 MB) und aktualisiert Flags bekannter Mails.
    /// 4. `reconcile` vergleicht den ganzen Ordner mit dem Cache: entfernt
    ///    Gelöschtes und aktualisiert Flags.
    /// 5. Bei gültigem Zustand: Mails, die seit dem letzten Abruf in den
    ///    Ordner gekommen sind und noch fehlen, werden nachgeladen
    ///    (höchstens `SyncStatePlanner.arrivalLimit` je Abruf). Fehlt
    ///    danach eine, bleibt UIDNEXT stehen und der nächste Abruf
    ///    versucht sie erneut.
    /// 6. Im Posteingang: ungelesene Mails, die nicht im Cache liegen (z. B.
    ///    älter als das Zeitfenster), werden nachgeladen – höchstens
    ///    `SyncStatePlanner.unreadBackfillLimit` je Abruf. Ihre UIDs kennt
    ///    der Abgleich bereits; eine eigene Suche ist nicht nötig.
    /// 7. Erst nach vollständigem Erfolg werden Zeitpunkt und Zustand
    ///    gespeichert. Bricht der Abruf ab, wiederholt der nächste ihn ab
    ///    dem alten Stand.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Passwort.
    ///   - folder: IMAP-Ordner (Standard: INBOX).
    /// - Throws: Verbindungsfehler oder IMAP-Fehler.
    static func refreshAndCache(
        _ credentials: MailCredentials,
        folder: String = MailFolder.inboxPath
    ) async throws {
        let account = credentials.account
        let outcome = try await MailSession.withIMAP(credentials) {
            server -> (decision: SyncStatePlanner.Decision, uidValidity: UInt32, uidNext: UInt32) in
            let selection = try await server.selectMailbox(folder)

            // 1. Vorgehen anhand des Sync-Zustands
            let serverValidity = selection.uidValidity.value
            let serverUIDNext = selection.uidNext.value
            let decision = SyncStatePlanner.decide(
                stored: MessageStore.shared.syncState(accountID: account.id, folder: folder),
                serverUIDValidity: serverValidity,
                serverUIDNext: serverUIDNext
            )
            if decision == .reset {
                Log.fetch.info("♻️ [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] UIDVALIDITY geändert → Ordner-Cache wird neu aufgebaut")
                MessageStore.shared.deleteFolder(accountID: account.id, folder: folder)
            }

            // 2. Serverseitig nur Mails des Standardfensters suchen
            let sinceDate = SyncWindow.standardStart()
            var uids = try await searchNewestFirst(
                on: server,
                criteria: [.since(sinceDate)],
                calendar: SyncWindow.calendar
            )

            Log.fetch.info("📬 [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] SEARCH ergab \(uids.count) UIDs (seit \(sinceDate, privacy: .public))")

            // Gekennzeichnete Mails des Posteingangs, auch ältere. Die Menge
            // ist klein, die Antwort bleibt weit unter den Puffergrenzen.
            // Bereits gecachte Mails bekommen dabei ihre Flags abgeglichen.
            if MailFolder.isInbox(folder) {
                let flagged = try await searchNewestFirst(
                    on: server,
                    criteria: [.flagged],
                    calendar: SyncWindow.calendar
                )
                let known = Set(uids.map(\.value))
                let older = flagged.filter { !known.contains($0.value) }
                uids += older
                Log.fetch.info("📬 [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] Gekennzeichnet: \(flagged.count), davon älter: \(older.count)")
            }

            // 3. Gefundene Mails speichern
            if uids.isEmpty {
                Log.fetch.info("📬 [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] Keine UIDs im Zeitraum")
            } else {
                try await cacheMessages(uids: uids, server: server, account: account, folder: folder)
            }

            // 4. Abgleich mit dem ganzen Ordner
            let serverState = try await reconcile(
                server: server, account: account, folder: folder, uidNext: serverUIDNext
            )

            // 5. Neuankünfte seit dem letzten Abruf
            var nextUIDNext = serverUIDNext
            if case .incremental(let fromUID) = decision {
                let arrivals = SyncStatePlanner.arrivals(
                    serverUIDs: serverState.all,
                    fromUID: fromUID,
                    serverUIDNext: serverUIDNext,
                    known: MessageStore.shared.cachedUIDs(accountID: account.id, folder: folder)
                )
                var failed = 0
                if !arrivals.toLoad.isEmpty {
                    let result = try await cacheMessages(
                        uids: arrivals.toLoad.map { SwiftMail.UID($0) },
                        server: server, account: account, folder: folder
                    )
                    failed = result.failed
                    Log.fetch.info("🆕 [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] Neuankünfte: \(result.saved) geladen, \(result.failed) fehlgeschlagen, \(arrivals.deferredCount) zurückgestellt")
                }
                // Fehlt eine Neuankunft, bleibt UIDNEXT stehen → nächster Abruf versucht sie erneut.
                nextUIDNext = SyncStatePlanner.uidNextAfterLoading(
                    plan: arrivals, fromUID: fromUID, failedCount: failed
                )
            }

            // 6. Ältere ungelesene Mails des Posteingangs (für die Sicht
            //    „Ungelesen“). Der Abgleich kennt ihre UIDs bereits – keine
            //    zusätzliche Abfrage. Fehlgeschlagene folgen beim nächsten
            //    Abruf, weil sie dann weiterhin im Cache fehlen.
            if MailFolder.isInbox(folder) {
                let backfill = SyncStatePlanner.unreadBackfill(
                    unseen: serverState.unseen,
                    known: MessageStore.shared.cachedUIDs(accountID: account.id, folder: folder)
                )
                if !backfill.toLoad.isEmpty {
                    let result = try await cacheMessages(
                        uids: backfill.toLoad.map { SwiftMail.UID($0) },
                        server: server, account: account, folder: folder
                    )
                    Log.fetch.info("✉️ [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] Ältere ungelesene: \(result.saved) geladen, \(result.failed) fehlgeschlagen, \(backfill.deferredCount) zurückgestellt")
                }
            }
            return (decision: decision, uidValidity: serverValidity, uidNext: nextUIDNext)
        }

        // 7. Stand und Zustand vermerken – erst hier, nach vollständigem
        //    Abruf einschließlich Abmelden.
        let state: FolderSyncState? = outcome.decision == .unsupported
            ? nil
            : FolderSyncState(uidValidity: outcome.uidValidity, uidNext: outcome.uidNext)
        MessageStore.shared.recordSync(accountID: account.id, folder: folder, state: state)
    }

    // MARK: - Server-Abgleich

    /// Gleicht den Cache eines Ordners mit dem Server ab.
    ///
    /// Verarbeitung: Holt alle UIDs mit Flags in einer einzigen Abfrage
    /// (`UID FETCH 1:* (FLAGS)`). Daraus ergibt sich:
    /// - welche Mails es auf dem Server nicht mehr gibt → werden entfernt,
    /// - welche Flags sich geändert haben → werden übernommen.
    ///
    /// Mails, die nur auf dem Server liegen, lädt der Abgleich nicht nach;
    /// das übernimmt der Abruf (Datumssuche und Neuankünfte).
    ///
    /// Der Ordner muss bereits ausgewählt sein. Schlägt die Abfrage fehl,
    /// wirft die Methode – gelöscht wird dann nichts. Als gelöscht gilt eine
    /// gecachte Mail nur bis zur Grenze aus UIDNEXT
    /// (`ServerReconciliation.removalLimit`).
    ///
    /// - Parameters:
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    ///   - account: Postfach.
    ///   - folder: IMAP-Ordner.
    ///   - uidNext: UIDNEXT aus der Auswahl des Ordners; 0 = unbekannt.
    /// - Returns: Der Stand des Ordners auf dem Server (alle UIDs und
    ///   Flags); daraus ermittelt der Abruf die Neuankünfte.
    /// - Throws: IMAP-Fehler.
    @discardableResult
    private static func reconcile(
        server: SwiftMail.IMAPServer,
        account: MailAccount,
        folder: String,
        uidNext: UInt32
    ) async throws -> ServerFolderState {
        let started = Date()

        // Alle Mails des Ordners mit ihren Flags – eine einzige Abfrage.
        let infos = try await server.fetchMessageInfos(
            uidRange: SwiftMail.UID(1)...,
            options: [.flags]
        )
        let fetchDone = Date()

        var state = ServerFolderState(all: [], unseen: [], flagged: [], answered: [], forwarded: [])
        for info in infos {
            guard let uid = info.uid?.value else { continue }
            let flags = FlagState(info.flags)
            state.all.insert(uid)
            if flags.isUnread { state.unseen.insert(uid) }
            if flags.isFlagged { state.flagged.insert(uid) }
            if flags.isAnswered { state.answered.insert(uid) }
            if flags.isForwarded { state.forwarded?.insert(uid) }
        }

        let plan = ServerReconciliation.plan(
            cached: MessageStore.shared.cachedFlagStates(
                accountID: account.id, folder: folder, since: .distantPast
            ),
            server: state,
            keepUIDsAbove: ServerReconciliation.removalLimit(in: state, uidNext: uidNext)
        )
        MessageStore.shared.apply(plan)

        let fetchMillis = Int(fetchDone.timeIntervalSince(started) * 1000)
        let totalMillis = Int(Date().timeIntervalSince(started) * 1000)
        Log.fetch.info("""
            🔁 [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] Abgleich: \(state.all.count) Mails im Ordner, \
            \(state.forwarded?.count ?? 0) mit \(FlagState.forwardedKeyword, privacy: .public), \
            \(plan.removedIDs.count) entfernt, \(plan.flagUpdates.count) Flags geändert \
            (Abfrage \(fetchMillis) ms, gesamt \(totalMillis) ms)
            """)
        return state
    }


    // MARK: - Suche auf dem Server

    /// Höchstzahl der Treffer je Ordner, die eine Serversuche zeigt.
    static let serverSearchLimit = 100

    /// Höchstzahl der Treffer, deren Kopfdaten geholt werden. UIDs sagen
    /// nichts über das Datum (z. B. nach einem Umzug per IMAPSYNC); die
    /// neuesten `serverSearchLimit` Treffer werden deshalb aus den Kopfdaten
    /// der höchsten UIDs nach Datum bestimmt.
    private static let serverSearchHeaderLimit = 300

    /// Ergebnis einer Serversuche in einem Ordner.
    struct ServerSearchResult {
        /// Treffer, die nicht im Cache liegen, neueste zuerst.
        let hits: [MessageListItem]
        /// `true`, wenn es mehr Treffer gab als gezeigt werden.
        let hasMore: Bool
    }

    /// Sucht in einem Ordner auf dem Server.
    ///
    /// Verarbeitung: Wählt den Ordner nur lesend aus (EXAMINE) und sucht
    /// mit TEXT (Eingabe ab drei Zeichen, Leerzeichen zählen mit) und für
    /// eine gewählte Person mit FROM/TO/CC – beides zusammen muss zutreffen.
    /// Treffer, die schon im Cache liegen, entfallen (die findet die lokale
    /// Suche). Von den übrigen werden für die höchsten
    /// `serverSearchHeaderLimit` UIDs die Kopfdaten geholt (in Paketen zu
    /// `headerBatchSize`, mit BODY.PEEK – nichts wird als gelesen markiert)
    /// und die neuesten `serverSearchLimit` als Listeneinträge geliefert.
    /// Gespeichert wird nichts; das geschieht erst beim Öffnen
    /// (`loadMessage`). Anhänge sind vor dem Öffnen nicht bekannt.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Passwort.
    ///   - folder: IMAP-Ordner.
    ///   - query: Eingabe im Suchfeld.
    ///   - address: Adresse einer gewählten Person; `nil` = keine.
    /// - Returns: Treffer außerhalb des Caches.
    /// - Throws: Verbindungs- oder IMAP-Fehler.
    static func searchOnServer(
        _ credentials: MailCredentials,
        folder: String,
        query: String,
        address: String?
    ) async throws -> ServerSearchResult {
        var criteria: [SwiftMail.SearchCriteria] = []
        if let address, !address.isEmpty {
            criteria.append(.or(.from(address), .or(.to(address), .cc(address))))
        }
        if SearchText.isSearchable(query) {
            criteria.append(.text(query))
        }
        guard !criteria.isEmpty else { return ServerSearchResult(hits: [], hasMore: false) }

        let account = credentials.account
        return try await MailSession.withIMAP(credentials) { server -> ServerSearchResult in
            _ = try await server.examineMailbox(folder)
            let uids = try await searchNewestFirst(
                on: server, criteria: criteria, calendar: SyncWindow.calendar
            )
            let cached = MessageStore.shared.cachedUIDs(accountID: account.id, folder: folder)
            let missing = uids.filter { !cached.contains($0.value) }
            let candidates = Array(missing.prefix(serverSearchHeaderLimit))

            var infos: [MessageInfo] = []
            for start in stride(from: 0, to: candidates.count, by: headerBatchSize) {
                let batch = Array(candidates[start..<min(start + headerBatchSize, candidates.count)])
                infos += try await server.fetchMessageInfosBulk(
                    using: UIDSet(batch),
                    options: .slim,
                    headerFields: extraHeaderFields
                )
            }
            let hits = infos
                .compactMap { listItem(from: $0, account: account, folder: folder) }
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            Log.fetch.info("🔎 [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] Serversuche: \(uids.count) Treffer, \(missing.count) nicht im Cache, \(min(hits.count, serverSearchLimit)) gezeigt")
            return ServerSearchResult(
                hits: Array(hits.prefix(serverSearchLimit)),
                hasMore: missing.count > serverSearchLimit
            )
        }
    }

    /// Listeneintrag aus den Kopfdaten einer Mail, die nicht im Cache liegt.
    ///
    /// Verarbeitung: Dieselben Regeln wie beim Speichern (Ersatztexte,
    /// Datum aus dem Kopf, sonst Eingangsdatum). Die Cache-ID ist die, die
    /// die Mail beim Laden erhält.
    ///
    /// - Parameters:
    ///   - info: Kopfdaten.
    ///   - account: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Listeneintrag; `nil` ohne UID.
    private static func listItem(from info: MessageInfo, account: MailAccount, folder: String) -> MessageListItem? {
        guard let uid = info.uid?.value else { return nil }
        let flags = FlagState(info.flags)
        let headers = headers(from: info)
        return MessageListItem(
            id: CachedMessage.makeID(accountID: account.id, folder: folder, uid: uid),
            accountID: account.id,
            folder: folder,
            uid: uid,
            subject: info.subject ?? "(kein Betreff)",
            from: info.from ?? "(unbekannt)",
            recipients: headers.toList,
            date: info.date ?? info.internalDate,
            isUnread: flags.isUnread,
            isFlagged: flags.isFlagged,
            isAnswered: flags.isAnswered,
            isForwarded: flags.isForwarded,
            hasAttachments: false,
            sizeBytes: info.size ?? 0,
            spamVerdict: headers.spamVerdict
        )
    }

    /// Lädt eine einzelne Mail vom Server und speichert sie im Cache.
    ///
    /// Verarbeitung: Wählt den Ordner aus und lädt die Mail auf demselben
    /// Weg wie der Abruf (Struktur, Text/HTML, Anhänge bis 5 MB). Liegt sie
    /// schon im Cache, werden nur die Flags abgeglichen.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Passwort.
    ///   - folder: IMAP-Ordner.
    ///   - uid: UID der Mail.
    /// - Returns: `true`, wenn die Mail danach im Cache liegt.
    /// - Throws: Verbindungs- oder IMAP-Fehler.
    static func loadMessage(_ credentials: MailCredentials, folder: String, uid: UInt32) async throws -> Bool {
        let account = credentials.account
        try await MailSession.withIMAP(credentials) { server -> Void in
            _ = try await server.selectMailbox(folder)
            _ = try await cacheMessages(
                uids: [SwiftMail.UID(uid)], server: server, account: account, folder: folder
            )
        }
        let id = CachedMessage.makeID(accountID: account.id, folder: folder, uid: uid)
        return MessageStore.shared.message(id: id) != nil
    }

    // MARK: - Ältere Nachrichten

    /// Lädt den nächsten Zeitraum (30 Tage) vor dem bisherigen Fensterbeginn
    /// eines Ordners nach.
    ///
    /// Verarbeitung: Schiebt den Fensterbeginn blockweise zurück und sucht
    /// per SEARCH SINCE/BEFORE. Leere Zeiträume werden übersprungen, bis
    /// Mails gefunden sind – sonst sähe ein Tipp auf „Ältere laden" aus,
    /// als passiere nichts. Der neue Fensterbeginn wird dauerhaft
    /// gespeichert – aber nur, wenn der Zeitraum vollständig geladen wurde
    /// (siehe `SyncWindow.startAfterLoading`).
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Passwort.
    ///   - folder: IMAP-Ordner (Standard: INBOX).
    /// - Returns: Ergebnis mit Anzahl geladener und fehlgeschlagener Mails
    ///   und ob es noch Älteres gibt.
    /// - Throws: Verbindungsfehler oder IMAP-Fehler.
    static func fetchOlder(
        _ credentials: MailCredentials,
        folder: String = MailFolder.inboxPath
    ) async throws -> OlderFetchResult {
        let account = credentials.account
        let searchCalendar = SyncWindow.calendar
        return try await MailSession.withIMAP(credentials) { server -> OlderFetchResult in
            let selection = try await server.selectMailbox(folder)

            var start = MessageStore.shared.windowStart(accountID: account.id, folder: folder)
                ?? SyncWindow.standardStart()

            let messageCount = selection.messageCount

            // Gibt es überhaupt Älteres? Nicht per SEARCH über den ganzen
            // Ordner – bei großen Postfächern sprengt die Liste aller UIDs
            // den Antwortpuffer (siehe hasMessages).
            guard try await hasMessages(
                on: server, before: start, messageCount: messageCount, calendar: searchCalendar
            ) else {
                Log.fetch.info("📬 [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] Keine älteren Nachrichten")
                return .noOlder
            }

            var loaded = 0
            var failed = 0
            for _ in 0..<SyncWindow.maxBlocksPerLoad {
                let block = SyncWindow.nextBlock(before: start)
                let uids = try await searchNewestFirst(
                    on: server,
                    criteria: [.since(block.since), .before(block.before)],
                    calendar: searchCalendar
                )
                Log.fetch.info("📬 [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] Zeitraum ab \(block.since, privacy: .public): \(uids.count) UIDs")
                if !uids.isEmpty {
                    let result = try await cacheMessages(
                        uids: uids, server: server, account: account, folder: folder
                    )
                    loaded = result.saved
                    failed = result.failed
                    // Nur bei vollständigem Laden zurückrücken – sonst bliebe
                    // eine Lücke, die kein späterer Abruf mehr schließt.
                    start = SyncWindow.startAfterLoading(
                        previous: block.before, loaded: block.since, failedCount: result.failed
                    )
                    break
                }
                start = block.since
                // Leerer Zeitraum: nur weiter zurück, wenn es noch Älteres gibt.
                guard try await hasMessages(
                    on: server, before: start, messageCount: messageCount, calendar: searchCalendar
                ) else { break }
            }

            // Fensterbeginn merken – schützt die Mails vor dem Aufräumen.
            MessageStore.shared.setWindowStart(start, accountID: account.id, folder: folder)

            let hasMore = try await hasMessages(
                on: server, before: start, messageCount: messageCount, calendar: searchCalendar
            )
            return OlderFetchResult.loaded(
                count: loaded, failed: failed, windowStart: start, hasMore: hasMore
            )
        }
    }

    /// Größe der Abschnitte (Sequenznummern), in denen `hasMessages` sucht.
    /// 1000 Nummern ergeben höchstens rund 6 KB Antwort – sicher unter den
    /// Puffergrenzen des IMAP-Parsers.
    private static let probeChunkSize = 1000

    /// Prüft, ob es im ausgewählten Ordner Mails vor einem Datum gibt.
    ///
    /// Verarbeitung: Sucht abschnittsweise über die Sequenznummern und
    /// endet beim ersten Treffer. Eine SEARCH über den ganzen Ordner
    /// würde bei großen Postfächern eine einzige riesige Antwortzeile
    /// liefern (PayloadTooLargeError). Die Ablagereihenfolge sagt nichts
    /// Verlässliches über das Datum, deshalb wird der ganze Ordner
    /// geprüft, bis ein Treffer vorliegt oder alle Abschnitte durch sind.
    ///
    /// - Parameters:
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    ///   - date: Datum (IMAP-Eingangsdatum, tagesgenau; BEFORE schließt
    ///     den Tag aus).
    ///   - messageCount: Anzahl der Nachrichten im Ordner (aus SELECT).
    ///   - calendar: Kalender für die IMAP-Suche.
    /// - Returns: true, wenn mindestens eine Mail vor `date` liegt.
    /// - Throws: IMAP-Fehler.
    private static func hasMessages(
        on server: SwiftMail.IMAPServer,
        before date: Date,
        messageCount: Int,
        calendar: Calendar
    ) async throws -> Bool {
        var lower = 1
        while lower <= messageCount {
            let upper = min(lower + probeChunkSize - 1, messageCount)
            let chunk = SwiftMail.SequenceNumberSet(
                SwiftMail.SequenceNumber(lower)...SwiftMail.SequenceNumber(upper)
            )
            let result: SwiftMail.ExtendedSearchResult<SwiftMail.SequenceNumber> = try await server.extendedSearch(
                identifierSet: chunk,
                criteria: [.before(date)],
                calendar: calendar
            )
            let hits = result.count
                ?? result.all?.count
                ?? result.ordered?.count
                ?? 0
            if hits > 0 { return true }
            lower = upper + 1
        }
        return false
    }

    // MARK: - Suche

    /// Sucht im ausgewählten Ordner und liefert die UIDs, höchste zuerst.
    ///
    /// Verarbeitung: Sucht bewusst ohne Server-Sortierung. Die dafür nötige
    /// IMAP-Erweiterung SORT bieten nicht alle Server an (Gmail z. B. nicht),
    /// und die Reihenfolge wird nur für das Laden der Kopfdaten gebraucht –
    /// die Liste sortiert sich aus dem Cache nach Datum. Das Ergebnis kommt
    /// je nach Server als ESEARCH (`all`) oder als einfache SEARCH-Antwort
    /// (`ordered`); beides wird gleich ausgelesen und nach UID absteigend
    /// geordnet, also grob in Eingangsreihenfolge „neueste zuerst“.
    ///
    /// - Parameters:
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    ///   - criteria: Suchkriterien.
    ///   - calendar: Kalender für Datumskriterien.
    /// - Returns: Gefundene UIDs, höchste zuerst; leer ohne Treffer.
    /// - Throws: IMAP-Fehler.
    private static func searchNewestFirst(
        on server: SwiftMail.IMAPServer,
        criteria: [SwiftMail.SearchCriteria],
        calendar: Calendar
    ) async throws -> [SwiftMail.UID] {
        let result: SwiftMail.ExtendedSearchResult<SwiftMail.UID> = try await server.extendedSearch(
            criteria: criteria,
            calendar: calendar
        )
        let uids = result.all?.toArray() ?? result.ordered ?? []
        return uids.sorted { $0.value > $1.value }
    }

    // MARK: - Gemeinsames Caching

    /// Holt Header und Body der übergebenen UIDs und legt neue Nachrichten
    /// samt Anhängen (≤ 5 MB) im Cache ab.
    ///
    /// Verarbeitung: Prüft zuerst, welche UIDs schon im Cache liegen.
    /// Bekannte Mails erhalten nur aktuelle Flags (und ggf. nachgefüllte
    /// Header). Neue Mails werden einzeln geladen; Nachricht und Anhänge
    /// werden gemeinsam in einer Transaktion gespeichert (`storeNewMessage`).
    ///
    /// Schlägt eine Mail fehl, wird der Ordner neu ausgewählt und die Mail
    /// genau einmal wiederholt. Hintergrund: SwiftMail baut eine
    /// abgerissene Verbindung still neu auf und meldet sich neu an, wählt
    /// den Ordner aber nicht wieder aus. Ohne neue Auswahl scheiterte jede
    /// weitere Mail der Runde. Scheitert die Mail auch danach, ist sie
    /// selbst defekt und wird übersprungen; sie zählt als fehlgeschlagen.
    /// Scheitert schon die neue Auswahl, ist die Verbindung tot und die
    /// Runde bricht ab.
    ///
    /// Die Kopfdaten werden in Paketen zu `headerBatchSize` Mails geholt.
    ///
    /// Gemeinsamer Teil von `refreshAndCache` (Datumssuche und
    /// Neuankünfte) und `fetchOlder`.
    ///
    /// - Parameters:
    ///   - uids: IMAP-UIDs der zu ladenden Mails.
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    ///   - account: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Anzahl neu gespeicherter und fehlgeschlagener Mails.
    /// - Throws: IMAP-Fehler bei der Bulk-Abfrage oder bei der neuen
    ///   Auswahl des Ordners (Fehler einzelner Mails werden gezählt).
    @discardableResult
    private static func cacheMessages(
        uids: [SwiftMail.UID],
        server: SwiftMail.IMAPServer,
        account: MailAccount,
        folder: String
    ) async throws -> CacheResult {
        // Welche UIDs haben wir schon im Cache – und wem fehlen noch Header?
        let alreadyCached = MessageStore.shared.cachedMessageIDs(
            forAccount: account.id, folder: folder
        )
        let needsHeaders = MessageStore.shared.messageIDsNeedingHeaders(
            forAccount: account.id, folder: folder
        )
        Log.fetch.info("📬 [\(account.displayName, privacy: .private)] Davon bereits im Cache: \(alreadyCached.count)")

        // Header für alle gefundenen UIDs holen (schlank + References),
        // in Paketen, damit keine einzelne Antwort zu groß wird.
        var infos: [MessageInfo] = []
        for start in stride(from: 0, to: uids.count, by: headerBatchSize) {
            let batch = Array(uids[start..<min(start + headerBatchSize, uids.count)])
            infos += try await server.fetchMessageInfosBulk(
                using: UIDSet(batch),
                options: .slim,
                headerFields: extraHeaderFields
            )
        }
        Log.fetch.info("📬 [\(account.displayName, privacy: .private)] fetchMessageInfosBulk lieferte \(infos.count) Infos")

        var savedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var headersBackfilled = 0

        for info in infos {
            guard let uid = info.uid else {
                skippedCount += 1
                continue
            }
            let msgID = CachedMessage.makeID(
                accountID: account.id, folder: folder, uid: uid.value
            )
            let flags = FlagState(info.flags)

            // Schon im Cache → Flags aktualisieren, ggf. Header nachfüllen
            if alreadyCached.contains(msgID) {
                MessageStore.shared.updateServerFlags(
                    messageID: msgID,
                    isUnread: flags.isUnread,
                    isFlagged: flags.isFlagged,
                    isAnswered: flags.isAnswered,
                    isForwarded: flags.isForwarded
                )
                if needsHeaders.contains(msgID) {
                    MessageStore.shared.updateHeaders(
                        messageID: msgID, headers: headers(from: info)
                    )
                    headersBackfilled += 1
                }
                continue
            }

            // Neu: Mail laden und speichern. Schlägt das fehl, kann die
            // Mail selbst defekt sein – oder SwiftMail hat eine abgerissene
            // Verbindung still neu aufgebaut, ohne den Ordner wieder
            // auszuwählen; dann scheitert jeder weitere Befehl mit
            // „No mailbox selected“. Deshalb: Ordner neu auswählen und die
            // Mail genau einmal wiederholen. Scheitert schon die Auswahl,
            // ist die Verbindung tot und die Runde bricht ab (wirft).
            let stored: Bool
            do {
                stored = try await storeNewMessage(
                    info: info, uid: uid, msgID: msgID, flags: flags,
                    server: server, account: account, folder: folder
                )
            } catch {
                Log.fetch.error("⚠️ Mail \(msgID, privacy: .public) fehlgeschlagen, Ordner wird neu ausgewählt: \(error.localizedDescription, privacy: .public)")
                _ = try await server.selectMailbox(folder)
                do {
                    stored = try await storeNewMessage(
                        info: info, uid: uid, msgID: msgID, flags: flags,
                        server: server, account: account, folder: folder
                    )
                } catch {
                    // Auch nach neuer Auswahl nicht ladbar: überspringen,
                    // ein späterer Abruf versucht sie erneut.
                    Log.fetch.error("⚠️ Mail \(msgID, privacy: .public) übersprungen: \(error.localizedDescription, privacy: .public)")
                    stored = false
                }
            }
            if stored {
                savedCount += 1
            } else {
                failedCount += 1
            }
        }

        Log.fetch.info("📬 [\(account.displayName, privacy: .private)] Fertig: \(savedCount) neu gespeichert, \(failedCount) fehlgeschlagen, \(alreadyCached.count) aus Cache, \(headersBackfilled) Header nachgefüllt, \(skippedCount) übersprungen (keine UID)")

        return CacheResult(saved: savedCount, failed: failedCount)
    }

    /// Lädt eine neue Mail samt Anhängen und eingebetteten Bildern (≤ 5 MB)
    /// und speichert sie.
    ///
    /// Verarbeitung: Holt zuerst nur die Struktur der Mail, dann gezielt
    /// Text- und HTML-Teil (`MessageContentPlan`). Anhänge und eingebettete
    /// Bilder werden einzeln geladen, wenn die Mail die Schwelle nicht
    /// überschreitet; sonst nur ihre Einträge gespeichert. Nachricht und Anhänge werden gemeinsam in
    /// einer Transaktion gespeichert. Lässt sich ein einzelner Anhang nicht
    /// laden, wird nur sein Eintrag (ohne Daten) gespeichert; er kann
    /// später per Antippen nachgeladen werden.
    ///
    /// - Parameters:
    ///   - info: Kopfdaten der Mail aus der Bulk-Abfrage.
    ///   - uid: UID der Mail.
    ///   - msgID: Cache-ID der Mail.
    ///   - flags: Ausgewertete IMAP-Flags.
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    ///   - account: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: `true` = gespeichert; `false` = Speichern zurückgerollt.
    /// - Throws: IMAP-Fehler beim Laden der Mail.
    private static func storeNewMessage(
        info: MessageInfo,
        uid: SwiftMail.UID,
        msgID: String,
        flags: FlagState,
        server: SwiftMail.IMAPServer,
        account: MailAccount,
        folder: String
    ) async throws -> Bool {
        let totalSize = info.size ?? 0
        let structure = try await server.fetchStructure(uid)
        let plan = MessageContentPlan(
            structure: structure,
            totalSize: totalSize,
            threshold: autoDownloadThreshold
        )

        // Nur Text und HTML der Mail selbst laden (roh; dekodiert wird beim
        // Zusammensetzen). Scheitert ein Teil, scheitert die Mail – der
        // Aufrufer wählt den Ordner neu und wiederholt sie einmal.
        var bodyData: [String: Data] = [:]
        for part in plan.bodyParts {
            bodyData[part.section.description] = try await server.fetchPart(
                section: part.section, of: uid
            )
        }
        let bodies = plan.bodies(withData: bodyData)
        let hasAttachments = !plan.attachments.isEmpty

        let cached = CachedMessage(
            id: msgID,
            accountID: account.id,
            accountDisplayName: account.displayName,
            folder: folder,
            uid: uid.value,
            subject: info.subject ?? "(kein Betreff)",
            from: info.from ?? "(unbekannt)",
            to: info.to.joined(separator: ", "),
            date: info.date ?? info.internalDate,
            isUnread: flags.isUnread,
            isFlagged: flags.isFlagged,
            isAnswered: flags.isAnswered,
            isForwarded: flags.isForwarded,
            totalSizeBytes: totalSize,
            hasAttachments: hasAttachments,
            textBody: bodies.text,
            htmlBody: bodies.html,
            fetchedAt: Date(),
            headers: headers(from: info)
        )

        // Anhänge und eingebettete Bilder zuerst vollständig einsammeln,
        // dann Nachricht und Anhänge gemeinsam speichern. Lässt sich ein
        // einzelner Teil nicht laden, wird nur sein Eintrag (ohne Daten)
        // gespeichert; ein Anhang kann dann per Antippen, ein Bild beim
        // Öffnen der Mail nachgeladen werden. So bleibt die Mail sichtbar
        // und vollständig beschrieben. Größere Mails: nur Einträge, Daten
        // erst bei Bedarf.
        let parts = plan.attachments.map { ($0, false) } + plan.inlineImages.map { ($0, true) }
        var cachedAttachments: [CachedAttachment] = []
        for (part, isInline) in parts {
            var data: Data?
            if plan.loadsAttachmentData {
                do {
                    data = try await server.fetchAndDecodeMessagePartData(
                        messageInfo: info, part: part
                    )
                } catch {
                    Log.fetch.error("⚠️ Teil \(part.section.description, privacy: .public) von Mail \(msgID, privacy: .public) nicht geladen, nur Eintrag gespeichert: \(error.localizedDescription, privacy: .public)")
                }
            }
            cachedAttachments.append(CachedAttachment(
                id: "\(msgID)-\(part.section)",
                messageID: msgID,
                filename: part.filename ?? (isInline ? "Bild" : "Anhang"),
                contentType: part.contentType,
                sizeBytes: data?.count ?? part.size ?? 0,
                data: data,
                contentID: isInline
                    ? MessageContentPlan.contentID(for: part)
                    : InlineImages.storedContentID(part.contentId),
                isInline: isInline
            ))
        }

        if !parts.isEmpty {
            let textKB = bodyData.values.reduce(0) { $0 + $1.count } / 1024
            let attachmentKB = cachedAttachments.reduce(0) { $0 + ($1.data?.count ?? 0) } / 1024
            Log.fetch.debug("📎 [\(account.displayName, privacy: .private)] Mail \(uid.value): \(plan.attachments.count) Anhänge, \(plan.inlineImages.count) eingebettete Bilder, Größe \(totalSize / 1024) KB, geladen: Text \(textKB) KB, Anhänge/Bilder \(attachmentKB) KB")
        }

        guard MessageStore.shared.saveMessageWithAttachments(cached, attachments: cachedAttachments) else {
            Log.fetch.error("⚠️ Mail \(msgID, privacy: .public) nicht gespeichert (Ablage zurückgerollt)")
            return false
        }
        return true
    }

    // MARK: - Fehlerarten

    /// Prüft, ob ein Fehler nur „keine Verbindung" bedeutet.
    ///
    /// Verarbeitung: Erkennt `IMAPError.connectionFailed` und `.timeout`
    /// sowie die Fälle des `ConnectionErrorClassifier`. Bei reinen
    /// Verbindungsfehlern meldet die App das still im Titel statt per Alert.
    ///
    /// - Parameter error: Zu prüfender Fehler.
    /// - Returns: true bei einem reinen Verbindungsfehler.
    static func isConnectionError(_ error: Error) -> Bool {
        if let imapError = error as? SwiftMail.IMAPError {
            switch imapError {
            case .connectionFailed, .timeout:
                return true
            default:
                break
            }
        }
        return ConnectionErrorClassifier.isConnectionError(error)
    }

    // MARK: - Helfer

    /// Überführt Adress-, Threading- und Spam-Kopfdaten aus dem MessageInfo
    /// ins Cache-Modell.
    ///
    /// Verarbeitung: Die Spam-Kopfzeilen kommen aus
    /// `additionalHeaderFields`, das Reihenfolge und Wiederholungen behält.
    /// Das Wörterbuch `additionalFields` wäre falsch: Bei mehreren
    /// X-Spam-Status-Zeilen gewänne dort die letzte – ein Absender könnte
    /// die Einstufung des Servers so überschreiben (wie im Spamfilter).
    ///
    /// - Parameter info: IMAP-Antwort mit Envelope-Daten und Zusatz-Headern.
    /// - Returns: Aufbereitete Kopfdaten für den Cache.
    private static func headers(from info: MessageInfo) -> CachedMessageHeaders {
        let references = info.references?
            .map(\.description)
            .joined(separator: " ")
        let spamLines = (info.additionalHeaderFields ?? []).map {
            SpamHeaderLine(name: $0.name, value: $0.value)
        }
        return CachedMessageHeaders(
            toList: info.to,
            ccList: info.cc,
            replyToList: info.replyTo,
            rfcMessageID: info.messageId?.description,
            rfcInReplyTo: info.inReplyTo?.description,
            rfcReferences: (references?.isEmpty ?? true) ? nil : references,
            spamVerdict: SpamHeaderParser.parse(spamLines)
        )
    }
}
