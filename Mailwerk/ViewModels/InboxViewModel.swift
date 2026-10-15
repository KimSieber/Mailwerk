//
//  InboxViewModel.swift
//  Mailwerk
//
//  Zweck: Zustand und Abläufe der Nachrichtenliste – welche Ansicht
//  gewählt ist (alle Posteingänge, Gekennzeichnet, ein Ordner), welche
//  Mails sie aus dem Cache zeigt, Abruf vom Server, „Ältere laden“,
//  Spamfilter beim Abruf und Rückfragen zum Anlegen eines Spam-Ordners.
//  Dazu die Aktionen an einzelnen Mails aus Wischaktionen und
//  Kontextmenü (gelesen, kennzeichnen, verschieben, löschen, Spam) samt
//  „Rückgängig“ für Kennzeichnung und Gelesen-Status, die Mehrfachauswahl
//  mit Sammelaktionen (kennzeichnen, gelesen, verschieben, löschen) sowie
//  der einzige Meldungskanal der Liste (`alert`).
//
//  Mehrfachauswahl: Die Auswahl hängt an der Cache-ID, nicht an der
//  Position. Mails, die beim Neuladen der Liste verschwinden, fallen aus
//  der Auswahl; ein Wechsel der Ansicht und jede Sammelaktion beenden den
//  Auswahlmodus.
//
//  Suche: Während einer Suche zeigt die Liste nur die Treffer
//  (`searchFilter`, Cache-IDs aus der lokalen Suche). Liste, Auswahl und
//  „Alle auswählen“ arbeiten mit `visibleMessages`.
//
//  Sortierung: Eine vom Standard („Datum, absteigend“) abweichende
//  Sortierung gilt nur für die gezeigte Ansicht. Ein Wechsel der Ansicht
//  setzt sie zurück; gespeichert wird sie nicht. Öffnen einer Mail,
//  Abruf, Aktionen und der Wechsel in andere Apps lassen sie bestehen.
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
//  Absenderbilder: Das ViewModel hält eine Kopie der Filterlisten und
//  beantwortet je Zeile, ob ein Bild gezeigt werden darf
//  (`SpamClassifier.allowsSenderImage`). Die Kopie wird bei jedem Laden
//  der Liste und nach Änderungen an den Listen neu gelesen.
//
//  Messung: In Debug-Builds gibt `loadFromCache` Laufzeit und Anzahl der
//  Mails aus (`⏱ …`), außerdem wie
//  viele Datenbankabfragen die Ansicht seit der letzten Liste ausgelöst
//  hat – Grundlage für Performance-Messungen.
//
//  Abgrenzung: Darstellung in InboxView, Abruf im MailFetchService,
//  Ablage im MessageStore.
//
//  Abhängigkeiten: AccountStore, SpamSettings, SpamFilterService,
//  MailFetchService, MailSession (Zugangsdaten), MessageActions, UndoOffer,
//  MessageActionDialogs, SpamMenuRequest, MessageSelection,
//  MessageStore, MessageSort, NetworkMonitor, SyncWindow, FetchCoordinator,
//  FolderKey, MailFolder, SpamClassifier, FilterAddress, Log.
//

import Foundation
import Observation
import os

/// Zustand und Abläufe der Nachrichtenliste.
@Observable
final class InboxViewModel {
    /// Quelle für Postfächer und Passwörter.
    private let accountStore: AccountStore
    /// Einstellungen des Spamfilters (an/aus, Schwelle).
    private let spamSettings: SpamSettings
    /// Wird auch von der Detailansicht für Blockieren und Vertrauen genutzt.
    let spamFilter: SpamFilterService

    /// Listeneinträge der aktuellen Ansicht (ohne Mailinhalt) in der
    /// gewählten Sortierung (`sort`).
    var messages: [MessageListItem] = [] {
        didSet { updateVisibleMessages() }
    }
    /// Cache-IDs der Suchtreffer; `nil` = keine Suche, alle Mails sichtbar.
    var searchFilter: Set<String>? {
        didSet {
            guard searchFilter != oldValue else { return }
            updateVisibleMessages()
            if let searchFilter, !selectedIDs.isEmpty {
                // Nicht mehr sichtbare Mails fallen aus der Auswahl.
                selectedIDs.formIntersection(searchFilter)
            }
        }
    }
    /// Die in der Liste gezeigten Einträge: alle bzw. während einer Suche
    /// nur die Treffer, in der gewählten Sortierung.
    private(set) var visibleMessages: [MessageListItem] = []
    /// Zählt das Neuladen der Liste aus dem Cache; die Suche läuft daraufhin
    /// erneut (neue oder geänderte Mails).
    private(set) var cacheGeneration = 0
    /// Sortierung der gezeigten Ansicht. Eine Änderung sortiert die Liste
    /// sofort um; ein Wechsel der Ansicht setzt sie auf die Grundstellung.
    var sort = MessageSort.standard {
        didSet {
            guard sort != oldValue else { return }
            messages = sorted(messages)
        }
    }
    /// `true`, wenn die Zeilen der Ansicht den Empfänger statt des
    /// Absenders zeigen (Gesendet, Entwürfe) – „Von“ sortiert dann danach.
    /// Setzt die Ansicht, die die Ordnerrolle kennt.
    var sortsByRecipients = false {
        didSet {
            guard sortsByRecipients != oldValue, sort.field == .person else { return }
            messages = sorted(messages)
        }
    }
    /// `true`, solange ein Abruf vom Server läuft.
    var isLoading = false
    /// Meldung für die Anzeige (Abruf- und Aktionsfehler); `nil` = keine.
    /// Einziger Meldungskanal der Liste.
    var alert: AlertItem?
    /// Filterlisten für die Entscheidung über Absenderbilder; `nil`,
    /// solange sie nicht gelesen sind oder sich nicht lesen ließen – dann
    /// zeigt die Liste vorsichtshalber keine Bilder.
    private(set) var imageFilterLists: FilterLists?
    /// Zählt Lesevorgänge der Filterlisten; ein überholtes Ergebnis wird
    /// verworfen, wenn inzwischen ein neueres Lesen begonnen hat.
    @ObservationIgnored private var filterListsGeneration = 0
    /// Auswahlmodus der Liste aktiv (Kreise vor den Zeilen, Befehlsleiste).
    var isSelecting = false
    /// Ausgewählte Mails (Cache-IDs).
    var selectedIDs: Set<String> = []
    /// Mails, für die gerade eine Aktion läuft (Zeile gesperrt).
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
    private var exhaustedFolders: Set<FolderKey> = []

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
            endSelection()
            // Die Sortierung gilt nur für die bisherige Ansicht.
            sort = .standard
            loadFromCache()
        }
    }

    /// Angebot „Rückgängig“ nach einer Änderung von Kennzeichnung oder
    /// Gelesen-Status; `nil` = kein Hinweis sichtbar.
    var undoOffer: UndoOffer?

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
    /// Ordner – als Listeneinträge ohne Mailinhalt –, entfernt nicht mehr
    /// vorhandene Mails aus der Mehrfachauswahl und liest die
    /// Filterlisten für die Absenderbilder neu. Eine abweichende
    /// Sortierung wird angewandt. In Debug-Builds werden Laufzeit, Anzahl
    /// und die zwischenzeitlichen Abfragen der Ansicht ausgegeben.
    func loadFromCache() {
        #if DEBUG
        let started = Date()
        #endif
        // Sammelsichten nur mit Postfächern, deren Abruf eingeschaltet ist.
        let accountIDs = accountStore.fetchingAccounts.map(\.id)
        syncState = currentSyncState()
        switch selection {
        case .allInboxes:
            messages = MessageStore.shared.allMessages(
                accountIDs: accountIDs, folder: MailFolder.inboxPath
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
        if !sort.isStandard {
            messages = sorted(messages)
        }
        if !selectedIDs.isEmpty {
            // Verschwundene Mails fallen aus der Auswahl.
            selectedIDs.formIntersection(messages.map(\.id))
        }
        reloadFilterLists()
        cacheGeneration += 1
        #if DEBUG
        reportCacheLoad(startedAt: started)
        #endif
    }

    // MARK: - Sichtbare Einträge

    /// Bildet die gezeigten Einträge neu: alle Mails bzw. nur die Treffer
    /// der Suche, Reihenfolge wie in `messages`.
    private func updateVisibleMessages() {
        if let searchFilter {
            visibleMessages = messages.filter { searchFilter.contains($0.id) }
        } else {
            visibleMessages = messages
        }
    }

    // MARK: - Sortierung

    /// Sortiert Listeneinträge nach der gewählten Sortierung.
    ///
    /// Verarbeitung: Der Cache liefert bereits nach Datum absteigend; nur
    /// eine abweichende Sortierung oder die Rückkehr zur Grundstellung
    /// sortiert um.
    ///
    /// - Parameter items: Listeneinträge.
    /// - Returns: Sortierte Einträge.
    private func sorted(_ items: [MessageListItem]) -> [MessageListItem] {
        sort.sorted(items, showsRecipients: sortsByRecipients)
    }

    // MARK: - Absenderbilder

    /// Liest die Filterlisten neu, auf denen die Entscheidung über
    /// Absenderbilder beruht.
    ///
    /// Verarbeitung: Läuft im Hintergrund; ein Ergebnis wird nur
    /// übernommen, wenn kein neueres Lesen begonnen hat und sich die Listen
    /// geändert haben – so baut die Liste nicht unnötig neu auf.
    func reloadFilterLists() {
        filterListsGeneration += 1
        let generation = filterListsGeneration
        Task {
            let lists = await spamFilter.currentLists()
            guard generation == filterListsGeneration,
                  lists != imageFilterLists else { return }
            imageFilterLists = lists
        }
    }

    /// Entscheidet, ob die Zeile einer Mail ein Absenderbild zeigen darf.
    ///
    /// Verarbeitung: Dieselbe Regel wie der Spamfilter – ein Bild nur,
    /// wenn der Filter die Mail behalten würde. Ohne gelesene Listen
    /// vorsichtshalber kein Bild.
    ///
    /// - Parameter message: Listeneintrag.
    /// - Returns: `true`, wenn ein Bild gezeigt werden darf.
    func showsSenderImage(for message: MessageListItem) -> Bool {
        guard let lists = imageFilterLists else { return false }
        return SpamClassifier.allowsSenderImage(
            sender: FilterAddress.sender(fromHeader: message.from),
            verdict: message.spamVerdict,
            lists: lists,
            scoreLimit: spamSettings.scoreLimit
        )
    }

    #if DEBUG
    /// Messung: gibt die Kennzahlen eines Ladevorgangs aus.
    ///
    /// - Parameter startedAt: Beginn des Ladevorgangs.
    private func reportCacheLoad(startedAt: Date) {
        let millis = Int(Date().timeIntervalSince(startedAt) * 1000)
        cacheLoadCount += 1
        let loadNumber = cacheLoadCount
        let count = messages.count
        let queries = viewQueryCount
        Log.view.debug("⏱ Liste aus Cache #\(loadNumber): \(count) Mails, \(millis) ms, Ansichtsabfragen seither: \(queries)")
        viewQueryCount = 0
    }
    #endif

    /// Stand der gewählten Ansicht.
    ///
    /// Verarbeitung: Sammelansichten sind so aktuell wie der älteste
    /// beteiligte Posteingang; ausgeschaltete Postfächer zählen nicht mit.
    ///
    /// - Returns: Stand oder `nil`, wenn kein (beteiligtes) Postfach eingerichtet ist.
    private func currentSyncState() -> SyncState? {
        switch selection {
        case .allInboxes, .flagged:
            let accounts = accountStore.fetchingAccounts
            guard !accounts.isEmpty else { return nil }
            return .oldest(accounts.map {
                MessageStore.shared.lastSync(accountID: $0.id, folder: MailFolder.inboxPath)
            })
        case .folder(let accountID, let path, _):
            return .oldest([MessageStore.shared.lastSync(accountID: accountID, folder: path)])
        }
    }

    // MARK: - Ältere Nachrichten

    /// Ordner, deren Fenster die aktuelle Ansicht bilden: bei einem Ordner
    /// dieser allein, bei „Alle Eingänge" die Posteingänge aller
    /// eingeschalteten Postfächer. Die Kennzeichen-Sicht lädt nicht nach.
    private var olderTargets: [(account: MailAccount, folder: String)] {
        switch selection {
        case .allInboxes:
            return accountStore.fetchingAccounts.map { ($0, MailFolder.inboxPath) }
        case .flagged:
            return []
        case .folder(let accountID, let path, _):
            guard let account = accountStore.accounts.first(where: { $0.id == accountID }) else { return [] }
            return [(account, path)]
        }
    }

    /// Ordner der Ansicht, für die es noch Älteres geben kann.
    private var openOlderTargets: [(account: MailAccount, folder: String)] {
        olderTargets.filter { !exhaustedFolders.contains(FolderKey(accountID: $0.account.id, folder: $0.folder)) }
    }

    /// Zeile „Ältere Nachrichten laden" anzeigen? Nicht in der
    /// Kennzeichen-Sicht und nicht ohne Postfächer.
    var showsOlderRow: Bool { !olderTargets.isEmpty }

    /// `true`, wenn der Server für alle Ordner der Ansicht nichts Älteres hat.
    var olderExhausted: Bool { showsOlderRow && openOlderTargets.isEmpty }

    /// Bis zu welchem Tag ein Tipp mindestens lädt – für die Beschriftung.
    /// Bei mehreren Postfächern der späteste der nächsten Zeiträume.
    var nextOlderDate: Date? {
        let standard = SyncWindow.standardStart()
        #if DEBUG
        viewQueryCount += openOlderTargets.count
        #endif
        return openOlderTargets
            .map { target -> Date in
                let start = MessageStore.shared.windowStart(accountID: target.account.id, folder: target.folder)
                    ?? standard
                return SyncWindow.nextBlock(before: start).since
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
            targets: targets.map { FolderKey(accountID: $0.account.id, folder: $0.folder) }
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
            let key = FolderKey(accountID: target.account.id, folder: target.folder)
            do {
                let credentials = try accountStore.credentials(for: target.account)
                let result = try await MailFetchService.fetchOlder(
                    credentials, folder: target.folder
                )
                switch result {
                case .noOlder:
                    exhaustedFolders.insert(key)
                case .loaded(let count, let failed, _, let hasMore):
                    Log.fetch.info("📬 [\(target.account.displayName, privacy: .private)/\(target.folder, privacy: .public)] \(count) ältere Nachrichten geladen, \(failed) fehlgeschlagen")
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
            Log.fetch.info("📴 \(context, privacy: .private): keine Verbindung (\(error.localizedDescription, privacy: .public))")
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
            accountIDs: accountStore.fetchingAccounts.map(\.id)
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
            Log.spam.info("📁 [\(pending.account.displayName, privacy: .private)] Spam-Ordner \(created, privacy: .public) angelegt")
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
    /// Beim Posteingang eines ausgeschalteten Postfachs ersetzt dieser
    /// Abruf die Runde über „Alle Eingänge“: Spamfilter, Posteingang und
    /// Spam-Ordner (`refreshAccount`).
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
        let kind = FetchSelection.folderRefresh(
            isInbox: path == MailFolder.inboxPath,
            isPaused: !accountStore.isFetchEnabled(accountID)
        )
        switch kind {
        case .fullAccount:
            let errors = await refreshAccount(account)
            if !errors.isEmpty {
                alert = AlertItem(title: "Fehler beim Abrufen", message: errors.joined(separator: "\n"))
            }
        case .folderOnly:
            do {
                try await MailFetchService.refreshAndCache(credentials, folder: path)
            } catch {
                if let message = classify(error, context: account.displayName) {
                    alert = AlertItem(title: "Fehler beim Abrufen", message: message)
                }
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
            Log.fetch.info("🔁 Abruf \(label, privacy: .public) läuft bereits – angeschlossen")
        } else if fetches.isBusy {
            Log.fetch.info("⏳ Abruf \(label, privacy: .public) wartet auf laufenden Abruf")
        }
        let outcome = await fetches.run(request, operation: operation)
        if outcome == .superseded {
            Log.fetch.info("⏭ Abruf \(label, privacy: .public) übersprungen – neuerer Ordner gewählt")
        }
    }

    /// Ruft alle Posteingänge vom Server ab.
    ///
    /// Verarbeitung: Ruft die eingeschalteten Postfächer nacheinander ab
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
            Log.fetch.info("📴 Refresh übersprungen: kein Netz")
            return
        }

        isLoading = true
        defer { isLoading = false }
        connectionFailed = false

        let accountCount = accountStore.fetchingAccounts.count
        let pausedCount = accountStore.accounts.count - accountCount
        Log.fetch.info("🔄 Refresh gestartet für \(accountCount) Konten (\(pausedCount) ausgeschaltet)")

        var errors: [String] = []
        var processed: Set<UUID> = []
        while let account = accountStore.fetchingAccounts.first(where: { !processed.contains($0.id) }) {
            processed.insert(account.id)
            errors += await refreshAccount(account)
            loadFromCache()

            if !network.isOnline {
                connectionFailed = true
                Log.fetch.info("📴 Refresh abgebrochen: Netz verloren")
                break
            }
        }

        if !errors.isEmpty {
            alert = AlertItem(title: "Fehler beim Abrufen", message: errors.joined(separator: "\n"))
        }
        let total = messages.count
        Log.fetch.info("🔄 Refresh fertig. Fehler: \(errors.count), Nachrichten gesamt: \(total)")
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
        Log.fetch.info("🔄 Starte Abruf: \(account.displayName, privacy: .private) (ID: \(account.id.uuidString, privacy: .public))")
        let credentials: MailCredentials
        do {
            credentials = try accountStore.credentials(for: account)
        } catch {
            Log.fetch.error("❌ \(account.displayName, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return [classify(error, context: account.displayName)].compactMap { $0 }
        }

        var errors: [String] = []
        if let message = await runSpamFilter(for: account) {
            errors.append(message)
        }

        do {
            try await MailFetchService.refreshAndCache(credentials)
        } catch {
            Log.fetch.error("❌ \(account.displayName, privacy: .private): \(error.localizedDescription, privacy: .public)")
            if let message = classify(error, context: account.displayName) {
                errors.append(message)
            }
            return errors
        }

        await refreshSpamFolder(of: account.id, credentials: credentials)
        Log.fetch.info("✅ \(account.displayName, privacy: .private): Abruf abgeschlossen")
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
            Log.spam.error("⚠️ \(account.displayName, privacy: .private): Spamfilter fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
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
            Log.fetch.info("📬 [\(account.displayName, privacy: .private)] Spam-Ordner \(spamFolder, privacy: .public) abgerufen")
        } catch {
            Log.fetch.error("⚠️ [\(account.displayName, privacy: .private)] Spam-Abruf fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }


    // MARK: - Aktionen an Mails (Wischaktionen und Kontextmenü)

    /// Schaltet gelesen/ungelesen um.
    ///
    /// Verarbeitung: Server und Cache über `MessageActions`, danach die
    /// Liste neu laden und 5 Sekunden „Rückgängig“ anbieten. Während der
    /// Aktion ist die Zeile gesperrt.
    ///
    /// - Parameter item: Betroffener Listeneintrag.
    @MainActor
    func toggleRead(_ item: MessageListItem) async {
        await applyChange(.read(item.isUnread), to: item, failureTitle: "Status ändern fehlgeschlagen")
    }

    /// Schaltet die Kennzeichnung um.
    ///
    /// Verarbeitung: Server und Cache über `MessageActions`, danach die
    /// Liste neu laden und 5 Sekunden „Rückgängig“ anbieten.
    ///
    /// - Parameter item: Betroffener Listeneintrag.
    @MainActor
    func toggleFlag(_ item: MessageListItem) async {
        await applyChange(.flagged(!item.isFlagged), to: item, failureTitle: "Kennzeichnen fehlgeschlagen")
    }

    /// Führt eine umkehrbare Änderung an einer Mail aus.
    ///
    /// Verarbeitung: Sperrt die Zeile während der Aktion. Bei Erfolg wird
    /// die Liste neu geladen und „Rückgängig“ angeboten, sonst erscheint
    /// eine Meldung.
    ///
    /// - Parameters:
    ///   - change: Änderung mit neuem Wert.
    ///   - item: Betroffener Listeneintrag.
    ///   - failureTitle: Überschrift der Fehlermeldung.
    @MainActor
    private func applyChange(_ change: MessageActions.StateChange, to item: MessageListItem, failureTitle: String) async {
        processingMessageIDs.insert(item.id)
        defer { processingMessageIDs.remove(item.id) }
        let target = MessageActions.Target(item)
        do {
            try await MessageActions.apply(change, to: target, accountStore: accountStore)
            offerUndo(UndoOffer(change: change, targets: [target]))
            loadFromCache()
        } catch {
            alert = .failure(failureTitle, error)
        }
    }

    /// Löscht eine Mail (Papierkorb oder endgültig).
    ///
    /// Verarbeitung: Die Rückfrage stellt die Ansicht vorher. Danach wird
    /// die Liste neu geladen.
    ///
    /// - Parameter item: Betroffener Listeneintrag.
    @MainActor
    func delete(_ item: MessageListItem) async {
        processingMessageIDs.insert(item.id)
        defer { processingMessageIDs.remove(item.id) }
        do {
            try await MessageActions.delete(MessageActions.Target(item), accountStore: accountStore)
            loadFromCache()
        } catch {
            alert = .failure("Löschen fehlgeschlagen", error)
        }
    }

    /// Verschiebt eine Mail in einen Ordner desselben Postfachs.
    ///
    /// - Parameters:
    ///   - item: Betroffener Listeneintrag.
    ///   - path: Server-Pfad des Zielordners.
    @MainActor
    func move(_ item: MessageListItem, to path: String) async {
        processingMessageIDs.insert(item.id)
        defer { processingMessageIDs.remove(item.id) }
        do {
            try await MessageActions.move(MessageActions.Target(item), to: path, accountStore: accountStore)
            loadFromCache()
        } catch {
            alert = .failure("Verschieben fehlgeschlagen", error)
        }
    }

    /// Führt eine Spam-Aktion (Blockieren, Vertrauen) an einer Mail aus.
    ///
    /// Verarbeitung: Die Spam-Aktionen brauchen die vollständige Mail; sie
    /// wird aus dem Cache geholt. Wurde die Mail verschoben, verschwindet
    /// sie aus der Liste – das genügt als Rückmeldung. Sonst bestätigt eine
    /// Meldung den Listeneintrag. Die Filterlisten werden neu gelesen
    /// (Absenderbilder).
    ///
    /// - Parameters:
    ///   - request: Spam-Aktion.
    ///   - item: Betroffener Listeneintrag.
    @MainActor
    func performSpamAction(_ request: SpamMenuRequest, for item: MessageListItem) async {
        guard let message = MessageStore.shared.message(id: item.id) else {
            alert = AlertItem(title: "Listeneintrag", message: "Die Mail ist nicht mehr vorhanden.")
            return
        }
        processingMessageIDs.insert(item.id)
        defer { processingMessageIDs.remove(item.id) }
        do {
            let moved = try await request.perform(on: message, using: spamFilter)
            loadFromCache()
            if !moved {
                alert = MessageActionDialogs.spamResultAlert(request)
            }
        } catch {
            alert = MessageActionDialogs.spamFailureAlert(request, error)
        }
    }

    // MARK: - Rückgängig

    /// Zeigt den „Rückgängig“-Hinweis und blendet ihn nach 5 Sekunden aus.
    ///
    /// Verarbeitung: Ein neues Angebot ersetzt ein noch sichtbares.
    ///
    /// - Parameter offer: Ausgeführte Änderung und betroffene Mails.
    @MainActor
    func offerUndo(_ offer: UndoOffer) {
        undoTask?.cancel()
        undoOffer = offer
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undoOffer = nil
        }
    }

    /// Blendet den „Rückgängig“-Hinweis aus, ohne etwas zu ändern.
    @MainActor
    func dismissUndo() {
        undoTask?.cancel()
        undoOffer = nil
    }

    /// Nimmt eine eben ausgeführte Änderung zurück.
    ///
    /// Verarbeitung: Je Ordner ein Serverbefehl; scheitert ein Ordner,
    /// laufen die übrigen weiter, und die Meldung nennt, was nicht
    /// zurückgenommen wurde.
    ///
    /// - Parameter offer: Ausgeführte Änderung und betroffene Mails.
    @MainActor
    func undo(_ offer: UndoOffer) async {
        dismissUndo()
        let outcome = await runBatch(offer.targets) {
            await MessageActions.apply(offer.change.reversed, to: offer.targets, accountStore: self.accountStore)
        }
        report(outcome, total: offer.targets.count, title: "Rückgängig fehlgeschlagen")
    }

    // MARK: - Mehrfachauswahl

    /// Ausgewählte Mails in der Reihenfolge der Liste.
    var selectedItems: [MessageListItem] {
        visibleMessages.filter { selectedIDs.contains($0.id) }
    }

    /// `true`, wenn alle Mails der Liste ausgewählt sind.
    var isAllSelected: Bool {
        !visibleMessages.isEmpty && visibleMessages.allSatisfy { selectedIDs.contains($0.id) }
    }

    /// Beginnt den Auswahlmodus mit einer ausgewählten Mail.
    ///
    /// Verarbeitung: Läuft der Modus schon, kommt die Mail zur Auswahl hinzu.
    ///
    /// - Parameter id: Cache-ID der Mail, auf der lange gedrückt wurde.
    func beginSelection(with id: String) {
        selectedIDs.insert(id)
        isSelecting = true
    }

    /// Wählt eine Mail aus bzw. ab (Klick im Auswahlmodus auf dem Mac).
    ///
    /// - Parameter id: Cache-ID der Mail.
    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Beendet den Auswahlmodus und leert die Auswahl.
    func endSelection() {
        isSelecting = false
        selectedIDs = []
    }

    /// Wählt alle Mails der Liste aus bzw. hebt die Auswahl auf, wenn
    /// schon alle ausgewählt sind.
    func toggleSelectAll() {
        selectedIDs = isAllSelected ? [] : Set(visibleMessages.map(\.id))
    }

    /// Kennzeichnet die Auswahl bzw. entfernt die Kennzeichnung
    /// (Regel siehe `MessageSelection.flagChange`).
    @MainActor
    func toggleFlagForSelection() async {
        await applyToSelection(
            MessageSelection.flagChange(for: selectedItems),
            failureTitle: "Kennzeichnen fehlgeschlagen"
        )
    }

    /// Markiert die Auswahl als gelesen bzw. ungelesen
    /// (Regel siehe `MessageSelection.readChange`).
    @MainActor
    func toggleReadForSelection() async {
        await applyToSelection(
            MessageSelection.readChange(for: selectedItems),
            failureTitle: "Status ändern fehlgeschlagen"
        )
    }

    /// Führt eine umkehrbare Änderung an der Auswahl aus.
    ///
    /// Verarbeitung: Nur Mails mit abweichendem Zustand werden geändert.
    /// Der Auswahlmodus endet sofort; danach wird für die gelungenen Mails
    /// „Rückgängig“ angeboten.
    ///
    /// - Parameters:
    ///   - change: Änderung mit neuem Wert.
    ///   - failureTitle: Überschrift der Fehlermeldung.
    @MainActor
    private func applyToSelection(_ change: MessageActions.StateChange, failureTitle: String) async {
        let targets = MessageSelection.targets(for: change, in: selectedItems)
        endSelection()
        guard !targets.isEmpty else { return }
        let outcome = await runBatch(targets) {
            await MessageActions.apply(change, to: targets, accountStore: self.accountStore)
        }
        if !outcome.succeeded.isEmpty {
            offerUndo(UndoOffer(change: change, targets: outcome.succeeded))
        }
        report(outcome, total: targets.count, title: failureTitle)
    }

    /// Löscht die Auswahl. Die Rückfrage stellt die Ansicht vorher.
    @MainActor
    func deleteSelection() async {
        let targets = selectedItems.map { MessageActions.Target($0) }
        endSelection()
        guard !targets.isEmpty else { return }
        let outcome = await runBatch(targets) {
            await MessageActions.delete(targets, accountStore: self.accountStore)
        }
        report(outcome, total: targets.count, title: "Löschen fehlgeschlagen")
    }

    /// Verschiebt die Auswahl in einen Ordner ihres Postfachs.
    ///
    /// - Parameter path: Server-Pfad des Zielordners.
    @MainActor
    func moveSelection(to path: String) async {
        let items = selectedItems
        endSelection()
        guard MessageSelection.canMove(items) else { return }
        let targets = items.map { MessageActions.Target($0) }
        let outcome = await runBatch(targets) {
            await MessageActions.move(targets, to: path, accountStore: self.accountStore)
        }
        report(outcome, total: targets.count, title: "Verschieben fehlgeschlagen")
    }

    /// Führt eine Sammelaktion aus: Zeilen sperren, ausführen, Liste neu laden.
    ///
    /// - Parameters:
    ///   - targets: Betroffene Mails.
    ///   - operation: Eigentliche Aktion.
    /// - Returns: Ergebnis der Aktion.
    @MainActor
    private func runBatch(
        _ targets: [MessageActions.Target],
        operation: () async -> MessageActions.BatchOutcome
    ) async -> MessageActions.BatchOutcome {
        let ids = Set(targets.map(\.id))
        processingMessageIDs.formUnion(ids)
        defer { processingMessageIDs.subtract(ids) }
        let outcome = await operation()
        loadFromCache()
        return outcome
    }

    /// Meldet gescheiterte Teile einer Sammelaktion ehrlich: wie viele
    /// Mails nicht bearbeitet wurden und warum, je Postfach.
    ///
    /// - Parameters:
    ///   - outcome: Ergebnis der Aktion.
    ///   - total: Anzahl der betroffenen Mails.
    ///   - title: Überschrift der Meldung.
    @MainActor
    private func report(_ outcome: MessageActions.BatchOutcome, total: Int, title: String) {
        guard !outcome.failures.isEmpty else { return }
        if total <= 1, let failure = outcome.failures.first {
            alert = .failure(title, failure.error)
            return
        }
        let lines = outcome.failures.map { failure -> String in
            let name = accountStore.accounts.first { $0.id == failure.accountID }?.displayName ?? "Postfach"
            return "\(name): \(failure.error.localizedDescription)"
        }
        alert = AlertItem(
            title: title,
            message: "\(outcome.failedCount) von \(total) Mails nicht bearbeitet.\n" + lines.joined(separator: "\n")
        )
    }
}
