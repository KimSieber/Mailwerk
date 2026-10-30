//
//  MailFetchService.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Holt Mails von IMAP-Servern und legt sie im lokalen Cache ab.
//
//  Zugangspunkte:
//  - `refreshAndCache`: Abruf der letzten 30 Tage (plus gekennzeichnete
//    und ungelesene im Posteingang, unabhängig vom Alter) mit
//    anschließendem Abgleich – für einen Ordner oder für mehrere Ordner
//    über eine gemeinsame Verbindung (Posteingang und Spam-Ordner: eine
//    Anmeldung statt zwei). Die Variante mit `prepare` lässt vor dem
//    ersten Ordner einen Vorlauf auf derselben Verbindung zu – den
//    Spamfilter (AccountRefreshService, Prüfbericht P-13).
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
//  Anzeige-Hinweise: Für jede neue Mail werden externe Inhalte, eigene
//  Farben und Sprache vorberechnet und mit ihr gespeichert
//  (MessageDisplayHints) – das Öffnen liest sie nur noch.
//
//  Spam-Angabe: Die Kopfdaten-Abfrage holt die Spam-Kopfzeilen des
//  Servers (X-Spam, X-Spam-Flag, X-Spam-Status) gleich mit; ihre Einstufung wird mit
//  der Mail gespeichert. Mails im Cache mit älterer Header-Version
//  bekommen sie beim nächsten Abruf ihres Ordners nachgefüllt – ohne
//  zusätzliche Server-Abfrage, weil die Kopfdaten ohnehin geholt werden.
//
//  Nebenläufigkeit (v0.2.3b, Prüfbericht P-02): `nonisolated`; die
//  Einstiege `refreshAndCache(_:folders:)`, `fetchOlder`, `searchOnServer`
//  und `loadMessage` sind `@concurrent` und laufen damit abseits des
//  Hauptthreads – samt Zerlegen der Antworten, Abgleich und Speichern. Die
//  Oberfläche bleibt während des Abrufs bedienbar. Ergebnisse gehen über
//  den Cache (MessageStore) an die Oberfläche, die nach dem Abruf neu lädt.
//
//  Abgrenzung: `MailActionService` setzt Flags und verschiebt Mails;
//  `MailSendService` versendet. Die Darstellung liegt im ViewModel.
//
//  Verbindung und Zugangsdaten kommen aus `MailSession`.
//
//  Aufteilung (Code-Review v0.3.1, Regeln 3 und 4): Hier liegen nur der
//  Ablauf und die Zugriffe auf Server und Cache. Entscheidungen treffen
//  reine Planer – SyncStatePlanner (Sync-Zustand), ServerReconciliation
//  (Abgleich, Stand des Ordners), FetchClassifier (neu / Flags geändert /
//  Kopfdaten nachtragen), ServerSearchPlan (Serversuche); die Modelle baut
//  FetchedMessageMapping.
//
//  Protokoll: Zeilen zu einem Ordner beginnen einheitlich mit
//  „[Postfach/Ordner]“ (`FolderContext`); der Postfachname ist privat.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailSession (Verbindung),
//  MessageStore (Cache), ServerReconciliation, SyncStatePlanner,
//  FetchClassifier, ServerSearchPlan, FetchedMessageMapping, SyncWindow
//  (Zeitfenster), MessageContentPlan (zu ladende Teile), FlagState (Flags),
//  MailFolder, MessageDisplayHints, Log.
//

import Foundation
import SwiftMail
import NIOIMAPCore
import os

/// Abruf von Mails und Abgleich des lokalen Caches.
nonisolated enum MailFetchService {

    /// Maximale Nachrichtengröße (RFC822.SIZE) in Bytes, bis zu der
    /// Anhänge automatisch mitgeladen werden. Darüber: erst bei Tap.
    static let autoDownloadThresholdBytes = 5 * 1024 * 1024  // 5 MB

    /// Zusätzlich zum ENVELOPE angeforderte Header: References (nicht Teil
    /// des ENVELOPE, für korrektes Threading) und die Spam-Kopfzeilen des
    /// Servers (für die gespeicherte Spam-Angabe).
    private static let extraHeaderFields = ["References"] + SpamHeaderParser.fieldNames

    /// Höchstzahl der Mails je Kopfdaten-Abfrage. Größere Mengen werden in
    /// mehreren Anfragen geholt, damit keine einzelne Antwort in einen
    /// Timeout läuft.
    private static let headerBatchSize = 100

    /// Ergebnis von `cacheMessages`.
    nonisolated private struct CacheResult {
        /// Neu gespeicherte Mails.
        let saved: Int
        /// Neue Mails, die nicht geladen oder gespeichert werden konnten.
        let failed: Int
    }

    /// Verbindung, Postfach und Ordner eines Abrufschritts – samt
    /// einheitlichem Protokoll „Symbol [Postfach/Ordner] Text“.
    ///
    /// Der Text wird öffentlich protokolliert; er enthält deshalb nur
    /// Zahlen, Cache-IDs, Datumsangaben und Fehlertexte, nie Adressen oder
    /// Betreffs. Der Postfachname ist privat (siehe Log).
    nonisolated private struct FolderContext {
        /// Angemeldete IMAP-Verbindung.
        let server: SwiftMail.IMAPServer
        /// Postfach.
        let account: MailAccount
        /// IMAP-Ordner.
        let folder: String

        /// Protokolliert einen Ablauf (`.info`).
        ///
        /// - Parameters:
        ///   - symbol: Kennzeichen der Zeile (z. B. „📬“).
        ///   - text: Öffentlicher Text.
        func info(_ symbol: String, _ text: String) {
            Log.fetch.info("\(symbol, privacy: .public) [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] \(text, privacy: .public)")
        }

        /// Protokolliert einen Fehler (`.error`).
        ///
        /// - Parameters:
        ///   - symbol: Kennzeichen der Zeile (z. B. „⚠️“).
        ///   - text: Öffentlicher Text.
        func error(_ symbol: String, _ text: String) {
            Log.fetch.error("\(symbol, privacy: .public) [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] \(text, privacy: .public)")
        }

        /// Protokolliert einen Messwert (`.debug`).
        ///
        /// - Parameters:
        ///   - symbol: Kennzeichen der Zeile (z. B. „📎“).
        ///   - text: Öffentlicher Text.
        func debug(_ symbol: String, _ text: String) {
            Log.fetch.debug("\(symbol, privacy: .public) [\(account.displayName, privacy: .private)/\(folder, privacy: .public)] \(text, privacy: .public)")
        }
    }

    // MARK: - Abruf

    /// Holt neue Nachrichten eines Ordners und gleicht den Cache ab.
    ///
    /// Verarbeitung: Wie `refreshAndCache(_:folders:)` mit einem einzigen
    /// Ordner; ein Fehler wird unverändert weitergegeben.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Passwort.
    ///   - folder: IMAP-Ordner (Standard: INBOX).
    /// - Throws: Verbindungsfehler oder IMAP-Fehler.
    static func refreshAndCache(
        _ credentials: MailCredentials,
        folder: String = MailFolder.inboxPath
    ) async throws {
        do {
            try await refreshAndCache(credentials, folders: [folder])
        } catch let failure as FolderRefreshError {
            throw failure.underlying
        }
    }

    /// Fehler beim Abruf mehrerer Ordner über eine Verbindung.
    nonisolated struct FolderRefreshError: LocalizedError {
        /// Ordner, bei dem der Abruf abbrach; `nil` = vor dem ersten Ordner
        /// (Verbindung, Anmeldung) oder beim Abmelden.
        let folder: String?
        /// Ordner, die vorher vollständig abgerufen und vermerkt wurden.
        let completed: [String]
        /// Eigentlicher Fehler.
        let underlying: Error

        /// Meldungstext des eigentlichen Fehlers.
        var errorDescription: String? { underlying.localizedDescription }
    }

    /// Holt neue Nachrichten mehrerer Ordner über *eine* Verbindung und
    /// gleicht den Cache ab – nacheinander, in der übergebenen Reihenfolge.
    ///
    /// Eine Verbindung statt einer je Ordner spart Anmeldungen. Manche
    /// Anbieter (z. B. Gmail) bremsen dichte Anmeldefolgen so stark, dass
    /// eine Anmeldung in die Zeitüberschreitung läuft.
    ///
    /// Verarbeitung je Ordner (`syncFolder`):
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
    ///
    /// Vermerken (Zeitpunkt und Zustand): Läuft alles durch, werden alle
    /// Ordner nach dem Abmelden vermerkt. Bricht der Abruf bei einem Ordner
    /// ab, werden die Ordner davor trotzdem vermerkt – ihr Abruf war
    /// vollständig; der abgebrochene und alle folgenden nicht, der nächste
    /// Abruf wiederholt sie ab dem alten Stand. Scheitert erst das Abmelden,
    /// wird nichts vermerkt.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Passwort.
    ///   - folders: IMAP-Ordner in Abrufreihenfolge.
    /// - Throws: `FolderRefreshError` mit dem Ordner, bei dem es abbrach.
    @concurrent
    static func refreshAndCache(_ credentials: MailCredentials, folders: [String]) async throws {
        try await refreshAndCache(credentials) { _ in folders }
    }

    /// Wie `refreshAndCache(_:folders:)`, aber mit Vorlauf: `prepare` läuft
    /// auf der angemeldeten Verbindung vor dem ersten Ordner und liefert
    /// die abzurufenden Ordner.
    ///
    /// Verarbeitung: Anmelden, `prepare` ausführen, dann die Ordner wie in
    /// `refreshAndCache(_:folders:)` abrufen und vermerken. Wirft
    /// `prepare`, gilt das wie ein Fehler vor dem ersten Ordner
    /// (`FolderRefreshError.folder == nil`, nichts vermerkt). Läuft im
    /// Kontext des Aufrufers (nicht `@concurrent`), damit `prepare` dessen
    /// Zustand ändern darf; der Aufrufer `AccountRefreshService.refresh`
    /// ist selbst `@concurrent`.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Zugang.
    ///   - prepare: Vorlauf auf der Verbindung; liefert die Ordner in
    ///     Abrufreihenfolge.
    /// - Throws: `FolderRefreshError` mit dem Ordner, bei dem es abbrach.
    static func refreshAndCache(
        _ credentials: MailCredentials,
        prepare: (SwiftMail.IMAPServer) async throws -> [String]
    ) async throws {
        let account = credentials.account
        var completed: [(folder: String, state: FolderSyncState?)] = []
        var current: String?
        do {
            try await MailSession.withIMAP(credentials) { server in
                let folders = try await prepare(server)
                for folder in folders {
                    current = folder
                    let state = try await syncFolder(folder, on: server, account: account)
                    completed.append((folder: folder, state: state))
                }
                current = nil
            }
        } catch {
            // Vor dem abgebrochenen Ordner vollständig abgerufene Ordner
            // vermerken; beim Abmelden (current == nil) bleibt alles offen.
            let finished = current == nil ? [] : completed
            for entry in finished {
                MessageStore.shared.recordSync(accountID: account.id, folder: entry.folder, state: entry.state)
            }
            throw FolderRefreshError(folder: current, completed: finished.map(\.folder), underlying: error)
        }
        // Stand und Zustand vermerken – erst hier, nach vollständigem
        // Abruf einschließlich Abmelden.
        for entry in completed {
            MessageStore.shared.recordSync(accountID: account.id, folder: entry.folder, state: entry.state)
        }
    }

    /// Ruft einen Ordner auf einer angemeldeten Verbindung ab (Schritte 1–6
    /// von `refreshAndCache(_:folders:)`). Messpunkt für Instruments:
    /// „Ordner-Sync“.
    ///
    /// - Parameters:
    ///   - folder: IMAP-Ordner.
    ///   - server: Angemeldete IMAP-Verbindung.
    ///   - account: Postfach.
    /// - Returns: Zu vermerkender Sync-Zustand; `nil`, wenn der Server ihn
    ///   nicht unterstützt.
    /// - Throws: Verbindungs- oder IMAP-Fehler.
    private static func syncFolder(
        _ folder: String,
        on server: SwiftMail.IMAPServer,
        account: MailAccount
    ) async throws -> FolderSyncState? {
        let interval = Log.beginInterval(Log.Interval.folderSync)
        defer { Log.endInterval(interval) }
        let context = FolderContext(server: server, account: account, folder: folder)
        let selection = try await server.selectMailbox(folder)
        let serverValidity = selection.uidValidity.value
        let serverUIDNext = selection.uidNext.value
        let decision = decideSync(uidValidity: serverValidity, uidNext: serverUIDNext, in: context)

        let uids = try await windowUIDs(in: context)
        if uids.isEmpty {
            context.info("📬", "Keine UIDs im Zeitraum")
        } else {
            try await cacheMessages(uids, in: context)
        }

        let serverState = try await reconcile(context, uidNext: serverUIDNext)
        var nextUIDNext = serverUIDNext
        if case .incremental(let fromUID) = decision {
            nextUIDNext = try await loadArrivals(
                from: fromUID, serverUIDNext: serverUIDNext, serverState: serverState, in: context
            )
        }
        if MailFolder.isInbox(folder) {
            try await backfillUnread(serverState, in: context)
        }
        return decision == .unsupported
            ? nil
            : FolderSyncState(uidValidity: serverValidity, uidNext: nextUIDNext)
    }

    /// Entscheidet anhand des gespeicherten Sync-Zustands über das Vorgehen
    /// (Schritt 1) und verwirft bei geänderter UIDVALIDITY den Cache des
    /// Ordners.
    ///
    /// - Parameters:
    ///   - uidValidity: UIDVALIDITY aus der Auswahl des Ordners.
    ///   - uidNext: UIDNEXT aus der Auswahl des Ordners.
    ///   - context: Verbindung, Postfach und Ordner.
    /// - Returns: Vorgehen für diesen Abruf.
    private static func decideSync(
        uidValidity: UInt32,
        uidNext: UInt32,
        in context: FolderContext
    ) -> SyncStatePlanner.Decision {
        let decision = SyncStatePlanner.decide(
            stored: MessageStore.shared.syncState(accountID: context.account.id, folder: context.folder),
            serverUIDValidity: uidValidity,
            serverUIDNext: uidNext
        )
        if decision == .reset {
            context.info("♻️", "UIDVALIDITY geändert → Ordner-Cache wird neu aufgebaut")
            MessageStore.shared.deleteFolder(accountID: context.account.id, folder: context.folder)
        }
        return decision
    }

    /// Sucht die Mails des Standardfensters (Schritt 2); im Posteingang
    /// zusätzlich alle gekennzeichneten, auch ältere.
    ///
    /// Verarbeitung: Gesucht wird serverseitig nur im Standardfenster. Die
    /// gekennzeichneten Mails sind wenige, die Antwort bleibt weit unter den
    /// Puffergrenzen; bereits gecachte bekommen dabei ihre Flags abgeglichen.
    ///
    /// - Parameter context: Verbindung, Postfach und Ordner.
    /// - Returns: UIDs, höchste zuerst (ältere gekennzeichnete am Ende).
    /// - Throws: IMAP-Fehler.
    private static func windowUIDs(in context: FolderContext) async throws -> [SwiftMail.UID] {
        let sinceDate = SyncWindow.standardStart()
        var uids = try await searchNewestFirst(
            on: context.server, criteria: [.since(sinceDate)], calendar: SyncWindow.calendar
        )
        context.info("📬", "SEARCH ergab \(uids.count) UIDs (seit \(sinceDate))")
        guard MailFolder.isInbox(context.folder) else { return uids }

        let flagged = try await searchNewestFirst(
            on: context.server, criteria: [.flagged], calendar: SyncWindow.calendar
        )
        let known = Set(uids.map(\.value))
        let older = flagged.filter { !known.contains($0.value) }
        uids += older
        context.info("📬", "Gekennzeichnet: \(flagged.count), davon älter: \(older.count)")
        return uids
    }

    /// Lädt Mails, die seit dem letzten Abruf in den Ordner gekommen sind
    /// und noch fehlen (Schritt 5).
    ///
    /// Verarbeitung: Die Auswahl trifft `SyncStatePlanner.arrivals`. Fehlt
    /// danach eine Neuankunft, bleibt UIDNEXT stehen – der nächste Abruf
    /// versucht sie erneut.
    ///
    /// - Parameters:
    ///   - fromUID: Gespeicherter UIDNEXT des letzten Abrufs.
    ///   - serverUIDNext: UIDNEXT aus der aktuellen Auswahl.
    ///   - serverState: Stand des Ordners aus dem Abgleich.
    ///   - context: Verbindung, Postfach und Ordner.
    /// - Returns: Zu vermerkender UIDNEXT.
    /// - Throws: IMAP-Fehler.
    private static func loadArrivals(
        from fromUID: UInt32,
        serverUIDNext: UInt32,
        serverState: ServerFolderState,
        in context: FolderContext
    ) async throws -> UInt32 {
        let arrivals = SyncStatePlanner.arrivals(
            serverUIDs: serverState.all,
            window: SyncStatePlanner.ArrivalWindow(fromUID: fromUID, serverUIDNext: serverUIDNext),
            known: MessageStore.shared.cachedUIDs(accountID: context.account.id, folder: context.folder)
        )
        var failed = 0
        if !arrivals.toLoad.isEmpty {
            let result = try await cacheMessages(arrivals.toLoad.map { SwiftMail.UID($0) }, in: context)
            failed = result.failed
            context.info("🆕", "Neuankünfte: \(result.saved) geladen, \(result.failed) fehlgeschlagen, \(arrivals.deferredCount) zurückgestellt")
        }
        return SyncStatePlanner.uidNextAfterLoading(plan: arrivals, fromUID: fromUID, failedCount: failed)
    }

    /// Lädt ältere ungelesene Mails des Posteingangs nach, die nicht im
    /// Cache liegen (Schritt 6, für die Sicht „Ungelesen“).
    ///
    /// Verarbeitung: Der Abgleich kennt ihre UIDs bereits – keine
    /// zusätzliche Abfrage. Fehlgeschlagene folgen beim nächsten Abruf,
    /// weil sie dann weiterhin im Cache fehlen.
    ///
    /// - Parameters:
    ///   - serverState: Stand des Ordners aus dem Abgleich.
    ///   - context: Verbindung, Postfach und Ordner.
    /// - Throws: IMAP-Fehler.
    private static func backfillUnread(_ serverState: ServerFolderState, in context: FolderContext) async throws {
        let backfill = SyncStatePlanner.unreadBackfill(
            unseen: serverState.unseen,
            known: MessageStore.shared.cachedUIDs(accountID: context.account.id, folder: context.folder)
        )
        guard !backfill.toLoad.isEmpty else { return }
        let result = try await cacheMessages(backfill.toLoad.map { SwiftMail.UID($0) }, in: context)
        context.info("✉️", "Ältere ungelesene: \(result.saved) geladen, \(result.failed) fehlgeschlagen, \(backfill.deferredCount) zurückgestellt")
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
    ///   - context: Verbindung (Ordner ausgewählt), Postfach und Ordner.
    ///   - uidNext: UIDNEXT aus der Auswahl des Ordners; 0 = unbekannt.
    /// - Returns: Der Stand des Ordners auf dem Server (alle UIDs und
    ///   Flags); daraus ermittelt der Abruf die Neuankünfte.
    /// - Throws: IMAP-Fehler.
    private static func reconcile(_ context: FolderContext, uidNext: UInt32) async throws -> ServerFolderState {
        let started = Date()
        let infos = try await context.server.fetchMessageInfos(
            uidRange: SwiftMail.UID(1)...,
            options: [.flags]
        )
        let fetchDone = Date()

        let state = ServerReconciliation.folderState(
            from: infos.compactMap { info in info.uid.map { (uid: $0.value, flags: FlagState(info.flags)) } }
        )
        let plan = ServerReconciliation.plan(
            cached: MessageStore.shared.cachedFlagStates(
                accountID: context.account.id, folder: context.folder, since: .distantPast
            ),
            server: state,
            keepUIDsAbove: ServerReconciliation.removalLimit(in: state, uidNext: uidNext)
        )
        MessageStore.shared.apply(plan)

        let fetchMillis = Int(fetchDone.timeIntervalSince(started) * 1000)
        let totalMillis = Int(Date().timeIntervalSince(started) * 1000)
        context.info("🔁", """
            Abgleich: \(state.all.count) Mails im Ordner, \
            \(state.forwarded?.count ?? 0) mit \(FlagState.forwardedKeyword), \
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
    nonisolated struct ServerSearchResult: Sendable {
        /// Treffer, die nicht im Cache liegen, neueste zuerst.
        let hits: [MessageListItem]
        /// `true`, wenn es mehr Treffer gab als gezeigt werden.
        let hasMore: Bool
    }

    /// Sucht in einem Ordner auf dem Server.
    ///
    /// Verarbeitung: Kriterien, Auswahl und Reihenfolge der Treffer
    /// bestimmt `ServerSearchPlan`. Hier: Ordner nur lesend auswählen
    /// (EXAMINE), suchen, Kopfdaten der ausgewählten Treffer holen (in
    /// Paketen, mit BODY.PEEK – nichts wird als gelesen markiert).
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
    @concurrent
    static func searchOnServer(
        _ credentials: MailCredentials,
        folder: String,
        query: String,
        address: String?
    ) async throws -> ServerSearchResult {
        let criteria = ServerSearchPlan.criteria(query: query, address: address)
        guard !criteria.isEmpty else { return ServerSearchResult(hits: [], hasMore: false) }

        let account = credentials.account
        return try await MailSession.withIMAP(credentials) { server -> ServerSearchResult in
            let context = FolderContext(server: server, account: account, folder: folder)
            _ = try await server.examineMailbox(folder)
            let uids = try await searchNewestFirst(
                on: server, criteria: criteria, calendar: SyncWindow.calendar
            )
            let selection = ServerSearchPlan.candidates(
                uids.map(\.value),
                cached: MessageStore.shared.cachedUIDs(accountID: account.id, folder: folder),
                limit: serverSearchHeaderLimit
            )
            let infos = try await fetchHeaders(selection.uids.map { SwiftMail.UID($0) }, on: server)
            let result = ServerSearchPlan.result(
                hits: infos.compactMap { FetchedMessageMapping.listItem(from: $0, account: account, folder: folder) },
                missingCount: selection.missingCount,
                limit: serverSearchLimit
            )
            context.info("🔎", "Serversuche: \(uids.count) Treffer, \(selection.missingCount) nicht im Cache, \(result.hits.count) gezeigt")
            return result
        }
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
    @concurrent
    static func loadMessage(_ credentials: MailCredentials, folder: String, uid: UInt32) async throws -> Bool {
        let account = credentials.account
        try await MailSession.withIMAP(credentials) { server -> Void in
            _ = try await server.selectMailbox(folder)
            let context = FolderContext(server: server, account: account, folder: folder)
            _ = try await cacheMessages([SwiftMail.UID(uid)], in: context)
        }
        let id = CachedMessage.makeID(accountID: account.id, folder: folder, uid: uid)
        return MessageStore.shared.message(id: id) != nil
    }

    // MARK: - Ältere Nachrichten

    /// Lädt den nächsten Zeitraum (30 Tage) vor dem bisherigen Fensterbeginn
    /// eines Ordners nach.
    ///
    /// Verarbeitung: Gibt es nichts Älteres, endet der Abruf sofort. Sonst
    /// sucht `loadOlderBlocks` den nächsten Zeitraum mit Mails. Der neue
    /// Fensterbeginn wird dauerhaft gespeichert – das schützt die Mails vor
    /// dem Aufräumen.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Passwort.
    ///   - folder: IMAP-Ordner (Standard: INBOX).
    /// - Returns: Ergebnis mit Anzahl geladener und fehlgeschlagener Mails
    ///   und ob es noch Älteres gibt.
    /// - Throws: Verbindungsfehler oder IMAP-Fehler.
    @concurrent
    static func fetchOlder(
        _ credentials: MailCredentials,
        folder: String = MailFolder.inboxPath
    ) async throws -> OlderFetchResult {
        let account = credentials.account
        return try await MailSession.withIMAP(credentials) { server -> OlderFetchResult in
            let context = FolderContext(server: server, account: account, folder: folder)
            let messageCount = try await server.selectMailbox(folder).messageCount
            let start = MessageStore.shared.windowStart(accountID: account.id, folder: folder)
                ?? SyncWindow.standardStart()

            // Gibt es überhaupt Älteres? Nicht per SEARCH über den ganzen
            // Ordner – bei großen Postfächern sprengt die Liste aller UIDs
            // den Antwortpuffer (siehe hasMessages).
            guard try await hasMessages(on: server, before: start, messageCount: messageCount) else {
                context.info("📬", "Keine älteren Nachrichten")
                return .noOlder
            }

            let outcome = try await loadOlderBlocks(before: start, messageCount: messageCount, in: context)
            MessageStore.shared.setWindowStart(outcome.start, accountID: account.id, folder: folder)
            let hasMore = try await hasMessages(on: server, before: outcome.start, messageCount: messageCount)
            return OlderFetchResult.loaded(
                count: outcome.loaded, failed: outcome.failed, windowStart: outcome.start, hasMore: hasMore
            )
        }
    }

    /// Schiebt das Zeitfenster blockweise zurück, bis ein Zeitraum Mails
    /// enthält, und lädt diese.
    ///
    /// Verarbeitung: Sucht je Block per SEARCH SINCE/BEFORE. Leere
    /// Zeiträume werden übersprungen (höchstens
    /// `SyncWindow.maxBlocksPerLoad`), sonst sähe ein Tipp auf „Ältere
    /// laden“ aus, als passiere nichts. Nach einem gefundenen Zeitraum rückt
    /// der Fensterbeginn nur bei vollständigem Laden zurück
    /// (`SyncWindow.startAfterLoading`) – sonst bliebe eine Lücke, die kein
    /// späterer Abruf mehr schließt.
    ///
    /// - Parameters:
    ///   - start: Bisheriger Fensterbeginn.
    ///   - messageCount: Anzahl der Nachrichten im Ordner (aus SELECT).
    ///   - context: Verbindung (Ordner ausgewählt), Postfach und Ordner.
    /// - Returns: Neuer Fensterbeginn, geladene und fehlgeschlagene Mails.
    /// - Throws: IMAP-Fehler.
    private static func loadOlderBlocks(
        before start: Date,
        messageCount: Int,
        in context: FolderContext
    ) async throws -> (start: Date, loaded: Int, failed: Int) {
        var start = start
        for _ in 0..<SyncWindow.maxBlocksPerLoad {
            let block = SyncWindow.nextBlock(before: start)
            let uids = try await searchNewestFirst(
                on: context.server,
                criteria: [.since(block.since), .before(block.before)],
                calendar: SyncWindow.calendar
            )
            context.info("📬", "Zeitraum ab \(block.since): \(uids.count) UIDs")
            if !uids.isEmpty {
                let result = try await cacheMessages(uids, in: context)
                let newStart = SyncWindow.startAfterLoading(
                    previous: block.before, loaded: block.since, failedCount: result.failed
                )
                return (newStart, result.saved, result.failed)
            }
            start = block.since
            guard try await hasMessages(on: context.server, before: start, messageCount: messageCount) else { break }
        }
        return (start, 0, 0)
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
    /// - Returns: true, wenn mindestens eine Mail vor `date` liegt.
    /// - Throws: IMAP-Fehler.
    private static func hasMessages(
        on server: SwiftMail.IMAPServer,
        before date: Date,
        messageCount: Int
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
                calendar: SyncWindow.calendar
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

    /// Holt die Kopfdaten (schlank, plus `extraHeaderFields`) zu UIDs.
    ///
    /// Verarbeitung: In Paketen zu `headerBatchSize`, damit keine einzelne
    /// Antwort zu groß wird; mit BODY.PEEK – nichts wird als gelesen
    /// markiert.
    ///
    /// - Parameters:
    ///   - uids: UIDs im ausgewählten Ordner.
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    /// - Returns: Kopfdaten aller Pakete.
    /// - Throws: IMAP-Fehler.
    private static func fetchHeaders(
        _ uids: [SwiftMail.UID],
        on server: SwiftMail.IMAPServer
    ) async throws -> [MessageInfo] {
        var infos: [MessageInfo] = []
        for start in stride(from: 0, to: uids.count, by: headerBatchSize) {
            let batch = Array(uids[start..<min(start + headerBatchSize, uids.count)])
            infos += try await server.fetchMessageInfosBulk(
                using: UIDSet(batch),
                options: .slim,
                headerFields: extraHeaderFields
            )
        }
        return infos
    }

    // MARK: - Gemeinsames Caching

    /// Höchstzahl neuer Mails, die gemeinsam in einem Commit gespeichert werden.
    private static let saveBatchCount = 10
    /// Höchstmenge geladener Daten (Text, HTML, Anhänge) in Bytes, ab der
    /// die gesammelten Mails gespeichert werden – begrenzt den Speicherbedarf.
    private static let saveBatchBytes = 8 * 1024 * 1024

    /// Eine geladene, noch nicht gespeicherte Mail samt Anhängen.
    nonisolated private struct LoadedMessage {
        /// Nachricht für den Cache.
        let message: CachedMessage
        /// Anhänge und eingebettete Bilder (mit oder ohne Daten).
        let attachments: [CachedAttachment]
        /// Geladene Datenmenge in Bytes (für die Paketgrenze).
        let byteCount: Int
        /// Vorberechnete Anzeige-Hinweise (externe Inhalte, eigene Farben,
        /// Sprache) – das Öffnen der Mail muss sie dann nicht mehr ermitteln.
        let hints: MessageDisplayHints
    }

    /// Geladene Mails, die gemeinsam in einem Commit gespeichert werden.
    ///
    /// Ein Commit je Paket (`saveBatchCount` Mails bzw. `saveBatchBytes`),
    /// jede Mail darin als eigener Savepoint – eine fehlerhafte Mail rollt
    /// nur sich selbst zurück.
    nonisolated private struct PendingBatch {
        /// Bezeichnung des Commits im Protokoll.
        let label: String
        /// Gesammelte Mails.
        private var messages: [LoadedMessage] = []
        /// Datenmenge der gesammelten Mails.
        private var byteCount = 0
        /// Bisher gespeicherte Mails.
        private(set) var saved = 0
        /// Bisher fehlgeschlagene Mails (nicht geladen oder nicht gespeichert).
        private(set) var failed = 0

        /// Legt das Paket an.
        ///
        /// - Parameter label: Bezeichnung des Commits im Protokoll.
        init(label: String) {
            self.label = label
        }

        /// `true`, wenn das Paket gespeichert werden sollte.
        var isFull: Bool {
            messages.count >= MailFetchService.saveBatchCount
                || byteCount >= MailFetchService.saveBatchBytes
        }

        /// Nimmt eine geladene Mail auf.
        ///
        /// - Parameter loaded: Geladene Mail.
        mutating func add(_ loaded: LoadedMessage) {
            messages.append(loaded)
            byteCount += loaded.byteCount
        }

        /// Zählt eine Mail, die nicht geladen werden konnte.
        mutating func countFailure() {
            failed += 1
        }

        /// Speichert die gesammelten Mails in einem Commit und zählt sie.
        ///
        /// Verarbeitung: Scheitert das gemeinsame Commit, ist keine Mail des
        /// Pakets gespeichert; alle zählen dann als fehlgeschlagen.
        mutating func flush() {
            guard !messages.isEmpty else { return }
            var stored = 0
            let pending = messages
            let committed = MessageStore.shared.batch(label) {
                for loaded in pending {
                    if MessageStore.shared.saveMessageWithAttachments(
                        loaded.message, attachments: loaded.attachments, hints: loaded.hints
                    ) {
                        stored += 1
                    } else {
                        Log.fetch.error("⚠️ Mail \(loaded.message.id, privacy: .public) nicht gespeichert (Ablage zurückgerollt)")
                    }
                }
            }
            let savedNow = committed ? stored : 0
            saved += savedNow
            failed += pending.count - savedNow
            messages = []
            byteCount = 0
        }
    }

    /// Holt Kopfdaten der übergebenen UIDs, gleicht bekannte Mails ab und
    /// legt neue samt Anhängen (≤ 5 MB) im Cache ab.
    ///
    /// Verarbeitung: Liest den Stand des Caches einmal, holt die Kopfdaten
    /// (`fetchHeaders`) und lässt `FetchClassifier` einordnen. Bekannte
    /// Mails erhalten nur geänderte Flags und ggf. nachgefüllte Kopfdaten –
    /// alles in einem gemeinsamen Commit (`applyKnownChanges`). Neue Mails
    /// lädt und speichert `saveNewMessages`.
    ///
    /// Gemeinsamer Teil von `refreshAndCache` (Datumssuche, Neuankünfte,
    /// ältere ungelesene), `fetchOlder` und `loadMessage`.
    ///
    /// - Parameters:
    ///   - uids: IMAP-UIDs der zu ladenden Mails.
    ///   - context: Verbindung (Ordner ausgewählt), Postfach und Ordner.
    /// - Returns: Anzahl neu gespeicherter und fehlgeschlagener Mails.
    /// - Throws: IMAP-Fehler bei der Bulk-Abfrage oder bei der neuen
    ///   Auswahl des Ordners (Fehler einzelner Mails werden gezählt).
    @discardableResult
    private static func cacheMessages(
        _ uids: [SwiftMail.UID],
        in context: FolderContext
    ) async throws -> CacheResult {
        let cache = cacheSnapshot(of: context)
        context.info("📬", "Davon bereits im Cache: \(cache.messageIDs.count)")

        let infos = try await fetchHeaders(uids, on: context.server)
        context.info("📬", "fetchMessageInfosBulk lieferte \(infos.count) Infos")

        let entries = infos.map { FetchClassifier.Entry(uid: $0.uid?.value, flags: FlagState($0.flags)) }
        let classification = FetchClassifier.classify(
            entries, cache: cache, accountID: context.account.id, folder: context.folder
        )
        applyKnownChanges(classification, entries: entries, infos: infos, in: context)

        let newMessages = classification.newMessages.map { target in
            FetchedMessage(
                info: infos[target.index],
                uid: SwiftMail.UID(target.uid),
                messageID: target.messageID,
                flags: entries[target.index].flags
            )
        }
        let result = try await saveNewMessages(newMessages, in: context)

        context.info("📬", "Fertig: \(result.saved) neu gespeichert, \(result.failed) fehlgeschlagen, \(cache.messageIDs.count) aus Cache (\(classification.flagUpdates.count) Flags geändert), \(classification.headerBackfills.count) Header nachgefüllt, \(classification.skippedCount) übersprungen (keine UID)")
        return result
    }

    /// Liest, was der Cache zum Ordner weiß: Cache-IDs, gespeicherte Flags
    /// und Mails mit älterer Header-Version.
    ///
    /// - Parameter context: Postfach und Ordner.
    /// - Returns: Stand des Caches für `FetchClassifier`.
    private static func cacheSnapshot(of context: FolderContext) -> FetchClassifier.CacheSnapshot {
        let accountID = context.account.id
        let flags = Dictionary(
            MessageStore.shared
                .cachedFlagStates(accountID: accountID, folder: context.folder, since: .distantPast)
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return FetchClassifier.CacheSnapshot(
            messageIDs: MessageStore.shared.cachedMessageIDs(forAccount: accountID, folder: context.folder),
            flags: flags,
            needsHeaders: MessageStore.shared.messageIDsNeedingHeaders(forAccount: accountID, folder: context.folder)
        )
    }

    /// Schreibt geänderte Flags und nachgefüllte Kopfdaten bekannter Mails
    /// in einem gemeinsamen Commit.
    ///
    /// - Parameters:
    ///   - classification: Einordnung aus `FetchClassifier`.
    ///   - entries: Ausgewertete Flags je Kopfdaten-Antwort.
    ///   - infos: Kopfdaten (gleiche Reihenfolge wie `entries`).
    ///   - context: Ordner (für die Bezeichnung des Commits).
    private static func applyKnownChanges(
        _ classification: FetchClassifier.Classification,
        entries: [FetchClassifier.Entry],
        infos: [MessageInfo],
        in context: FolderContext
    ) {
        guard !classification.flagUpdates.isEmpty || !classification.headerBackfills.isEmpty else { return }
        MessageStore.shared.batch("bekannte Mails \(context.folder)") {
            for target in classification.flagUpdates {
                MessageStore.shared.updateServerFlags(
                    messageID: target.messageID, flags: entries[target.index].flags
                )
            }
            for target in classification.headerBackfills {
                MessageStore.shared.updateHeaders(
                    messageID: target.messageID,
                    headers: FetchedMessageMapping.headers(from: infos[target.index])
                )
            }
        }
    }

    /// Lädt neue Mails einzeln und speichert sie paketweise (`PendingBatch`).
    ///
    /// Verarbeitung: Eine Mail, die sich auch nach neuer Auswahl des
    /// Ordners nicht laden lässt, wird übersprungen und zählt als
    /// fehlgeschlagen. Ist die Verbindung tot (die neue Auswahl scheitert),
    /// werden die bis dahin geladenen Mails noch gespeichert, dann bricht
    /// die Runde ab.
    ///
    /// - Parameters:
    ///   - messages: Neue Mails aus der Kopfdaten-Abfrage.
    ///   - context: Verbindung (Ordner ausgewählt), Postfach und Ordner.
    /// - Returns: Anzahl gespeicherter und fehlgeschlagener Mails.
    /// - Throws: IMAP-Fehler bei der neuen Auswahl des Ordners.
    private static func saveNewMessages(
        _ messages: [FetchedMessage],
        in context: FolderContext
    ) async throws -> CacheResult {
        var batch = PendingBatch(label: "neue Mails \(context.folder)")
        for message in messages {
            let loaded: LoadedMessage?
            do {
                loaded = try await loadWithRetry(message, in: context)
            } catch {
                batch.flush()
                throw error
            }
            guard let loaded else {
                batch.countFailure()
                continue
            }
            batch.add(loaded)
            if batch.isFull { batch.flush() }
        }
        batch.flush()
        return CacheResult(saved: batch.saved, failed: batch.failed)
    }

    /// Lädt eine neue Mail; scheitert das, wird der Ordner neu ausgewählt
    /// und die Mail genau einmal wiederholt.
    ///
    /// Hintergrund: Schlägt das Laden fehl, kann die Mail selbst defekt
    /// sein – oder SwiftMail hat eine abgerissene Verbindung still neu
    /// aufgebaut und sich neu angemeldet, den Ordner aber nicht wieder
    /// ausgewählt; dann scheitert jeder weitere Befehl mit „No mailbox
    /// selected“. Ohne neue Auswahl scheiterte jede weitere Mail der Runde.
    ///
    /// - Parameters:
    ///   - message: Neue Mail aus der Kopfdaten-Abfrage.
    ///   - context: Verbindung (Ordner ausgewählt), Postfach und Ordner.
    /// - Returns: Geladene Mail; `nil`, wenn sie auch nach neuer Auswahl
    ///   nicht ladbar ist (ein späterer Abruf versucht sie erneut).
    /// - Throws: IMAP-Fehler, wenn schon die neue Auswahl scheitert – die
    ///   Verbindung ist dann tot.
    private static func loadWithRetry(
        _ message: FetchedMessage,
        in context: FolderContext
    ) async throws -> LoadedMessage? {
        do {
            return try await loadNewMessage(message, in: context)
        } catch {
            context.error("⚠️", "Mail \(message.messageID) fehlgeschlagen, Ordner wird neu ausgewählt: \(error.localizedDescription)")
        }
        _ = try await context.server.selectMailbox(context.folder)
        do {
            return try await loadNewMessage(message, in: context)
        } catch {
            context.error("⚠️", "Mail \(message.messageID) übersprungen: \(error.localizedDescription)")
            return nil
        }
    }

    /// Lädt eine neue Mail samt Anhängen und eingebetteten Bildern (≤ 5 MB),
    /// ohne sie zu speichern.
    ///
    /// Verarbeitung: Holt zuerst nur die Struktur der Mail, dann gezielt
    /// Text- und HTML-Teil (`MessageContentPlan`, `fetchBodies`), danach
    /// Anhänge und eingebettete Bilder (`fetchAttachments`). Die Modelle
    /// baut `FetchedMessageMapping`; die Anzeige-Hinweise
    /// (MessageDisplayHints) werden gleich hier im Hintergrund berechnet –
    /// beim Öffnen wird dann nur gelesen. Gespeichert wird paketweise in
    /// `saveNewMessages`.
    ///
    /// - Parameters:
    ///   - message: Neue Mail aus der Kopfdaten-Abfrage.
    ///   - context: Verbindung (Ordner ausgewählt), Postfach und Ordner.
    /// - Returns: Geladene Mail samt Anhängen und Datenmenge.
    /// - Throws: IMAP-Fehler beim Laden der Struktur oder des Textes.
    private static func loadNewMessage(
        _ message: FetchedMessage,
        in context: FolderContext
    ) async throws -> LoadedMessage {
        let totalSize = message.info.size ?? 0
        let plan = MessageContentPlan(
            structure: try await context.server.fetchStructure(message.uid),
            totalSize: totalSize,
            threshold: autoDownloadThresholdBytes
        )
        let bodyData = try await fetchBodies(of: plan, uid: message.uid, on: context.server)
        let bodies = plan.bodies(withData: bodyData)
        let cached = FetchedMessageMapping.message(
            message,
            account: context.account,
            folder: context.folder,
            content: FetchedMessageMapping.Content(
                text: bodies.text, html: bodies.html,
                hasAttachments: !plan.attachments.isEmpty, fetchedAt: Date()
            )
        )
        let attachments = await fetchAttachments(of: plan, for: message, in: context)

        let textBytes = bodyData.values.reduce(0) { $0 + $1.count }
        let attachmentBytes = attachments.reduce(0) { $0 + ($1.data?.count ?? 0) }
        if !attachments.isEmpty {
            context.debug("📎", "Mail \(message.uid.value): \(plan.attachments.count) Anhänge, \(plan.inlineImages.count) eingebettete Bilder, Größe \(totalSize / 1024) KB, geladen: Text \(textBytes / 1024) KB, Anhänge/Bilder \(attachmentBytes / 1024) KB")
        }
        return LoadedMessage(
            message: cached,
            attachments: attachments,
            byteCount: textBytes + attachmentBytes,
            hints: MessageDisplayHints.compute(for: cached)
        )
    }

    /// Lädt Text- und HTML-Teile der Mail selbst (roh; dekodiert wird beim
    /// Zusammensetzen).
    ///
    /// Verarbeitung: Scheitert ein Teil, scheitert die Mail – der Aufrufer
    /// wählt den Ordner neu und wiederholt sie einmal.
    ///
    /// - Parameters:
    ///   - plan: Zu ladende Teile.
    ///   - uid: UID der Mail.
    ///   - server: Verbindung mit ausgewähltem Ordner.
    /// - Returns: Rohdaten je Abschnittsnummer.
    /// - Throws: IMAP-Fehler.
    private static func fetchBodies(
        of plan: MessageContentPlan,
        uid: SwiftMail.UID,
        on server: SwiftMail.IMAPServer
    ) async throws -> [String: Data] {
        var bodyData: [String: Data] = [:]
        for part in plan.bodyParts {
            bodyData[part.section.description] = try await server.fetchPart(section: part.section, of: uid)
        }
        return bodyData
    }

    /// Sammelt Anhänge und eingebettete Bilder vollständig ein.
    ///
    /// Verarbeitung: Daten werden nur bei Mails bis zur Schwelle geladen
    /// (`plan.loadsAttachmentData`); größere Mails bekommen nur Einträge,
    /// Daten erst bei Bedarf. Lässt sich ein einzelner Teil nicht laden,
    /// wird nur sein Eintrag (ohne Daten) übernommen – ein Anhang kann dann
    /// per Antippen, ein Bild beim Öffnen der Mail nachgeladen werden. So
    /// bleibt die Mail sichtbar und vollständig beschrieben.
    ///
    /// - Parameters:
    ///   - plan: Teile der Mail.
    ///   - message: Neue Mail aus der Kopfdaten-Abfrage.
    ///   - context: Verbindung (Ordner ausgewählt), Postfach und Ordner.
    /// - Returns: Einträge aller Anhänge und eingebetteten Bilder.
    private static func fetchAttachments(
        of plan: MessageContentPlan,
        for message: FetchedMessage,
        in context: FolderContext
    ) async -> [CachedAttachment] {
        let parts = plan.attachments.map { ($0, false) } + plan.inlineImages.map { ($0, true) }
        var attachments: [CachedAttachment] = []
        for (part, isInline) in parts {
            var data: Data?
            if plan.loadsAttachmentData {
                do {
                    data = try await context.server.fetchAndDecodeMessagePartData(
                        messageInfo: message.info, part: part
                    )
                } catch {
                    context.error("⚠️", "Teil \(part.section.description) von Mail \(message.messageID) nicht geladen, nur Eintrag gespeichert: \(error.localizedDescription)")
                }
            }
            attachments.append(FetchedMessageMapping.attachment(
                for: part, data: data, isInline: isInline, messageID: message.messageID
            ))
        }
        return attachments
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
}
