//
//  InboxView.swift
//  Mailwerk
//
//  Zweck: Hauptansicht mit der Nachrichtenliste. Zeigt die gewählte
//  Ansicht (alle Posteingänge, Gekennzeichnet, ein Ordner), Titel mit
//  Stand und Verbindungshinweis, Wischaktionen (gelesen, kennzeichnen)
//  samt „Rückgängig“, die Zeile „Ältere Nachrichten laden“, die
//  Ordnerleiste sowie Einstellungen und Verfassen. Aktualisiert wird auf
//  iPhone/iPad durch Herunterziehen, auf dem Mac per Knopf bzw. ⌘R.
//  Kommen Postfächer hinzu (beim ersten Start aus iCloud oder neu
//  eingerichtet), wird automatisch abgerufen.
//
//  Die Liste arbeitet mit Listeneinträgen ohne Mailinhalt
//  (`MessageListItem`). Erst beim Öffnen einer Mail lädt
//  `MessageDetailLoader` die vollständige Nachricht aus dem Cache.
//
//  ViewModel und Ordnerkatalog legt die App einmal beim Start an und
//  reicht sie herein. Würde die Ansicht sie selbst im `init` erzeugen,
//  entstünde bei jedem Neuaufbau durch SwiftUI ein weiteres, sofort
//  verworfenes ViewModel samt Laden der Liste aus dem Cache.
//
//  Meldungen und Rückfragen laufen über je einen Kanal (`alertItem`,
//  `confirmationRequest`, siehe Dialogs.swift).
//
//  Abgrenzung: Zustand, Abruf und Wischaktionen im InboxViewModel,
//  Mailansicht in MessageDetailView, Ordnerleiste in FolderSidebarView.
//
//  Abhängigkeiten: InboxViewModel, MessageStore, MailActionService,
//  FolderCatalog, NetworkMonitor, MessageDetailView, ComposeView, Dialogs.
//

import SwiftUI

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
            // zwei Kindern erschiene z. B. die Toolbar doppelt (v0.1.7d).
            Group {
                if viewModel.messages.isEmpty && viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Postfächer werden abgerufen …")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.messages.isEmpty {
                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 0) {
                                ContentUnavailableView(
                                    viewModel.selection == .flagged
                                        ? "Keine gekennzeichneten Nachrichten"
                                        : "Keine Nachrichten",
                                    systemImage: viewModel.selection == .flagged ? "flag" : "tray",
                                    description: Text(
                                        accountStore.accounts.isEmpty
                                            ? "Richte zuerst ein Postfach ein."
                                            : viewModel.selection == .flagged
                                                ? "Kennzeichne Nachrichten, damit sie hier erscheinen."
                                                : viewModel.selection.accountID != nil
                                                    ? "Dieser Ordner enthält keine Nachrichten."
                                                    : "Zieh nach unten, um abzurufen."
                                    )
                                )
                                // Auch ein leerer Ordner kann ältere Mails haben
                                // (z. B. ein Archiv ohne Eingänge der letzten 30 Tage).
                                if viewModel.showsOlderRow && !accountStore.accounts.isEmpty {
                                    olderRow
                                        .padding(.horizontal)
                                }
                            }
                            .frame(minHeight: geo.size.height)
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
            .toolbar {
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
            .task {
                guard !hasLoadedOnce else { return }
                hasLoadedOnce = true
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
                }
            }
            .sheet(isPresented: $showingAccounts) {
                AccountListView(accountStore: accountStore)
            }
            .confirmationRequest(spamFolderConfirmation)
            .sheet(isPresented: $showingSpamSettings) {
                SpamSettingsView(settings: spamSettings, filterLists: filterLists)
            }
            .sheet(isPresented: $showingCompose) {
                ComposeView(
                    accountStore: accountStore,
                    kind: .new,
                    onSent: { viewModel.loadFromCache() }
                )
            }
        }
        // Einziger Meldungskanal der Liste – am äußeren Element, getrennt
        // von der Rückfrage am Inhalt.
        .alertItem($viewModel.alert)
        .overlay(alignment: .bottom) {
            if let undo = viewModel.undoUnflag {
                UndoBanner(
                    onUndo: { Task { await viewModel.undo(undo) } },
                    onDismiss: { viewModel.dismissUndoUnflag() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 16)
                .padding(.horizontal, 16)
            }
        }
        .animation(.snappy(duration: 0.25), value: viewModel.undoUnflag?.id)
        .sideDrawer(isPresented: $showingFolders) {
            FolderSidebarView(
                accounts: accountStore.accounts,
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

    /// Liste der Nachrichten samt Zeile „Ältere Nachrichten laden“.
    ///
    /// Eigene Eigenschaft statt Teil von `body`, damit der Compiler den
    /// Ausdruck in vertretbarer Zeit prüfen kann.
    private var messageList: some View {
        List {
            ForEach(viewModel.messages) { message in
                messageRow(for: message)
            }

            // Letzte Zeile der Liste – gehört IN die List, damit
            // der Zweig ein einzelnes View bleibt.
            if viewModel.showsOlderRow {
                Section {
                    olderRow
                }
            }
        }
    }

    /// Eine Zeile der Liste: Link zur Mail, Wischaktionen, Sperre während
    /// einer laufenden Aktion.
    ///
    /// Verarbeitung: Der Link öffnet `MessageDetailLoader`, der die
    /// vollständige Mail erst beim Öffnen aus dem Cache lädt.
    ///
    /// - Parameter message: Darzustellender Listeneintrag.
    /// - Returns: Die fertige Zeile.
    private func messageRow(for message: MessageListItem) -> some View {
        NavigationLink {
            MessageDetailLoader(
                messageID: message.id,
                accountStore: accountStore,
                spamFilter: viewModel.spamFilter,
                onChange: { viewModel.loadFromCache() }
            )
        } label: {
            InboxRow(
                message: message,
                colorHex: accountStore.accounts
                    .first(where: { $0.id == message.accountID })?.colorHex
            )
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
        .disabled(viewModel.processingMessageIDs.contains(message.id))
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
        if outcome == .deleted || outcome == .notFound {
            MessageStore.shared.deleteFolder(accountID: account.id, folder: node.id)
            if case .folder(let accountID, let path, _) = viewModel.selection,
               accountID == account.id, path == node.id {
                viewModel.selection = .allInboxes
            }
        }
        return outcome
    }

    // MARK: - Rückfragen

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

/// „Rückgängig"-Hinweis am unteren Rand. Verschwindet nach 5 Sekunden
/// oder auf Tipp – je nachdem, was zuerst kommt.
private struct UndoBanner: View {
    /// Stellt die Kennzeichnung wieder her.
    let onUndo: () -> Void
    /// Blendet den Hinweis aus.
    let onDismiss: () -> Void

    /// Hinweis mit „Rückgängig“ und Schließen.
    var body: some View {
        HStack {
            Text("Kennzeichnung entfernt")
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

/// Zeile der Nachrichtenliste: Farbstreifen des Postfachs, Absender,
/// Symbole (beantwortet, weitergeleitet, gekennzeichnet, Anhang), Datum,
/// Betreff und Vorschau.
private struct InboxRow: View {
    /// Darzustellender Listeneintrag.
    let message: MessageListItem
    /// Farbe des Postfachs; `nil` = kein Streifen.
    let colorHex: String?

    /// Aufbau der Zeile.
    var body: some View {
        HStack(spacing: 0) {
            // Farbstreifen am linken Rand (nur wenn Farbe gesetzt)
            if let hex = colorHex {
                Color(hex: hex)
                    .frame(width: 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.from)
                        .font(message.isUnread ? .headline : .subheadline)
                        .lineLimit(1)
                    Spacer()
                    if message.isAnswered {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Beantwortet")
                    }
                    if message.isForwarded {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Weitergeleitet")
                    }
                    if message.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if message.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(message.date ?? Date(), format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(message.subject)
                    .font(.subheadline)
                    .lineLimit(1)

                if let preview = message.preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, colorHex != nil ? 8 : 0)
        }
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
            print("⏱ Mail geöffnet: \(millis) ms, Mailtext \(bytes / 1024) KB")
            #endif
        } else {
            isMissing = true
        }
    }
}
