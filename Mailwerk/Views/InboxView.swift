//
//  InboxView.swift
//  Mailwerk
//
//  Zweck: Hauptansicht mit der Nachrichtenliste. Zeigt die gewählte
//  Ansicht (alle Posteingänge, Gekennzeichnet, ein Ordner), Titel mit
//  Stand und Verbindungshinweis, Wischaktionen (gelesen, kennzeichnen),
//  das Kontextmenü einer Mail per langem Drücken (dasselbe Menü wie in
//  der Mailansicht, siehe MessageMenu), „Rückgängig“ für Kennzeichnung
//  und Gelesen-Status, die Mehrfachauswahl (über „Auswählen“ im
//  Kontextmenü; Auswahlkreise, „Alle auswählen“, „Fertig“ und schwebende
//  Befehlsleiste unten), die Zeile „Ältere Nachrichten laden“, die
//  Ordnerleiste sowie Einstellungen und Verfassen. Eine neue Mail geht vom
//  Postfach des gezeigten Ordners aus, in Sammelansichten vom
//  Standard-Postfach. Aktualisiert wird auf
//  iPhone/iPad durch Herunterziehen, auf dem Mac per Knopf bzw. ⌘R.
//  Kommen Postfächer hinzu (beim ersten Start aus iCloud oder neu
//  eingerichtet) oder wird der Abruf eines Postfachs wieder
//  eingeschaltet, wird automatisch abgerufen. Ein Ordner eines
//  ausgeschalteten Postfachs lädt beim Öffnen auch dessen Ordnerliste.
//
//  Die Liste arbeitet mit Listeneinträgen ohne Mailinhalt
//  (`MessageListItem`). Erst beim Öffnen einer Mail lädt
//  `MessageDetailLoader` die vollständige Nachricht aus dem Cache. Im
//  Ordner „Entwürfe“ öffnet ein Tipp den Entwurf zum Weiterbearbeiten
//  (`DraftComposeLoader`).
//
//  ViewModel und Ordnerkatalog legt die App einmal beim Start an und
//  reicht sie herein. Würde die Ansicht sie selbst im `init` erzeugen,
//  entstünde bei jedem Neuaufbau durch SwiftUI ein weiteres, sofort
//  verworfenes ViewModel samt Laden der Liste aus dem Cache.
//
//  Meldungen und Rückfragen laufen über je einen Kanal (`alertItem`,
//  `confirmationRequest`, siehe Dialogs.swift).
//
//  Abgrenzung: Zustand, Abruf und Aktionen an Mails im InboxViewModel,
//  Aufbau einer Zeile in MessageRow, Mailansicht in MessageDetailView,
//  Ordnerleiste in FolderSidebarView.
//
//  Abhängigkeiten: InboxViewModel, MessageStore, MailActionService,
//  FolderCatalog, NetworkMonitor, MessageRow, MessageRowParty,
//  ContactImageDirectory, SenderIconCache, FilterListCloudEvents,
//  MessageDetailView, MessageMenu, MessageActionDialogs, FolderMoveSheet,
//  MessageSelection, SelectionActionBar,
//  ComposeView, DraftComposeLoader, Dialogs, Log.
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
    /// Entwurf, der zum Weiterbearbeiten geöffnet wird.
    @State private var draftToEdit: DraftEditRequest?
    /// Mail, für die aus dem Kontextmenü ein Zielordner gewählt wird.
    @State private var moveItem: MessageListItem?
    /// Rückfrage aus dem Kontextmenü (Löschen, Spam); einziger
    /// Rückfragekanal der Liste neben der Warteschlange der Spam-Ordner.
    @State private var listConfirmation: ConfirmationRequest?
    /// Ordnerwahl für die Mehrfachauswahl geöffnet.
    @State private var showingSelectionMove = false
    /// Netzzustand (online/offline).
    private let network = NetworkMonitor.shared

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
                MessageStore.shared.folderListing(accountID: account.id).map {
                    FolderTreeBuilder.build(listing: $0, configuredSpamFolder: account.spamFolder)
                }
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

    /// Verbindungshinweis für die zweite Titelzeile, `nil` = alles in Ordnung.
    private var connectionStatus: String? {
        if !network.isOnline { return "Offline" }
        if viewModel.connectionFailed { return "Keine Verbindung" }
        return nil
    }

    /// Ruft die gerade angezeigte Ansicht ab.
    ///
    /// Verarbeitung: Ein gewählter Ordner wird allein abgerufen, sonst
    /// alle Posteingänge samt Spam-Ordnern.
    @MainActor
    private func refreshCurrentView() async {
        if case .folder(let accountID, let path, _) = viewModel.selection {
            await viewModel.refreshFolder(accountID: accountID, path: path)
        } else {
            await viewModel.refresh()
        }
    }

    /// Farbe des Postfachs, wenn ein einzelner Ordner gewählt ist.
    private var selectedAccountColor: Color? {
        guard let id = viewModel.selection.accountID,
              let hex = accountStore.accounts.first(where: { $0.id == id })?.colorHex
        else { return nil }
        return Color(hex: hex)
    }

    /// Aufbau der Ansicht: Liste bzw. Lade- oder Leerzustand, Symbolleiste,
    /// Dialoge, „Rückgängig“-Hinweis und Ordnerleiste.
    var body: some View {
        NavigationStack {
            // WICHTIG: Jeder Zweig dieser Group muss genau EIN View liefern.
            // Modifier an einer Group wirken auf jedes Kind einzeln – bei
            // zwei Kindern erschiene z. B. die Toolbar doppelt.
            Group {
                if viewModel.messages.isEmpty && viewModel.isLoading {
                    InitialLoadingView()
                } else if viewModel.messages.isEmpty {
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
            #if os(iOS)
            // iPhone/iPad: Aktualisieren durch Herunterziehen der Liste.
            // Auf dem Mac gibt es dafür einen eigenen Knopf (refreshButton).
            .refreshable {
                await refreshCurrentView()
            }
            #endif
            // Feine Linie als Abgrenzung unter der Überschrift
            .safeAreaInset(edge: .top, spacing: 0) {
                Divider()
            }
            .navigationTitle(viewModel.selection.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { listToolbar }
            // Befehlsleiste im Auswahlmodus – schwebt über der Liste am
            // unteren Rand, wo später die Suche sitzt.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isSelecting {
                    selectionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: viewModel.isSelecting)
            .task {
                guard !hasLoadedOnce else { return }
                hasLoadedOnce = true
                // Kontaktbilder parallel zum Abruf: Die Systemabfrage zur
                // Berechtigung soll den Abruf nicht aufhalten.
                Task { await ContactImageDirectory.shared.start() }
                await viewModel.refresh()
            }
            .onChange(of: accountStore.accounts.map(\.id)) { oldIDs, newIDs in
                // Neue Postfächer (beim ersten Start aus iCloud oder neu
                // eingerichtet): Liste zeigen und alle Posteingänge abrufen.
                // Reine Änderungen wie Name oder Farbe lösen nichts aus.
                guard !Set(newIDs).isSubset(of: Set(oldIDs)) else { return }
                viewModel.loadFromCache()
                Task { await viewModel.refresh() }
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
            .onChange(of: viewModel.selection) { _, newSelection in
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
            .onChange(of: accountStore.pausedAccountIDs) { oldPaused, newPaused in
                // Abruf ein-/ausgeschaltet: Sammelsichten neu zusammenstellen;
                // wieder eingeschaltete Postfächer gleich abrufen.
                viewModel.loadFromCache()
                guard !oldPaused.isSubset(of: newPaused) else { return }
                Task { await viewModel.refresh() }
            }
            .sheet(isPresented: $showingAccounts) {
                AccountListView(accountStore: accountStore)
            }
            .confirmationRequest(confirmation)
            .sheet(isPresented: $showingSpamSettings, onDismiss: {
                // Listen können sich geändert haben (Absenderbilder).
                viewModel.reloadFilterLists()
            }) {
                SpamSettingsView(settings: spamSettings, filterLists: filterLists)
            }
            .sheet(isPresented: $showingCompose) {
                // Absender: Postfach des gezeigten Ordners; Sammelansichten
                // (z. B. „Alle Eingänge“) haben keines → Standard-Postfach.
                ComposeView(
                    accountStore: accountStore,
                    kind: .new,
                    senderAccountID: viewModel.selection.accountID,
                    onSent: { viewModel.loadFromCache() }
                )
            }
            .sheet(item: $listCompose) { request in
                ComposeView(
                    accountStore: accountStore,
                    kind: request.kind,
                    original: request.original,
                    onSent: { viewModel.loadFromCache() }
                )
            }
            .sheet(item: $draftToEdit) { request in
                DraftComposeLoader(
                    messageID: request.id,
                    accountStore: accountStore,
                    onSent: { refreshAfterDraft() }
                )
            }
            .sheet(isPresented: $showingSelectionMove) {
                selectionMoveSheet
            }
            .sheet(item: $moveItem) { item in
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
        }
        // Einziger Meldungskanal der Liste – am äußeren Element, getrennt
        // von der Rückfrage am Inhalt.
        .alertItem($viewModel.alert)
        .overlay(alignment: .bottom) {
            if let offer = viewModel.undoOffer {
                UndoBanner(
                    text: offer.text,
                    onUndo: { Task { await viewModel.undo(offer) } },
                    onDismiss: { viewModel.dismissUndo() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 16)
                .padding(.horizontal, 16)
            }
        }
        .animation(.snappy(duration: 0.25), value: viewModel.undoOffer?.id)
        .sideDrawer(isPresented: $showingFolders) {
            FolderSidebarView(
                accounts: accountStore.accounts,
                pausedAccountIDs: accountStore.pausedAccountIDs,
                catalog: folderCatalog,
                expandedAccounts: $expandedFolderAccounts,
                selection: $viewModel.selection,
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
                onClose: { showingFolders = false }
            )
        }
    }

    // MARK: - Symbolleiste

    /// Symbolleiste: im Auswahlmodus „Alle auswählen“, Anzahl und „Fertig“,
    /// sonst Ordnerleiste, Titel, Ladeanzeige, Verfassen und Einstellungen.
    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        if viewModel.isSelecting {
            ToolbarItem(placement: .navigation) {
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
                    withAnimation(.snappy(duration: 0.25)) { viewModel.endSelection() }
                }
            }
        } else {
            ToolbarItem(placement: .navigation) {
                Button {
                    showingFolders = true
                } label: {
                    Label("Ordner", systemImage: "sidebar.left")
                }
            }
            ToolbarItem(placement: .principal) {
                InboxTitle(
                    selection: viewModel.selection,
                    accountColor: selectedAccountColor,
                    syncState: viewModel.syncState,
                    connectionStatus: connectionStatus
                )
            }
            ToolbarItem(placement: Self.progressPlacement) {
                if viewModel.isLoading && !viewModel.messages.isEmpty {
                    ProgressView()
                }
            }
            #if os(macOS)
            ToolbarItem {
                refreshButton
            }
            #endif
            ToolbarItem {
                Button {
                    showingCompose = true
                } label: {
                    Label("Neue Nachricht", systemImage: "square.and.pencil")
                }
                .disabled(accountStore.accounts.isEmpty)
            }
            ToolbarItem {
                Menu {
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
                } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
            }
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
            onDelete: {
                listConfirmation = MessageActionDialogs.deleteConfirmation(count: items.count) {
                    runSelectionAction { await viewModel.deleteSelection() }
                }
            }
        )
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

    // MARK: - Aktualisieren (Mac)

    #if os(macOS)
    /// Knopf „Aktualisieren“ in der Symbolleiste des Mac, auch per ⌘R.
    ///
    /// Auf dem Mac ist Herunterziehen keine übliche Bedienung; deshalb gibt
    /// es dort einen ausdrücklichen Knopf. Während ein Abruf läuft, ist er
    /// gesperrt, damit nicht mehrere Abrufe gleichzeitig starten.
    private var refreshButton: some View {
        Button {
            Task { await refreshCurrentView() }
        } label: {
            Label("Aktualisieren", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .help("Aktualisieren (⌘R)")
        .disabled(viewModel.isLoading || accountStore.accounts.isEmpty)
    }
    #endif

    // MARK: - Nachrichtenliste

    /// Liste der Nachrichten samt Zeile „Ältere Nachrichten laden“. Im
    /// Auswahlmodus mit Auswahlkreisen; die Zeile „Ältere“ entfällt dann.
    ///
    /// Eigene Eigenschaft statt Teil von `body`, damit der Compiler den
    /// Ausdruck in vertretbarer Zeit prüfen kann.
    private var messageList: some View {
        let colors = accountColors
        let recipients = showsRecipients
        let drafts = showsDrafts
        return List(selection: listSelection) {
            ForEach(viewModel.messages) { message in
                messageRow(
                    for: message,
                    colorHex: colors[message.accountID],
                    showsRecipients: recipients,
                    opensDraft: drafts
                )
            }

            // Letzte Zeile der Liste – gehört IN die List, damit
            // der Zweig ein einzelnes View bleibt.
            if viewModel.showsOlderRow && !viewModel.isSelecting {
                Section {
                    olderRow
                }
            }
        }
        #if os(iOS)
        // Auswahlmodus: Kreise vor den Zeilen, Tipp wählt aus statt zu öffnen.
        .environment(\.editMode, .constant(viewModel.isSelecting ? .active : .inactive))
        #endif
    }

    /// Auswahlbindung der Liste: auf iPhone/iPad nur im Auswahlmodus. Auf
    /// dem Mac nie – dort wählt die Zeile selbst per Klick aus (siehe
    /// `selectableRow`), weil die Listenauswahl des Mac einen einfachen
    /// Klick als Ersetzen der Auswahl versteht.
    private var listSelection: Binding<Set<String>>? {
        #if os(macOS)
        return nil
        #else
        return viewModel.isSelecting ? $viewModel.selectedIDs : nil
        #endif
    }

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

    /// Eine Zeile der Liste: Link zur Mail, Wischaktionen, Kontextmenü,
    /// Sperre während einer laufenden Aktion.
    ///
    /// Verarbeitung: Der Link öffnet `MessageDetailLoader`, der die
    /// vollständige Mail erst beim Öffnen aus dem Cache lädt. Im
    /// Entwürfe-Ordner öffnet ein Tipp stattdessen das Verfassen-Fenster
    /// (`DraftComposeLoader`).
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
        Group {
            if viewModel.isSelecting {
                // Im Auswahlmodus kein Link: Ein Tipp wählt aus statt zu
                // öffnen. Auf dem Mac würde der Link den Klick sonst selbst
                // verarbeiten und die Mail öffnen.
                selectableRow(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
            } else if opensDraft {
                Button {
                    draftToEdit = DraftEditRequest(id: message.id)
                } label: {
                    rowContent(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    MessageDetailLoader(
                        messageID: message.id,
                        accountStore: accountStore,
                        spamFilter: viewModel.spamFilter,
                        scoreLimit: spamSettings.scoreLimit,
                        onChange: { viewModel.loadFromCache() }
                    )
                } label: {
                    rowContent(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
                }
            }
        }
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
        .contextMenu {
            MessageMenuItems(
                context: MessageMenuContext(message),
                showsSelect: true,
                onAction: { handleMenuAction($0, for: message) }
            ) {
                EmptyView()
            }
        }
        .disabled(viewModel.processingMessageIDs.contains(message.id))
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
        let party = MessageRowParty.make(for: message, showsRecipients: showsRecipients)
        let showsImage = viewModel.showsSenderImage(for: message)
        // Nur erlaubte Zeilen fragen nach Bildern – Spam löst so keinen
        // Logo-Abruf aus. Ein Kontaktbild hat Vorrang vor dem Logo.
        let contactImage = showsImage ? ContactImageDirectory.shared.image(for: party.address) : nil
        return MessageRow(
            message: message,
            party: party,
            showsImage: showsImage,
            contactImage: contactImage,
            logoImage: showsImage && contactImage == nil
                ? SenderIconCache.shared.image(forAddress: party.address)
                : nil,
            colorHex: colorHex
        )
    }

    /// Zeile im Auswahlmodus.
    ///
    /// Verarbeitung: Auf iPhone/iPad zeichnet die Liste im Bearbeitungsmodus
    /// die Auswahlkreise selbst. Der Mac kennt diesen Modus nicht; dort
    /// zeigt die Zeile einen eigenen Kreis, und ein Klick wählt aus bzw. ab
    /// – so verhält sich die Auswahl wie auf dem iPhone.
    ///
    /// - Parameters:
    ///   - message: Darzustellender Listeneintrag.
    ///   - colorHex: Farbe des Postfachs; `nil` = keine Farbe gewählt.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Die auswählbare Zeile.
    @ViewBuilder
    private func selectableRow(
        for message: MessageListItem,
        colorHex: String?,
        showsRecipients: Bool
    ) -> some View {
        #if os(macOS)
        let isSelected = viewModel.selectedIDs.contains(message.id)
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            rowContent(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleSelection(message.id) }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        #else
        rowContent(for: message, colorHex: colorHex, showsRecipients: showsRecipients)
        #endif
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
            withAnimation(.snappy(duration: 0.25)) {
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

    /// Platz für die Ladeanzeige in der Symbolleiste. `.topBarLeading`
    /// gibt es auf macOS nicht; dort ordnet das System selbst ein.
    private static var progressPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarLeading
        #endif
    }
}

/// Überschrift der Liste: klein, mit Symbol passend zur Auswahl.
/// Bei einem gewählten Ordner erscheint ein Farbpunkt des Postfachs.
/// Auf dem Mac trägt die Fensterleiste den Titel bereits
/// (`navigationTitle`), dort bleibt der Platz leer.
private struct InboxTitle: View {
    /// Gewählte Ansicht (Titel und Symbol).
    let selection: MailboxSelection
    /// Farbe des Postfachs bei einem einzelnen Ordner; sonst `nil`.
    var accountColor: Color?
    /// Stand der Ansicht; erscheint als zweite Zeile. Der untere
    /// Bildschirmrand bleibt so frei (später für die Suche vorgesehen).
    var syncState: SyncState?
    /// „Offline" bzw. „Keine Verbindung", sonst `nil`.
    var connectionStatus: String?

    /// Titelzeile mit Symbol und darunter der Stand.
    var body: some View {
        #if os(iOS)
        VStack(spacing: 1) {
            HStack(spacing: 6) {
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
                    statusLine(syncState)
                        .font(.caption2)
                        .foregroundStyle(connectionStatus == nil ? Color.secondary : Color.orange)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        #else
        EmptyView()
        #endif
    }

    /// Text der Standzeile.
    ///
    /// - Parameter state: Stand der Ansicht.
    /// - Returns: „Aktualisiert: …“ bzw. mit Verbindungshinweis.
    private func statusLine(_ state: SyncState) -> Text {
        switch (state, connectionStatus) {
        case (.at(let date), nil):
            return Text("Aktualisiert: \(date, format: .relative(presentation: .named))")
        case (.at(let date), let status?):
            return Text("\(status) · Stand: \(date, format: .relative(presentation: .named))")
        case (.never, nil):
            return Text("Noch nicht abgerufen")
        case (.never, let status?):
            return Text("\(status) · noch nicht abgerufen")
        }
    }
}

/// Ladeanzeige, solange beim ersten Abruf noch keine Mail im Cache liegt.
private struct InitialLoadingView: View {
    /// Fortschrittsanzeige mit Hinweis.
    var body: some View {
        VStack(spacing: 16) {
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
                        systemImage: selection == .flagged ? "flag" : "tray",
                        description: Text(hint)
                    )
                    footer()
                }
                .frame(minHeight: geo.size.height)
            }
        }
    }

    /// Überschrift des Hinweises.
    private var title: String {
        selection == .flagged ? "Keine gekennzeichneten Nachrichten" : "Keine Nachrichten"
    }

    /// Erklärender Text: was zu tun ist bzw. warum die Liste leer ist.
    private var hint: String {
        guard hasAccounts else { return "Richte zuerst ein Postfach ein." }
        switch selection {
        case .flagged:
            return "Kennzeichne Nachrichten, damit sie hier erscheinen."
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
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 6)
    }
}

/// Entwurf zum Weiterbearbeiten: Cache-ID für das Sheet.
private struct DraftEditRequest: Identifiable {
    /// Cache-ID des Entwurfs.
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

/// „Rückgängig"-Hinweis am unteren Rand. Verschwindet nach 5 Sekunden
/// oder auf Tipp – je nachdem, was zuerst kommt.
private struct UndoBanner: View {
    /// Was geändert wurde, z. B. „Kennzeichnung entfernt“.
    let text: String
    /// Nimmt die Änderung zurück.
    let onUndo: () -> Void
    /// Blendet den Hinweis aus.
    let onDismiss: () -> Void

    /// Hinweis mit „Rückgängig“ und Schließen.
    var body: some View {
        HStack {
            Text(text)
                .font(.subheadline)
            Spacer()
            Button("Rückgängig") { onUndo() }
                .font(.subheadline.weight(.semibold))
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

/// Lädt beim Öffnen die vollständige Mail aus dem Cache und zeigt sie an.
///
/// Die Liste hält nur Listeneinträge ohne Mailinhalt. Diese Ansicht holt
/// die Nachricht beim ersten Erscheinen über `MessageStore.message(id:)`
/// und übergibt sie unverändert an `MessageDetailView`. Ist die Mail
/// inzwischen nicht mehr im Cache (anderswo gelöscht oder verschoben),
/// erscheint ein Hinweis.
private struct MessageDetailLoader: View {
    /// Cache-ID der zu öffnenden Mail.
    let messageID: String
    /// Quelle für Postfächer und Passwörter.
    let accountStore: AccountStore
    /// Spamfilter für Blockieren und Vertrauen.
    let spamFilter: SpamFilterService
    /// Score-Obergrenze für vertrauenswürdige Absender (externe Inhalte).
    let scoreLimit: Double
    /// Wird nach Änderungen an der Mail aufgerufen (Liste neu laden).
    let onChange: () -> Void

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
                    accountStore: accountStore,
                    spamFilter: spamFilter,
                    scoreLimit: scoreLimit,
                    onChange: onChange
                )
            } else if isMissing {
                ContentUnavailableView(
                    "Nachricht nicht mehr vorhanden",
                    systemImage: "envelope",
                    description: Text("Sie wurde inzwischen gelöscht oder verschoben.")
                )
            } else {
                ProgressView()
            }
        }
        .task { load() }
    }

    /// Lädt die Mail einmalig aus dem Cache.
    ///
    /// Verarbeitung: Läuft nur beim ersten Erscheinen; kehrt man aus einer
    /// Unteransicht zurück, bleibt die geladene Mail erhalten. In Debug-
    /// Builds wird die Ladezeit ausgegeben (`⏱ Mail geöffnet …`).
    private func load() {
        guard message == nil, !isMissing else { return }
        #if DEBUG
        let started = Date()
        #endif
        if let loaded = MessageStore.shared.message(id: messageID) {
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
