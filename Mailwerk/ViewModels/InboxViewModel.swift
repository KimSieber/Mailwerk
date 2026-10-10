//
//  InboxViewModel.swift
//  Mailwerk
//
//  Zweck: Zustand und Abläufe der Nachrichtenliste – welche Ansicht
//  gewählt ist (alle Posteingänge, Gekennzeichnet, ein Ordner), welche
//  Mails sie aus dem Cache zeigt, Abruf vom Server, „Ältere laden“,
//  Spamfilter beim Abruf und Rückfragen zum Anlegen eines Spam-Ordners.
//  Dazu die Wischaktionen der Liste (gelesen, kennzeichnen) samt
//  „Rückgängig“ und der einzige Meldungskanal der Liste (`alert`).
//
//  Ablauf: Die Liste wird immer zuerst aus dem lokalen Cache gezeigt
//  (`loadFromCache`), der Abruf vom Server läuft danach und aktualisiert
//  die Liste schrittweise. Ohne Netz bleibt es beim Cache; der Zustand
//  wird still im Titel angezeigt.
//
//  Abrufe (Posteingänge, Ordner, „Ältere laden“) laufen über den
//  `FetchCoordinator` nacheinander und ohne Doppelungen. Gleichzeitige
//  Abrufe würden denselben Ordner über zwei Verbindungen bearbeiten und
//  sich den Sync-Zustand gegenseitig überschreiben.
//
//  Die Liste hält nur Listeneinträge (`MessageListItem`) ohne Mailinhalt;
//  die vollständige Nachricht wird erst beim Öffnen geladen.
//
//  Messung: In Debug-Builds gibt `loadFromCache` Laufzeit, Anzahl der
//  Mails und Menge der geladenen Vorschautexte aus (`⏱ …`), außerdem wie
//  viele Datenbankabfragen die Ansicht seit der letzten Liste ausgelöst
//  hat. Grundlage für die Performance-Arbeiten in v0.1.9c.
//
//  Abgrenzung: Darstellung in InboxView, Abruf im MailFetchService,
//  Ablage im MessageStore.
//
//  Abhängigkeiten: AccountStore, SpamSettings, SpamFilterService,
//  MailFetchService, MailSession (Zugangsdaten), MessageActions,
//  MessageStore,
//  NetworkMonitor, SyncWindow, FetchCoordinator.
//

import Foundation
import Observation

/// Zustand und Abläufe der Nachrichtenliste.
@Observable
final class InboxViewModel {
    /// Quelle für Postfächer und Passwörter.
    private let accountStore: AccountStore
    /// Einstellungen des Spamfilters (an/aus, Schwelle).
    private let spamSettings: SpamSettings
    /// Wird auch von der Detailansicht für Blockieren und Vertrauen genutzt.
    let spamFilter: SpamFilterService

    /// Listeneinträge der aktuellen Ansicht (ohne Mailinhalt), absteigend nach Datum.
    var messages: [MessageListItem] = []
    /// `true`, solange ein Abruf vom Server läuft.
    var isLoading = false
    /// Meldung für die Anzeige (Abruf- und Aktionsfehler); `nil` = keine.
    /// Einziger Meldungskanal der Liste.
    var alert: AlertItem?
    /// Mails, für die gerade eine Wischaktion läuft (Zeile gesperrt).
    var processingMessageIDs: Set<String> = []
    /// Zeitgeber, der den „Rückgängig“-Hinweis nach 5 Sekunden ausblendet.
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    /// Stand der aktuellen Ansicht laut Datenbank (Tabelle folder_sync).
    /// Überlebt Neustarts und ist auch offline bekannt. `nil` nur, wenn
    /// kein Postfach eingerichtet ist.
    var syncState: SyncState?
    /// `true`, wenn der letzte Abrufversuch dieser Ansicht an der
    /// Verbindung scheiterte. Wird still im Titel angezeigt, nicht als Alert.
    var connectionFailed = false

    /// Läuft gerade „Ältere Nachrichten laden"?
    var isLoadingOlder = false
    /// Letzter Nachladeversuch scheiterte an der Verbindung – die Zeile
    /// zeigt das selbst an, bis zum nächsten Versuch oder Ansichtswechsel.
    var olderConnectionFailed = false
    /// Ordner, für die der Server nichts Älteres mehr hat. Nur für diese
    /// Sitzung – nach einem Neustart stellt ein Tipp das erneut fest.
    private var exhaustedFolders: Set<String> = []

    /// Netzzustand (online/offline).
    private let network = NetworkMonitor.shared

    /// Stimmt die Abrufe ab: nacheinander, ohne Doppelungen; bei mehreren
    /// wartenden Ordnern zählt nur der zuletzt gewählte.
    private let fetches = FetchCoordinator<FetchRequest>(
        supersedes: FetchRequest.supersedes
    )

    #if DEBUG
    /// Messung: Anzahl der Aufrufe von `loadFromCache` in dieser Sitzung.
    /// Nicht beobachtet, damit das Zählen keine Neuzeichnung auslöst.
    @ObservationIgnored private var cacheLoadCount = 0
    /// Messung: Datenbankabfragen, die die Ansicht über berechnete Werte
    /// seit der letzten Liste ausgelöst hat. Nicht beobachtet, weil sie
    /// während der Darstellung hochgezählt wird.
    @ObservationIgnored private var viewQueryCount = 0
    #endif

    /// Aktive Ansicht. Ändert sich durch die Seitenleiste.
    var selection: MailboxSelection = .allInboxes {
        didSet {
            // Der Verbindungsstatus gilt für die bisherige Ansicht; die neue
            // ermittelt ihn bei ihrem eigenen Abruf.
            connectionFailed = false
            olderConnectionFailed = false
            loadFromCache()
        }
    }

    /// Nachricht, deren Kennzeichen gerade entfernt wurde – zeigt den
    /// „Rückgängig"-Hinweis in der Kennzeichen-Sicht.
    var undoUnflag: UndoUnflag?

    /// Angaben, um ein entferntes Kennzeichen wiederherzustellen.
    struct UndoUnflag: Identifiable {
        /// Kennung für SwiftUI (Cache-ID der Mail).
        var id: String { target.id }
        /// Betroffene Mail.
        let target: MessageActions.Target
    }

    /// Ein Postfach ohne Spam-Ordner samt Vorschlag. Angelegt wird nur nach
    /// Bestätigung durch den Nutzer.
    struct PendingSpamFolder: Identifiable {
        /// Kennung für SwiftUI (ID des Postfachs).
        var id: UUID { account.id }
        /// Postfach ohne Spam-Ordner.
        let account: MailAccount
        /// Vorgeschlagener Ordnername.
        let proposal: String
    }

    /// Offene Rückfragen zum Anlegen eines Spam-Ordners. Bleiben bestehen,
    /// bis sie beantwortet sind – auch über weitere Abrufe hinweg.
    var pendingSpamFolders: [PendingSpamFolder] = []

    /// Postfächer, für die in dieser Sitzung abgelehnt wurde. Verhindert,
    /// dass bei jedem Abruf erneut gefragt wird.
    private var declinedSpamFolders: Set<UUID> = []

    /// Legt das ViewModel an und zeigt sofort den Cache.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Passwörter.
    ///   - filterLists: Black-/Whitelist für den Spamfilter.
    ///   - spamSettings: Einstellungen des Spamfilters.
    init(
        accountStore: AccountStore,
        filterLists: any FilterListRepository,
        spamSettings: SpamSettings
    ) {
        self.accountStore = accountStore
        self.spamSettings = spamSettings
        self.spamFilter = SpamFilterService(
            accountStore: accountStore,
            filterLists: filterLists
        )
        loadFromCache()
    }

    /// Lädt die Mails der aktuellen Ansicht aus dem lokalen Cache.
    ///
    /// Verarbeitung: Ermittelt den Stand der Ansicht und liest je nach
    /// Auswahl alle Posteingänge, die gekennzeichneten Mails oder einen
    /// Ordner – als Listeneinträge ohne Mailinhalt. In Debug-Builds werden
    /// Laufzeit, Anzahl, Menge der Vorschautexte und die zwischenzeitlichen
    /// Abfragen der Ansicht ausgegeben.
    func loadFromCache() {
        #if DEBUG
        let started = Date()
        #endif
        let accountIDs = accountStore.accounts.map(\.id)
        syncState = currentSyncState()
        switch selection {
        case .allInboxes:
            messages = MessageStore.shared.allMessages(
                accountIDs: accountIDs, folder: MailFetchService.inboxFolder
            )
        case .flagged:
            messages = MessageStore.shared.flaggedInboxMessages(
                accountIDs: accountIDs
            )
        case .folder(let accountID, let path, _):
            messages = MessageStore.shared.folderMessages(
                accountID: accountID, folder: path
            )
        }
        #if DEBUG
        reportCacheLoad(startedAt: started)
        #endif
    }

    #if DEBUG
    /// Messung: gibt die Kennzahlen eines Ladevorgangs aus.
    ///
    /// Verarbeitung: Die Laufzeit wird vor dem Zählen der Textmenge
    /// genommen, damit das Zählen sie nicht verfälscht. Gezählt wird, was
    /// die Liste tatsächlich im Speicher hält: die Vorschautexte.
    ///
    /// - Parameter startedAt: Beginn des Ladevorgangs.
    private func reportCacheLoad(startedAt: Date) {
        let millis = Int(Date().timeIntervalSince(startedAt) * 1000)
        cacheLoadCount += 1
        let textBytes = messages.reduce(0) { $0 + ($1.preview?.utf8.count ?? 0) }
        print("⏱ Liste aus Cache #\(cacheLoadCount): \(messages.count) Mails, \(millis) ms, Vorschautexte \(textBytes / 1024) KB, Ansichtsabfragen seither: \(viewQueryCount)")
        viewQueryCount = 0
    }
    #endif

    /// Stand der gewählten Ansicht.
    ///
    /// Verarbeitung: Sammelansichten sind so aktuell wie der älteste
    /// beteiligte Posteingang.
    ///
    /// - Returns: Stand oder `nil`, wenn kein Postfach eingerichtet ist.
    private func currentSyncState() -> SyncState? {
        let accounts = accountStore.accounts
        guard !accounts.isEmpty else { return nil }
        switch selection {
        case .allInboxes, .flagged:
            return .oldest(accounts.map {
                MessageStore.shared.lastSync(accountID: $0.id, folder: MailFetchService.inboxFolder)
            })
        case .folder(let accountID, let path, _):
            return .oldest([MessageStore.shared.lastSync(accountID: accountID, folder: path)])
        }
    }

    // MARK: - Ältere Nachrichten

    /// Ordner, deren Fenster die aktuelle Ansicht bilden: bei einem Ordner
    /// dieser allein, bei „Alle Eingänge" die Posteingänge aller Postfächer.
    /// Die Kennzeichen-Sicht lädt nicht nach.
    private var olderTargets: [(account: MailAccount, folder: String)] {
        switch selection {
        case .allInboxes:
            return accountStore.accounts.map { ($0, MailFetchService.inboxFolder) }
        case .flagged:
            return []
        case .folder(let accountID, let path, _):
            guard let account = accountStore.accounts.first(where: { $0.id == accountID }) else { return [] }
            return [(account, path)]
        }
    }

    /// Schlüssel für die Menge der ausgeschöpften Ordner.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Zusammengesetzter Schlüssel.
    private func exhaustedKey(_ accountID: UUID, _ folder: String) -> String {
        "\(accountID.uuidString)|\(folder)"
    }

    /// Ordner der Ansicht, für die es noch Älteres geben kann.
    private var openOlderTargets: [(account: MailAccount, folder: String)] {
        olderTargets.filter { !exhaustedFolders.contains(exhaustedKey($0.account.id, $0.folder)) }
    }

    /// Zeile „Ältere Nachrichten laden" anzeigen? Nicht in der
    /// Kennzeichen-Sicht und nicht ohne Postfächer.
    var showsOlderRow: Bool { !olderTargets.isEmpty }

    /// `true`, wenn der Server für alle Ordner der Ansicht nichts Älteres hat.
    var olderExhausted: Bool { showsOlderRow && openOlderTargets.isEmpty }

    /// Bis zu welchem Tag ein Tipp mindestens lädt – für die Beschriftung.
    /// Bei mehreren Postfächern der späteste der nächsten Zeiträume.
    var nextOlderDate: Date? {
        let standard = SyncWindow.standardStart(now: Date(), days: MailFetchService.syncDays)
        #if DEBUG
        viewQueryCount += openOlderTargets.count
        #endif
        return openOlderTargets
            .map { target -> Date in
                let start = MessageStore.shared.windowStart(accountID: target.account.id, folder: target.folder)
                    ?? standard
                return SyncWindow.nextBlock(before: start, days: MailFetchService.syncDays).since
            }
            .max()
    }

    /// Lädt für die aktuelle Ansicht den nächsten älteren Zeitraum nach.
    ///
    /// Verarbeitung: Die Ordner der Ansicht werden beim Tippen festgehalten,
    /// damit ein späterer Ansichtswechsel nicht den falschen Ordner
    /// nachladen lässt. Die Zeile zeigt sofort „wird geladen“, auch wenn
    /// der Abruf noch auf einen laufenden wartet. Ausgeführt wird über den
    /// `FetchCoordinator`, also nie gleichzeitig mit einem anderen Abruf.
    @MainActor
    func loadOlder() async {
        guard !isLoadingOlder else { return }
        guard network.isOnline else {
            connectionFailed = true
            olderConnectionFailed = true
            return
        }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        olderConnectionFailed = false

        let targets = openOlderTargets
        let request = FetchRequest.older(
            targets: targets.map { exhaustedKey($0.account.id, $0.folder) }
        )
        await coordinated(request, label: "Ältere laden") {
            await self.performLoadOlder(targets)
        }
    }

    /// Lädt für die festgehaltenen Ordner den nächsten älteren Zeitraum.
    ///
    /// Verarbeitung: Ruft je Ordner `MailFetchService.fetchOlder` auf.
    /// Ordner ohne Älteres werden für diese Sitzung vermerkt. Konnten Mails
    /// eines Zeitraums nicht geladen werden, erscheint ein Hinweis; der
    /// Zeitraum wird beim nächsten Tipp erneut versucht. Verbindungsfehler
    /// werden still in der Zeile angezeigt, andere Fehler gesammelt gemeldet.
    ///
    /// - Parameter targets: Ordner der Ansicht zum Zeitpunkt des Tippens.
    @MainActor
    private func performLoadOlder(_ targets: [(account: MailAccount, folder: String)]) async {
        var errors: [String] = []
        for target in targets {
            let key = exhaustedKey(target.account.id, target.folder)
            do {
                let credentials = try accountStore.credentials(for: target.account)
                let result = try await MailFetchService.fetchOlder(
                    credentials, folder: target.folder
                )
                switch result {
                case .noOlder:
                    exhaustedFolders.insert(key)
                case .loaded(let count, let failed, _, let hasMore):
                    print("📬 [\(target.account.displayName)/\(target.folder)] \(count) ältere Nachrichten geladen, \(failed) fehlgeschlagen")
                    if failed > 0 {
                        // Fensterbeginn ist stehen geblieben; erneutes Tippen
                        // versucht denselben Zeitraum noch einmal.
                        errors.append("\(target.account.displayName): \(failed) ältere Nachrichten konnten nicht geladen werden. Bitte „Ältere laden“ erneut tippen.")
                    } else if !hasMore {
                        exhaustedFolders.insert(key)
                    }
                }
            } catch {
                if let message = classify(error, context: target.account.displayName) {
                    errors.append(message)
                } else {
                    olderConnectionFailed = true
                }
                if !network.isOnline { break }
            }
            loadFromCache()
        }
        loadFromCache()
        if !errors.isEmpty {
            alert = AlertItem(title: "Ältere Nachrichten", message: errors.joined(separator: "\n"))
        }
    }

    /// Ordnet einen Abruffehler ein.
    ///
    /// Verarbeitung: Verbindungsfehler werden still vermerkt
    /// (`connectionFailed`), alle anderen als Meldungstext zurückgegeben.
    ///
    /// - Parameters:
    ///   - error: Aufgetretener Fehler.
    ///   - context: Bezeichnung für die Meldung (z. B. Postfachname).
    /// - Returns: Meldungstext oder `nil` bei einem Verbindungsfehler.
    private func classify(_ error: Error, context: String) -> String? {
        if MailFetchService.isConnectionError(error) || !network.isOnline {
            connectionFailed = true
            print("📴 \(context): keine Verbindung (\(error.localizedDescription))")
            return nil
        }
        return "\(context): \(error.localizedDescription)"
    }

    /// Anzahl gekennzeichneter Mails in den Posteingängen (für die Leiste).
    var flaggedCount: Int {
        #if DEBUG
        viewQueryCount += 1
        #endif
        return MessageStore.shared.flaggedInboxCount(
            accountIDs: accountStore.accounts.map(\.id)
        )
    }

    /// Legt den vorgeschlagenen Spam-Ordner an.
    ///
    /// Verarbeitung: Beim nächsten Abruf wird das Postfach dann
    /// mitgefiltert. Die Rückfrage wird in jedem Fall entfernt.
    ///
    /// - Parameter pending: Rückfrage mit Postfach und Vorschlag.
    @MainActor
    func createSpamFolder(for pending: PendingSpamFolder) async {
        do {
            let created = try await spamFilter.createSpamFolder(
                pending.proposal, for: pending.account
            )
            print("📁 [\(pending.account.displayName)] Spam-Ordner \(created) angelegt")
        } catch {
            alert = AlertItem(
                title: "Spam-Ordner nicht angelegt",
                message: "\(pending.account.displayName): \(error.localizedDescription)"
            )
        }
        dismissSpamFolderRequest(pending, declineForSession: false)
    }

    /// Entfernt eine Rückfrage aus der Warteschlange.
    ///
    /// - Parameters:
    ///   - pending: Zu entfernende Rückfrage.
    ///   - declineForSession: `true` = in dieser Sitzung nicht erneut fragen.
    func dismissSpamFolderRequest(_ pending: PendingSpamFolder, declineForSession: Bool) {
        if declineForSession {
            declinedSpamFolders.insert(pending.account.id)
        }
        pendingSpamFolders.removeAll { $0.id == pending.id }
    }

    /// Ruft einen einzelnen Ordner ab (beim Antippen in der Leiste).
    ///
    /// Verarbeitung: Ausgeführt über den `FetchCoordinator`. Werden mehrere
    /// Ordner angetippt, während noch ein Abruf läuft, wird nur der zuletzt
    /// gewählte abgerufen.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - path: IMAP-Ordner.
    @MainActor
    func refreshFolder(accountID: UUID, path: String) async {
        await coordinated(.folder(accountID: accountID, path: path), label: "Ordner \(path)") {
            await self.performRefreshFolder(accountID: accountID, path: path)
        }
    }

    /// Ruft einen einzelnen Ordner vom Server ab.
    ///
    /// Verarbeitung: Ohne Netz bleibt es beim Cache; sonst wird der Ordner
    /// vom Server geholt und die Liste danach aus dem Cache neu geladen.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - path: IMAP-Ordner.
    @MainActor
    private func performRefreshFolder(accountID: UUID, path: String) async {
        guard let account = accountStore.accounts.first(where: { $0.id == accountID }) else { return }
        let credentials: MailCredentials
        do {
            credentials = try accountStore.credentials(for: account)
        } catch {
            alert = AlertItem(title: "Fehler beim Abrufen", message: "\(account.displayName): \(error.localizedDescription)")
            return
        }

        // Ohne Netz gar nicht erst versuchen: Cache zeigen, still vermerken.
        guard network.isOnline else {
            connectionFailed = true
            loadFromCache()
            return
        }

        isLoading = true
        defer { isLoading = false }

        connectionFailed = false
        do {
            try await MailFetchService.refreshAndCache(credentials, folder: path)
        } catch {
            if let message = classify(error, context: account.displayName) {
                alert = AlertItem(title: "Fehler beim Abrufen", message: message)
            }
        }
        loadFromCache()
    }

    /// Ruft alle Posteingänge ab (Start, Pull-to-Refresh).
    ///
    /// Verarbeitung: Ausgeführt über den `FetchCoordinator`. Läuft der
    /// Abruf schon, wird auf ihn gewartet statt ein zweites Mal abzurufen.
    @MainActor
    func refresh() async {
        await coordinated(.inboxes, label: "Posteingänge") {
            await self.performRefresh()
        }
    }

    /// Führt einen Abruf über den `FetchCoordinator` aus und protokolliert,
    /// was mit ihm geschah (Konsole, zur Kontrolle doppelter Abrufe).
    ///
    /// - Parameters:
    ///   - request: Art des Abrufs.
    ///   - label: Bezeichnung für die Konsole.
    ///   - operation: Eigentlicher Abruf.
    @MainActor
    private func coordinated(
        _ request: FetchRequest,
        label: String,
        operation: @escaping @MainActor () async -> Void
    ) async {
        if fetches.isScheduled(request) {
            print("🔁 Abruf \(label) läuft bereits – angeschlossen")
        } else if fetches.isBusy {
            print("⏳ Abruf \(label) wartet auf laufenden Abruf")
        }
        let outcome = await fetches.run(request, operation: operation)
        if outcome == .superseded {
            print("⏭ Abruf \(label) übersprungen – neuerer Ordner gewählt")
        }
    }

    /// Ruft alle Posteingänge vom Server ab.
    ///
    /// Verarbeitung: Ruft die Postfächer nacheinander ab
    /// (`refreshAccount`) und lädt die Liste nach jedem Postfach neu, damit
    /// sie schrittweise wächst. Kommen während des Abrufs Postfächer hinzu,
    /// werden sie in derselben Runde mit abgerufen – so geht keines
    /// verloren, wenn sich ein neuer Abruf diesem anschließt. Geht das Netz
    /// verloren, bricht die Runde ab, statt die übrigen Postfächer einzeln in
    /// Zeitüberschreitungen laufen zu lassen. Ein gewählter Ordner wird hier
    /// nicht abgerufen – das übernimmt `refreshFolder`.
    @MainActor
    private func performRefresh() async {
        // Ohne Netz gar nicht erst versuchen: Cache zeigen, still vermerken.
        guard network.isOnline else {
            connectionFailed = true
            loadFromCache()
            print("📴 Refresh übersprungen: kein Netz")
            return
        }

        isLoading = true
        defer { isLoading = false }
        connectionFailed = false

        print("🔄 Refresh gestartet für \(accountStore.accounts.count) Konten")

        var errors: [String] = []
        var processed: Set<UUID> = []
        while let account = accountStore.accounts.first(where: { !processed.contains($0.id) }) {
            processed.insert(account.id)
            errors += await refreshAccount(account)
            loadFromCache()

            if !network.isOnline {
                connectionFailed = true
                print("📴 Refresh abgebrochen: Netz verloren")
                break
            }
        }

        if !errors.isEmpty {
            alert = AlertItem(title: "Fehler beim Abrufen", message: errors.joined(separator: "\n"))
        }
        print("🔄 Refresh fertig. Fehler: \(errors.count), Nachrichten gesamt: \(messages.count)")
    }

    /// Ruft ein Postfach ab: Spamfilter, Posteingang, Spam-Ordner.
    ///
    /// Verarbeitung: Erst filtern, dann abrufen – so landet erkannter Spam
    /// gar nicht erst im Posteingang. Ein Fehler des Filters verhindert den
    /// Abruf nicht. Scheitert der Posteingang, entfällt der Spam-Ordner,
    /// denn dann liegt meist die Verbindung danieder.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Meldungstexte der aufgetretenen Fehler (Verbindungsfehler
    ///   werden still vermerkt und erscheinen hier nicht).
    @MainActor
    private func refreshAccount(_ account: MailAccount) async -> [String] {
        print("🔄 Starte Abruf: \(account.displayName) (ID: \(account.id.uuidString))")
        let credentials: MailCredentials
        do {
            credentials = try accountStore.credentials(for: account)
        } catch {
            print("❌ \(account.displayName): \(error.localizedDescription)")
            return [classify(error, context: account.displayName)].compactMap { $0 }
        }

        var errors: [String] = []
        if let message = await runSpamFilter(for: account) {
            errors.append(message)
        }

        do {
            try await MailFetchService.refreshAndCache(credentials)
        } catch {
            print("❌ \(account.displayName): \(error.localizedDescription)")
            if let message = classify(error, context: account.displayName) {
                errors.append(message)
            }
            return errors
        }

        await refreshSpamFolder(of: account.id, credentials: credentials)
        print("✅ \(account.displayName): Abruf abgeschlossen")
        return errors
    }

    /// Führt den Spamfilter für ein Postfach aus, sofern er eingeschaltet ist.
    ///
    /// Verarbeitung: Fehlt dem Postfach ein Spam-Ordner, wird eine Rückfrage
    /// eingereiht – höchstens eine je Postfach, und nicht, wenn sie in
    /// dieser Sitzung abgelehnt wurde. Offene Rückfragen bleiben über
    /// weitere Abrufe hinweg bestehen; hat das Postfach inzwischen einen
    /// Spam-Ordner, entfällt seine Rückfrage.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Meldungstext bei einem Fehler, sonst `nil`.
    @MainActor
    private func runSpamFilter(for account: MailAccount) async -> String? {
        guard spamSettings.isEnabled else { return nil }
        do {
            let outcome = try await spamFilter.run(
                for: account, scoreLimit: spamSettings.scoreLimit
            )
            if case .needsSpamFolder(let proposal) = outcome {
                let alreadyAsked = pendingSpamFolders.contains { $0.id == account.id }
                if !alreadyAsked, !declinedSpamFolders.contains(account.id) {
                    pendingSpamFolders.append(
                        PendingSpamFolder(account: account, proposal: proposal)
                    )
                }
            } else {
                pendingSpamFolders.removeAll { $0.id == account.id }
            }
            return nil
        } catch {
            print("⚠️ \(account.displayName): Spamfilter fehlgeschlagen: \(error.localizedDescription)")
            return classify(error, context: "\(account.displayName): Spamfilter")
        }
    }

    /// Ruft den Spam-Ordner eines Postfachs mit ab – dort wird am meisten
    /// gearbeitet.
    ///
    /// Verarbeitung: Der Spam-Ordner wird frisch aus dem Postfach gelesen,
    /// weil der Spamfilter ihn eben erst gefunden und gemerkt haben kann.
    /// Fehler werden nur protokolliert; der Posteingang ist dann bereits
    /// aktuell.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - credentials: Zugangsdaten des Postfachs.
    @MainActor
    private func refreshSpamFolder(of accountID: UUID, credentials: MailCredentials) async {
        guard let account = accountStore.accounts.first(where: { $0.id == accountID }),
              let spamFolder = account.spamFolder, !spamFolder.isEmpty else { return }
        do {
            try await MailFetchService.refreshAndCache(credentials, folder: spamFolder)
            print("📬 [\(account.displayName)] Spam-Ordner \(spamFolder) abgerufen")
        } catch {
            print("⚠️ [\(account.displayName)] Spam-Abruf fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: - Aktionen an Mails (Wischaktionen)

    /// Schaltet gelesen/ungelesen um.
    ///
    /// Verarbeitung: Server und Cache über `MessageActions`, danach die
    /// Liste neu laden. Während der Aktion ist die Zeile gesperrt.
    ///
    /// - Parameter item: Betroffener Listeneintrag.
    @MainActor
    func toggleRead(_ item: MessageListItem) async {
        processingMessageIDs.insert(item.id)
        defer { processingMessageIDs.remove(item.id) }
        do {
            try await MessageActions.setRead(
                item.isUnread, for: MessageActions.Target(item), accountStore: accountStore
            )
            loadFromCache()
        } catch {
            alert = .failure("Status ändern fehlgeschlagen", error)
        }
    }

    /// Schaltet die Kennzeichnung um.
    ///
    /// Verarbeitung: Server und Cache über `MessageActions`. In der Ansicht
    /// „Gekennzeichnet“ erscheint nach dem Entfernen 5 Sekunden lang ein
    /// „Rückgängig“-Hinweis.
    ///
    /// - Parameter item: Betroffener Listeneintrag.
    @MainActor
    func toggleFlag(_ item: MessageListItem) async {
        processingMessageIDs.insert(item.id)
        defer { processingMessageIDs.remove(item.id) }
        let target = MessageActions.Target(item)
        let newFlagged = !item.isFlagged
        do {
            try await MessageActions.setFlagged(newFlagged, for: target, accountStore: accountStore)
            if selection == .flagged && !newFlagged {
                offerUndoUnflag(for: target)
            }
            loadFromCache()
        } catch {
            alert = .failure("Kennzeichnen fehlgeschlagen", error)
        }
    }

    /// Zeigt den „Rückgängig“-Hinweis und blendet ihn nach 5 Sekunden aus.
    ///
    /// - Parameter target: Mail, deren Kennzeichnung entfernt wurde.
    @MainActor
    private func offerUndoUnflag(for target: MessageActions.Target) {
        undoTask?.cancel()
        undoUnflag = UndoUnflag(target: target)
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undoUnflag = nil
        }
    }

    /// Blendet den „Rückgängig“-Hinweis aus, ohne etwas zu ändern.
    @MainActor
    func dismissUndoUnflag() {
        undoTask?.cancel()
        undoUnflag = nil
    }

    /// Stellt eine eben entfernte Kennzeichnung wieder her.
    ///
    /// - Parameter undo: Angaben zur betroffenen Mail.
    @MainActor
    func undo(_ undo: UndoUnflag) async {
        dismissUndoUnflag()
        do {
            try await MessageActions.setFlagged(true, for: undo.target, accountStore: accountStore)
            loadFromCache()
        } catch {
            alert = .failure("Rückgängig fehlgeschlagen", error)
        }
    }
}
