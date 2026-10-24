//
//  WatchConnector.swift
//  MailwerkWatch
//
//  Zweck: Austausch der Watch mit dem iPhone (WatchConnectivity). Die Watch
//  spricht nie selbst mit den Mailservern; sie bittet das iPhone darum.
//
//  Aktualisieren (beim Öffnen, „Aktualisieren“, Herunterziehen):
//  1. Anfrage `sync` mit allen offenen Aktionen und Abrufwunsch. Die
//     Antwort ist der Stand aus dem Cache des iPhones und wird sofort
//     übernommen.
//  2. Fehlende Inhalte und Absenderbilder werden in kleinen Gruppen
//     nachgeholt, neueste Mails zuerst.
//  3. Hat das iPhone die Aktionen ausgeführt und abgerufen, schickt es den
//     neuen Stand von sich aus (`receivePush`); danach folgen wieder die
//     fehlenden Inhalte.
//  Nach einer einzelnen Aktion (gelesen, Kennzeichen, Spam) geht nur die
//  Aktion hinaus, ohne Abruf.
//
//  Ist das iPhone nicht erreichbar, bleibt alles auf der Watch; die
//  Aktionen kommen mit der nächsten Aktualisierung mit.
//
//  Hintergrund: Ruft die iPhone-App selbst ab, schickt sie den Stand als
//  Datei; watchOS weckt die Watch-App dafür kurz
//  (`WKWatchConnectivityRefreshBackgroundTask`). Die Aufgabe wird erst
//  abgeschlossen, wenn nichts mehr aussteht.
//
//  Abgrenzung: Gegenstück auf dem iPhone → WatchBridge; Speicher →
//  WatchStore; Übertragungsform → WatchTransfer, WatchWire.
//
//  Abhängigkeiten: Foundation, WatchConnectivity, WatchKit, WatchStore,
//  WatchTransfer, WatchWire, Log.
//

import Foundation
import WatchConnectivity
import WatchKit
import os

/// Austausch der Watch mit dem iPhone.
final class WatchConnector {
    /// Gemeinsame Instanz der App.
    static let shared = WatchConnector()

    /// Mails, deren Inhalt in einer Anfrage geholt werden.
    static let bodiesPerRequest = 6
    /// Absenderbilder je Anfrage.
    static let imagesPerRequest = 20
    /// Längste Wartezeit auf den neuen Stand nach einer Aktualisierung.
    static let pushTimeout: Duration = .seconds(60)

    /// Sitzung mit dem iPhone; `nil`, bis `start` lief.
    private var session: WCSession?
    /// Empfänger der Ereignisse der Sitzung (die Sitzung hält ihn nur schwach).
    private let sessionDelegate = WatchConnectorSessionDelegate()
    /// `true`, solange eine Aktualisierung läuft.
    private var isSyncing = false
    /// `true`, solange fehlende Inhalte geholt werden.
    private var isFetchingContent = false
    /// Wartet auf den neuen Stand nach einer Aktualisierung.
    private var pushTimeoutTask: Task<Void, Never>?
    /// Hintergrundaufgaben, die auf Daten des iPhones warten.
    private var heldTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    /// Speicher der App.
    private let store = WatchStore.shared

    /// Nur die gemeinsame Instanz.
    private init() {}

    // MARK: - Start

    /// Richtet die Sitzung ein. Aufruf einmal beim Start der App.
    func start() {
        guard session == nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = sessionDelegate
        session.activate()
        self.session = session
    }

    // MARK: - Aktualisieren

    /// Übergibt offene Aktionen und lässt alle Posteingänge abrufen.
    ///
    /// Verarbeitung: Ohne erreichbares iPhone wird nur der Zustand vermerkt.
    /// Läuft schon eine Aktualisierung, geschieht nichts.
    func refresh() async {
        await sync(refresh: true)
    }

    /// Übergibt offene Aktionen ohne Abruf (nach einer Aktion).
    func sendPending() {
        guard !store.pending.isEmpty else { return }
        Task { await sync(refresh: false) }
    }

    /// Fragt das iPhone nach dem Stand und übergibt die offenen Aktionen.
    ///
    /// - Parameter refresh: `true` = das iPhone ruft alle Posteingänge ab.
    private func sync(refresh: Bool) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        guard let session = await activeSession() else {
            store.status = .unreachable
            return
        }
        guard session.isCompanionAppInstalled else {
            store.status = .companionMissing
            return
        }
        guard session.isReachable else {
            store.status = .unreachable
            return
        }
        store.status = .syncing
        do {
            let payload = try await request(.sync(actions: store.pending, refresh: refresh), on: session)
            store.receive(payload)
            waitForPush()
            await fetchMissingContent()
        } catch {
            Log.watch.error("⚠️ Aktualisierung gescheitert: \(error.localizedDescription, privacy: .public)")
            store.status = .unreachable
        }
    }

    /// Wartet auf den neuen Stand des iPhones; bleibt er aus, gilt die
    /// Aktualisierung nach `pushTimeout` als beendet (der Stand aus dem
    /// Cache bleibt).
    private func waitForPush() {
        pushTimeoutTask?.cancel()
        pushTimeoutTask = Task {
            try? await Task.sleep(for: Self.pushTimeout)
            guard !Task.isCancelled, store.status == .syncing else { return }
            store.status = .idle
        }
    }

    /// Holt fehlende Inhalte und Absenderbilder, neueste Mails zuerst.
    ///
    /// Verarbeitung: In Gruppen; Mails, die das iPhone nicht mehr kennt,
    /// bleiben ohne Inhalt, bis die nächste Lieferung sie entfernt.
    private func fetchMissingContent() async {
        guard !isFetchingContent, let session else { return }
        isFetchingContent = true
        defer { isFetchingContent = false }
        var asked: Set<String> = []
        while session.isReachable {
            let bodies = store.missingBodyIDs.filter { !asked.contains($0) }.prefix(Self.bodiesPerRequest)
            let images = store.missingImageKeys.filter { !asked.contains($0) }.prefix(Self.imagesPerRequest)
            guard !bodies.isEmpty || !images.isEmpty else { break }
            asked.formUnion(bodies)
            asked.formUnion(images)
            do {
                let payload = try await request(.content(mailIDs: Array(bodies), imageKeys: Array(images)), on: session)
                store.receive(payload)
            } catch {
                Log.watch.error("⚠️ Inhalte nicht geholt: \(error.localizedDescription, privacy: .public)")
                break
            }
        }
    }

    /// Holt den Inhalt einer einzelnen Mail sofort (geöffnete Mail).
    ///
    /// - Parameter id: Cache-ID.
    func fetchBody(_ id: String) async {
        guard let session = await activeSession(), session.isReachable else { return }
        do {
            let keys = store.mail(id: id)?.avatarKey.map { [$0] } ?? []
            store.receive(try await request(.content(mailIDs: [id], imageKeys: keys), on: session))
        } catch {
            Log.watch.error("⚠️ Inhalt nicht geholt: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Lieferungen des iPhones

    /// Nimmt den Stand an, den das iPhone von sich aus schickt.
    ///
    /// - Parameter data: Kodiertes erstes Stück der Lieferung.
    fileprivate func receivePush(_ data: Data) async {
        guard let session, let chunk = try? WatchWire.decode(WatchChunk.self, from: data) else { return }
        do {
            store.receive(try await assemble(chunk, on: session))
            pushTimeoutTask?.cancel()
            if store.status == .syncing { store.status = .idle }
            await fetchMissingContent()
        } catch {
            Log.watch.error("⚠️ Stand des iPhones nicht gelesen: \(error.localizedDescription, privacy: .public)")
        }
        completeHeldTasksIfIdle()
    }

    /// Nimmt eine Datei des iPhones an (Stand samt Inhalten).
    ///
    /// - Parameter blob: Inhalt der Datei.
    fileprivate func receiveFile(_ blob: Data) {
        do {
            store.receive(try WatchWire.unpack(blob))
        } catch {
            Log.watch.error("⚠️ Datei des iPhones nicht lesbar: \(error.localizedDescription, privacy: .public)")
        }
        completeHeldTasksIfIdle()
    }

    // MARK: - Hintergrund

    /// Hält eine Hintergrundaufgabe, bis die Daten des iPhones da sind.
    ///
    /// Verarbeitung: Spätestens nach 20 Sekunden wird sie abgeschlossen,
    /// damit watchOS die App nicht wegen einer offenen Aufgabe beendet.
    ///
    /// - Parameter task: Aufgabe von watchOS.
    func hold(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        start()
        heldTasks.append(task)
        completeHeldTasksIfIdle()
        Task {
            try? await Task.sleep(for: .seconds(20))
            completeHeldTasks()
        }
    }

    /// Schließt die gehaltenen Aufgaben ab, wenn nichts mehr aussteht.
    private func completeHeldTasksIfIdle() {
        guard let session, session.activationState == .activated, !session.hasContentPending else { return }
        completeHeldTasks()
    }

    /// Schließt alle gehaltenen Aufgaben ab.
    private func completeHeldTasks() {
        let tasks = heldTasks
        heldTasks = []
        tasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
    }

    /// Aktivierung abgeschlossen.
    fileprivate func didActivate() {
        completeHeldTasksIfIdle()
    }

    // MARK: - Anfragen

    /// Aktive Sitzung; wartet nach dem Start kurz auf die Aktivierung.
    ///
    /// - Returns: Sitzung oder `nil`, wenn sie sich nicht aktivieren ließ.
    private func activeSession() async -> WCSession? {
        start()
        guard let session else { return nil }
        for _ in 0..<30 where session.activationState != .activated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return session.activationState == .activated ? session : nil
    }

    /// Stellt eine Anfrage und setzt die Antwort aus ihren Stücken zusammen.
    ///
    /// - Parameters:
    ///   - request: Anfrage.
    ///   - session: Aktive Sitzung.
    /// - Returns: Lieferung des iPhones.
    /// - Throws: Fehler der Verbindung oder unlesbare Antwort.
    private func request(_ request: WatchRequest, on session: WCSession) async throws -> WatchPayload {
        let reply = try await send(try WatchWire.encode(request), on: session)
        let chunk = try WatchWire.decode(WatchChunk.self, from: reply)
        return try await assemble(chunk, on: session)
    }

    /// Holt die übrigen Stücke einer Lieferung und entpackt sie.
    ///
    /// - Parameters:
    ///   - first: Erstes erhaltenes Stück.
    ///   - session: Aktive Sitzung.
    /// - Returns: Lieferung.
    /// - Throws: Fehler der Verbindung oder unlesbare Daten.
    private func assemble(_ first: WatchChunk, on session: WCSession) async throws -> WatchPayload {
        var assembler = WatchChunkAssembler(first)
        for index in assembler.missing {
            let reply = try await send(try WatchWire.encode(WatchRequest.chunk(token: first.token, index: index)), on: session)
            assembler.add(try WatchWire.decode(WatchChunk.self, from: reply))
        }
        guard let blob = assembler.blob else { throw WatchWireError.undecodable }
        return try WatchWire.unpack(blob)
    }

    /// Schickt Daten an das iPhone und wartet auf die Antwort.
    ///
    /// - Parameters:
    ///   - data: Kodierte Anfrage.
    ///   - session: Aktive Sitzung.
    /// - Returns: Antwort.
    /// - Throws: Fehler von WatchConnectivity.
    private func send(_ data: Data, on session: WCSession) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            session.sendMessageData(
                data,
                replyHandler: { @Sendable reply in continuation.resume(returning: reply) },
                errorHandler: { @Sendable error in continuation.resume(throwing: error) }
            )
        }
    }
}

// MARK: - Ereignisse der Sitzung

/// Empfänger der Ereignisse von WatchConnectivity.
///
/// Bewusst ein eigener Typ ohne Actor-Bindung: Das System ruft ihn auf
/// einem eigenen Thread auf; alles Weitere geschieht auf dem Main-Actor.
nonisolated final class WatchConnectorSessionDelegate: NSObject, WCSessionDelegate {

    /// Aktivierung abgeschlossen.
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Log.watch.error("⚠️ Sitzung mit dem iPhone: \(error.localizedDescription, privacy: .public)")
        }
        Task { @MainActor in WatchConnector.shared.didActivate() }
    }

    /// Erreichbarkeit des iPhones geändert: offene Aktionen gleich nachholen.
    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in WatchConnector.shared.sendPending() }
    }

    /// Stand, den das iPhone von sich aus schickt.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in await WatchConnector.shared.receivePush(messageData) }
    }

    /// Datei des iPhones. Sie ist nur während dieses Aufrufs lesbar und wird
    /// deshalb sofort gelesen.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let blob = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in WatchConnector.shared.receiveFile(blob) }
    }
}
