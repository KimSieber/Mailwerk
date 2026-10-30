//
//  WatchBridge.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 20.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Anbindung der Apple Watch auf dem iPhone (WatchConnectivity).
//  Die Watch darf unter watchOS nicht selbst mit den Mailservern sprechen;
//  das iPhone übernimmt das für sie – auch wenn die App auf dem iPhone
//  geschlossen ist (die Anfrage der Watch weckt sie im Hintergrund).
//
//  Ablauf einer Aktualisierung (`WatchRequest.sync`):
//  1. Sofortige Antwort mit dem Stand aus dem Cache des iPhones – die Watch
//     zeigt ihn ohne Wartezeit.
//  2. Die mitgeschickten Aktionen der Watch werden auf dem Server
//     ausgeführt, danach werden (beim Öffnen und Aktualisieren, nicht nach
//     einer einzelnen Aktion) alle Posteingänge abgerufen – über dasselbe
//     ViewModel wie in der App, damit sich Abrufe nicht doppeln.
//  3. Der neue Stand samt Ergebnis der Aktionen geht als eigene
//     Nachricht an die Watch (bzw. als Datei im Hintergrund, wenn sie
//     inzwischen nicht mehr erreichbar ist).
//
//  Aktionen: Mail nicht mehr im Cache → verworfen (der Server gewinnt).
//  Ohne Netz oder bei einem Verbindungsfehler bleibt die Aktion auf der
//  Watch offen und kommt mit der nächsten Aktualisierung wieder. Andere
//  Fehler werden als gescheitert gemeldet. Bereits ausgeführte Aktionen
//  werden nicht doppelt ausgeführt (`completed`).
//
//  Sofort: Ändert sich auf dem iPhone etwas (Aktion, Abruf) und ist die
//  Watch-App gerade offen, geht der neue Stand aus dem Cache nach kurzer
//  Wartezeit an sie (`cacheReloaded`). Aktionen der Watch zeigt die Liste
//  auf dem iPhone sofort.
//
//  Hintergrund: Ruft die App selbst ab (Start, Herunterziehen), bekommt die
//  Watch den neuen Stand als Datei im Hintergrund – samt den Inhalten, die
//  sie noch nicht hat. So ist er beim nächsten Öffnen der Watch schon da.
//  Damit die App im Hintergrund nicht mitten im Abruf angehalten wird,
//  hält `BackgroundGrace` sie für die Dauer wach (soweit iOS es zulässt).
//
//  Hinweise zum Abruf: ohne Netz „iPhone ohne Internet“, sonst je
//  Postfach, das den Server nicht erreichte, eine Zeile
//  (AccountFetchState) – die Watch zeigt alle.
//
//  Große Lieferungen werden gepackt und in Stücke geteilt (WatchWire); die
//  Stücke bleiben einige Minuten zum Abholen bereit.
//
//  Nur iPhone (WatchConnectivity); auf Mac und Vision Pro entfällt die Datei.
//
//  Abgrenzung: Zusammenstellen der Lieferungen → WatchSnapshotBuilder;
//  Übertragungsform → WatchTransfer, WatchWire; Gegenstück auf der Watch →
//  WatchConnector.
//
//  Abhängigkeiten: Foundation, WatchConnectivity, AppObjects (AccountStore,
//  InboxViewModel, SpamSettings), MessageActions, SpamMenuRequest,
//  MessageStore, NetworkMonitor, ConnectionErrorClassifier,
//  MailFetchService (Verbindungsfehler), ContactImageDirectory,
//  ContactSuggestionService, AccountFetchState, Log.
//

#if os(iOS) && canImport(WatchConnectivity)
import Foundation
import WatchConnectivity
import os

/// Anbindung der Apple Watch auf dem iPhone.
final class WatchBridge {
    /// Gemeinsame Instanz der App.
    static let shared = WatchBridge()

    /// Wie lange Stücke einer Lieferung zum Abholen bereitliegen.
    static let deliveryLifetimeSeconds: TimeInterval = 300

    /// Höchstzahl gemerkter Ergebnisse von Watch-Aktionen; darüber wird
    /// der Speicher geleert, damit er nicht unbegrenzt wächst.
    static let maxRememberedActions = 500
    /// Schlüssel der an die Watch gelieferten Inhalte in den UserDefaults.
    private static let deliveredBodiesKey = "WatchBridge.deliveredBodies"

    /// Objekte der App; `nil`, bis `start` lief.
    private var objects: AppObjects?
    /// Sitzung mit der Watch; `nil`, wenn das Gerät keine Watch unterstützt.
    private var session: WCSession?
    /// Empfänger der Ereignisse der Sitzung (die Sitzung hält ihn nur schwach).
    private let sessionDelegate = WatchBridgeSessionDelegate()
    /// Lieferungen mit mehreren Stücken, die die Watch noch abholt.
    private var deliveries: [UUID: (chunks: [WatchChunk], createdAt: Date)] = [:]
    /// Aktionen der Watch, die noch auszuführen sind.
    private var waitingActions: [WatchAction] = []
    /// `true`, solange eine Aktualisierung für die Watch läuft.
    private var isSyncing = false
    /// Die Watch wünscht einen Abruf aller Posteingänge.
    private var refreshRequested = false
    /// Ergebnisse bereits ausgeführter Aktionen (gegen doppeltes Ausführen).
    private var completed: [UUID: WatchActionOutcome.Result] = [:]
    /// Kennzeichen des zuletzt gelieferten Stands (nichts doppelt senden).
    private var lastSignature: String?
    /// Wartet kurz, bevor eine Änderung auf dem iPhone an die offene
    /// Watch-App geht; weitere Änderungen in dieser Zeit ersetzen sie.
    private var pendingPush: Task<Void, Never>?

    /// Wartezeit, in der Änderungen auf dem iPhone zusammengefasst werden.
    static let pushDelay: Duration = .seconds(1)

    /// Nur die gemeinsame Instanz.
    private init() {}

    // MARK: - Start

    /// Richtet die Sitzung ein. Aufruf einmal beim App-Start, damit
    /// Anfragen der Watch auch nach einem Start im Hintergrund ankommen.
    ///
    /// - Parameter objects: Objekte der App.
    func start(objects: AppObjects) {
        guard self.objects == nil, WCSession.isSupported() else { return }
        self.objects = objects
        objects.inbox.onInboxesRefreshed = { [weak self] in self?.inboxesRefreshed() }
        objects.inbox.onCacheReloaded = { [weak self] in self?.cacheReloaded() }
        let session = WCSession.default
        session.delegate = sessionDelegate
        session.activate()
        self.session = session
        // Kontaktbilder auch nach einem Start im Hintergrund (ohne Liste).
        // Nur bei erteilter Berechtigung – im Hintergrund darf keine
        // Systemabfrage erscheinen.
        if ContactSuggestionService.shared.isAccessAllowed {
            Task { await ContactImageDirectory.shared.start() }
        }
        Log.watch.info("⌚️ Anbindung der Watch gestartet")
    }

    // MARK: - Anfragen der Watch

    /// Beantwortet eine Anfrage der Watch.
    ///
    /// - Parameter data: Kodierte Anfrage (`WatchRequest`).
    /// - Returns: Kodiertes erstes Stück der Antwort; leer bei einer
    ///   unlesbaren Anfrage oder einem nicht mehr vorhandenen Stück.
    fileprivate func handle(_ data: Data) async -> Data {
        guard let objects, let request = try? WatchWire.decode(WatchRequest.self, from: data) else {
            Log.watch.error("⚠️ Anfrage der Watch nicht lesbar")
            return Data()
        }
        switch request {
        case .sync(let actions, let refresh):
            Log.watch.info("⌚️ Aktualisierung angefragt, \(actions.count, privacy: .public) Aktionen, Abruf: \(refresh, privacy: .public)")
            let reply = deliver(.snapshot(await snapshot(objects, isFresh: false)))
            enqueue(actions, refresh: refresh)
            return reply
        case .content(let mailIDs, let imageKeys):
            let content = WatchSnapshotBuilder.content(mailIDs: mailIDs, imageKeys: imageKeys)
            rememberDelivered(content.bodies.map(\.id))
            return deliver(.content(content))
        case .chunk(let token, let index):
            purgeDeliveries()
            guard let chunks = deliveries[token]?.chunks, chunks.indices.contains(index),
                  let data = try? WatchWire.encode(chunks[index]) else { return Data() }
            return data
        }
    }

    /// Nimmt Aktionen an und startet die Aktualisierung, falls keine läuft.
    ///
    /// Verarbeitung: Läuft schon eine, holt sie die neuen Aktionen (und
    /// einen gewünschten Abruf) in einer weiteren Runde ab. Eine Aktion, die
    /// schon wartet, wird nicht doppelt aufgenommen.
    ///
    /// - Parameters:
    ///   - actions: Aktionen der Watch.
    ///   - refresh: `true` = danach alle Posteingänge abrufen.
    private func enqueue(_ actions: [WatchAction], refresh: Bool) {
        let waiting = Set(waitingActions.map(\.id))
        waitingActions += actions.filter { !waiting.contains($0.id) }
        refreshRequested = refreshRequested || refresh
        guard !isSyncing else { return }
        isSyncing = true
        let grace = BackgroundGrace.begin(reason: "Aktualisierung für die Apple Watch")
        Task {
            defer {
                isSyncing = false
                grace.end()
            }
            await runSync()
        }
    }

    /// Führt die wartenden Aktionen aus, ruft bei Bedarf ab und liefert den
    /// neuen Stand.
    ///
    /// Verarbeitung: Kommen währenddessen Aktionen oder ein Abrufwunsch
    /// hinzu, folgt eine weitere Runde.
    private func runSync() async {
        guard let objects else { return }
        repeat {
            let batch = waitingActions
            let refresh = refreshRequested
            waitingActions = []
            refreshRequested = false
            let outcomes = await perform(batch, objects: objects)
            if !batch.isEmpty {
                // Die Liste auf dem iPhone zeigt die Aktionen der Watch sofort.
                objects.inbox.loadFromCache()
            }
            var problems: [String] = []
            if refresh {
                await objects.inbox.refresh()
                if !NetworkMonitor.shared.isOnline {
                    problems.append("iPhone ohne Internet")
                } else {
                    // Je nicht erreichbarem Postfach eine Zeile.
                    problems += AccountFetchState.watchProblems(
                        accounts: objects.accountStore.fetchingAccounts.map { (id: $0.id, name: $0.displayName) },
                        unreachable: AccountFetchState.shared.unreachable
                    )
                }
            }
            push(.snapshot(await snapshot(objects, isFresh: refresh, outcomes: outcomes, problems: problems)))
        } while !waitingActions.isEmpty || refreshRequested
    }

    /// Führt Aktionen der Watch auf Server und Cache aus.
    ///
    /// Verarbeitung: Schon erledigte Aktionen (`completed`) werden nur
    /// erneut bestätigt – die Watch schickt eine Aktion, bis sie die Antwort
    /// sieht. Ohne Netz bleiben alle offen. Ausführen und Fehler auswerten
    /// übernehmen `execute` und `failureHandling`.
    ///
    /// - Parameters:
    ///   - actions: Aktionen in ihrer Reihenfolge.
    ///   - objects: Objekte der App.
    /// - Returns: Ergebnisse; ohne Eintrag bleibt eine Aktion offen.
    private func perform(_ actions: [WatchAction], objects: AppObjects) async -> [WatchActionOutcome] {
        var outcomes: [WatchActionOutcome] = []
        for action in actions {
            if let result = completed[action.id] {
                outcomes.append(WatchActionOutcome(actionID: action.id, result: result))
                continue
            }
            guard NetworkMonitor.shared.isOnline else { continue }
            if let result = await performOne(action, objects: objects) {
                record(result, for: action, into: &outcomes)
            }
        }
        return outcomes
    }

    /// Führt eine einzelne, noch nicht erledigte Aktion aus.
    ///
    /// - Parameters:
    ///   - action: Aktion der Watch.
    ///   - objects: Objekte der App.
    /// - Returns: Ergebnis; `nil`, wenn die Aktion offen bleibt (keine
    ///   Verbindung).
    private func performOne(_ action: WatchAction, objects: AppObjects) async -> WatchActionOutcome.Result? {
        guard let message = MessageStore.shared.message(id: action.mailID) else { return .dropped }
        do {
            try await execute(action.change, spamRequest: action.spamRequest, on: message, objects: objects)
            Log.watch.info("⌚️ Aktion der Watch ausgeführt")
            return .done
        } catch {
            switch Self.failureHandling(for: error, spamRequest: action.spamRequest) {
            case .keepOpen:
                Log.watch.info("⌚️ Aktion der Watch bleibt offen (keine Verbindung)")
                return nil
            case .fail(let reason):
                Log.watch.error("⚠️ Aktion der Watch gescheitert: \(error.localizedDescription, privacy: .public)")
                return .failed(reason)
            }
        }
    }

    /// Setzt die Änderung einer Aktion an der Mail um.
    ///
    /// - Parameters:
    ///   - change: Gewünschte Änderung (gelesen, gekennzeichnet, Spam-Liste).
    ///   - spamRequest: Eintrag für die Filterlisten (nur bei Spam).
    ///   - message: Betroffene Mail aus dem Cache.
    ///   - objects: Objekte der App.
    /// - Throws: Fehler der Aktion (Server, Filterlisten).
    private func execute(
        _ change: WatchAction.Change,
        spamRequest: SpamMenuRequest?,
        on message: CachedMessage,
        objects: AppObjects
    ) async throws {
        let target = MessageActions.Target(message)
        switch change {
        case .read(let isRead):
            try await MessageActions.apply(.read(isRead), to: target, accountStore: objects.accountStore)
        case .flagged(let isFlagged):
            try await MessageActions.apply(.flagged(isFlagged), to: target, accountStore: objects.accountStore)
        case .spam:
            if let spamRequest {
                _ = try await spamRequest.perform(on: message, using: objects.inbox.spamFilter)
            }
        }
    }

    /// Umgang mit einem Fehler beim Ausführen einer Aktion der Watch.
    nonisolated enum FailureHandling: Equatable {
        /// Keine Verbindung: Aktion bleibt offen, die Watch schickt sie erneut.
        case keepOpen
        /// Aktion gescheitert; der Text erscheint auf der Watch.
        case fail(String)
    }

    /// Wertet einen Fehler beim Ausführen einer Aktion aus.
    ///
    /// Verarbeitung: Reine Verbindungsfehler lassen die Aktion offen.
    /// Steht ein Spam-Eintrag schon auf der anderen Liste, erklärt der Text
    /// das wie im Spam-Menü der App; sonst gilt die Fehlermeldung.
    ///
    /// - Parameters:
    ///   - error: Aufgetretener Fehler.
    ///   - spamRequest: Eintrag für die Filterlisten, falls Spam-Aktion.
    /// - Returns: Offen lassen oder mit Text scheitern.
    nonisolated static func failureHandling(for error: Error, spamRequest: SpamMenuRequest?) -> FailureHandling {
        if ConnectionErrorClassifier.isConnectionError(error) || MailFetchService.isConnectionError(error) {
            return .keepOpen
        }
        if case FilterListError.alreadyOnOtherList(let list) = error, let spamRequest {
            return .fail(SpamMenuTexts.otherListMessage(spamRequest, list: list))
        }
        return .fail(error.localizedDescription)
    }

    /// Merkt das Ergebnis einer Aktion.
    ///
    /// - Parameters:
    ///   - result: Ergebnis.
    ///   - action: Aktion.
    ///   - outcomes: Ergebnisse dieser Runde.
    private func record(_ result: WatchActionOutcome.Result, for action: WatchAction, into outcomes: inout [WatchActionOutcome]) {
        completed[action.id] = result
        outcomes.append(WatchActionOutcome(actionID: action.id, result: result))
        if completed.count > Self.maxRememberedActions {
            completed = [:]
        }
    }

    // MARK: - Lieferungen

    /// Stand der Mails für die Watch.
    ///
    /// Verarbeitung: Die Filterlisten werden frisch gelesen; lassen sie sich
    /// nicht lesen, entscheidet die Watch vorsichtig.
    ///
    /// - Parameters:
    ///   - objects: Objekte der App.
    ///   - isFresh: `true` direkt nach einem Abruf.
    ///   - outcomes: Ergebnisse von Aktionen.
    ///   - problems: Hinweise zum Abruf.
    /// - Returns: Stand.
    private func snapshot(
        _ objects: AppObjects,
        isFresh: Bool,
        outcomes: [WatchActionOutcome] = [],
        problems: [String] = []
    ) async -> WatchSnapshot {
        let lists = await objects.inbox.spamFilter.currentLists()
        // Messpunkt (v0.2.3c): Entscheidung, ob der Watch-Stand vom
        // Hauptthread gelöst werden muss.
        let interval = Log.beginInterval(Log.Interval.watchSnapshot)
        defer { Log.endInterval(interval) }
        let accounts = objects.accountStore.fetchingAccounts
        return WatchSnapshotBuilder.snapshot(
            WatchSnapshotBuilder.Frame(
                accounts: accounts,
                lists: lists,
                scoreLimit: objects.spamSettings.scoreLimit,
                isFresh: isFresh,
                outcomes: outcomes,
                problems: problems
            ),
            cache: WatchSnapshotBuilder.cacheData(accounts: accounts, spamFolders: objects.inbox.spamFolders)
        )
    }

    /// Packt eine Lieferung und legt ihre Stücke zum Abholen bereit.
    ///
    /// - Parameter payload: Lieferung.
    /// - Returns: Kodiertes erstes Stück; leer, wenn das Packen scheitert.
    private func deliver(_ payload: WatchPayload) -> Data {
        purgeDeliveries()
        guard let blob = try? WatchWire.pack(payload) else {
            Log.watch.error("⚠️ Lieferung an die Watch nicht packbar")
            return Data()
        }
        let token = UUID()
        let chunks = WatchWire.split(blob, token: token)
        if chunks.count > 1 {
            deliveries[token] = (chunks, Date())
        }
        Log.watch.debug("⌚️ Lieferung: \(blob.count / 1024, privacy: .public) KB in \(chunks.count, privacy: .public) Stücken")
        do {
            return try WatchWire.encode(chunks[0])
        } catch {
            Log.watch.error("⚠️ Erstes Stück der Lieferung nicht kodierbar: \(error.localizedDescription, privacy: .public)")
            return Data()
        }
    }

    /// Entfernt abgelaufene Lieferungen.
    private func purgeDeliveries() {
        let limit = Date().addingTimeInterval(-Self.deliveryLifetimeSeconds)
        deliveries = deliveries.filter { $0.value.createdAt > limit }
    }

    /// Schickt eine Lieferung an die Watch: als Nachricht, wenn sie gerade
    /// erreichbar ist, sonst als Datei im Hintergrund.
    ///
    /// - Parameter payload: Lieferung (Stand der Mails).
    private func push(_ payload: WatchPayload) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        if case .snapshot(let snapshot) = payload {
            lastSignature = Self.signature(of: snapshot)
        }
        if session.isReachable {
            let first = deliver(payload)
            session.sendMessageData(first, replyHandler: nil) { @Sendable error in
                Log.watch.error("⚠️ Stand nicht an die Watch gesendet: \(error.localizedDescription, privacy: .public)")
            }
        } else if case .snapshot(let snapshot) = payload {
            Task { await transferPackage(snapshot) }
        }
    }

    /// Nach einem Abruf in der App: neuen Stand im Hintergrund liefern.
    ///
    /// Verarbeitung: Nicht während einer Aktualisierung für die Watch (die
    /// liefert selbst) und nicht, wenn sich gegenüber der letzten
    /// Lieferung nichts geändert hat.
    private func inboxesRefreshed() {
        guard let objects, !isSyncing, let session,
              session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        Task {
            let snapshot = await snapshot(objects, isFresh: true)
            guard Self.signature(of: snapshot) != lastSignature else { return }
            lastSignature = Self.signature(of: snapshot)
            await transferPackage(snapshot)
        }
    }

    /// Nach einer Änderung auf dem iPhone (Aktion, Abruf): den neuen Stand
    /// an die Watch-App schicken, wenn sie gerade offen ist.
    ///
    /// Verarbeitung: Nur bei erreichbarer Watch (Watch-App im Vordergrund),
    /// nicht während einer Aktualisierung für die Watch (die liefert
    /// selbst). Änderungen innerhalb von `pushDelay` werden zu einer
    /// Lieferung zusammengefasst; unveränderte Stände gehen nicht hinaus.
    /// Geliefert wird der Stand aus dem Cache, ohne Abruf vom Server.
    private func cacheReloaded() {
        guard !isSyncing, let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled, session.isReachable else { return }
        pendingPush?.cancel()
        pendingPush = Task {
            try? await Task.sleep(for: Self.pushDelay)
            guard !Task.isCancelled, !isSyncing, let objects else { return }
            let snapshot = await snapshot(objects, isFresh: false)
            guard Self.signature(of: snapshot) != lastSignature else { return }
            push(.snapshot(snapshot))
            Log.watch.info("⌚️ Änderung auf dem iPhone an die offene Watch-App geschickt")
        }
    }

    /// Schickt Stand und fehlende Inhalte als Datei an die Watch.
    ///
    /// Verarbeitung: Eine noch laufende ältere Datei wird abgebrochen. Mit
    /// dabei sind die Inhalte der Mails, die die Watch noch nicht bekommen
    /// hat, und deren Absenderbilder. Gepackt wird abseits des Main-Actors,
    /// damit die Liste in der App nicht stockt.
    ///
    /// - Parameter snapshot: Stand.
    private func transferPackage(_ snapshot: WatchSnapshot) async {
        guard let session else { return }
        let delivered = deliveredBodies()
        let missing = snapshot.mails.map(\.id).filter { !delivered.contains($0) }
        let missingSet = Set(missing)
        let keys = Array(Set(snapshot.mails.filter { missingSet.contains($0.id) }.compactMap(\.avatarKey)))
        let interval = Log.beginInterval(Log.Interval.watchSnapshot)
        let content = WatchSnapshotBuilder.content(mailIDs: missing, imageKeys: keys)
        Log.endInterval(interval)
        let packed = await Task.detached(priority: .utility) {
            Result { try WatchWire.pack(.package(snapshot, content)) }
        }.value
        let blob: Data
        switch packed {
        case .success(let data):
            blob = data
        case .failure(let error):
            Log.watch.error("⚠️ Stand für die Watch nicht packbar: \(error.localizedDescription, privacy: .public)")
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(UUID().uuidString).mwpack")
        do {
            try blob.write(to: url, options: .atomic)
        } catch {
            Log.watch.error("⚠️ Datei für die Watch nicht geschrieben: \(error.localizedDescription, privacy: .public)")
            return
        }
        session.outstandingFileTransfers.forEach { $0.cancel() }
        session.transferFile(url, metadata: nil)
        rememberDelivered(content.bodies.map(\.id), keeping: Set(snapshot.mails.map(\.id)))
        Log.watch.info("⌚️ Stand als Datei an die Watch: \(snapshot.mails.count, privacy: .public) Mails, \(content.bodies.count, privacy: .public) Inhalte, \(blob.count / 1024, privacy: .public) KB")
    }

    /// Kennzeichen eines Stands: Mails mit Zustand und Listen.
    ///
    /// - Parameter snapshot: Stand.
    /// - Returns: Kennzeichen zum Vergleich.
    private static func signature(of snapshot: WatchSnapshot) -> String {
        let mails = snapshot.mails.map { "\($0.id)|\($0.isUnread)|\($0.isFlagged)|\($0.box.rawValue)" }
        return mails.joined(separator: ";") + "#\(snapshot.unreadInboxTotal)#\(String(describing: snapshot.lists))"
    }

    // MARK: - Gelieferte Inhalte

    /// Cache-IDs der Mails, deren Inhalt die Watch schon bekommen hat.
    ///
    /// - Returns: Menge der Cache-IDs.
    private func deliveredBodies() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.deliveredBodiesKey) ?? [])
    }

    /// Vermerkt gelieferte Inhalte.
    ///
    /// - Parameters:
    ///   - ids: Neu gelieferte Cache-IDs.
    ///   - keeping: Wenn angegeben, bleiben nur IDs aus dieser Menge vermerkt
    ///     (Mails, die nicht mehr zur Auswahl gehören, fallen heraus).
    private func rememberDelivered(_ ids: [String], keeping: Set<String>? = nil) {
        var delivered = deliveredBodies().union(ids)
        if let keeping {
            delivered.formIntersection(keeping)
        }
        UserDefaults.standard.set(Array(delivered), forKey: Self.deliveredBodiesKey)
    }
}

// MARK: - Ereignisse der Sitzung

/// Empfänger der Ereignisse von WatchConnectivity.
///
/// Bewusst ein eigener Typ ohne Actor-Bindung: Das System ruft ihn auf
/// einem eigenen Thread auf; Anfragen gehen an den Main-Actor
/// (`WatchBridge.handle`).
nonisolated final class WatchBridgeSessionDelegate: NSObject, WCSessionDelegate {

    /// Aktivierung abgeschlossen; ein Fehler wird protokolliert.
    ///
    /// - Parameters:
    ///   - session: Sitzung mit der Watch.
    ///   - activationState: Erreichter Zustand (nicht ausgewertet).
    ///   - error: Fehler der Aktivierung, sonst `nil`.
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Log.watch.error("⚠️ Sitzung mit der Watch: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sitzung vorübergehend inaktiv (Wechsel der Watch); nichts zu tun.
    ///
    /// - Parameter session: Sitzung mit der Watch.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Sitzung beendet (Wechsel der Watch) – für die neue Watch neu aktivieren.
    ///
    /// - Parameter session: Beendete Sitzung.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Anfrage der Watch mit Antwort.
    ///
    /// Verarbeitung: Die Anfrage wird am Main-Actor beantwortet
    /// (`WatchBridge.handle`); die Antwortfunktion wird dafür in
    /// `ReplyHandler` verpackt.
    ///
    /// - Parameters:
    ///   - session: Sitzung mit der Watch.
    ///   - messageData: Kodierte Anfrage.
    ///   - replyHandler: Gibt die kodierte Antwort an die Watch zurück.
    func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        let reply = ReplyHandler(replyHandler)
        Task { @MainActor in
            reply.send(await WatchBridge.shared.handle(messageData))
        }
    }

    /// Datei an die Watch übertragen (oder gescheitert): aufräumen.
    ///
    /// - Parameters:
    ///   - session: Sitzung mit der Watch.
    ///   - fileTransfer: Abgeschlossene Übertragung; ihre Datei wird gelöscht.
    ///   - error: Fehler der Übertragung, sonst `nil`.
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        do {
            try FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        } catch {
            Log.watch.debug("⌚️ Übertragene Datei nicht gelöscht: \(error.localizedDescription, privacy: .public)")
        }
        if let error {
            Log.watch.info("⌚️ Datei für die Watch nicht übertragen: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Hält die Antwortfunktion von WatchConnectivity für den Main-Actor.
private nonisolated final class ReplyHandler: @unchecked Sendable {
    /// Antwortfunktion des Systems.
    private let handler: (Data) -> Void

    /// Übernimmt die Antwortfunktion.
    ///
    /// - Parameter handler: Antwortfunktion.
    init(_ handler: @escaping (Data) -> Void) {
        self.handler = handler
    }

    /// Antwortet.
    ///
    /// - Parameter data: Antwort.
    func send(_ data: Data) {
        handler(data)
    }
}

/// Hält die App im Hintergrund wach, solange eine Aufgabe für die Watch läuft.
///
/// `ProcessInfo.performExpiringActivity` hält die App so lange wach, wie der
/// übergebene Block läuft; der Block wartet deshalb auf `end()`. Läuft die
/// Zeit ab, gibt er sofort frei.
nonisolated final class BackgroundGrace: @unchecked Sendable {
    /// Freigabe des wartenden Blocks.
    private let semaphore = DispatchSemaphore(value: 0)

    /// Beginnt die Wachphase.
    ///
    /// - Parameter reason: Grund (für das System).
    /// - Returns: Wachphase; mit `end()` beenden.
    static func begin(reason: String) -> BackgroundGrace {
        let grace = BackgroundGrace()
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
            if expired {
                grace.semaphore.signal()
            } else {
                grace.semaphore.wait()
            }
        }
        return grace
    }

    /// Beendet die Wachphase.
    func end() {
        semaphore.signal()
    }
}
#endif
