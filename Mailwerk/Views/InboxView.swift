//
//  InboxView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.09.2026
//  Geändert: 31.10.2026
//
//  Zweck: Hauptansicht mit der Nachrichtenliste. Zeigt die gewählte
//  Ansicht (alle Posteingänge, Ungelesen, Gekennzeichnet, Spam, ein
//  Ordner), Titel mit Stand und Verbindungshinweis, die eigene untere
//  Leiste (ListBottomBar: Sortieren, Suche als großer Kreis, Neue Mail),
//  den Rückgängig-Balken mit ablaufender Füllung, Wischaktionen
//  (gelesen, kennzeichnen),
//  das Kontextmenü einer Mail per langem Drücken (dasselbe Menü wie in
//  der Mailansicht, siehe MessageMenu), „Rückgängig“ für Kennzeichnung
//  und Gelesen-Status, die Mehrfachauswahl (iPhone/iPad über „Auswählen“
//  im Kontextmenü; Auswahlkreise, „Alle auswählen“, „Fertig“ und
//  schwebende Befehlsleiste unten; Mac siehe unten), die Zeile „Ältere Nachrichten laden“, die
//  Ordnerleiste sowie Einstellungen (Zahnrad: Postfächer, Spamfilter,
//  auf iPhone/iPad zuletzt „Über Mailwerk“). Sortieren, Suche und Verfassen liegen
//  auf dem iPhone/iPad in der eigenen Leiste am unteren Rand (einhändige
//  Bedienung, ListBottomBar), auf dem Mac in der eigenen Kopfleiste über
//  der Liste (MacListHeaderBar); im
//  Auswahlmodus ersetzt die Befehlsleiste die untere Leiste. Eine
//  abweichende Sortierung hebt den Knopf hervor (Kreis in der
//  Akzentfarbe). Die Suche (`searchable`) öffnet der Suchkreis; ihr Feld
//  steht auf dem iPhone/iPad oben unter dem Titel, nur dort stellt iOS
//  keinen zweiten Suchknopf in die untere Leiste: Treffer aus dem Cache
//  ersetzen die Liste, darunter Namensvorschläge als Marken und der
//  Abschnitt „Auf dem Server“ (Serversuche auf Knopfdruck; ein Tipp lädt
//  den Treffer und öffnet ihn). Eine neue Mail geht vom
//  Postfach des gezeigten Ordners aus, in Sammelansichten vom
//  Standard-Postfach. Aktualisiert wird auf
//  iPhone/iPad durch Herunterziehen, auf dem Mac per Knopf bzw. ⌘R.
//  Kommen Postfächer hinzu (beim ersten Start aus iCloud oder neu
//  eingerichtet) oder wird der Abruf eines Postfachs wieder
//  eingeschaltet, wird automatisch abgerufen. Ein Ordner eines
//  ausgeschalteten Postfachs lädt beim Öffnen auch dessen Ordnerliste.
//
//  Ist die Anmeldung eines Postfachs (OAuth 2) abgelaufen, steht über der
//  Liste eine schmale Leiste „Anmeldung für ‚…‘ abgelaufen – Neu
//  anmelden“ (SignInRequiredBar); ein Tipp öffnet direkt das
//  Anmeldefenster. Nach erfolgreicher Anmeldung wird die Ansicht sofort
//  abgerufen.
//
//  Die zweite Titelzeile nennt den Stand und Verbindungsprobleme: ohne
//  Netz „Offline“, sind alle Postfächer der Ansicht nicht erreichbar
//  „Keine Verbindung“, sonst das betroffene Postfach bzw. deren Anzahl
//  (AccountFetchState). Die Ordnerleiste zeigt dazu ein gelbes
//  Warnzeichen am Postfach. Auf dem Mac steht dieselbe Zeile unter dem
//  Titel in der Kopfleiste der Liste; während eines Abrufs zeigt dort der
//  Knopf „Aktualisieren“ selbst den Kreisel.
//
//  Am Listenende steht „Ältere Nachrichten laden“; in den Sichten
//  „Ungelesen“ und „Mit Kennzeichnung“, die jeder Abruf unabhängig vom
//  Alter vollständig holt, stattdessen ein Hinweis darauf.
//
//  Die Liste liegt auf der getönten Fläche der App, die Zeilen als Karten
//  (AppTheme); im Auswahlmodus sind ausgewählte Zeilen leicht getönt.
//
//  Die Liste arbeitet mit Listeneinträgen ohne Mailinhalt
//  (`MessageListItem`). Erst beim Öffnen einer Mail lädt
//  `MessageDetailLoader` die vollständige Nachricht aus dem Cache. Im
//  Ordner „Entwürfe” öffnet ein Tipp den Entwurf zum Weiterbearbeiten
//  (`DraftComposeLoader`).
//
//  iPad: Auf dem iPad (horizontalSizeClass == .regular) erscheint eine
//  geteilte Ansicht. Ohne ausgewählte Mail füllt die Liste die volle
//  (verbleibende) Breite. Mit ausgewählter Mail:
//  - Querformat: 2 Spalten (Liste + Detail, Ordner per SideDrawer) oder
//    3 Spalten (Ordnerleiste + Liste + Detail) – Einstellung je Gerät.
//    Bei 3 Spalten steht die Ordnerleiste dauerhaft, auch ohne
//    ausgewählte Mail; der Knopf für die einblendbare Leiste entfällt.
//  - Hochformat: 2 Spalten (Liste + Detail).
//  - In beiden Ausrichtungen schaltet ein Knopf in der Detailansicht
//    auf Vollbild und zurück.
//  Alle Zustände nutzen dasselbe Spaltengerüst; nur die Breiten ändern
//  sich. Die Liste wird dabei nie neu angelegt (siehe `regularColumns`).
//  Die geöffnete Mail ist in der Liste hinterlegt; Pfeile in der
//  Mailansicht und die Pfeiltasten schalten zur vorigen bzw. nächsten
//  Mail, nach Löschen oder Verschieben rückt die nächste nach
//  (MessageStepping). Bei drei Spalten lassen sich Mails auf einen Ordner
//  der festen Leiste ziehen. Auf dem iPhone bleibt die Navigation
//  unverändert (Push per NavigationStack).
//
//  Mac: Das Fenster übernimmt das Spaltengerüst des iPad
//  (`macColumns`) mit festen Breiten – Ordnerleiste 280 pt, Liste 380 pt
//  neben einer geöffneten Mail, Mailansicht mindestens 450 pt. Ohne
//  geöffnete Mail reicht die Liste bis zum rechten Rand, es gibt keinen
//  Platzhalter. Beim Verkleinern verschwindet erst die feste
//  Ordnerleiste (dann einblendbar), darunter gilt eine Spalte wie auf dem
//  iPhone mit Zurück-Knopf in der Mailansicht (Stufen: MacColumnLayout).
//  Die System-Symbolleiste entfällt (Fensterstil ohne Titelleiste, siehe
//  MailwerkApp); über der Liste steht eine eigene Kopfleiste mit Knöpfen,
//  Titel, Stand und bei Bedarf dem Suchfeld (MacListHeaderBar,
//  MacSearchField), über der Mailansicht die Kopfleiste der Mail
//  (MacDetailHeaderBar). Der Ordner-Knopf bzw. ⌥⌘S schaltet die feste
//  Ordnerleiste bzw. öffnet die einblendbare. Die Liste arbeitet wie im
//  Spaltengerüst des iPad (`usesColumns`): Ein Klick wählt die Zeile und
//  öffnet die Mail rechts, die Pfeiltasten bewegen die Auswahl, Mails
//  lassen sich auf einen Ordner der festen Leiste ziehen, ein Rechtsklick
//  öffnet das Kontextmenü, und die Zeile unter dem Mauszeiger ist dezent
//  hervorgehoben. Mehrfachauswahl wie in Apple Mail (`macSelection`,
//  Regeln in MacListSelection): ⌘-Klick wählt einzelne Mails dazu,
//  ⇧-Klick einen Bereich, ⌘A alle; bei mehreren zeigt die Mailansicht
//  „n Mails ausgewählt“, und Kontextmenü (MessageSelectionMenuItems) bzw.
//  Entf-Taste wirken auf alle ausgewählten Mails. Den Auswahlmodus von
//  iPhone/iPad gibt es auf dem Mac nicht. Treffer der Serversuche öffnen sich in der Mailansicht
//  (`selectedServerHit`).
//
//  Alle Layouts verwenden dieselbe Liste und dieselbe Zeile; sie
//  unterscheiden sich darin, wie ein Tipp die Mail öffnet (`usesColumns`)
//  und wo die Knöpfe stehen. Abruf, Beobachter und Blätter hängen
//  gemeinsam am äußeren Element.
//
//  Menübefehle und Tastaturkürzel (iPhone/iPad mit Tastatur, Mac) stehen in
//  InboxCommands; die Liste stellt dafür ihre Aktionen bereit
//  (`commandActions`). Die zusätzlichen Befehle des Mac (Sidebar,
//  Alle E-Mails auswählen, Postfächer) stehen in MacMenuCommands
//  (`macMenuActions`).
//
//  ViewModel und Ordnerkatalog legt die App einmal beim Start an und
//  reicht sie herein. Würde die Ansicht sie selbst im `init` erzeugen,
//  entstünde bei jedem Neuaufbau durch SwiftUI ein weiteres, sofort
//  verworfenes ViewModel samt Laden der Liste aus dem Cache.
//
//  Meldungen und Rückfragen laufen über je einen Kanal (`alertItem`,
//  `confirmationRequest`, siehe Dialogs.swift).
//
//  „Auf iPhone fortfahren“ von der Apple Watch (Handoff, WatchHandoff)
//  öffnet die dort offene Mail als Blatt über der Liste.
//
//  Jedes Blatt meldet sich als offenes Fenster (`countsAsOpenWindow`),
//  damit ein mailto:-Link von außen erst danach eine neue Mail öffnet
//  (ExternalMailtoRouter).
//
//  Abgrenzung: Zustand, Abruf und Aktionen an Mails im InboxViewModel,
//  Aufbau einer Zeile in MessageRow, Mailansicht in MessageDetailView,
//  Ordnerleiste in FolderSidebarView.
//
//  Abhängigkeiten: InboxViewModel, MessageStore, MailActionService,
//  FolderCatalog, NetworkMonitor, MessageRow, MessageRowParty,
//  ContactImageDirectory, SenderIconCache, FilterListCloudEvents,
//  MessageDetailView, MessageMenu, MessageActionDialogs, FolderMoveSheet,
//  MessageSelection, SelectionActionBar, MessageSort, SearchIndexBuilder,
//  SearchViewModel, SearchPerson, ServerMessageLoader, MessageStepping,
//  ComposeView, DraftComposeLoader, Dialogs, AppTheme, ListBottomBar,
//  UndoOffer, OAuthSignInState, SignInRequiredBar, ExternalMailtoPresenter,
//  WatchHandoff, AccountFetchState, AboutView (nur iPhone/iPad), MacMenuCommands, MacColumnLayout,
//  MacListHeaderBar, MacSearchField (nur Mac), Log.
//

import SwiftUI
import os

/// Hauptansicht mit der Nachrichtenliste.
struct InboxView: View {
    /// Quelle für Postfächer und Passwörter.
    let accountStore: AccountStore
    /// Black-/Whitelist für den Spamfilter.
    let filterLists: any FilterListRepository
    /// Einstellungen des Spamfilters.
    let spamSettings: SpamSettings
    /// Zustand der Liste. Wird einmal beim App-Start angelegt und hier
    /// nur verwendet – siehe `MailwerkApp`.
    @Bindable var viewModel: InboxViewModel
    /// Postfachverwaltung geöffnet.
    @State private var showingAccounts = false
    /// Spamfilter-Einstellungen geöffnet.
    @State private var showingSpamSettings = false
    /// „Über Mailwerk“ geöffnet (iPhone/iPad; der Mac hat ein eigenes Fenster).
    @State private var showingAbout = false
    /// Neue Mail wird verfasst.
    @State private var showingCompose = false
    /// Ordnerleiste eingeblendet.
    @State private var showingFolders = false
    /// Ordnerbäume der Postfächer; nur für diese App-Sitzung. Wird wie
    /// das ViewModel einmal beim App-Start angelegt.
    let folderCatalog: FolderCatalog
    /// In der Leiste aufgeklappte Postfächer. Bewusst nicht gespeichert:
    /// Nach einem Neustart ist wieder alles zugeklappt.
    @State private var expandedFolderAccounts: Set<UUID> = []
    /// Erster Abruf nach dem Start ist erfolgt.
    @State private var hasLoadedOnce = false
    /// Antwort bzw. Weiterleitung aus dem Kontextmenü.
    @State private var listCompose: ListComposeRequest?
    /// Breite der Ansicht – bestimmt die Mindestbreite des Titels.
    @State private var viewWidth: CGFloat = 0
    /// Entwurf, der zum Weiterbearbeiten geöffnet wird.
    @State private var draftToEdit: DraftEditRequest?
    /// Mail, die auf der Apple Watch offen war („Auf iPhone fortfahren“).
    @State private var handoffMessage: HandoffMessageRequest?
    /// Mail, für die aus dem Kontextmenü ein Zielordner gewählt wird.
    @State private var moveItem: MessageListItem?
    /// Rückfrage aus dem Kontextmenü (Löschen, Spam); einziger
    /// Rückfragekanal der Liste neben der Warteschlange der Spam-Ordner.
    @State private var listConfirmation: ConfirmationRequest?
    /// Ordnerwahl für die Mehrfachauswahl geöffnet.
    @State private var showingSelectionMove = false
    /// Netzzustand (online/offline).
    private let network = NetworkMonitor.shared
    /// Postfächer, deren Anmeldung abgelaufen ist.
    private let signInState = OAuthSignInState.shared
    /// Postfächer, deren letzter Abruf den Server nicht erreichte.
    private let fetchState = AccountFetchState.shared
    #if os(macOS)
    /// Feste Ordnerleiste eingeschaltet (Ordner-Knopf, ⌥⌘S in breiten
    /// Fenstern). Beim Start eingeschaltet.
    @State private var macSidebarEnabled = true
    /// Breite des Fensterinhalts – bestimmt die Stufe (MacColumnLayout).
    @State private var macWindowWidth: CGFloat = MacColumnLayout.defaultSize.width
    /// Anstoß für den Fokus im Suchfeld (⌘F, Lupe).
    @State private var searchFocusTick = 0
    /// In der Mailansicht geöffneter Treffer der Serversuche; `nil` = keiner.
    @State private var selectedServerHit: MessageListItem?
    /// Ausgewählte Mails der Liste (⌘-/⇧-Klick). Genau eine = die
    /// geöffnete Mail (`selectedMessageID`); mehrere = keine geöffnet,
    /// die Mailansicht zeigt die Anzahl.
    @State private var macSelection: Set<String> = []
    #endif
    /// Postfach, das gerade neu angemeldet wird; `nil` = keins.
    @State private var renewingAccountID: UUID?
    /// Zustand der Suche. Bewusst als `@State`: Das Anlegen ist billig
    /// (kein Laden im `init`), SwiftUI behält das erste Objekt.
    @State private var search: SearchViewModel

    // MARK: - iPad-Spaltenlayout

    /// Größenklasse: `.regular` auf dem iPad (quer und hoch), `.compact`
    /// auf dem iPhone. Auf dem Mac nicht gesetzt, dort steht immer das
    /// Spaltengerüst (`macColumns`).
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// Auf dem iPad im Querformat drei Spalten statt zwei. Einstellung je
    /// Gerät, über das Einstellungsmenü umschaltbar.
    @AppStorage("iPadLandscapeThreeColumns") private var usesThreeColumns = false
    /// ID der im Spaltengerüst geöffneten Mail; `nil` = keine Mail offen →
    /// Liste auf voller Breite (iPad und Mac).
    /// Auf dem iPhone immer `nil`.
    @State private var selectedMessageID: String?
    /// `true`, wenn die Detailansicht auf dem iPad den vollen Bildschirm
    /// einnimmt; der Knopf links oben bzw. Esc schaltet zurück.
    @State private var isDetailFullscreen = false
    /// `true` im Querformat; wird über `onGeometryChange` aktualisiert,
    /// damit kein veraltetes `UIScreen.main` nötig ist.
    @State private var isLandscape = false

    /// Übernimmt die beim App-Start angelegten Objekte.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Passwörter.
    ///   - filterLists: Black-/Whitelist für den Spamfilter.
    ///   - spamSettings: Einstellungen des Spamfilters.
    ///   - viewModel: Zustand der Liste.
    ///   - folderCatalog: Ordnerbäume der Postfächer.
    init(
        accountStore: AccountStore,
        filterLists: any FilterListRepository,
        spamSettings: SpamSettings,
        viewModel: InboxViewModel,
        folderCatalog: FolderCatalog
    ) {
        self.accountStore = accountStore
        self.filterLists = filterLists
        self.spamSettings = spamSettings
        self._viewModel = Bindable(viewModel)
        self.folderCatalog = folderCatalog
        self._search = State(initialValue: SearchViewModel(accountStore: accountStore))
    }

    /// Legt den Ordnerkatalog für die Ordnerleiste an.
    ///
    /// Verarbeitung: Der Katalog lädt Ordnerbäume vom Server und greift
    /// ohne Verbindung auf die zuletzt gespeicherte Ordnerliste zurück.
    /// Aufgerufen genau einmal beim App-Start (`MailwerkApp`), damit der
    /// Katalog nicht bei jedem Neuaufbau der Ansicht neu entsteht.
    ///
    /// - Parameter accountStore: Quelle für Postfächer und Passwörter.
    /// - Returns: Neuer Ordnerkatalog.
    static func makeFolderCatalog(accountStore: AccountStore) -> FolderCatalog {
        FolderCatalog(
            loader: { account in
                try await MailActionService.fetchFolderTree(for: account, accountStore: accountStore)
            },
            cached: { account in
                // Im Hintergrund lesen und aufbauen (v0.2.3d).
                await MailActionService.cachedFolderTree(accountID: account.id, spamFolder: account.spamFolder)
            }
        )
    }

    /// Zeile „Ältere Nachrichten laden" am Listenende.
    private var olderRow: some View {
        OlderMessagesRow(
            isLoading: viewModel.isLoadingOlder,
            isExhausted: viewModel.olderExhausted,
            isOnline: network.isOnline,
            connectionFailed: viewModel.olderConnectionFailed,
            nextDate: viewModel.nextOlderDate,
            action: { Task { await viewModel.loadOlder() } }
        )
    }

    /// Verbindungshinweis für die zweite Titelzeile, `nil` = alles in
    /// Ordnung. Regel siehe `AccountFetchState.titleStatus`.
    private var connectionStatus: String? {
        AccountFetchState.titleStatus(
            isOnline: network.isOnline,
            accounts: viewModel.viewAccounts.map { (id: $0.id, name: $0.displayName) },
            unreachable: fetchState.unreachable
        )
    }

    /// Ruft die gerade angezeigte Ansicht ab.
    ///
    /// Verarbeitung: Ein gewählter Ordner wird allein abgerufen, sonst
    /// alle Posteingänge samt Spam-Ordnern. In der Sicht „Ungelesen“ fallen
    /// dabei die schon gelesenen Mails heraus.
    @MainActor
    private func refreshCurrentView() async {
        if case .folder(let accountID, let path, _) = viewModel.selection {
            await viewModel.refreshFolder(accountID: accountID, path: path)
        } else {
            if viewModel.selection == .unread {
                viewModel.releaseKeptUnread()
            }
            await viewModel.refresh()
        }
    }

    /// Postfächer, deren Anmeldung abgelaufen ist, in ihrer Reihenfolge.
    private var expiredAccounts: [MailAccount] {
        accountStore.accounts.filter { signInState.isSignInRequired($0.id) }
    }

    /// Meldet ein Postfach neu an (Tipp auf die Hinweisleiste).
    ///
    /// Verarbeitung: Öffnet das Anmeldefenster des Anbieters. Gelingt die
    /// Anmeldung, verschwindet die Leiste und die Ansicht wird abgerufen
    /// (siehe `onChange` auf `signInRequired`). Schließt der Nutzer das
    /// Fenster, bleibt die Leiste ohne Meldung stehen; andere Fehler
    /// erscheinen als Meldung.
    ///
    /// - Parameter account: Postfach mit abgelaufener Anmeldung.
    @MainActor
    private func renewSignIn(_ account: MailAccount) async {
        guard renewingAccountID == nil else { return }
        renewingAccountID = account.id
        defer { renewingAccountID = nil }
        do {
            try await signInState.renewSignIn(for: account, accountStore: accountStore)
        } catch OAuthError.cancelled {
            return
        } catch {
            viewModel.alert = .failure("Anmeldung für „\(account.displayName)“", error)
        }
    }

    /// Farbe des Postfachs, wenn ein einzelner Ordner gewählt ist.
    private var selectedAccountColor: Color? {
        guard let id = viewModel.selection.accountID,
              let hex = accountStore.accounts.first(where: { $0.id == id })?.colorHex
        else { return nil }
        return Color(hex: hex)
    }

    /// Aufbau der Ansicht: auf dem iPhone der NavigationStack mit Push
    /// (`listStack`), auf dem iPad das Spaltengerüst (`regularColumns`),
    /// auf dem Mac das eigene Spaltengerüst mit Breitenstufen
    /// (`macColumns`).
    /// Alle zeigen dieselbe Liste; Abruf, Beobachter und Blätter hängen
    /// für alle gemeinsam am äußeren Element.
    var body: some View {
        withSheets(withSelectionTracking(withListLifecycle(layout)))
            // Einziger Meldungskanal der Liste – am äußeren Element,
            // getrennt von der Rückfrage (`withSheets`).
            .alertItem($viewModel.alert)
            // Einblendbare Ordnerleiste (iPhone, iPad mit zwei Spalten, Mac
            // in schmalen Fenstern).
            .sideDrawer(isPresented: $showingFolders) {
                folderSidebar(onClose: { showingFolders = false })
            }
            // Menübefehle und Tastaturkürzel (InboxCommands).
            .focusedSceneValue(\.inboxCommands, commandActions)
            #if os(macOS)
            // Mac: zusätzliche Menübefehle (MacMenuCommands).
            .focusedSceneValue(\.macMenuActions, macMenuActions)
            #endif
    }

    /// Grundaufbau je Plattform und Größenklasse.
    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if usesColumns {
            regularColumns
        } else {
            listStack
        }
        #else
        macColumns
        #endif
    }

    /// `true`, wenn die Liste im Spaltengerüst steht (iPad in breiten
    /// Fenstern und der Mac): Ein Tipp bzw. Klick zeigt die Mail rechts
    /// daneben statt per Push.
    private var usesColumns: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular
        #else
        return true
        #endif
    }

    /// Ordnerleiste – als einblendbare Leiste (`sideDrawer`) und als feste
    /// erste Spalte (iPad mit drei Spalten, Mac) derselbe Inhalt.
    ///
    /// - Parameters:
    ///   - acceptsDrops: `true`, wenn Mails auf Ordner gezogen werden
    ///     können – nur in der festen Spalte; die einblendbare Leiste
    ///     verdeckt die Liste.
    ///   - onClose: Schließt die Leiste nach einer Auswahl.
    /// - Returns: Die Ordnerleiste.
    private func folderSidebar(acceptsDrops: Bool = false, onClose: @escaping () -> Void) -> some View {
        let drop: ((MailAccount, FolderNode, [String]) -> Void)? = acceptsDrops
            ? { account, node, ids in dropMessages(ids, on: node, in: account) }
            : nil
        return FolderSidebarView(
            accounts: accountStore.accounts,
            pausedAccountIDs: accountStore.pausedAccountIDs,
            signInRequiredIDs: signInState.signInRequired,
            unreachableIDs: fetchState.unreachable,
            catalog: folderCatalog,
            expandedAccounts: $expandedFolderAccounts,
            selection: $viewModel.selection,
            unreadCount: viewModel.unreadCount,
            flaggedCount: viewModel.flaggedCount,
            onCreateFolder: { account, parentPath, name in
                _ = try await MailActionService.createFolder(
                    named: name,
                    parentPath: parentPath,
                    accountID: account.id,
                    accountStore: accountStore
                )
            },
            onDeleteFolder: { account, node in
                try await deleteFolder(node, in: account)
            },
            onClose: onClose,
            onDropMessages: drop
        )
    }

    // MARK: - Mailansicht

    /// Angaben für eine aus der Liste geöffnete Mail.
    ///
    /// - Parameter showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Postfächer, Spamfilter, Rückmeldung und Personensuche.
    private func detailContext(showsRecipients: Bool) -> MessageDetailContext {
        MessageDetailContext(
            accountStore: accountStore,
            spamFilter: viewModel.spamFilter,
            scoreLimit: spamSettings.scoreLimit,
            onChange: { viewModel.loadFromCache() },
            onSearchPerson: { startPersonSearch($0) },
            showsRecipients: showsRecipients
        )
    }

    /// Angaben für eine von der Watch übergebene Mail (Blatt über der
    /// Liste): ohne Personensuche, die Liste darunter ist verdeckt.
    private var handoffDetailContext: MessageDetailContext {
        MessageDetailContext(
            accountStore: accountStore,
            spamFilter: viewModel.spamFilter,
            scoreLimit: spamSettings.scoreLimit,
            onChange: { viewModel.loadFromCache() }
        )
    }

    /// Ein Servertreffer wurde geladen und liegt jetzt im Cache: Er wird
    /// zum lokalen Treffer.
    ///
    /// - Parameter hit: Geladener Treffer.
    private func serverHitLoaded(_ hit: MessageListItem) {
        search.removeServerHit(hit.id)
        viewModel.loadFromCache()
    }

    // MARK: - Abruf, Beobachter, Blätter

    /// Erster Abruf und Beobachter für Postfächer, Netz, Anmeldung und
    /// Suche – für beide Layouts gemeinsam.
    ///
    /// - Parameter content: Grundaufbau.
    /// - Returns: Aufbau mit Abruf und Beobachtern.
    private func withListLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .task { await initialLoad() }
            .onChange(of: accountStore.accounts.map(\.id)) { oldIDs, newIDs in
                // Neue Postfächer (beim ersten Start aus iCloud oder neu
                // eingerichtet): Liste zeigen und alle Posteingänge abrufen.
                // Reine Änderungen wie Name oder Farbe lösen nichts aus.
                guard !Set(newIDs).isSubset(of: Set(oldIDs)) else { return }
                viewModel.loadFromCache()
                Task { await viewModel.refresh() }
            }
            .onChange(of: showsRecipients, initial: true) { _, recipients in
                // „Von“ sortiert in Gesendet/Entwürfen nach dem Empfänger.
                viewModel.sortsByRecipients = recipients
            }
            .onReceive(FilterListCloudEvents.remoteChangesImported) {
                // Listen von einem anderen Gerät übernommen (Absenderbilder).
                viewModel.reloadFilterLists()
            }
            .onChange(of: network.isOnline) { wasOnline, isOnline in
                // Netz ist zurück: aktuelle Ansicht selbst abrufen.
                guard isOnline, !wasOnline else { return }
                Task { await refreshCurrentView() }
            }
            .onChange(of: signInState.signInRequired) { oldExpired, newExpired in
                // Wieder angemeldet (hier, unter „Postfach bearbeiten“ oder
                // über die Ordnerleiste): gleich abrufen.
                guard !oldExpired.isSubset(of: newExpired) else { return }
                Task { await refreshCurrentView() }
            }
            .onChange(of: accountStore.pausedAccountIDs) { oldPaused, newPaused in
                // Abruf ein-/ausgeschaltet: Sammelsichten neu zusammenstellen;
                // wieder eingeschaltete Postfächer gleich abrufen.
                updateSearchScope()
                viewModel.loadFromCache()
                guard !oldPaused.isSubset(of: newPaused) else { return }
                Task { await viewModel.refresh() }
            }
            .onChange(of: search.matchingIDs) { _, ids in
                viewModel.searchFilter = ids
            }
            .onChange(of: viewModel.cacheGeneration) {
                // Cache neu geladen (Abruf, Aktion, geladener Treffer).
                search.refreshLocal()
            }
            // Apple Watch: „Auf iPhone fortfahren“ öffnet die dort offene
            // Mail als Blatt über der Liste.
            .onContinueUserActivity(WatchHandoff.activityType) { activity in
                guard let id = activity.userInfo?[WatchHandoff.messageIDKey] as? String else { return }
                handoffMessage = HandoffMessageRequest(id: id)
            }
    }

    /// Erster Start der Liste: Hintergrundaufgaben anstoßen, Liste aus dem
    /// Cache zeigen, dann abrufen – nur beim ersten Erscheinen.
    ///
    /// Verarbeitung: Kontaktbilder laden parallel zum Abruf, damit die
    /// Systemabfrage zur Berechtigung den Abruf nicht aufhält. Fehlende
    /// Einträge im Suchindex werden im Hintergrund nachgetragen – das erste
    /// Anfassen der Ablage öffnet die Datenbank (Prüfbericht P-18). Die
    /// Web-Ansicht wird vorgewärmt, sobald die Liste steht; die erste
    /// geöffnete Mail spart dann den Start des WebKit-Prozesses (P-12).
    /// Erst die Liste aus dem Cache, dann der Abruf – sonst konkurrieren
    /// beide beim Start um den Hauptthread (P-18).
    @MainActor
    private func initialLoad() async {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        Task { await ContactImageDirectory.shared.start() }
        Task.detached(priority: .utility) {
            await SearchIndexBuilder.run(store: MessageStore.shared)
        }
        Task {
            try? await Task.sleep(for: Self.webViewPrewarmDelay)
            MailWebViewPool.shared.prewarm()
        }
        await viewModel.waitForFirstList()
        await viewModel.refresh()
    }

    /// Wartezeit nach dem Start, bis die Web-Ansicht vorgewärmt wird – die
    /// Liste soll zuerst stehen.
    private static let webViewPrewarmDelay: Duration = .seconds(1)

    /// Beobachter für die gewählte Ansicht und die geöffnete Mail.
    ///
    /// Verarbeitung: Ein Ordnerwechsel lädt den Ordner nach und schließt
    /// die geöffnete Mail. Verschwindet die geöffnete Mail aus der Liste
    /// (gelöscht, verschoben), rückt die nächste nach (MessageStepping).
    /// Wird das Fenster schmal (Größenklasse kompakt), gilt wieder die
    /// Push-Navigation – die Auswahl der Spaltenansicht entfällt.
    ///
    /// - Parameter content: Aufbau.
    /// - Returns: Aufbau mit Beobachtern.
    private func withSelectionTracking<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: viewModel.selection, initial: true) {
                updateSearchScope()
            }
            .onChange(of: viewModel.selection) { _, newSelection in
                closeSelectedMessage()
                // Cache sofort zeigen (didSet in selection), dann im
                // Hintergrund vom Server nachladen.
                if case .folder(let accountID, let path, _) = newSelection {
                    Task { await viewModel.refreshFolder(accountID: accountID, path: path) }
                    // Ausgeschaltetes Postfach: Ordnerliste jetzt mit laden.
                    if !accountStore.isFetchEnabled(accountID),
                       let account = accountStore.accounts.first(where: { $0.id == accountID }) {
                        Task { await folderCatalog.retry(account) }
                    }
                }
            }
            .onChange(of: viewModel.messages) { oldMessages, newMessages in
                #if os(macOS)
                pruneMacSelection()
                #endif
                guard selectedMessageID != nil else { return }
                let next = MessageStepping.replacement(
                    for: selectedMessageID,
                    oldIDs: oldMessages.map(\.id),
                    newIDs: newMessages.map(\.id)
                )
                if next == nil {
                    closeSelectedMessage()
                } else {
                    selectedMessageID = next
                }
            }
            #if os(iOS)
            .onChange(of: horizontalSizeClass) { _, sizeClass in
                if sizeClass != .regular { closeSelectedMessage() }
            }
            #endif
            #if os(macOS)
            .onChange(of: selectedMessageID) { _, id in
                // Eine Mail der Liste ersetzt einen geöffneten Servertreffer.
                if id != nil { selectedServerHit = nil }
                // Weiterschalten, Nachrücken nach Löschen: Die Auswahl der
                // Liste folgt der geöffneten Mail.
                if let id, macSelection != [id] { macSelection = [id] }
            }
            #endif
    }

    /// Blätter und Rückfrage der Liste – für beide Layouts gemeinsam.
    ///
    /// - Parameter content: Aufbau.
    /// - Returns: Aufbau mit Blättern.
    private func withSheets<Content: View>(_ content: Content) -> some View {
        withMessageSheets(withSettingsSheets(content))
    }

    /// Blätter für Postfächer, Spam-Einstellungen und „Über“ samt Rückfrage.
    ///
    /// - Parameter content: Aufbau.
    /// - Returns: Aufbau mit Blättern.
    private func withSettingsSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showingAccounts) {
                AccountListView(accountStore: accountStore)
                    .countsAsOpenWindow()
            }
            .confirmationRequest(confirmation)
            .sheet(isPresented: $showingSpamSettings, onDismiss: {
                // Listen können sich geändert haben (Absenderbilder).
                viewModel.reloadFilterLists()
            }) {
                SpamSettingsView(settings: spamSettings, filterLists: filterLists)
                    .countsAsOpenWindow()
            }
            #if os(iOS)
            .sheet(isPresented: $showingAbout) {
                AboutView()
                    .countsAsOpenWindow()
            }
            #endif
    }

    /// Blätter rund um Mails: Verfassen, Antworten/Weiterleiten, Entwurf,
    /// Übergabe von der Watch und Verschieben.
    ///
    /// - Parameter content: Aufbau.
    /// - Returns: Aufbau mit Blättern.
    private func withMessageSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showingCompose) {
                // Absender: Postfach des gezeigten Ordners; Sammelansichten
                // (z. B. „Alle Eingänge“) haben keines → Standard-Postfach.
                ComposeView(
                    accountStore: accountStore,
                    kind: .new,
                    senderAccountID: viewModel.selection.accountID,
                    onSent: { viewModel.loadFromCache() }
                )
                .countsAsOpenWindow()
            }
            .sheet(item: $listCompose) { request in
                ComposeView(
                    accountStore: accountStore,
                    kind: request.kind,
                    original: request.original,
                    onSent: { viewModel.loadFromCache() }
                )
                .countsAsOpenWindow()
            }
            .sheet(item: $handoffMessage) { request in
                handoffSheet(request)
            }
            .sheet(item: $draftToEdit) { request in
                DraftComposeLoader(
                    messageID: request.id,
                    accountStore: accountStore,
                    onSent: { refreshAfterDraft() }
                )
                .countsAsOpenWindow()
            }
            .sheet(isPresented: $showingSelectionMove) {
                selectionMoveSheet
                    .countsAsOpenWindow()
            }
            .sheet(item: $moveItem) { item in
                moveSheet(for: item)
            }
    }

    /// Von der Watch übergebene Mail als Blatt mit „Fertig“.
    ///
    /// - Parameter request: Übergebene Mail.
    /// - Returns: Blatt mit der Mailansicht.
    private func handoffSheet(_ request: HandoffMessageRequest) -> some View {
        NavigationStack {
            MessageDetailLoader(messageID: request.id, context: handoffDetailContext)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") { handoffMessage = nil }
                    }
                }
        }
        .countsAsOpenWindow()
    }

    /// Ordnerauswahl zum Verschieben einer Mail.
    ///
    /// - Parameter item: Zu verschiebende Mail.
    /// - Returns: Blatt mit der Ordnerauswahl ihres Postfachs.
    private func moveSheet(for item: MessageListItem) -> some View {
        Group {
            if let account = accountStore.accounts.first(where: { $0.id == item.accountID }) {
                FolderMoveSheet(
                    account: account,
                    currentFolder: item.folder,
                    accountStore: accountStore
                ) { path in
                    Task { await viewModel.move(item, to: path) }
                }
            }
        }
        .countsAsOpenWindow()
    }

    // MARK: - Liste

    /// Liste im NavigationStack. Auf dem iPhone öffnet ein Tipp die Mail per
    /// Push; im Spaltengerüst des iPad steht derselbe Stapel links – dort
    /// öffnen nur noch die Treffer der Serversuche per Push. Auf dem Mac
    /// ohne NavigationStack: Ein Stapel brächte eine System-Symbolleiste
    /// mit; die Servertreffer öffnen sich dort in der Mailansicht.
    @ViewBuilder
    private var listStack: some View {
        #if os(macOS)
        listContent
        #else
        NavigationStack {
            listContent
        }
        #endif
    }

    /// Liste samt Lade- und Leerzustand, Suchfeld, Symbolleiste,
    /// Rückgängig-Balken und unterer Leiste.
    private var listContent: some View {
        // WICHTIG: Jeder Zweig dieser Group muss genau EIN View liefern.
        // Modifier an einer Group wirken auf jedes Kind einzeln – bei
        // zwei Kindern erschiene z. B. die Toolbar doppelt.
        Group {
            // Ladeanzeige auch, bis die Liste das erste Mal aus dem Cache
            // gelesen ist (läuft im Hintergrund) – sonst blitzte kurz
            // „Keine Mails“ auf.
            if viewModel.messages.isEmpty && (viewModel.isLoading || !viewModel.hasLoadedCache) {
                InitialLoadingView()
            } else if viewModel.messages.isEmpty && !search.isPresented {
                EmptyMailboxView(
                    selection: viewModel.selection,
                    hasAccounts: !accountStore.accounts.isEmpty
                ) {
                    // Auch ein leerer Ordner kann ältere Mails haben
                    // (z. B. ein Archiv ohne Eingänge im Standardfenster).
                    if viewModel.showsOlderRow && !accountStore.accounts.isEmpty {
                        olderRow
                            .padding(.horizontal)
                    }
                }
            } else {
                messageList
            }
        }
        // Getönte Fläche hinter Liste, Lade- und Leerzustand.
        .appBackground()
        #if os(iOS)
        // iPhone/iPad: Aktualisieren durch Herunterziehen der Liste.
        // Auf dem Mac gibt es dafür einen eigenen Knopf (MacListHeaderBar).
        .refreshable {
            await refreshCurrentView()
        }
        #endif
        // Feine Linie als Abgrenzung unter der Überschrift, darunter
        // ggf. die Hinweise „Anmeldung abgelaufen“.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                ForEach(expiredAccounts) { account in
                    SignInRequiredBar(
                        accountName: account.displayName,
                        isRenewing: renewingAccountID == account.id,
                        onRenew: { Task { await renewSignIn(account) } }
                    )
                    Divider()
                }
            }
        }
        #if os(macOS)
        // Mac: eigene Kopfleiste (Knöpfe, Titel und Stand, Suchfeld) über
        // den Hinweisleisten – statt System-Symbolleiste und `.searchable`.
        .safeAreaInset(edge: .top, spacing: 0) {
            macListHeader
        }
        #else
        .searchable(
            text: $search.text,
            tokens: $search.tokens,
            isPresented: $search.isPresented,
            placement: Self.searchPlacement,
            prompt: "Suchen"
        ) { person in
            Label(person.title, systemImage: "person.fill")
        }
        .searchSuggestions {
            ForEach(search.suggestions) { person in
                PersonSuggestionRow(person: person)
                    .searchCompletion(person)
            }
        }
        // Die obere Leiste (Ordner, Titel, Einstellungen bzw. „Alle
        // auswählen“ und „Fertig“) bleibt während der Suche stehen –
        // iOS blendet sie sonst aus.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        #endif
        // Mac: Titel nur für Fenstermenü und Mission Control; angezeigt
        // wird er in der eigenen Kopfleiste.
        .navigationTitle(viewModel.selection.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewWidth = $0 }
        #if !os(macOS)
        .toolbar { listToolbar }
        #endif
        // „Rückgängig“ über der unteren Leiste: Als Überlagerung des
        // Inhalts hält es den sicheren Bereich ein und verdeckt die
        // Knöpfe nicht.
        .overlay(alignment: .bottom) {
            if let offer = viewModel.undoOffer {
                UndoBar(
                    text: offer.text,
                    systemImage: offer.systemImage,
                    duration: UndoOffer.duration,
                    onUndo: { Task { await viewModel.undo(offer) } },
                    onDismiss: { viewModel.dismissUndo() }
                )
                // Neues Angebot = neuer Balken, der Lauf beginnt von vorn.
                .id(offer.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, AppSpacing.medium)
                .padding(.horizontal, AppSpacing.large)
            }
        }
        .animation(AppAnimation.standard, value: viewModel.undoOffer?.id)
        // Untere Leiste bzw. Befehlsleiste im Auswahlmodus – schwebt
        // über der Liste am unteren Rand.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomInset
        }
        .animation(AppAnimation.standard, value: viewModel.isSelecting)
        .animation(AppAnimation.standard, value: search.isPresented)
    }

    // MARK: - Spaltengerüst (iPad)

    /// `true`, wenn die Ordnerleiste fest als erste Spalte steht.
    ///
    /// Verarbeitung: Im Spaltengerüst, im Querformat und mit der
    /// Einstellung „Drei Spalten“ steht die Leiste dauerhaft – auch ohne
    /// geöffnete Mail, damit sie beim Ordnerwechsel nicht verschwindet. Nur
    /// im Vollbild der Detailansicht tritt sie zurück.
    private var showsPermanentSidebar: Bool {
        usesColumns && isLandscape && usesThreeColumns
            && !(selectedMessageID != nil && isDetailFullscreen)
    }

    /// Schließt die geöffnete Mail (Mac: auch einen geöffneten
    /// Servertreffer); die Liste nimmt wieder die volle Breite ein.
    private func closeSelectedMessage() {
        selectedMessageID = nil
        isDetailFullscreen = false
        #if os(macOS)
        selectedServerHit = nil
        macSelection = []
        #endif
    }

    /// Geöffnete Mail als Listeneintrag; `nil` = keine oder nicht mehr in
    /// der Liste.
    private var selectedMessageItem: MessageListItem? {
        guard let id = selectedMessageID else { return nil }
        return viewModel.visibleMessages.first { $0.id == id }
    }

    /// Öffnet die vorige bzw. nächste Mail der Liste.
    ///
    /// Verarbeitung: Nur im Spaltengerüst, nicht im Auswahlmodus und nicht
    /// in Entwürfen (dort öffnet ein Tipp das Verfassen-Fenster). Ohne
    /// geöffnete Mail beginnt es bei der ersten Zeile.
    ///
    /// - Parameter direction: Richtung.
    private func stepMessage(_ direction: MessageStepping.Direction) {
        guard let id = steppingTarget(direction) else { return }
        selectedMessageID = id
    }

    /// Ziel beim Weiterschalten.
    ///
    /// - Parameter direction: Richtung.
    /// - Returns: ID der Nachbarmail; `nil` = keine bzw. Weiterschalten
    ///   gerade nicht möglich.
    private func steppingTarget(_ direction: MessageStepping.Direction) -> String? {
        guard usesColumns, !viewModel.isSelecting, !showsDrafts else { return nil }
        return MessageStepping.neighbor(
            of: selectedMessageID,
            in: viewModel.visibleMessages.map(\.id),
            direction: direction
        )
    }

    /// Verschiebt auf einen Ordner gezogene Mails.
    ///
    /// Verarbeitung: Nur Mails aus der Liste, nur innerhalb des Postfachs
    /// und nur in gültige Ordner (MessageSelection.dropTargets). Wird eine
    /// Mail auf einen Ordner eines anderen Postfachs gezogen, erklärt eine
    /// Meldung, warum nichts geschieht.
    ///
    /// - Parameters:
    ///   - ids: Gezogene Kennungen.
    ///   - node: Zielordner.
    ///   - account: Postfach des Zielordners.
    private func dropMessages(_ ids: [String], on node: FolderNode, in account: MailAccount) {
        let items = MessageSelection.dropTargets(
            ids: ids, in: viewModel.messages, accountID: account.id, folder: node
        )
        guard !items.isEmpty else {
            let dragged = Set(ids)
            if viewModel.messages.contains(where: { dragged.contains($0.id) && $0.accountID != account.id }) {
                viewModel.alert = AlertItem(
                    title: "Nicht verschoben",
                    message: "Mails lassen sich nur in Ordner desselben Postfachs verschieben."
                )
            }
            return
        }
        for item in items {
            Task { await viewModel.move(item, to: node.id) }
        }
    }

    // MARK: - Spaltengerüst (Mac)

    #if os(macOS)
    /// Breitenstufe des Fensters (MacColumnLayout).
    private var macStage: MacColumnLayout.Stage {
        MacColumnLayout.stage(width: macWindowWidth, sidebarEnabled: macSidebarEnabled)
    }

    /// `true`, wenn die Ordnerleiste sichtbar ist – fest als Spalte oder
    /// eingeblendet (Beschriftung des Befehls in „Darstellung“).
    private var isSidebarVisible: Bool {
        macStage == .threeColumns || showingFolders
    }

    /// Ordner-Knopf bzw. ⌥⌘S.
    ///
    /// Verarbeitung: In breiten Fenstern (ab 1110 pt) wird die feste
    /// Ordnerleiste ein- bzw. ausgeschaltet; in schmaleren öffnet bzw.
    /// schließt sich die einblendbare Leiste (MacColumnLayout).
    private func toggleFolders() {
        switch MacColumnLayout.folderButtonAction(width: macWindowWidth) {
        case .toggleSidebar:
            showingFolders = false
            withAnimation(AppAnimation.standard) { macSidebarEnabled.toggle() }
        case .toggleDrawer:
            showingFolders.toggle()
        }
    }

    /// Öffnet einen Treffer der Serversuche in der Mailansicht.
    ///
    /// - Parameter hit: Treffer (noch nicht im Cache).
    private func openServerHit(_ hit: MessageListItem) {
        selectedMessageID = nil
        macSelection = []
        selectedServerHit = hit
    }

    // MARK: - Mehrfachauswahl (Mac)

    /// Auswahl der Liste auf dem Mac (Mehrfachauswahl mit ⌘ und ⇧).
    private var macListSelection: Binding<Set<String>> {
        Binding(
            get: { macSelection },
            set: { applyMacSelection($0) }
        )
    }

    /// Ausgewählte Mails, wenn es mehrere sind; sonst leer (eine einzelne
    /// ist die geöffnete Mail).
    private var macMultiSelection: [MessageListItem] {
        guard macSelection.count > 1 else { return [] }
        return viewModel.visibleMessages.filter { macSelection.contains($0.id) }
    }

    /// Übernimmt eine neue Auswahl: keine Mail → Mailansicht schließen,
    /// eine → öffnen, mehrere → „n Mails ausgewählt“ (MacListSelection).
    ///
    /// - Parameter ids: Von der Liste gemeldete Kennungen.
    private func applyMacSelection(_ ids: Set<String>) {
        let outcome = MacListSelection.outcome(
            for: ids,
            visibleIDs: viewModel.visibleMessages.map(\.id)
        )
        switch outcome {
        case .ignore:
            return
        case .empty:
            closeSelectedMessage()
        case .open(let id):
            macSelection = [id]
            selectedMessageID = id
        case .multiple(let mails):
            macSelection = mails
            selectedMessageID = nil
            selectedServerHit = nil
        }
    }

    /// Entfernt Mails, die nicht mehr in der Liste stehen, aus einer
    /// Mehrfachauswahl (nach Löschen, Verschieben, Abruf). Eine einzelne
    /// geöffnete Mail regelt das Nachrücken (`MessageStepping`).
    private func pruneMacSelection() {
        guard macSelection.count > 1 else { return }
        let kept = MacListSelection.pruned(macSelection, visibleIDs: viewModel.visibleMessages.map(\.id))
        if kept != macSelection { applyMacSelection(kept) }
    }

    /// Kontextmenü der Liste: für eine Mail das volle Menü, für mehrere
    /// ausgewählte die Sammelaktionen. Ein Rechtsklick auf eine nicht
    /// ausgewählte Zeile gilt nur für diese.
    ///
    /// - Parameter ids: Zeilen, für die das Menü gilt.
    /// - Returns: Einträge; leer bei Zeilen ohne Mail (Serversuche).
    @ViewBuilder
    private func macContextMenu(for ids: Set<String>) -> some View {
        let items = viewModel.visibleMessages.filter { ids.contains($0.id) }
        if items.count == 1, let item = items.first {
            MessageMenuItems(
                context: MessageMenuContext(item),
                onAction: { handleMenuAction($0, for: item) }
            ) {
                EmptyView()
            }
        } else if items.count > 1 {
            MessageSelectionMenuItems(items: items) { action in
                handleSelectionMenuAction(action, for: items)
            }
        }
    }

    /// Führt eine Aktion des Kontextmenüs für mehrere Mails aus – über die
    /// Sammelaktionen des ViewModels (dieselben wie die Befehlsleiste auf
    /// iPhone/iPad, mit „Rückgängig“).
    ///
    /// - Parameters:
    ///   - action: Gewählte Aktion.
    ///   - items: Betroffene Mails.
    private func handleSelectionMenuAction(_ action: MessageMenuAction, for items: [MessageListItem]) {
        viewModel.selectedIDs = Set(items.map(\.id))
        switch action {
        case .toggleFlag:
            runSelectionAction { await viewModel.toggleFlagForSelection() }
        case .toggleRead:
            runSelectionAction { await viewModel.toggleReadForSelection() }
        case .move:
            showingSelectionMove = true
        case .delete:
            confirmDeleteSelection()
        case .select, .reply, .spam:
            break
        }
    }

    /// Mailansicht bei mehreren ausgewählten Mails: Anzahl statt Mail.
    ///
    /// - Parameters:
    ///   - count: Anzahl ausgewählter Mails.
    ///   - onBack: Zurück-Knopf (eine Spalte); `nil` = keiner.
    /// - Returns: Platzhalter über die ganze Fläche.
    private func macMultiSelectionPlaceholder(count: Int, onBack: (() -> Void)?) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: "rectangle.stack")
                .font(.largeTitle)
            Text("\(count) Mails ausgewählt")
                .font(.title3)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let onBack {
                Button("Zurück", systemImage: "chevron.left", action: onBack)
                    .padding(AppSpacing.medium)
            }
        }
    }

    /// Aktionen für die zusätzlichen Menübefehle des Mac (MacMenuCommands).
    ///
    /// Verarbeitung: Eine Aktion fehlt (`nil`), solange sie nicht möglich
    /// ist – der Befehl ist dann ausgegraut. „Alle E-Mails auswählen“ gibt
    /// es nicht in Entwürfen, dort öffnet ein Klick die Mail zum
    /// Weiterbearbeiten; sonst wählt es alle Mails der Liste aus
    /// (`macSelection`).
    private var macMenuActions: MacMenuActions {
        MacMenuActions(
            toggleSidebar: { toggleFolders() },
            isSidebarVisible: isSidebarVisible,
            selectAll: InboxCommandActions.enabled(!viewModel.visibleMessages.isEmpty && !showsDrafts) {
                applyMacSelection(Set(viewModel.visibleMessages.map(\.id)))
            },
            showAccounts: { showingAccounts = true }
        )
    }

    /// Spaltengerüst des Mac: Ordnerleiste, Liste, Mailansicht – mit
    /// festen Breiten wie auf dem iPad und Stufen je Fensterbreite.
    ///
    /// Verarbeitung: Die Aufteilung liefert MacColumnLayout. Die Liste
    /// behält in allen Stufen ihre Identität (Ausblenden per Breite 0 und
    /// Deckkraft, kein Austausch des Ansichtsbaums) – Suchzustand und
    /// Scrollposition bleiben erhalten. Ohne geöffnete Mail reicht sie bis
    /// zum rechten Rand. Die feste Ordnerleiste nimmt gezogene Mails an.
    /// Wird sie sichtbar, schließt sich eine eingeblendete Leiste.
    private var macColumns: some View {
        let hasDetail = selectedMessageID != nil || selectedServerHit != nil || macSelection.count > 1
        let columns = MacColumnLayout.columns(
            width: macWindowWidth,
            sidebarEnabled: macSidebarEnabled,
            hasMessage: hasDetail
        )
        return HStack(spacing: 0) {
            if columns.showsSidebar {
                folderSidebar(acceptsDrops: true, onClose: {})
                    .frame(width: MacColumnLayout.sidebarWidth)
                    .background(AppTheme.background)
                Divider()
            }
            listStack
                .frame(width: columns.listWidth)
                .frame(maxWidth: columns.listWidth == nil ? .infinity : nil)
                .opacity(columns.showsList ? 1 : 0)
                .allowsHitTesting(columns.showsList)
                .accessibilityHidden(!columns.showsList)
            if columns.showsDetail {
                if columns.showsList {
                    Divider()
                }
                macDetailView(onBack: columns.showsBackButton ? { closeSelectedMessage() } : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Nebelblau auch hinter Spaltengrenzen und der Zeile der
        // Fensterknöpfe.
        .background(AppTheme.background.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            macWindowWidth = width
        }
        .onChange(of: columns.showsSidebar) { _, shows in
            if shows { showingFolders = false }
        }
    }

    /// Mailansicht des Mac: die geöffnete Mail bzw. ein Treffer der
    /// Serversuche, jeweils mit eigener Kopfleiste; bei mehreren
    /// ausgewählten Mails deren Anzahl.
    ///
    /// - Parameter onBack: Zurück-Knopf (eine Spalte); `nil` = keiner.
    /// - Returns: Mailansicht.
    @ViewBuilder
    private func macDetailView(onBack: (() -> Void)?) -> some View {
        if let id = selectedMessageID {
            MessageDetailLoader(
                messageID: id,
                context: detailContext(showsRecipients: showsRecipients),
                onBack: onBack,
                placeholderAccountID: selectedMessageItem?.accountID
            )
            // Eigene Identität je Mail: Der Loader lädt nur einmal; ohne
            // `.id` bliebe beim Klick auf eine andere Mail die alte stehen.
            .id(id)
        } else if let hit = selectedServerHit {
            ServerMessageLoader(
                hit: hit,
                context: detailContext(showsRecipients: showsRecipients),
                onReturn: { serverHitLoaded(hit) },
                onBack: onBack
            )
            .id(hit.id)
        } else if macSelection.count > 1 {
            macMultiSelectionPlaceholder(count: macSelection.count, onBack: onBack)
        }
    }

    /// Kopfleiste über der Liste (Mac): Knöpfe, Titel mit Stand und das
    /// Suchfeld.
    private var macListHeader: some View {
        let statusText: (() -> String)? = viewModel.syncState.map { state in
            { InboxTitle.statusText(state, connectionStatus: connectionStatus) }
        }
        return MacListHeaderBar(
            title: viewModel.selection.title,
            systemImage: viewModel.selection.systemImage,
            accountColor: selectedAccountColor,
            statusText: statusText,
            statusIsWarning: connectionStatus != nil,
            onFolders: { toggleFolders() },
            isLoading: viewModel.isLoading,
            canRefresh: !accountStore.accounts.isEmpty,
            onRefresh: {
                guard !viewModel.isLoading else { return }
                Task { await refreshCurrentView() }
            },
            isSortChanged: !viewModel.sort.isStandard,
            onSearch: { openSearch() },
            canCompose: !accountStore.accounts.isEmpty,
            onCompose: { showingCompose = true },
            search: search,
            searchFocusTrigger: searchFocusTick,
            sortMenu: { sortMenuContent },
            settingsMenu: { settingsMenuContent }
        )
    }
    #endif

    #if os(iOS)
    /// Spaltengerüst des iPad: optionale Ordnerleiste, Liste, Detail.
    ///
    /// Verarbeitung: Alle drei Zustände (Liste allein, Spalten, Vollbild)
    /// verwenden denselben Aufbau; es ändern sich nur Rahmenbreiten und
    /// eingeblendete Nachbarn. Die Liste behält damit ihre Identität –
    /// NavigationStack, Suchfeld und Scrollposition werden beim Antippen
    /// einer Mail nicht verworfen. Ein Austausch des ganzen Ansichtsbaums
    /// mitten in der Berührung kann unter iOS einen Übergang hängen lassen,
    /// danach nimmt die App keine Eingaben mehr an.
    private var regularColumns: some View {
        let hasMessage = selectedMessageID != nil
        let showsList = !(hasMessage && isDetailFullscreen)
        return HStack(spacing: 0) {
            if showsPermanentSidebar {
                folderSidebar(acceptsDrops: true, onClose: {})
                    .frame(width: 280)
                    .background(AppTheme.background)
                Divider()
            }
            // Mailliste: ohne Mail volle Breite, sonst feste Breite,
            // im Vollbild Breite null (bleibt aber bestehen).
            listStack
                // Ausblenden per Deckkraft statt `.clipped()`: Das
                // Abschneiden träfe auch die getönte Fläche unter der
                // Statusleiste, die dann weiß erschiene.
                .frame(width: regularListWidth(hasMessage: hasMessage, showsList: showsList))
                .frame(maxWidth: hasMessage ? nil : .infinity)
                .opacity(showsList ? 1 : 0)
                .allowsHitTesting(showsList)
                .accessibilityHidden(!showsList)
            if hasMessage {
                if showsList {
                    Divider()
                }
                NavigationStack {
                    regularDetailView
                }
            }
        }
        // Getönte Fläche auch hinter Spaltengrenzen und Statusleiste.
        .background(AppTheme.background.ignoresSafeArea())
        // Ausrichtung aus der tatsächlichen Fenstergröße ableiten (auch
        // korrekt bei Split View / Stage Manager).
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width > proxy.size.height
        } action: { landscape in
            isLandscape = landscape
        }
        // Wird die feste Ordnerleiste sichtbar, ist die einblendbare
        // überflüssig – sonst lägen zwei gleiche Leisten übereinander.
        .onChange(of: showsPermanentSidebar) { _, permanent in
            if permanent { showingFolders = false }
        }
    }

    /// Breite der Mailliste im Spaltengerüst.
    ///
    /// - Parameters:
    ///   - hasMessage: `true`, wenn eine Mail geöffnet ist.
    ///   - showsList: `false` im Vollbild der Detailansicht.
    /// - Returns: Breite in Punkt; `nil` = volle Breite (keine Mail).
    private func regularListWidth(hasMessage: Bool, showsList: Bool) -> CGFloat? {
        guard hasMessage else { return nil }
        guard showsList else { return 0 }
        return isLandscape ? 380 : 320
    }

    /// Detailansicht im Spaltengerüst: die geöffnete Mail mit Knöpfen für
    /// Vollbild sowie vorige und nächste Mail.
    @ViewBuilder
    private var regularDetailView: some View {
        if let id = selectedMessageID {
            MessageDetailLoader(
                messageID: id,
                context: detailContext(showsRecipients: showsRecipients),
                onToggleFullscreen: {
                    withAnimation(AppAnimation.standard) {
                        isDetailFullscreen.toggle()
                    }
                },
                isFullscreen: isDetailFullscreen,
                stepping: stepButtons
            )
            // Eigene Identität je Mail: Der Loader lädt nur einmal; ohne
            // `.id` bliebe beim Antippen einer anderen Mail die alte stehen.
            .id(id)
        }
    }

    #endif

    /// Pfeile „Vorige/Nächste E-Mail“ der Mailansicht; ohne Ziel (Anfang
    /// bzw. Ende der Liste) ausgegraut.
    private var stepButtons: MessageStepButtons {
        let previous: (() -> Void)? = steppingTarget(.previous) == nil
            ? nil
            : { stepMessage(.previous) }
        let next: (() -> Void)? = steppingTarget(.next) == nil
            ? nil
            : { stepMessage(.next) }
        return MessageStepButtons(previous: previous, next: next)
    }

    /// Aktionen für Menübefehle und Tastaturkürzel (InboxCommands).
    ///
    /// Verarbeitung: Eine Aktion fehlt (`nil`), solange sie nicht möglich
    /// ist – der Befehl ist dann samt Kürzel ausgegraut. Weiterschalten und
    /// Löschen gibt es nur im Spaltengerüst (iPad, Mac), Vollbild nur auf
    /// dem iPad. Steht der Cursor im Suchfeld, behalten Pfeiltasten dort
    /// ihre Bedeutung beim Schreiben.
    private var commandActions: InboxCommandActions {
        InboxCommandActions(
            newMail: InboxCommandActions.enabled(!accountStore.accounts.isEmpty) {
                showingCompose = true
            },
            refresh: InboxCommandActions.enabled(!viewModel.isLoading && !accountStore.accounts.isEmpty) {
                Task { await refreshCurrentView() }
            },
            search: {
                openSearch()
            },
            nextMail: InboxCommandActions.enabled(steppingTarget(.next) != nil) {
                stepMessage(.next)
            },
            previousMail: InboxCommandActions.enabled(steppingTarget(.previous) != nil) {
                stepMessage(.previous)
            },
            deleteMail: InboxCommandActions.enabled(canDeleteFromCommand) {
                deleteFromCommand()
            },
            exitFullscreen: InboxCommandActions.enabled(isDetailFullscreen && selectedMessageID != nil && !showingFolders) {
                withAnimation(AppAnimation.standard) { isDetailFullscreen = false }
            }
        )
    }

    /// `true`, wenn Entf bzw. „Löschen“ im Menü etwas löscht: die
    /// geöffnete Mail im Spaltengerüst oder (Mac) mehrere ausgewählte.
    private var canDeleteFromCommand: Bool {
        guard usesColumns, !viewModel.isSelecting else { return false }
        #if os(macOS)
        if !macMultiSelection.isEmpty { return true }
        #endif
        return selectedMessageItem != nil
    }

    /// Löscht nach Rückfrage die geöffnete Mail bzw. (Mac) alle
    /// ausgewählten Mails.
    private func deleteFromCommand() {
        #if os(macOS)
        let items = macMultiSelection
        if !items.isEmpty {
            handleSelectionMenuAction(.delete, for: items)
            return
        }
        #endif
        if let item = selectedMessageItem {
            handleMenuAction(.delete, for: item)
        }
    }

    // MARK: - Symbolleiste

    #if !os(macOS)
    /// Symbolleiste (iPhone/iPad): im Auswahlmodus „Alle auswählen“, Anzahl
    /// und „Fertig“, sonst Ordnerleiste, Titel und Einstellungen; Sortieren,
    /// Suche und Verfassen stehen in der eigenen unteren Leiste.
    /// Steht die Ordnerleiste fest als erste Spalte (iPad mit drei
    /// Spalten), entfällt der Knopf für die einblendbare Leiste. Auf dem
    /// iPad bieten die Einstellungen im Spaltengerüst zusätzlich „Drei
    /// Spalten im Querformat“. Der Mac hat keine Symbolleiste, sondern
    /// eine eigene Kopfleiste (`macListHeader`).
    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        if viewModel.isSelecting {
            ToolbarItem(placement: Self.leadingPlacement) {
                Button(viewModel.isAllSelected ? "Auswahl aufheben" : "Alle auswählen") {
                    viewModel.toggleSelectAll()
                }
            }
            ToolbarItem(placement: .principal) {
                Text("\(viewModel.selectedIDs.count) ausgewählt")
                    .font(.subheadline.weight(.semibold))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    withAnimation(AppAnimation.standard) { viewModel.endSelection() }
                }
            }
        } else {
            if !showsPermanentSidebar {
                ToolbarItem(placement: Self.leadingPlacement) {
                    Button {
                        showingFolders = true
                    } label: {
                        Label("Ordner", systemImage: "sidebar.left")
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                // Die Ladeanzeige steht in der Titelzeile, nicht als eigenes
                // Element: So bleibt die Leiste immer gleich aufgebaut und
                // das System ordnet keine Knöpfe um.
                InboxTitle(
                    selection: viewModel.selection,
                    accountColor: selectedAccountColor,
                    syncState: viewModel.syncState,
                    connectionStatus: connectionStatus,
                    isLoading: viewModel.isLoading && !viewModel.messages.isEmpty,
                    minWidth: max(0, viewWidth - Self.toolbarButtonsWidth)
                )
            }
            // Die untere Leiste ist ein Eigenbau (ListBottomBar, siehe
            // `bottomInset`); das Suchfeld steht oben unter dem Titel
            // (`searchPlacement`).
            ToolbarItem {
                Menu {
                    settingsMenuContent
                } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
            }
        }
    }
    #endif

    /// Inhalt des Einstellungsmenüs: Postfächer, Spamfilter; auf dem iPad
    /// im Spaltengerüst zusätzlich „Drei Spalten im Querformat“; auf
    /// iPhone/iPad zuletzt „Über Mailwerk“ (der Mac bietet es im Menü
    /// „Mailwerk“).
    @ViewBuilder
    private var settingsMenuContent: some View {
        Button {
            showingAccounts = true
        } label: {
            Label("Postfächer", systemImage: "envelope")
        }
        Button {
            showingSpamSettings = true
        } label: {
            Label("Spamfilter", systemImage: "shield")
        }
        #if os(iOS)
        if usesColumns {
            Divider()
            Toggle(isOn: $usesThreeColumns) {
                Label("Drei Spalten im Querformat", systemImage: "rectangle.split.3x1")
            }
        }
        Divider()
        Button {
            showingAbout = true
        } label: {
            Label("Über Mailwerk", systemImage: "info.circle")
        }
        #endif
    }

    // MARK: - Sortieren und Verfassen

    /// Inhalt des Sortiermenüs: oben die Richtung, darunter das Feld; die
    /// aktive Wahl trägt ein Häkchen.
    @ViewBuilder
    private var sortMenuContent: some View {
        Picker("Richtung", selection: $viewModel.sort.ascending) {
            Text("Aufsteigend").tag(true)
            Text("Absteigend").tag(false)
        }
        .pickerStyle(.inline)
        Picker("Sortieren nach", selection: $viewModel.sort.field) {
            ForEach(MessageSort.Field.allCases) { field in
                Text(field.title(showsRecipients: showsRecipients)).tag(field)
            }
        }
        .pickerStyle(.inline)
    }

    /// Untere Leiste auf iPhone/iPad (Eigenbau, siehe ListBottomBar):
    /// Sortieren, Suche als großer Kreis, Neue Mail.
    private var listBottomBar: some View {
        ListBottomBar(
            isComposeEnabled: !accountStore.accounts.isEmpty,
            onSearch: { search.isPresented = true },
            onCompose: { showingCompose = true }
        ) {
            Menu {
                sortMenuContent
            } label: {
                SortBarLabel(isChanged: !viewModel.sort.isStandard)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    /// Inhalt am unteren Rand: im Auswahlmodus die Befehlsleiste, sonst auf
    /// iPhone/iPad die untere Leiste – außer während einer Suche, dann
    /// gehört der untere Rand der Tastatur bzw. den Treffern.
    @ViewBuilder
    private var bottomInset: some View {
        if viewModel.isSelecting {
            selectionBar
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            #if os(iOS)
            if !search.isPresented {
                listBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #endif
        }
    }

    // MARK: - Suche

    /// Öffnet das Suchfeld (Suchkreis, Lupe, ⌘F).
    ///
    /// Verarbeitung: Auf dem Mac erhält das Feld den Fokus, auch wenn es
    /// schon offen ist; in der einspaltigen Darstellung schließt sich eine
    /// geöffnete Mail, damit die Liste mit dem Feld zu sehen ist.
    private func openSearch() {
        #if os(macOS)
        prepareMacSearch()
        #endif
        search.isPresented = true
    }

    #if os(macOS)
    /// Bereitet auf dem Mac das Öffnen der Suche vor: Fokus ins Feld, in der
    /// einspaltigen Darstellung die Mail schließen.
    private func prepareMacSearch() {
        if macStage == .singleColumn {
            closeSelectedMessage()
        }
        searchFocusTick += 1
    }
    #endif

    /// Startet die Suche nach einer Person aus dem Mailkopf („Suchen nach …“).
    ///
    /// Verarbeitung: Die Mail schließt sich zuerst (animiert); das Suchfeld
    /// öffnet sich erst danach, weil iOS ein Öffnen während des
    /// Zurückgehens übergeht. Auf dem Mac öffnet sich die Suchzeile über
    /// der Liste mit der Person als Marke.
    ///
    /// - Parameter person: Gesuchte Person.
    private func startPersonSearch(_ person: SearchPerson) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            #if os(macOS)
            prepareMacSearch()
            #endif
            search.startSearch(for: person)
        }
    }

    /// Setzt den Suchbereich auf die gezeigte Ansicht.
    private func updateSearchScope() {
        search.updateScope(
            for: viewModel.selection,
            fetchingAccountIDs: accountStore.fetchingAccounts.map(\.id),
            spamFolders: viewModel.spamFolders
        )
    }

    /// Abschnitt „Auf dem Server“: Knopf zum Weitersuchen, Ladeanzeige
    /// bzw. die Treffer, die nicht im Cache liegen.
    ///
    /// - Parameters:
    ///   - colors: Farbe je Postfach.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Der Abschnitt.
    private func serverSection(colors: [UUID: String], showsRecipients: Bool) -> some View {
        Section {
            switch search.serverState {
            case .idle:
                // Gleiche Gestaltung wie „Ältere Nachrichten laden“;
                // offline ausgegraut mit Hinweis.
                ServerSearchRow(
                    isSearching: false,
                    isOnline: network.isOnline,
                    action: { search.searchServer() }
                )
            case .searching:
                ServerSearchRow(isSearching: true, isOnline: network.isOnline, action: {})
            case .done(let hasMore, let unreachable):
                ForEach(search.serverHits) { hit in
                    serverHitRow(hit, colorHex: colors[hit.accountID], showsRecipients: showsRecipients)
                }
                serverSearchNotes(hasMore: hasMore, unreachable: unreachable)
            }
        } header: {
            Text("Auf dem Server")
        }
        .cardRowBackground()
    }

    /// Zeile eines Treffers der Serversuche. Auf dem Mac öffnet er sich in
    /// der Mailansicht neben der Liste (kein NavigationStack), sonst per
    /// Push; geladen wird er erst beim Öffnen (`ServerMessageLoader`).
    ///
    /// - Parameters:
    ///   - hit: Treffer.
    ///   - colorHex: Farbe des Postfachs; `nil` = keine.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Die Zeile.
    @ViewBuilder
    private func serverHitRow(_ hit: MessageListItem, colorHex: String?, showsRecipients: Bool) -> some View {
        #if os(macOS)
        Button {
            openServerHit(hit)
        } label: {
            rowContent(for: hit, colorHex: colorHex, showsRecipients: showsRecipients)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #else
        NavigationLink {
            ServerMessageLoader(
                hit: hit,
                context: detailContext(showsRecipients: showsRecipients),
                onReturn: { serverHitLoaded(hit) }
            )
        } label: {
            rowContent(for: hit, colorHex: colorHex, showsRecipients: showsRecipients)
        }
        #endif
    }

    /// Hinweise unter den Servertreffern: keine weiteren Treffer, Suche
    /// verfeinern, nicht erreichbare Postfächer (mit „erneut versuchen“).
    ///
    /// - Parameters:
    ///   - hasMore: Es gab mehr Treffer als gezeigt.
    ///   - unreachable: Anzahl nicht erreichbarer Postfächer.
    /// - Returns: Die Hinweise.
    @ViewBuilder
    private func serverSearchNotes(hasMore: Bool, unreachable: Int) -> some View {
        if search.serverHits.isEmpty {
            Text("Keine weiteren Treffer auf dem Server")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if hasMore {
            Text("Weitere Treffer – Suche verfeinern")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if unreachable > 0 {
            Button("Nicht alle Postfächer erreichbar – erneut versuchen") {
                search.searchServer()
            }
            .font(.footnote)
            .foregroundStyle(network.isOnline ? Color.accentColor : Color.secondary)
            .disabled(!network.isOnline)
        }
    }

    // MARK: - Mehrfachauswahl

    /// Befehlsleiste für die Auswahl; Symbole passend zur Auswahl.
    private var selectionBar: some View {
        let items = viewModel.selectedItems
        return SelectionActionBar(
            flagEntry: MessageMenuLabels.flag(
                isFlagged: MessageSelection.flagChange(for: items) == .flagged(false)
            ),
            readEntry: MessageMenuLabels.read(
                isUnread: MessageSelection.readChange(for: items) == .read(true)
            ),
            hasSelection: !items.isEmpty,
            canMove: MessageSelection.canMove(items),
            onFlag: { runSelectionAction { await viewModel.toggleFlagForSelection() } },
            onRead: { runSelectionAction { await viewModel.toggleReadForSelection() } },
            onMove: { showingSelectionMove = true },
            onDelete: { confirmDeleteSelection() }
        )
    }

    /// Fragt nach, ob die ausgewählten Mails (`viewModel.selectedIDs`)
    /// gelöscht werden sollen, und löscht sie dann.
    private func confirmDeleteSelection() {
        listConfirmation = MessageActionDialogs.deleteConfirmation(count: viewModel.selectedItems.count) {
            runSelectionAction { await viewModel.deleteSelection() }
        }
    }

    /// Startet eine Sammelaktion. Das Ende des Auswahlmodus animiert die
    /// Ansicht selbst (`animation(value: isSelecting)`).
    ///
    /// - Parameter action: Sammelaktion des ViewModels.
    private func runSelectionAction(_ action: @escaping @MainActor () async -> Void) {
        Task { await action() }
    }

    /// Ordnerwahl für die Auswahl: Postfach der ausgewählten Mails, der
    /// gemeinsame Ordner ist ausgegraut.
    @ViewBuilder
    private var selectionMoveSheet: some View {
        let items = viewModel.selectedItems
        if MessageSelection.canMove(items),
           let accountID = items.first?.accountID,
           let account = accountStore.accounts.first(where: { $0.id == accountID }) {
            FolderMoveSheet(
                account: account,
                currentFolder: MessageSelection.commonFolder(items) ?? "",
                accountStore: accountStore
            ) { path in
                runSelectionAction { await viewModel.moveSelection(to: path) }
            }
        }
    }

    // MARK: - Nachrichtenliste

    /// Liste der Nachrichten samt Zeile „Ältere Nachrichten laden“. Im
    /// Auswahlmodus mit Auswahlkreisen; die Zeile „Ältere“ entfällt dann.
    /// Während einer Suche nur die Treffer, darunter statt „Ältere“ der
    /// Abschnitt „Auf dem Server“.
    ///
    /// Im Spaltengerüst ist die geöffnete Mail die Auswahl der Liste
    /// (`columnSelection`): Ein Tipp wählt sie aus, und die Pfeiltasten
    /// bewegen die Auswahl über die Tastaturnavigation des Systems – wie in
    /// Apple Mail. Die Liste rollt mit, wenn die Mail per Pfeil-Knopf oder
    /// nach dem Löschen wechselt. Ränder und Zeilenabstände sind dort fest
    /// (`ColumnListMargins`), damit nichts springt, wenn die Liste von
    /// voller Breite auf Spaltenbreite wechselt. Im Auswahlmodus und in
    /// Entwürfen gilt die gewöhnliche Liste. Der Mac wählt mit ⌘ und ⇧
    /// mehrere Mails (`macListSelection`); das Kontextmenü hängt dort an der
    /// Liste und gilt für die Auswahl (`macContextMenu`).
    ///
    /// Eigene Eigenschaft statt Teil von `body`, damit der Compiler den
    /// Ausdruck in vertretbarer Zeit prüfen kann.
    private var messageList: some View {
        ScrollViewReader { proxy in
            Group {
                #if os(macOS)
                // Entwürfe: Ein Klick öffnet das Verfassen-Fenster, keine
                // Auswahl; das Kontextmenü braucht trotzdem eine Bindung.
                List(selection: showsDrafts ? Binding<Set<String>>.constant([]) : macListSelection) {
                    messageListRows
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    macContextMenu(for: ids)
                }
                #else
                if usesColumns && !viewModel.isSelecting && !showsDrafts {
                    List(selection: columnSelection) {
                        messageListRows
                    }
                } else {
                    List(selection: listSelection) {
                        messageListRows
                    }
                }
                #endif
            }
            .modifier(ColumnListMargins(isActive: usesColumns))
            #if os(iOS)
            // Auswahlmodus: Kreise vor den Zeilen, Tipp wählt aus statt zu öffnen.
            .environment(\.editMode, .constant(viewModel.isSelecting ? .active : .inactive))
            #endif
            .onChange(of: selectedMessageID) { _, id in
                guard let id else { return }
                withAnimation(AppAnimation.quick) { proxy.scrollTo(id) }
            }
        }
    }

    /// Zeilen der Liste – für beide Varianten der Liste dieselben.
    @ViewBuilder
    private var messageListRows: some View {
        let colors = accountColors
        let recipients = showsRecipients
        let drafts = showsDrafts
        let columns = usesColumns
        ForEach(viewModel.visibleMessages) { message in
            messageRow(
                for: message,
                colorHex: colors[message.accountID],
                showsRecipients: recipients,
                opensDraft: drafts
            )
            // Ausgewählte (grau) bzw. geöffnete Zeilen (hellblau) tönt
            // die Karte selbst – die eigene Zeilenfarbe ersetzt die
            // Auswahlfarbe des Systems. Auf dem Mac tönt sie zusätzlich die
            // Zeile unter dem Mauszeiger.
            #if os(macOS)
            .modifier(HoverCardRowBackground(isOpened: macSelection.contains(message.id)))
            #else
            .cardRowBackground(
                isSelected: viewModel.isSelecting && viewModel.selectedIDs.contains(message.id),
                isOpened: !viewModel.isSelecting && message.id == selectedMessageID
            )
            #endif
            .modifier(ColumnRowInsets(isActive: columns))
        }

        // Letzte Zeile der Liste – gehört IN die List, damit
        // der Zweig ein einzelnes View bleibt.
        if search.isFiltering {
            if viewModel.visibleMessages.isEmpty {
                Text("Keine Treffer auf diesem Gerät")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .modifier(ColumnRowInsets(isActive: columns))
                    .cardRowBackground()
            }
            if search.offersServerSearch && !viewModel.isSelecting {
                serverSection(colors: colors, showsRecipients: recipients)
                    .modifier(ColumnRowInsets(isActive: columns))
            }
        } else if viewModel.showsOlderRow && !viewModel.isSelecting {
            Section {
                olderRow
                    .modifier(ColumnRowInsets(isActive: columns))
            }
            .cardRowBackground()
        } else if let note = completeListNote, !viewModel.isSelecting {
            // Statt „Ältere laden“: Diese Sichten sind schon vollständig.
            Section {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.small)
                    .modifier(ColumnRowInsets(isActive: columns))
            }
            .cardRowBackground()
        }
    }

    #if os(iOS)
    /// Auswahl der Liste im Spaltengerüst (iPad): die geöffnete Mail.
    ///
    /// Verarbeitung: Ein Tipp oder eine Pfeiltaste setzt die Auswahl und
    /// öffnet damit die Mail rechts; hebt die Liste die Auswahl auf, schließt
    /// sich die Mail.
    private var columnSelection: Binding<String?> {
        Binding(
            get: { selectedMessageID },
            set: { id in
                if id == nil {
                    closeSelectedMessage()
                } else {
                    selectedMessageID = id
                }
            }
        )
    }
    #endif

    /// Hinweis am Listenende der Sichten, die jeder Abruf unabhängig vom
    /// Alter vollständig holt („Ungelesen“, „Mit Kennzeichnung“) – dort
    /// gibt es kein „Ältere laden“; der Hinweis zeigt, dass nichts fehlt.
    /// `nil` in allen anderen Ansichten.
    private var completeListNote: String? {
        switch viewModel.selection {
        case .unread:  return "Alle ungelesenen Nachrichten – unabhängig vom Alter"
        case .flagged: return "Alle gekennzeichneten Nachrichten – unabhängig vom Alter"
        case .allInboxes, .spam, .folder: return nil
        }
    }

    #if os(iOS)
    /// Auswahlbindung der Liste (iPhone/iPad): nur im Auswahlmodus; die
    /// Liste zeichnet dann Auswahlkreise.
    private var listSelection: Binding<Set<String>>? {
        viewModel.isSelecting ? $viewModel.selectedIDs : nil
    }
    #endif

    /// Farbe je Postfach – einmal je Listenaufbau statt einer Suche je Zeile.
    /// Postfächer ohne Farbe fehlen.
    private var accountColors: [UUID: String] {
        Dictionary(
            accountStore.accounts.compactMap { account in
                account.colorHex.map { (account.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// `true`, wenn die gezeigte Ansicht ein Gesendet- oder Entwürfe-Ordner
    /// ist – dort zeigen die Zeilen den Empfänger statt des Absenders.
    ///
    /// Die Rolle kommt aus dem Ordnerbaum des Postfachs; die Ansicht wird
    /// über die Ordnerleiste gewählt, der Baum liegt dann vor.
    private var showsRecipients: Bool {
        guard case .folder(let accountID, let path, _) = viewModel.selection,
              case .loaded(let tree) = folderCatalog.state(for: accountID),
              let role = tree.node(withPath: path)?.role else { return false }
        return role == .sent || role == .drafts
    }

    /// Aktualisiert die Liste nach Senden oder Sichern eines Entwurfs.
    ///
    /// Verarbeitung: Die alte Fassung ist schon aus dem Cache entfernt; die
    /// neu gesicherte kommt erst mit einem Abruf des Ordners. Deshalb wird
    /// der gezeigte Ordner gleich neu abgerufen.
    private func refreshAfterDraft() {
        viewModel.loadFromCache()
        guard case .folder(let accountID, let path, _) = viewModel.selection else { return }
        Task { await viewModel.refreshFolder(accountID: accountID, path: path) }
    }

    /// `true`, wenn die gezeigte Ansicht ein Entwürfe-Ordner ist – dort
    /// öffnet ein Tipp die Mail zum Weiterbearbeiten statt zum Lesen.
    private var showsDrafts: Bool {
        guard case .folder(let accountID, let path, _) = viewModel.selection,
              case .loaded(let tree) = folderCatalog.state(for: accountID) else { return false }
        return tree.node(withPath: path)?.role == .drafts
    }

    /// Eine Zeile der Liste: öffnet die Mail, Wischaktionen, Kontextmenü,
    /// Sperre während einer laufenden Aktion.
    ///
    /// Verarbeitung: Auf dem iPhone öffnet ein Link `MessageDetailLoader`
    /// per Push; im Spaltengerüst (iPad, Mac) zeigt ein Tipp bzw. Klick die
    /// Mail in der Detailspalte – die Liste wählt die Zeile aus
    /// (`columnSelection`), auch per Pfeiltaste –, und die Zeile lässt sich
    /// auf einen Ordner der festen Ordnerleiste ziehen. Im
    /// Entwürfe-Ordner öffnet ein Tipp stattdessen das Verfassen-Fenster
    /// (`DraftComposeLoader`). Der Loader lädt die vollständige Mail erst
    /// beim Öffnen aus dem Cache.
    ///
    /// - Parameters:
    ///   - message: Darzustellender Listeneintrag.
    ///   - colorHex: Farbe des Postfachs; `nil` = keine Farbe gewählt.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    ///   - opensDraft: `true` im Entwürfe-Ordner.
    /// - Returns: Die fertige Zeile.
    private func messageRow(
        for message: MessageListItem,
        colorHex: String?,
        showsRecipients: Bool,
        opensDraft: Bool
    ) -> some View {
        rowLink(for: message, colorHex: colorHex, showsRecipients: showsRecipients, opensDraft: opensDraft)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await viewModel.toggleRead(message) }
                } label: {
                    Label(
                        message.isUnread ? "Gelesen" : "Ungelesen",
                        systemImage: message.isUnread ? "envelope.open" : "envelope.badge"
                    )
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    Task { await viewModel.toggleFlag(message) }
                } label: {
                    Label(
                        message.isFlagged ? "Entflaggen" : "Flaggen",
                        systemImage: message.isFlagged ? "flag.slash" : "flag"
                    )
                }
                .tint(.orange)
            }
            #if os(iOS)
            // Mac: Kontextmenü an der Liste (`macContextMenu`), damit es
            // für alle ausgewählten Mails gilt.
            .contextMenu {
                MessageMenuItems(
                    context: MessageMenuContext(message),
                    showsSelect: true,
                    onAction: { handleMenuAction($0, for: message) }
                ) {
                    EmptyView()
                }
            }
            #endif
            // Ziehen auf einen Ordner nur, wo die feste Ordnerleiste daneben
            // stehen kann (Spaltengerüst von iPad und Mac), und nicht im
            // Auswahlmodus.
            .modifier(MessageDragSource(
                messageID: message.id,
                isEnabled: usesColumns && !viewModel.isSelecting
            ))
            .disabled(viewModel.processingMessageIDs.contains(message.id))
    }

    /// Inhalt einer Zeile je nach Lage: im Auswahlmodus ohne Link, im
    /// Entwürfe-Ordner als Knopf (Verfassen-Fenster), im Spaltengerüst
    /// ohne eigenen Knopf (die Liste wählt aus), sonst als Link zur Mail.
    ///
    /// - Parameters:
    ///   - message: Listeneintrag.
    ///   - colorHex: Farbe des Postfachs; `nil` = keine.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    ///   - opensDraft: `true` im Entwürfe-Ordner.
    /// - Returns: Inhalt der Zeile.
    @ViewBuilder
    private func rowLink(
        for message: MessageListItem,
        colorHex: String?,
        showsRecipients: Bool,
        opensDraft: Bool
    ) -> some View {
        if viewModel.isSelecting {
            // Im Auswahlmodus kein Link: Ein Tipp wählt aus statt zu
            // öffnen. Die Auswahl selbst zeichnet die Liste (`listSelection`).
            rowContent(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
        } else if opensDraft {
            Button {
                draftToEdit = DraftEditRequest(id: message.id)
            } label: {
                rowContent(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if usesColumns {
            // Kein eigener Knopf: Die Liste wählt die Zeile aus
            // (`columnSelection`) – per Tipp wie per Pfeiltaste.
            rowContent(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
                .contentShape(Rectangle())
                #if os(iOS)
                // Normale Schriftfarben auch in der ausgewählten Zeile:
                // Das System stellt die Schrift sonst auf Weiß um,
                // passend zu seinem kräftigen Auswahlhintergrund –
                // unsere Karte hinterlegt aber hellblau
                // (`cardRowBackground`). Die Zeile färbt mit Stufen
                // (primär, sekundär); sie stehen hier fest auf den
                // Textfarben des Systems, statt sich von der Auswahl
                // abzuleiten.
                .foregroundStyle(
                    Color(uiColor: .label),
                    Color(uiColor: .secondaryLabel),
                    Color(uiColor: .tertiaryLabel)
                )
                #endif
        } else {
            NavigationLink {
                MessageDetailLoader(
                    messageID: message.id,
                    context: detailContext(showsRecipients: showsRecipients)
                )
            } label: {
                rowContent(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
            }
        }
    }

    /// Inhalt einer Zeile: Absenderbild, Namen, Datum, Betreff.
    ///
    /// - Parameters:
    ///   - message: Darzustellender Listeneintrag.
    ///   - colorHex: Farbe des Postfachs; `nil` = keine Farbe gewählt.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Die Zeile ohne Link.
    private func rowContent(
        for message: MessageListItem,
        colorHex: String?,
        showsRecipients: Bool
    ) -> some View {
        // Vorberechnet im ViewModel (Person, Bild-Erlaubnis, Spam-Hinweis).
        let model = viewModel.rowModel(for: message, showsRecipients: showsRecipients)
        // Bilder holt die Zeile selbst (nur bei Erlaubnis – Spam löst
        // keinen Logo-Abruf aus).
        return MessageRow(
            message: message,
            party: model.party,
            showsImage: model.showsImage,
            colorHex: colorHex,
            spamMark: model.spamMark
        )
        // Unveränderte Zeilen beim Neuzeichnen der Liste überspringen.
        .equatable()
    }

    // MARK: - Kontextmenü

    /// Führt eine Aktion aus dem Kontextmenü einer Mail aus.
    ///
    /// Verarbeitung: Antworten und Weiterleiten brauchen die vollständige
    /// Mail und laden sie aus dem Cache. Löschen und Spam-Aktionen fragen
    /// vorher nach; Verschieben öffnet die Ordnerwahl.
    ///
    /// - Parameters:
    ///   - action: Gewählte Aktion.
    ///   - item: Betroffener Listeneintrag.
    private func handleMenuAction(_ action: MessageMenuAction, for item: MessageListItem) {
        switch action {
        case .select:
            withAnimation(AppAnimation.standard) {
                viewModel.beginSelection(with: item.id)
            }
        case .reply(let kind):
            if let original = MessageStore.shared.message(id: item.id) {
                listCompose = ListComposeRequest(kind: kind, original: original)
            } else {
                viewModel.alert = AlertItem(
                    title: "Nachricht nicht mehr vorhanden",
                    message: "Sie wurde inzwischen gelöscht oder verschoben."
                )
            }
        case .toggleFlag:
            Task { await viewModel.toggleFlag(item) }
        case .toggleRead:
            Task { await viewModel.toggleRead(item) }
        case .move:
            moveItem = item
        case .spam(let request):
            listConfirmation = MessageActionDialogs.spamConfirmation(request) {
                Task { await viewModel.performSpamAction(request, for: item) }
            }
        case .delete:
            listConfirmation = MessageActionDialogs.deleteConfirmation(count: 1) {
                Task { await viewModel.delete(item) }
            }
        }
    }

    // MARK: - Ordner löschen

    /// Löscht einen leeren Ordner auf dem Server.
    ///
    /// Verarbeitung: Räumt danach seinen Cache ab und verlässt die Ansicht,
    /// falls sie gerade offen ist.
    ///
    /// - Parameters:
    ///   - node: Zu löschender Ordner.
    ///   - account: Postfach des Ordners.
    /// - Returns: Ergebnis auf dem Server (gelöscht, nicht gefunden …).
    /// - Throws: Verbindungs- oder Serverfehler.
    @MainActor
    private func deleteFolder(_ node: FolderNode, in account: MailAccount) async throws -> FolderDeletion.Outcome {
        let outcome = try await MailActionService.deleteFolder(
            node.id, accountID: account.id, accountStore: accountStore
        )
        if outcome.removesFolder {
            MessageStore.shared.deleteFolder(accountID: account.id, folder: node.id)
            if case .folder(let accountID, let path, _) = viewModel.selection,
               accountID == account.id, path == node.id {
                viewModel.selection = .allInboxes
            }
        }
        return outcome
    }

    // MARK: - Rückfragen

    /// Einziger Rückfragekanal der Liste: zuerst eine Rückfrage aus dem
    /// Kontextmenü, sonst die erste offene Frage „Spam-Ordner anlegen?“.
    ///
    /// Verarbeitung: Schließt sich die Rückfrage aus dem Kontextmenü, wird
    /// sie verworfen; die Warteschlange der Spam-Ordner räumt ihre Knöpfe
    /// selbst ab.
    private var confirmation: Binding<ConfirmationRequest?> {
        Binding(
            get: { listConfirmation ?? spamFolderConfirmation.wrappedValue },
            set: { newValue in
                if newValue == nil { listConfirmation = nil }
            }
        )
    }

    /// Rückfrage „Spam-Ordner anlegen?“ zur ersten offenen Anfrage.
    ///
    /// Verarbeitung: Die Anfragen stehen in einer Warteschlange des
    /// ViewModels; gezeigt wird immer die erste. Beide Knöpfe nehmen sie
    /// sofort aus der Warteschlange, damit sie nicht erneut erscheint,
    /// während das Anlegen noch läuft. „Nicht jetzt“ fragt für dieses
    /// Postfach in dieser Sitzung nicht wieder.
    private var spamFolderConfirmation: Binding<ConfirmationRequest?> {
        Binding(
            get: {
                viewModel.pendingSpamFolders.first.map { pending in
                    ConfirmationRequest(
                        id: "spamFolder-\(pending.account.id.uuidString)",
                        title: "Spam-Ordner anlegen?",
                        message: "Das Postfach „\(pending.account.displayName)“ hat keinen Spam-Ordner. Ohne ihn kann der Filter dort nichts aussortieren. Vorgeschlagen wird „\(pending.proposal)“.",
                        confirmLabel: "Anlegen",
                        isDestructive: false,
                        cancelLabel: "Nicht jetzt",
                        onCancel: {
                            viewModel.dismissSpamFolderRequest(pending, declineForSession: true)
                        },
                        onConfirm: {
                            viewModel.dismissSpamFolderRequest(pending, declineForSession: false)
                            Task { await viewModel.createSpamFolder(for: pending) }
                        }
                    )
                }
            },
            set: { _ in }
        )
    }

    // MARK: - Plattform

    #if !os(macOS)
    /// Platz, den die Knöpfe links und rechts samt Rändern in der
    /// Symbolleiste belegen. Der Rest der Breite ist die Mindestbreite des
    /// Titels: So ist er immer breiter als der Platz für einen zentrierten
    /// Titel, und iOS setzt ihn stets linksbündig statt je nach Länge mal
    /// mittig, mal links.
    private static let toolbarButtonsWidth: CGFloat = 200

    /// Platz des Suchfelds. iPhone/iPad: oben unter dem Titel – nur dort
    /// stellt iOS keinen eigenen Suchknopf in die untere Leiste, die
    /// Mailwerk selbst gestaltet (ListBottomBar). Geöffnet wird es über den
    /// Suchkreis unten; die Tastatur bleibt unten, die Bedienung damit
    /// einhändig. Der Mac hat ein eigenes Suchfeld (MacSearchField).
    private static var searchPlacement: SearchFieldPlacement {
        .navigationBarDrawer(displayMode: .automatic)
    }

    /// Platz links in der Symbolleiste (Ordnerleiste, „Alle auswählen“).
    /// Auf dem iPhone/iPad fest `.topBarLeading` – `.navigation` ist dort nur
    /// ein Wunsch, und iOS schob den Knopf beim Umbau der Leiste
    /// gelegentlich nach rechts.
    private static var leadingPlacement: ToolbarItemPlacement {
        .topBarLeading
    }
    #endif
}

/// Überschrift der Liste: klein, mit Symbol passend zur Auswahl.
/// Bei einem gewählten Ordner erscheint ein Farbpunkt des Postfachs.
/// Während eines Abrufs steht ein kleines Drehsymbol vor der Standzeile.
/// Eine Mindestbreite hält den Titel auf dem iPhone/iPad immer
/// linksbündig: iOS zentriert einen Titel nur, solange er zwischen die
/// Knöpfe passt, und rückt ihn sonst nach links – je nach Länge sprang er.
/// Auf dem Mac zeigt die eigene Kopfleiste Titel und Standzeile
/// (MacListHeaderBar); von hier kommt dort nur der Text der Standzeile
/// (`statusText`).
private struct InboxTitle: View {
    /// Gewählte Ansicht (Titel und Symbol).
    let selection: MailboxSelection
    /// Farbe des Postfachs bei einem einzelnen Ordner; sonst `nil`.
    var accountColor: Color?
    /// Stand der Ansicht; erscheint als zweite Zeile. Der untere
    /// Bildschirmrand bleibt so frei für die untere Leiste.
    var syncState: SyncState?
    /// „Offline“, „Keine Verbindung“ bzw. welche Postfächer nicht
    /// erreichbar sind (AccountFetchState.titleStatus), sonst `nil`.
    var connectionStatus: String?
    /// Ein Abruf läuft – kleines Drehsymbol vor der Standzeile.
    var isLoading = false
    /// Mindestbreite (iPhone/iPad): hält den Titel stets linksbündig.
    var minWidth: CGFloat = 0

    /// Titelzeile mit Symbol und darunter der Stand.
    var body: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: AppSpacing.small) {
                if let color = accountColor {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                }
                Image(systemName: selection.systemImage)
                    .foregroundStyle(.secondary)
                Text(selection.title)
            }
            .font(.subheadline.weight(.semibold))

            if let syncState {
                // Minütlich neu berechnen, damit „vor 5 Minuten" mitläuft.
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    HStack(spacing: AppSpacing.xSmall) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(Self.statusText(syncState, connectionStatus: connectionStatus))
                    }
                    .font(.caption2)
                    .foregroundStyle(connectionStatus == nil ? Color.secondary : Color.orange)
                }
            }
        }
        .lineLimit(1)
        .frame(minWidth: minWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        #else
        EmptyView()
        #endif
    }

    /// Text der Standzeile – auf iPhone/iPad unter dem Titel, auf dem Mac
    /// in der Kopfleiste der Liste. Eine Regel für beide, damit die Texte
    /// nie auseinanderlaufen.
    ///
    /// Verarbeitung: Die Zeitangabe („vor 5 Minuten“) gilt für den
    /// Zeitpunkt des Aufrufs; der Aufrufer ruft minütlich neu auf.
    ///
    /// - Parameters:
    ///   - state: Stand der Ansicht.
    ///   - connectionStatus: Verbindungshinweis; `nil` = keiner.
    /// - Returns: „Aktualisiert: …“ bzw. mit Verbindungshinweis.
    static func statusText(_ state: SyncState, connectionStatus: String?) -> String {
        switch (state, connectionStatus) {
        case (.at(let date), nil):
            return "Aktualisiert: \(date.formatted(.relative(presentation: .named)))"
        case (.at(let date), let status?):
            return "\(status) · Stand: \(date.formatted(.relative(presentation: .named)))"
        case (.never, nil):
            return "Noch nicht abgerufen"
        case (.never, let status?):
            return "\(status) · noch nicht abgerufen"
        }
    }
}

/// Namensvorschlag der Suche: Name fett, Adresse grau dahinter.
private struct PersonSuggestionRow: View {
    /// Vorgeschlagene Person.
    let person: SearchPerson

    /// Name und Adresse in einer Zeile.
    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            if let name = person.name {
                Text(name)
                    .fontWeight(.semibold)
                Text(person.address)
                    .foregroundStyle(.secondary)
            } else {
                Text(person.address)
            }
        }
        .lineLimit(1)
    }
}

/// Ladeanzeige, solange beim ersten Abruf noch keine Mail im Cache liegt.
private struct InitialLoadingView: View {
    /// Fortschrittsanzeige mit Hinweis.
    var body: some View {
        VStack(spacing: AppSpacing.xLarge) {
            ProgressView()
                .controlSize(.large)
            Text("Postfächer werden abgerufen …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Leere Liste: Hinweis passend zur Ansicht, darunter optional die Zeile
/// „Ältere Nachrichten laden“. Scrollbar, damit Herunterziehen zum
/// Abrufen auch bei leerer Liste funktioniert.
private struct EmptyMailboxView<Footer: View>: View {
    /// Gewählte Ansicht.
    let selection: MailboxSelection
    /// Mindestens ein Postfach ist eingerichtet.
    let hasAccounts: Bool
    /// Inhalt unter dem Hinweis (Zeile „Ältere Nachrichten laden“).
    @ViewBuilder let footer: () -> Footer

    /// Hinweis und Fußzeile, mindestens so hoch wie der verfügbare Platz.
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    ContentUnavailableView(
                        title,
                        systemImage: systemImage,
                        description: Text(hint)
                    )
                    footer()
                }
                .frame(minHeight: geo.size.height)
            }
        }
    }

    /// Symbol des Hinweises – das der Ansicht, bei Ordnern ein Fach.
    private var systemImage: String {
        if case .folder = selection { return "tray" }
        return selection.systemImage
    }

    /// Überschrift des Hinweises.
    private var title: String {
        switch selection {
        case .unread:  return "Keine ungelesenen Nachrichten"
        case .flagged: return "Keine gekennzeichneten Nachrichten"
        case .spam:    return "Kein Spam"
        case .allInboxes, .folder: return "Keine Nachrichten"
        }
    }

    /// Erklärender Text: was zu tun ist bzw. warum die Liste leer ist.
    private var hint: String {
        guard hasAccounts else { return "Richte zuerst ein Postfach ein." }
        switch selection {
        case .unread:
            return "In den Posteingängen ist alles gelesen."
        case .flagged:
            return "Kennzeichne Nachrichten, damit sie hier erscheinen."
        case .spam:
            return "Die Spam-Ordner der Postfächer sind leer."
        case .folder:
            return "Dieser Ordner enthält keine Nachrichten."
        case .allInboxes:
            return "Zieh nach unten, um abzurufen."
        }
    }
}

/// Bewusste Aktion am Listenende: den nächsten älteren Zeitraum laden.
private struct OlderMessagesRow: View {
    /// Nachladen läuft.
    let isLoading: Bool
    /// Der Server hat nichts Älteres mehr.
    let isExhausted: Bool
    /// Gerät ist online.
    let isOnline: Bool
    /// Letzter Versuch scheiterte an der Verbindung.
    let connectionFailed: Bool
    /// Bis zu diesem Tag lädt ein Tipp mindestens.
    let nextDate: Date?
    /// Startet das Nachladen.
    let action: () -> Void

    /// Schaltfläche bzw. Hinweis „Keine älteren Nachrichten“.
    var body: some View {
        Group {
            if isExhausted {
                Text("Keine älteren Nachrichten")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button(action: action) {
                    HStack(spacing: AppSpacing.medium) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        VStack(alignment: .leading, spacing: AppSpacing.tiny) {
                            Text(isLoading ? "Ältere Nachrichten werden geladen …" : "Ältere Nachrichten laden")
                            if !isOnline {
                                Text("Offline – nicht verfügbar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if connectionFailed && !isLoading {
                                Text("Keine Verbindung – erneut versuchen")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else if let nextDate, !isLoading {
                                Text("bis \(nextDate, format: .dateTime.day().month(.abbreviated).year())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .disabled(isLoading || !isOnline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.small)
    }
}

/// Knopf „Auf dem Server weitersuchen“ am Ende der Treffer – gestaltet wie
/// „Ältere Nachrichten laden“: volle Breite, Symbol „Wolke mit Lupe“
/// links, zweizeiliger Text. Offline ausgegraut; während der Suche mit
/// Kreisel statt Symbol.
private struct ServerSearchRow: View {
    /// Die Serversuche läuft.
    let isSearching: Bool
    /// Gerät ist online.
    let isOnline: Bool
    /// Startet die Serversuche.
    let action: () -> Void

    /// Schaltfläche mit Symbol und zwei Zeilen.
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.medium) {
                if isSearching {
                    ProgressView()
                } else {
                    CloudSearchSymbol()
                        .foregroundStyle(isOnline ? Color.accentColor : Color.secondary)
                }
                VStack(alignment: .leading, spacing: AppSpacing.tiny) {
                    Text(isSearching ? "Suche auf dem Server …" : "Auf dem Server weitersuchen")
                        .foregroundStyle(isOnline && !isSearching ? Color.accentColor : Color.secondary)
                    Text(isOnline ? "Treffer werden nur angezeigt, nicht gespeichert" : "Offline – nicht verfügbar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSearching || !isOnline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.small)
    }
}

/// Entwurf zum Weiterbearbeiten: Cache-ID für das Sheet.
private struct DraftEditRequest: Identifiable {
    /// Cache-ID des Entwurfs.
    let id: String
}

/// Auf der Apple Watch geöffnete Mail: Cache-ID für das Sheet.
private struct HandoffMessageRequest: Identifiable {
    /// Cache-ID der Mail.
    let id: String
}

/// Antwort bzw. Weiterleitung aus dem Kontextmenü: Art und vollständige
/// Ursprungsmail für das Sheet.
private struct ListComposeRequest: Identifiable {
    /// Kennung für SwiftUI.
    let id = UUID()
    /// Antworten, Allen antworten oder Weiterleiten.
    let kind: ComposeKind
    /// Ursprungsmail aus dem Cache.
    let original: CachedMessage
}

/// „Rückgängig“-Balken am unteren Rand: Symbol, Text und rechts
/// „Rückgängig“ auf einer Kapsel in der Akzentfarbe. Eine hellere Füllung
/// läuft in der Laufzeit des Angebots von rechts nach links zurück und
/// zeigt so, wie lange „Rückgängig“ noch möglich ist. Ein Tipp irgendwo auf
/// den Balken nimmt die Änderung zurück, Wischen nach unten blendet ihn
/// sofort aus. Das Ausblenden nach Ablauf übernimmt das ViewModel.
private struct UndoBar: View {
    /// Was geändert wurde, z. B. „Kennzeichnung entfernt“.
    let text: String
    /// SF-Symbol des neuen Zustands.
    let systemImage: String
    /// Laufzeit des Angebots.
    let duration: Duration
    /// Nimmt die Änderung zurück.
    let onUndo: () -> Void
    /// Blendet den Hinweis aus.
    let onDismiss: () -> Void

    /// Verschiebung beim Wischen nach unten.
    @State private var dragOffset: CGFloat = 0
    /// Beginn der Laufzeit; der Balken entsteht je Angebot neu (`id`).
    @State private var start = Date.now

    /// Balken mit ablaufender Füllung.
    var body: some View {
        Button(action: onUndo) {
            HStack(spacing: AppSpacing.large) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.regular)
                Text("Rückgängig")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.xxLarge)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(alignment: .leading) {
                // Ablaufende Füllung: hellt das Blau links auf und
                // schrumpft nach links. Fortlaufend aus der verstrichenen
                // Zeit berechnet – unabhängig von Animationen, die beim
                // Einblenden sonst den Lauf übernähmen.
                TimelineView(.animation) { context in
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(.white.opacity(0.22))
                            .frame(width: proxy.size.width * remaining(at: context.date))
                    }
                }
            }
            .clipShape(Capsule())
            // Getöntes Glas in der Akzentfarbe: Fläche, Lichtkante und
            // Wölbung kommen vom System, in Hell und Dunkel.
            .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 30 {
                        onDismiss()
                    } else {
                        withAnimation(AppAnimation.quick) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityLabel("\(text). Rückgängig")
        .accessibilityHint("Wischen nach unten blendet den Hinweis aus.")
    }

    /// Verbleibender Anteil der Laufzeit.
    ///
    /// - Parameter date: Zeitpunkt der Darstellung.
    /// - Returns: 1 = voll, 0 = abgelaufen.
    private func remaining(at date: Date) -> CGFloat {
        let total = duration / .seconds(1)
        guard total > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        return CGFloat(min(1, max(0, 1 - elapsed / total)))
    }
}

/// Lädt beim Öffnen die vollständige Mail aus dem Cache und zeigt sie an.
///
/// Die Liste hält nur Listeneinträge ohne Mailinhalt. Diese Ansicht holt
/// die Nachricht beim ersten Erscheinen über `MessageStore.message(id:)`
/// und übergibt sie unverändert an `MessageDetailView`. Ist die Mail
/// inzwischen nicht mehr im Cache (anderswo gelöscht oder verschoben),
/// erscheint ein Hinweis.
///
/// Mac: Solange die Mail lädt bzw. fehlt, steht schon die Kopfleiste der
/// Mailansicht mit ausgegrauten Knöpfen und dem Postfach aus dem
/// Listeneintrag – beim Mailwechsel springt nichts.
private struct MessageDetailLoader: View {
    /// Cache-ID der zu öffnenden Mail.
    let messageID: String
    /// Postfächer, Spamfilter und Rückmeldungen der Liste.
    let context: MessageDetailContext
    /// Schaltet zwischen Vollbild und Spaltenansicht (iPad).
    var onToggleFullscreen: (() -> Void)? = nil
    /// `true` im Vollbild; steuert das Symbol der Schaltfläche.
    var isFullscreen = false
    /// Vorige/nächste Mail der Liste (iPad); `nil` = keine Knöpfe.
    var stepping: MessageStepButtons? = nil
    /// Zurück-Knopf der Mac-Kopfleiste (eine Spalte); `nil` = keiner.
    var onBack: (() -> Void)? = nil
    /// Postfach der Mail laut Listeneintrag – für die Kopfleiste des Mac,
    /// solange die Mail lädt; `nil` = unbekannt.
    var placeholderAccountID: UUID? = nil

    /// Geladene Mail; `nil`, solange sie lädt oder fehlt.
    @State private var message: CachedMessage?
    /// Die Mail liegt nicht mehr im Cache.
    @State private var isMissing = false

    /// Detailansicht, Ladeanzeige oder Hinweis.
    var body: some View {
        Group {
            if let message {
                MessageDetailView(
                    message: message,
                    accountStore: context.accountStore,
                    spamFilter: context.spamFilter,
                    scoreLimit: context.scoreLimit,
                    onChange: context.onChange,
                    onSearchPerson: context.onSearchPerson,
                    showsRecipients: context.showsRecipients,
                    onToggleFullscreen: onToggleFullscreen,
                    isFullscreen: isFullscreen,
                    stepping: stepping,
                    onBack: onBack
                )
            } else if isMissing {
                ContentUnavailableView(
                    "Nachricht nicht mehr vorhanden",
                    systemImage: "envelope",
                    description: Text("Sie wurde inzwischen gelöscht oder verschoben.")
                )
                .detailPlaceholder { placeholderHeader }
            } else {
                ProgressView()
                    .detailPlaceholder { placeholderHeader }
            }
        }
        // Auch Lade- und Hinweiszustand auf der getönten Fläche.
        .appBackground()
        .task { await load() }
    }

    /// Kopfleiste mit ausgegrauten Knöpfen, solange die Mail lädt bzw.
    /// fehlt (nur Mac).
    @ViewBuilder
    private var placeholderHeader: some View {
        #if os(macOS)
        let account = placeholderAccountID.flatMap { id in
            context.accountStore.accounts.first { $0.id == id }
        }
        MacDetailHeaderBar(
            placeholderFor: account?.displayName ?? "",
            accountColor: account?.colorHex.map { Color(hex: $0) },
            onBack: onBack
        )
        #endif
    }

    /// Lädt die Mail einmalig aus dem Cache – im Hintergrund.
    ///
    /// Verarbeitung: Läuft nur beim ersten Erscheinen; kehrt man aus einer
    /// Unteransicht zurück, bleibt die geladene Mail erhalten. Gelesen wird
    /// abseits des Hauptthreads (`MessageOpenPreparation.loadMessage`,
    /// Prüfbericht P-11), bis dahin zeigt die Ansicht die Ladeanzeige. In
    /// Debug-Builds wird die Ladezeit ausgegeben (`⏱ Mail geöffnet …`).
    /// Messpunkt für Instruments: „Mail aus Cache“; außerdem startet hier
    /// die Gesamtmessung „Mail sichtbar“ (MessageOpenTimer).
    @MainActor
    private func load() async {
        guard message == nil, !isMissing else { return }
        // Messpunkt „Mail sichtbar“ – endet in der Mailansicht.
        MessageOpenTimer.shared.start(messageID: messageID)
        #if DEBUG
        let started = Date()
        #endif
        if let loaded = await MessageOpenPreparation.loadMessage(id: messageID) {
            message = loaded
            #if DEBUG
            let millis = Int(Date().timeIntervalSince(started) * 1000)
            let bytes = (loaded.textBody?.utf8.count ?? 0) + (loaded.htmlBody?.utf8.count ?? 0)
            Log.view.debug("⏱ Mail geöffnet: \(millis) ms, Mailtext \(bytes / 1024) KB")
            #endif
        } else {
            isMissing = true
        }
    }
}

// MARK: - Spaltengerüst: feste Abstände, Ziehen

/// Fester waagerechter Innenabstand einer Listenzeile im Spaltengerüst.
///
/// Das System bemisst den Abstand nach der Breite der Liste; ohne feste
/// Vorgabe spränge der Zeileninhalt, wenn die Liste von voller Breite auf
/// Spaltenbreite wechselt. Senkrecht bleibt der Systemstandard, auf dem
/// iPhone alles unverändert.
private struct ColumnRowInsets: ViewModifier {
    /// `true` im Spaltengerüst.
    let isActive: Bool

    /// Innenabstand links und rechts in Punkt.
    private static let inset: CGFloat = 16

    /// Zeile mit festem bzw. unverändertem Abstand.
    ///
    /// - Parameter content: Listenzeile.
    /// - Returns: Zeile mit festem Abstand im Spaltengerüst.
    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.listRowInsets(.horizontal, Self.inset)
        } else {
            content
        }
    }
}

/// Fester Seitenrand der Liste im Spaltengerüst – aus demselben Grund wie
/// `ColumnRowInsets`, hier für die Karten selbst.
private struct ColumnListMargins: ViewModifier {
    /// `true` im Spaltengerüst.
    let isActive: Bool

    /// Seitenrand links und rechts in Punkt.
    private static let margin: CGFloat = 16

    /// Liste mit festem bzw. unverändertem Rand.
    ///
    /// - Parameter content: Liste.
    /// - Returns: Liste mit festem Rand im Spaltengerüst.
    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.contentMargins(.horizontal, Self.margin, for: .scrollContent)
        } else {
            content
        }
    }
}

/// Macht eine Listenzeile ziehbar – gezogen wird nur die Kennung der Mail.
/// Was damit geschieht, prüft das Ziel (Ordnerzeile, MessageSelection).
private struct MessageDragSource: ViewModifier {
    /// Cache-ID der Mail.
    let messageID: String
    /// `true`, wenn die Zeile gezogen werden darf.
    let isEnabled: Bool

    /// Zeile mit bzw. ohne Ziehen.
    ///
    /// - Parameter content: Listenzeile.
    /// - Returns: Ziehbare bzw. unveränderte Zeile.
    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(messageID)
        } else {
            content
        }
    }
}

#if os(macOS)
/// Zeilenhintergrund der Mailliste auf dem Mac: wie `cardRowBackground`,
/// dazu eine dezente Tönung, solange der Mauszeiger über der Zeile steht.
///
/// Der Zustand „Maus darüber“ liegt in der Zeile selbst. Läge er in der
/// InboxView, würde jede Mausbewegung über eine Zeilengrenze die ganze
/// Liste neu aufbauen lassen.
private struct HoverCardRowBackground: ViewModifier {
    /// Die Zeile ist geöffnet bzw. ausgewählt.
    let isOpened: Bool

    /// Mauszeiger steht über der Zeile.
    @State private var isHovered = false

    /// Zeile mit Kartenhintergrund und Hover-Tönung.
    ///
    /// - Parameter content: Listenzeile.
    /// - Returns: Zeile, die auf den Mauszeiger reagiert.
    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .cardRowBackground(isOpened: isOpened, isHovered: isHovered)
    }
}
#endif
