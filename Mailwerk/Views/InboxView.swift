//
//  InboxView.swift
//  Mailwerk
//

import SwiftUI

struct InboxView: View {
    let accountStore: AccountStore
    let filterLists: any FilterListRepository
    let spamSettings: SpamSettings
    @State private var viewModel: InboxViewModel
    @State private var showingAccounts = false
    @State private var showingSpamSettings = false
    @State private var showingCompose = false
    @State private var showingFolders = false
    /// Ordnerbäume der Postfächer; nur für diese App-Sitzung.
    @State private var folderCatalog: FolderCatalog
    /// In der Leiste aufgeklappte Postfächer. Bewusst nicht gespeichert:
    /// Nach einem Neustart ist wieder alles zugeklappt.
    @State private var expandedFolderAccounts: Set<UUID> = []
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?
    @State private var processingMessageIDs: Set<String> = []
    @State private var undoTask: Task<Void, Never>?
    private let network = NetworkMonitor.shared

    init(
        accountStore: AccountStore,
        filterLists: any FilterListRepository,
        spamSettings: SpamSettings
    ) {
        self.accountStore = accountStore
        self.filterLists = filterLists
        self.spamSettings = spamSettings
        _viewModel = State(initialValue: InboxViewModel(
            accountStore: accountStore,
            filterLists: filterLists,
            spamSettings: spamSettings
        ))
        _folderCatalog = State(initialValue: FolderCatalog { account in
            try await MailActionService.fetchFolderTree(for: account, accountStore: accountStore)
        })
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

    /// Ruft die gerade angezeigte Ansicht ab – einen Ordner allein, sonst
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
                    List {
                        ForEach(viewModel.messages) { message in
                            NavigationLink {
                                MessageDetailView(
                                    message: message,
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
                                    Task { await toggleRead(message) }
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
                                    Task { await toggleFlag(message) }
                                } label: {
                                    Label(
                                        message.isFlagged ? "Entflaggen" : "Flaggen",
                                        systemImage: message.isFlagged ? "flag.slash" : "flag"
                                    )
                                }
                                .tint(.orange)
                            }
                            .disabled(processingMessageIDs.contains(message.id))
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
            }
            .refreshable {
                await refreshCurrentView()
            }
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
            .alert(
                "Spam-Ordner anlegen?",
                isPresented: Binding(
                    get: { viewModel.pendingSpamFolders.first != nil },
                    set: { _ in }
                ),
                presenting: viewModel.pendingSpamFolders.first
            ) { pending in
                Button("Anlegen") {
                    Task { await viewModel.createSpamFolder(for: pending) }
                }
                Button("Nicht jetzt", role: .cancel) {
                    viewModel.dismissSpamFolderRequest(pending, declineForSession: true)
                }
            } message: { pending in
                Text("Das Postfach „\(pending.account.displayName)“ hat keinen Spam-Ordner. Ohne ihn kann der Filter dort nichts aussortieren. Vorgeschlagen wird „\(pending.proposal)“.")
            }
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
            .alert(
                "Fehler beim Abrufen",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "Aktion fehlgeschlagen",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .overlay(alignment: .bottom) {
            if let undo = viewModel.undoUnflag {
                UndoBanner(
                    onUndo: { undoUnflag(undo) },
                    onDismiss: { viewModel.undoUnflag = nil }
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

    // MARK: - Ordner löschen

    /// Löscht einen leeren Ordner auf dem Server, räumt danach seinen
    /// Cache ab und verlässt die Ansicht, falls sie gerade offen ist.
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

    // MARK: - Swipe-Aktionen

    @MainActor
    private func toggleRead(_ message: CachedMessage) async {
        processingMessageIDs.insert(message.id)
        defer { processingMessageIDs.remove(message.id) }

        let markAsRead = message.isUnread
        do {
            try await MailActionService.setRead(
                uid: Int(message.uid),
                isRead: markAsRead,
                accountID: message.accountID,
                accountStore: accountStore,
                folder: message.folder
            )
            MessageStore.shared.updateFlags(messageID: message.id, isUnread: !markAsRead)
            viewModel.loadFromCache()
        } catch {
            errorMessage = "Status ändern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func toggleFlag(_ message: CachedMessage) async {
        processingMessageIDs.insert(message.id)
        defer { processingMessageIDs.remove(message.id) }

        let newFlagged = !message.isFlagged
        do {
            try await MailActionService.setFlagged(
                uid: Int(message.uid),
                isFlagged: newFlagged,
                accountID: message.accountID,
                accountStore: accountStore,
                folder: message.folder
            )
            MessageStore.shared.updateFlagged(messageID: message.id, isFlagged: newFlagged)

            // In der Kennzeichen-Sicht: Entflaggen bietet „Rückgängig" an.
            if viewModel.selection == .flagged && !newFlagged {
                undoTask?.cancel()
                viewModel.undoUnflag = InboxViewModel.UndoUnflag(
                    messageID: message.id,
                    messageUID: message.uid,
                    accountID: message.accountID,
                    folder: message.folder
                )
                undoTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    viewModel.undoUnflag = nil
                }
            }

            viewModel.loadFromCache()
        } catch {
            errorMessage = "Kennzeichnen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func undoUnflag(_ undo: InboxViewModel.UndoUnflag) {
        undoTask?.cancel()
        viewModel.undoUnflag = nil
        Task {
            do {
                try await MailActionService.setFlagged(
                    uid: Int(undo.messageUID),
                    isFlagged: true,
                    accountID: undo.accountID,
                    accountStore: accountStore,
                    folder: undo.folder
                )
                MessageStore.shared.updateFlagged(messageID: undo.messageID, isFlagged: true)
                viewModel.loadFromCache()
            } catch {
                errorMessage = "Rückgängig fehlgeschlagen: \(error.localizedDescription)"
            }
        }
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
    let selection: MailboxSelection
    var accountColor: Color?
    /// Stand der Ansicht; erscheint als zweite Zeile. Der untere
    /// Bildschirmrand bleibt so frei (später für die Suche vorgesehen).
    var syncState: SyncState?
    /// „Offline" bzw. „Keine Verbindung", sonst `nil`.
    var connectionStatus: String?

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
    let isLoading: Bool
    let isExhausted: Bool
    let isOnline: Bool
    /// Letzter Versuch scheiterte an der Verbindung.
    let connectionFailed: Bool
    let nextDate: Date?
    let action: () -> Void

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
    let onUndo: () -> Void
    let onDismiss: () -> Void

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

private struct InboxRow: View {
    let message: CachedMessage
    let colorHex: String?

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

                if let body = message.textBody {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, colorHex != nil ? 8 : 0)
        }
    }
}
