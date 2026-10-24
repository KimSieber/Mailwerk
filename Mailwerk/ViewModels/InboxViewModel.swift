//
//  InboxViewModel.swift
//  Mailwerk
//
//  Zweck: Zustand und Abläufe der Nachrichtenliste – welche Ansicht
//  gewählt ist (alle Posteingänge, Ungelesen, Gekennzeichnet, Spam, ein
//  Ordner), welche Mails sie aus dem Cache zeigt, Abruf vom Server,
//  „Ältere laden“, Spamfilter beim Abruf und Rückfragen zum Anlegen eines
//  Spam-Ordners.
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
//  Sicht „Ungelesen“: Mails, die während des Besuchs der Sicht gelesen
//  werden, bleiben bis zum Verlassen der Sicht bzw. bis zum Herunterziehen
//  stehen (`keptUnreadIDs`) – so lässt sich ein versehentliches „Gelesen“
//  gleich wieder umkehren, und die Liste springt nicht unter dem Finger
//  weg. Der Zähler in der Seitenleiste sinkt trotzdem sofort.
//
//  Sicht „Spam“: die Spam-Ordner aller Postfächer mit eingeschaltetem
//  Abruf gemeinsam; „Ältere laden“ lädt in allen zugleich nach. Die
//  Spam-Ordner sind auch bei ausgeschaltetem Spamfilter bekannt
//  (`locateSpamFolderIfNeeded`). Jeder Abruf der Posteingänge holt –
//  gleich aus welcher Sammelsicht – je Postfach Posteingang und
//  Spam-Ordner über eine gemeinsame Verbindung; scheitert nur der
//  Spam-Ordner, folgt ein zweiter Versuch (`retrySpamFolder`).
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
//  Laden aus dem Cache (v0.2.3b): `loadFromCache` liest im Hintergrund
//  (InboxCacheReader) – Einträge, Stand, Zähler „Ungelesen“/„Mit
//  Kennzeichnung“ und Fensterbeginn für „Ältere laden“ in einem Durchgang –
//  und übernimmt das Ergebnis auf dem Main-Actor; ein überholtes Ergebnis
//  wird verworfen. Zähler und Fensterbeginn sind gespeicherte Werte, die
//  Ansicht fragt beim Neuzeichnen keine Datenbank mehr ab.
//
//  Erreichbarkeit je Postfach: Scheitert der Abruf eines Postfachs an der
//  Verbindung, gilt nur dieses Postfach als „nicht erreichbar“
//  (AccountFetchState) – bis zu seinem nächsten erfolgreichen Abruf. Die
//  Titelzeile, das Warnzeichen am Postfach und die Apple Watch zeigen das
//  an. Fehler des Spamfilters oder nur des Spam-Ordners zählen nicht.
//
//  Abgelaufene Anmeldung (OAuth 2): Ein solches Postfach wird in der
//  Abrufrunde übersprungen; seine Mails bleiben im Cache sichtbar. Der
//  Fehler erscheint nicht als Meldung – das übernehmen Warnzeichen und
//  Hinweisleiste (OAuthSignInState, InboxView).
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
//  Abhängigkeiten: AccountStore, SpamSettings, SpamFilterService, InboxCacheReader,
//  MailFetchService, MailSession (Zugangsdaten), MessageActions, UndoOffer,
//  MessageActionDialogs, SpamMenuRequest, MessageSelection,
//  MessageStore, MessageSort, NetworkMonitor, SyncWindow, FetchCoordinator,
//  FolderKey, MailFolder, SpamClassifier, SpamMark, FilterAddress, OAuthError,
//  OAuthSignInState, AccountFetchState, Log.
//
//  Apple Watch: `onInboxesRefreshed` meldet jeden Abruf der Posteingänge,
//  `onCacheReloaded` jedes Neuladen der Liste an die WatchBridge, die der
//  Watch daraufhin den neuen Stand liefert.
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
        didSet {
            updateVisibleMessages()
            rebuildRowModels()
        }
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
            guard sortsByRecipients != oldValue else { return }
            rebuildRowModels()
            guard sort.field == .person else { return }
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
    private(set) var imageFilterLists: FilterLists? {
        didSet {
            listsRevision += 1
            rebuildRowModels()
        }
    }

    /// Zählt Änderungen der Filterlisten – billiger Vergleich, ob die
    /// Zeilenmodelle noch zu den Listen passen (statt die Listen je Zeile
    /// zu vergleichen).
    @ObservationIgnored private var listsRevision = 0

    /// Schlüssel, mit dem die Zeilenmodelle berechnet wurden: Ansicht,
    /// Stand der Filterlisten, Score-Obergrenze.
    private struct RowModelKey: Equatable {
        let showsRecipients: Bool
        let listsRevision: Int
        let scoreLimit: Double
    }

    /// Vorberechnete Anzeige je Zeile (Cache-ID → Modell), im Hintergrund
    /// gebildet (Prüfbericht P-08). Gilt nur für die Eingaben
    /// `rowModelKey`; weichen die aktuellen ab, rechnet `rowModel(for:…)`
    /// die Zeile direkt.
    private(set) var rowModels: [String: MessageRowModel] = [:]
    /// Schlüssel, mit dem `rowModels` berechnet wurde.
    @ObservationIgnored private var rowModelKey: RowModelKey?
    /// Zählt die Berechnungen der Zeilenmodelle; ein überholtes Ergebnis
    /// wird verworfen.
    @ObservationIgnored private var rowModelGeneration = 0
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
    /// Postfächer, deren letzter Abruf den Server nicht erreichte – je
    /// Postfach, nicht je Ansicht (Titelzeile, Warnzeichen, Watch).
    private let fetchState = AccountFetchState.shared

    /// Läuft gerade „Ältere Nachrichten laden"?
    var isLoadingOlder = false
    /// Letzter Nachladeversuch scheiterte an der Verbindung – die Zeile
    /// zeigt das selbst an, bis zum nächsten Versuch oder Ansichtswechsel.
    var olderConnectionFailed = false
    /// Ordner, für die der Server nichts Älteres mehr hat. Nur für diese
    /// Sitzung – nach einem Neustart stellt ein Tipp das erneut fest.
    private var exhaustedFolders: Set<FolderKey> = []
    /// Sicht „Ungelesen“: Mails, die bei diesem Besuch der Sicht schon
    /// gezeigt wurden. Sie bleiben stehen, auch wenn sie inzwischen gelesen
    /// sind; ein Wechsel der Ansicht oder Herunterziehen leert die Menge.
    @ObservationIgnored private var keptUnreadIDs: Set<String> = []

    /// Netzzustand (online/offline).
    private let network = NetworkMonitor.shared

    /// Wird nach jedem Abruf aller Posteingänge aufgerufen (auch ohne Netz
    /// oder nach Fehlern) – die Anbindung der Apple Watch liefert dann den
    /// neuen Stand (WatchBridge).
    @ObservationIgnored var onInboxesRefreshed: (() -> Void)?

    /// Wird nach jedem Neuladen der Liste aus dem Cache aufgerufen (Aktion,
    /// Abruf, Ansichtswechsel) – die Anbindung der Apple Watch schickt dann
    /// einer gerade offenen Watch-App den neuen Stand (WatchBridge).
    @ObservationIgnored var onCacheReloaded: (() -> Void)?

    /// Stimmt die Abrufe ab: nacheinander, ohne Doppelungen; bei mehreren
    /// wartenden Ordnern zählt nur der zuletzt gewählte.
    private let fetches = FetchCoordinator<FetchRequest>(
        supersedes: FetchRequest.supersedes
    )

    #if DEBUG
    /// Messung: Anzahl der Ladevorgänge aus dem Cache in dieser Sitzung.
    /// Nicht beobachtet, damit das Zählen keine Neuzeichnung auslöst.
    @ObservationIgnored private var cacheLoadCount = 0
    #endif

    /// Zählt die Ladevorgänge aus dem Cache; ein Ergebnis wird nur
    /// übernommen, wenn seither kein neuerer begonnen hat.
    @ObservationIgnored private var loadGeneration = 0

    /// `true`, sobald die Liste einmal aus dem Cache geladen ist. Bis dahin
    /// zeigt die Ansicht die Ladeanzeige statt „Keine Mails“.
    private(set) var hasLoadedCache = false

    /// Anzahl ungelesener Mails in den Posteingängen (für die Leiste).
    /// Wird beim Laden aus dem Cache mitgelesen – die Ansicht fragt die
    /// Datenbank nicht mehr bei jedem Neuzeichnen.
    private(set) var unreadCount = 0

    /// Anzahl gekennzeichneter Mails in den Posteingängen (für die Leiste),
    /// mitgelesen wie `unreadCount`.
    private(set) var flaggedCount = 0

    /// Gespeicherter Fensterbeginn je Ordner der Ansicht (für „Ältere
    /// laden“), mitgelesen beim Laden aus dem Cache. Fehlt ein Ordner, gilt
    /// das Standardfenster.
    private var windowStarts: [FolderKey: Date] = [:]

    /// Aktive Ansicht. Ändert sich durch die Seitenleiste.
    var selection: MailboxSelection = .allInboxes {
        didSet {
            // Der Hinweis der Zeile „Ältere laden“ gilt für die bisherige
            // Ansicht. Die Erreichbarkeit der Postfächer bleibt bestehen –
            // sie gilt je Postfach, nicht je Ansicht.
            olderConnectionFailed = false
            endSelection()
            // Die Sortierung gilt nur für die bisherige Ansicht.
            sort = .standard
            // Gelesene der Sicht „Ungelesen“ fallen beim Verlassen heraus.
            keptUnreadIDs = []
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
    /// Verarbeitung: Beschreibt die Ansicht als Anfrage (`cacheRequest`)
    /// und lässt `InboxCacheReader` sie im Hintergrund lesen – Einträge,
    /// Abrufzeitpunkte, Zähler und Fensterbeginn in einem Durchgang. Das
    /// Ergebnis übernimmt `apply(_:for:)` auf dem Main-Actor, aber nur,
    /// wenn seither kein neuerer Ladevorgang begonnen hat (sonst wäre es
    /// überholt, z. B. nach einem schnellen Ansichtswechsel). Die Funktion
    /// kehrt sofort zurück; die Liste aktualisiert sich, sobald das
    /// Ergebnis vorliegt. In Debug-Builds werden Laufzeit und Anzahl
    /// ausgegeben. Messpunkt für Instruments: „Liste aus Cache“ (nur das
    /// Lesen im Hintergrund).
    func loadFromCache() {
        loadGeneration += 1
        let generation = loadGeneration
        let request = cacheRequest()
        #if DEBUG
        let started = Date()
        #endif
        Task {
            let interval = Log.beginInterval(Log.Interval.listFromCache)
            let snapshot = await InboxCacheReader.read(request)
            Log.endInterval(interval)
            guard generation == loadGeneration else { return }
            apply(snapshot, for: request)
            #if DEBUG
            reportCacheLoad(startedAt: started)
            #endif
        }
    }

    /// Beschreibt die gezeigte Ansicht als Anfrage an den Cache.
    ///
    /// Verarbeitung: Sammelsichten nur mit Postfächern, deren Abruf
    /// eingeschaltet ist. Die Standzeile richtet sich bei Sammelsichten nach
    /// den Posteingängen bzw. Spam-Ordnern, bei einem Ordner nach diesem.
    /// Die Sicht „Ungelesen“ nimmt die bei diesem Besuch schon gezeigten
    /// Mails mit.
    ///
    /// - Returns: Anfrage für `InboxCacheReader`.
    private func cacheRequest() -> InboxCacheReader.Request {
        let accountIDs = accountStore.fetchingAccounts.map(\.id)
        let inboxes = accountIDs.map { FolderKey(accountID: $0, folder: MailFolder.inboxPath) }
        let source: InboxCacheReader.Source
        let syncFolders: [FolderKey]
        switch selection {
        case .allInboxes:
            source = .inboxes(accountIDs)
            syncFolders = inboxes
        case .unread:
            source = .unread(accountIDs, keeping: keptUnreadIDs)
            syncFolders = inboxes
        case .flagged:
            source = .flagged(accountIDs)
            syncFolders = inboxes
        case .spam:
            let folders = spamFolders
            source = .folders(folders)
            syncFolders = folders
        case .folder(let accountID, let path, _):
            source = .folder(accountID: accountID, path: path)
            syncFolders = [FolderKey(accountID: accountID, folder: path)]
        }
        return InboxCacheReader.Request(
            source: source,
            syncFolders: syncFolders,
            countAccountIDs: accountIDs,
            windowFolders: olderTargets.map { FolderKey(accountID: $0.account.id, folder: $0.folder) }
        )
    }

    /// Übernimmt eine Momentaufnahme aus dem Cache.
    ///
    /// Verarbeitung: Setzt den Stand der Ansicht, merkt in der Sicht
    /// „Ungelesen“ die gezeigten Mails, sortiert bei abweichender
    /// Sortierung und weist Liste, Zähler und Fensterbeginn nur bei
    /// geändertem Inhalt zu – jede Zuweisung lässt die Ansicht neu
    /// zeichnen. Danach fallen verschwundene Mails aus der Mehrfachauswahl,
    /// die Filterlisten für die Absenderbilder werden neu gelesen, die Suche
    /// erfährt vom neuen Stand (`cacheGeneration`) und die Apple Watch
    /// ebenso (`onCacheReloaded`).
    ///
    /// - Parameters:
    ///   - snapshot: Gelesene Daten.
    ///   - request: Anfrage, aus der sie stammen.
    private func apply(_ snapshot: InboxCacheReader.Snapshot, for request: InboxCacheReader.Request) {
        let newSyncState: SyncState? = request.syncFolders.isEmpty ? nil : .oldest(snapshot.syncDates)
        if newSyncState != syncState { syncState = newSyncState }
        if case .unread = request.source {
            keptUnreadIDs.formUnion(snapshot.items.map(\.id))
        }
        var loaded = snapshot.items
        if !sort.isStandard {
            loaded = sorted(loaded)
        }
        if loaded != messages { messages = loaded }
        if snapshot.unreadCount != unreadCount { unreadCount = snapshot.unreadCount }
        if snapshot.flaggedCount != flaggedCount { flaggedCount = snapshot.flaggedCount }
        if snapshot.windowStarts != windowStarts { windowStarts = snapshot.windowStarts }
        if !selectedIDs.isEmpty {
            // Verschwundene Mails fallen aus der Auswahl.
            selectedIDs.formIntersection(messages.map(\.id))
        }
        if !hasLoadedCache { hasLoadedCache = true }
        reloadFilterLists()
        cacheGeneration += 1
        onCacheReloaded?()
    }

    /// Sicht „Ungelesen“: lässt die bei diesem Besuch gelesenen Mails
    /// fallen (Herunterziehen). Die Liste zeigt danach nur Ungelesenes.
    func releaseKeptUnread() {
        keptUnreadIDs = []
    }

    /// Postfächer der gewählten Ansicht – Grundlage des Hinweises
    /// „nicht erreichbar“ in der Titelzeile.
    ///
    /// Verarbeitung: Sammelansichten umfassen die Postfächer mit
    /// eingeschaltetem Abruf, ein Ordner nur sein Postfach.
    var viewAccounts: [MailAccount] {
        switch selection {
        case .allInboxes, .unread, .flagged, .spam:
            return accountStore.fetchingAccounts
        case .folder(let accountID, _, _):
            return accountStore.accounts.filter { $0.id == accountID }
        }
    }

    /// Spam-Ordner der Postfächer mit eingeschaltetem Abruf; Postfächer
    /// ohne bekannten Spam-Ordner fehlen.
    var spamFolders: [FolderKey] {
        accountStore.fetchingAccounts.compactMap { account in
            guard let folder = account.spamFolder, !folder.isEmpty else { return nil }
            return FolderKey(accountID: account.id, folder: folder)
        }
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

    /// Anzeige einer Zeile: Person, Erlaubnis für ein Absenderbild und
    /// Spam-Hinweis.
    ///
    /// Verarbeitung: Liefert das vorberechnete Modell, wenn es mit den
    /// aktuellen Eingaben (Ansicht, Filterlisten, Score-Obergrenze)
    /// entstanden ist; sonst – etwa im Augenblick zwischen einer Änderung
    /// und dem Ende der Hintergrundberechnung – wird die Zeile direkt
    /// berechnet. So zeigt die Liste nie einen veralteten Stand. Regeln wie
    /// beim Spamfilter: ein Bild nur, wenn der Filter die Mail behalten
    /// würde; ohne gelesene Listen weder Bild noch Hinweis.
    ///
    /// - Parameters:
    ///   - message: Listeneintrag.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Modell der Zeile.
    func rowModel(for message: MessageListItem, showsRecipients: Bool) -> MessageRowModel {
        if currentRowModelKey(showsRecipients: showsRecipients) == rowModelKey,
           let model = rowModels[message.id] {
            return model
        }
        return MessageRowModel.make(for: message, inputs: currentRowModelInputs(showsRecipients: showsRecipients))
    }

    /// Aktueller Schlüssel der Zeilenmodelle.
    ///
    /// - Parameter showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Schlüssel aus Ansicht, Listenstand und Score-Obergrenze.
    private func currentRowModelKey(showsRecipients: Bool) -> RowModelKey {
        RowModelKey(
            showsRecipients: showsRecipients,
            listsRevision: listsRevision,
            scoreLimit: spamSettings.scoreLimit
        )
    }

    /// Aktuelle Eingaben der Zeilenmodelle.
    ///
    /// - Parameter showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Eingaben aus Filterlisten und Score-Obergrenze.
    private func currentRowModelInputs(showsRecipients: Bool) -> MessageRowModel.Inputs {
        MessageRowModel.Inputs(
            showsRecipients: showsRecipients,
            lists: imageFilterLists,
            scoreLimit: spamSettings.scoreLimit
        )
    }

    /// Berechnet die Zeilenmodelle der Liste im Hintergrund neu.
    ///
    /// Verarbeitung: Aufgerufen bei neuer Liste, geänderten Filterlisten und
    /// beim Wechsel zwischen Absender- und Empfängeranzeige. Das Ergebnis
    /// wird nur übernommen, wenn seither keine neuere Berechnung begonnen
    /// hat. Bis dahin rechnet `rowModel(for:…)` sichtbare Zeilen direkt.
    private func rebuildRowModels() {
        rowModelGeneration += 1
        let generation = rowModelGeneration
        let items = messages
        let inputs = currentRowModelInputs(showsRecipients: sortsByRecipients)
        let key = currentRowModelKey(showsRecipients: sortsByRecipients)
        Task {
            let models = await Self.buildRowModels(for: items, inputs: inputs)
            guard generation == rowModelGeneration else { return }
            rowModelKey = key
            rowModels = models
        }
    }

    /// Berechnet Zeilenmodelle abseits des Hauptthreads.
    ///
    /// - Parameters:
    ///   - items: Listeneinträge.
    ///   - inputs: Gemeinsame Eingaben.
    /// - Returns: Modelle je Cache-ID.
    @concurrent
    nonisolated private static func buildRowModels(
        for items: [MessageListItem],
        inputs: MessageRowModel.Inputs
    ) async -> [String: MessageRowModel] {
        MessageRowModel.makeAll(for: items, inputs: inputs)
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
        Log.view.debug("⏱ Liste aus Cache #\(loadNumber): \(count) Mails, \(millis) ms bis zur Übernahme")
    }
    #endif

    // MARK: - Ältere Nachrichten

    /// Ordner, deren Fenster die aktuelle Ansicht bilden: bei einem Ordner
    /// dieser allein, bei „Alle Eingänge" die Posteingänge und bei „Spam“
    /// die Spam-Ordner aller eingeschalteten Postfächer. Die Sichten
    /// „Ungelesen“ und „Mit Kennzeichnung“ laden nicht nach – ihre Mails
    /// holt jeder Abruf unabhängig vom Alter.
    private var olderTargets: [(account: MailAccount, folder: String)] {
        switch selection {
        case .allInboxes:
            return accountStore.fetchingAccounts.map { ($0, MailFolder.inboxPath) }
        case .unread, .flagged:
            return []
        case .spam:
            return spamFolders.compactMap { key in
                guard let account = accountStore.accounts.first(where: { $0.id == key.accountID }) else { return nil }
                return (account: account, folder: key.folder)
            }
        case .folder(let accountID, let path, _):
            guard let account = accountStore.accounts.first(where: { $0.id == accountID }) else { return [] }
            return [(account, path)]
        }
    }

    /// Ordner der Ansicht, für die es noch Älteres geben kann.
    private var openOlderTargets: [(account: MailAccount, folder: String)] {
        olderTargets.filter { !exhaustedFolders.contains(FolderKey(accountID: $0.account.id, folder: $0.folder)) }
    }

    /// Zeile „Ältere Nachrichten laden" anzeigen? Nicht in den Sichten
    /// „Ungelesen“ und „Mit Kennzeichnung“ und nicht ohne Postfächer.
    var showsOlderRow: Bool { !olderTargets.isEmpty }

    /// `true`, wenn der Server für alle Ordner der Ansicht nichts Älteres hat.
    var olderExhausted: Bool { showsOlderRow && openOlderTargets.isEmpty }

    /// Bis zu welchem Tag ein Tipp mindestens lädt – für die Beschriftung.
    /// Bei mehreren Postfächern der späteste der nächsten Zeiträume.
    /// Liest den Fensterbeginn aus `windowStarts` (beim Laden aus dem Cache
    /// mitgelesen) – ohne Datenbankabfrage beim Neuzeichnen.
    var nextOlderDate: Date? {
        let standard = SyncWindow.standardStart()
        return openOlderTargets
            .map { target -> Date in
                let key = FolderKey(accountID: target.account.id, folder: target.folder)
                let start = windowStarts[key] ?? standard
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
        // Liste nach dem letzten Ordner schon neu geladen? Dann entfällt das
        // abschließende Neuladen (bisher doppelt).
        var isListCurrent = false
        for target in targets {
            isListCurrent = false
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
            isListCurrent = true
        }
        if !isListCurrent {
            loadFromCache()
        }
        if !errors.isEmpty {
            alert = AlertItem(title: "Ältere Nachrichten", message: errors.joined(separator: "\n"))
        }
    }

    /// Ordnet einen Abruffehler ein.
    ///
    /// Verarbeitung: Eine abgelaufene Anmeldung (OAuth 2) wird nur
    /// protokolliert – sie zeigen Warnzeichen und Hinweisleiste.
    /// Verbindungsfehler werden nur protokolliert; ob ein Postfach als
    /// „nicht erreichbar“ gilt, entscheidet der Aufrufer
    /// (`updateReachability`), weil nicht jeder Teilschritt zählt. Alle
    /// anderen Fehler werden als Meldungstext zurückgegeben.
    ///
    /// - Parameters:
    ///   - error: Aufgetretener Fehler.
    ///   - context: Bezeichnung für die Meldung (z. B. Postfachname).
    /// - Returns: Meldungstext oder `nil` bei abgelaufener Anmeldung bzw.
    ///   einem Verbindungsfehler.
    private func classify(_ error: Error, context: String) -> String? {
        if let oauthError = error as? OAuthError, oauthError == .signInRequired {
            Log.fetch.info("🔑 \(context, privacy: .private): Anmeldung abgelaufen – übersprungen")
            return nil
        }
        if isConnectionFailure(error) {
            Log.fetch.info("📴 \(context, privacy: .private): keine Verbindung (\(error.localizedDescription, privacy: .public))")
            return nil
        }
        return "\(context): \(error.localizedDescription)"
    }

    /// Prüft, ob ein Fehler an der Verbindung lag.
    ///
    /// Verarbeitung: Ohne Netz gilt jeder Fehler als Verbindungsfehler
    /// (die Ursache ist dann klar, die Meldung wäre irreführend).
    ///
    /// - Parameter error: Aufgetretener Fehler.
    /// - Returns: `true` bei einem Verbindungsfehler.
    private func isConnectionFailure(_ error: Error) -> Bool {
        MailFetchService.isConnectionError(error) || !network.isOnline
    }

    /// Vermerkt nach dem Abruf eines Postfachs, ob es erreichbar war.
    ///
    /// Verarbeitung: Erfolg löscht „nicht erreichbar“; ein
    /// Verbindungsfehler setzt es. Andere Fehler (Anmeldung, Protokoll)
    /// ändern nichts – sie erscheinen als Meldung. Ohne Netz am Gerät wird
    /// nichts gesetzt: Dann zeigt die Titelzeile „Offline“, und das
    /// Postfach selbst ist nicht schuld.
    ///
    /// - Parameters:
    ///   - account: Abgerufenes Postfach.
    ///   - error: Fehler des Abrufs; `nil` = erfolgreich.
    private func updateReachability(of account: MailAccount, error: Error?) {
        guard let error else {
            fetchState.setUnreachable(false, for: account.id, name: account.displayName)
            return
        }
        guard network.isOnline, MailFetchService.isConnectionError(error) else { return }
        fetchState.setUnreachable(true, for: account.id, name: account.displayName)
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

        // Ohne Netz gar nicht erst versuchen: Cache zeigen; die Titelzeile
        // zeigt „Offline“.
        guard network.isOnline else {
            loadFromCache()
            return
        }

        isLoading = true
        defer { isLoading = false }

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
                updateReachability(of: account, error: nil)
            } catch {
                updateReachability(of: account, error: error)
                if let message = classify(error, context: account.displayName) {
                    alert = AlertItem(title: "Fehler beim Abrufen", message: message)
                }
            }
        }
        loadFromCache()
    }

    /// Ruft alle Posteingänge ab (Start, Pull-to-Refresh, Apple Watch).
    ///
    /// Verarbeitung: Ausgeführt über den `FetchCoordinator`. Läuft der
    /// Abruf schon, wird auf ihn gewartet statt ein zweites Mal abzurufen.
    /// Danach erfährt `onInboxesRefreshed` davon.
    @MainActor
    func refresh() async {
        await coordinated(.inboxes, label: "Posteingänge") {
            await self.performRefresh()
            self.onInboxesRefreshed?()
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
    /// Messpunkt für Instruments: „Abruf gesamt“.
    @MainActor
    private func performRefresh() async {
        // Ohne Netz gar nicht erst versuchen: Cache zeigen; die Titelzeile
        // zeigt „Offline“.
        guard network.isOnline else {
            loadFromCache()
            Log.fetch.info("📴 Refresh übersprungen: kein Netz")
            return
        }

        isLoading = true
        defer { isLoading = false }
        let interval = Log.beginInterval(Log.Interval.refreshAll)
        defer { Log.endInterval(interval) }

        let accountCount = accountStore.fetchingAccounts.count
        let pausedCount = accountStore.accounts.count - accountCount
        Log.fetch.info("🔄 Refresh gestartet für \(accountCount) Konten (\(pausedCount) ausgeschaltet)")

        var errors: [String] = []
        var processed: Set<UUID> = []
        while let account = accountStore.fetchingAccounts.first(where: { !processed.contains($0.id) }) {
            processed.insert(account.id)
            // Abgelaufene Anmeldung: nicht abrufen, bis neu angemeldet ist.
            if OAuthSignInState.shared.isSignInRequired(account.id) {
                Log.fetch.info("🔑 \(account.displayName, privacy: .private): Anmeldung abgelaufen – übersprungen")
                continue
            }
            errors += await refreshAccount(account)
            loadFromCache()

            if !network.isOnline {
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
    /// Abruf nicht – außer einer abgelaufenen Anmeldung. Posteingang und
    /// Spam-Ordner kommen über eine gemeinsame Verbindung (eine Anmeldung
    /// weniger; manche Anbieter bremsen dichte Anmeldefolgen aus).
    /// Scheitert der Posteingang, entfällt der Spam-Ordner, denn dann liegt
    /// meist die Verbindung danieder. Scheitert nur der Spam-Ordner, wird
    /// er nach kurzer Pause einmal allein abgerufen (`retrySpamFolder`).
    /// Messpunkt für Instruments: „Abruf Postfach“.
    ///
    /// Erreichbarkeit (`updateReachability`): Es zählt allein der
    /// Posteingang. Ein Verbindungsfehler des Spamfilters oder nur des
    /// Spam-Ordners markiert das Postfach nicht als „nicht erreichbar“.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Meldungstexte der aufgetretenen Fehler (Verbindungsfehler
    ///   werden am Postfach vermerkt und erscheinen hier nicht).
    @MainActor
    private func refreshAccount(_ account: MailAccount) async -> [String] {
        let interval = Log.beginInterval(Log.Interval.refreshAccount)
        defer { Log.endInterval(interval) }
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
        // Hat der Spamfilter festgestellt, dass die Anmeldung abgelaufen
        // ist, scheitert auch der Abruf – gar nicht erst versuchen.
        if OAuthSignInState.shared.isSignInRequired(account.id) {
            return errors
        }
        // Filter aus: Spam-Ordner trotzdem ermitteln (Sammelansicht „Spam“).
        await locateSpamFolderIfNeeded(for: account)

        // Spam-Ordner frisch aus dem Postfach lesen: Der Spamfilter kann ihn
        // eben erst gefunden und gemerkt haben.
        let spamFolder = currentSpamFolder(of: account.id)
        let folders = [MailFolder.inboxPath] + (spamFolder.map { [$0] } ?? [])
        do {
            try await MailFetchService.refreshAndCache(credentials, folders: folders)
            updateReachability(of: account, error: nil)
            if let spamFolder {
                Log.fetch.info("📬 [\(account.displayName, privacy: .private)] Spam-Ordner \(spamFolder, privacy: .public) abgerufen")
            }
        } catch {
            let failure = error as? MailFetchService.FolderRefreshError
            let underlying = failure?.underlying ?? error
            if let spamFolder, failure?.completed.contains(MailFolder.inboxPath) == true {
                // Posteingang ist aktuell, nur der Spam-Ordner fehlt: Das
                // Postfach war erreichbar.
                updateReachability(of: account, error: nil)
                Log.fetch.error("⚠️ [\(account.displayName, privacy: .private)] Spam-Abruf fehlgeschlagen: \(underlying.localizedDescription, privacy: .public)")
                await retrySpamFolder(spamFolder, of: account, credentials: credentials)
            } else {
                updateReachability(of: account, error: underlying)
                Log.fetch.error("❌ \(account.displayName, privacy: .private): \(underlying.localizedDescription, privacy: .public)")
                if let message = classify(underlying, context: account.displayName) {
                    errors.append(message)
                }
                return errors
            }
        }

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

    /// Ermittelt den Spam-Ordner eines Postfachs, wenn der Spamfilter aus
    /// ist und noch keiner gemerkt ist.
    ///
    /// Verarbeitung: Bei eingeschaltetem Filter übernimmt das der
    /// Filterlauf. Sonst sucht der Spamfilter-Dienst den Ordner einmalig
    /// (danach ist er gemerkt). Fehler werden nur protokolliert – der Abruf
    /// des Posteingangs geht vor.
    ///
    /// - Parameter account: Postfach.
    @MainActor
    private func locateSpamFolderIfNeeded(for account: MailAccount) async {
        guard !spamSettings.isEnabled else { return }
        let current = accountStore.accounts.first(where: { $0.id == account.id }) ?? account
        guard (current.spamFolder ?? "").isEmpty else { return }
        do {
            try await spamFilter.locateSpamFolder(for: current)
        } catch {
            Log.spam.error("⚠️ [\(account.displayName, privacy: .private)] Spam-Ordner nicht ermittelt: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Spam-Ordner eines Postfachs, frisch aus der Postfachliste gelesen.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: IMAP-Pfad; `nil`, wenn keiner bekannt ist.
    private func currentSpamFolder(of accountID: UUID) -> String? {
        guard let folder = accountStore.accounts.first(where: { $0.id == accountID })?.spamFolder,
              !folder.isEmpty else { return nil }
        return folder
    }

    /// Pause vor dem zweiten Versuch beim Spam-Ordner.
    private static let spamRetryDelay: Duration = .seconds(2)

    /// Ruft den Spam-Ordner nach einem gescheiterten Versuch einmal allein ab.
    ///
    /// Verarbeitung: Nach kurzer Pause über eine eigene Verbindung – fängt
    /// Aussetzer ab, etwa eine Anmeldung, die beim Anbieter in die
    /// Zeitüberschreitung lief. Ohne Netz entfällt der Versuch. Fehler
    /// werden nur protokolliert: Der Posteingang ist bereits aktuell, und
    /// die Standzeile der Sicht „Spam“ zeigt, dass der Ordner zurückliegt.
    ///
    /// - Parameters:
    ///   - folder: IMAP-Pfad des Spam-Ordners.
    ///   - account: Postfach.
    ///   - credentials: Zugangsdaten des Postfachs.
    @MainActor
    private func retrySpamFolder(_ folder: String, of account: MailAccount, credentials: MailCredentials) async {
        try? await Task.sleep(for: Self.spamRetryDelay)
        guard network.isOnline else { return }
        do {
            try await MailFetchService.refreshAndCache(credentials, folder: folder)
            Log.fetch.info("📬 [\(account.displayName, privacy: .private)] Spam-Ordner \(folder, privacy: .public) im zweiten Versuch abgerufen")
        } catch {
            Log.fetch.error("⚠️ [\(account.displayName, privacy: .private)] Spam-Abruf auch im zweiten Versuch fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
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

    /// Zeigt den „Rückgängig“-Hinweis und blendet ihn nach
    /// `UndoOffer.duration` (5 Sekunden) aus.
    ///
    /// Verarbeitung: Ein neues Angebot ersetzt ein noch sichtbares.
    ///
    /// - Parameter offer: Ausgeführte Änderung und betroffene Mails.
    @MainActor
    func offerUndo(_ offer: UndoOffer) {
        undoTask?.cancel()
        undoOffer = offer
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: UndoOffer.duration)
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
