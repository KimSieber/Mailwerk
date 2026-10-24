//
//  FolderSidebarView.swift
//  Mailwerk
//
//  Zweck: Inhalt der Ordnerleiste. Oben die Sammelansichten über alle
//  Postfächer – „Alle Eingänge“, „Ungelesen“ (mit Zahl), „Mit
//  Kennzeichnung“ (mit Zahl) und „Spam“ (alle Spam-Ordner, ohne Zahl); ein
//  Tipp wählt die Ansicht und schließt die Leiste. Darunter je Postfach
//  ein aufklappbarer Abschnitt mit dem Ordnerbaum.
//
//  Ein Postfach, dessen Abruf auf diesem Gerät ausgeschaltet ist, trägt
//  vor dem Namen ein orangefarbenes Pause-Zeichen (FetchPausedBadge);
//  seine Ordnerliste wird nicht von selbst geladen (siehe FolderCatalog).
//  Ist die Anmeldung eines Postfachs abgelaufen, steht davor ein rotes
//  Warnzeichen (SignInRequiredBadge); hat sein letzter Abruf den Server
//  nicht erreicht, ein gelbes (FetchFailedBadge). Die Zeichen stellt
//  AccountStatusBadges zusammen; ihre Hinweise erscheinen als Tooltip
//  (Maus, Trackpad) und in der VoiceOver-Beschreibung des Postfachkopfs.
//
//  Ordner sind auswählbar: Ein Tipp zeigt den Ordnerinhalt. Unterordner
//  sind immer sichtbar und nur durch Einrückung erkennbar; auf- und
//  zuklappen lassen sich nur die Postfächer.
//
//  Langes Drücken (Mac: Rechtsklick) öffnet ein Kontextmenü – am Postfach
//  „Neuer Ordner …“, an einem Ordner „Neuer Unterordner …“ und bei
//  gewöhnlichen Ordnern „Löschen …“. Sonderordner lassen sich nicht
//  löschen; bei Ordnern mit Unterordnern ist der Eintrag ausgegraut. Ob
//  ein Ordner Mails enthält, prüft erst der Server unmittelbar vor dem
//  Löschen.
//
//  Steht die Leiste als feste Spalte neben der Liste (iPad, drei Spalten),
//  lassen sich Mails auf einen Ordner ziehen und werden dorthin
//  verschoben (`onDropMessages`). Der Ordner hebt sich dabei hervor (ab
//  iOS 27). Die einblendbare Leiste nimmt nichts an – sie verdeckt die
//  Liste ohnehin.
//
//  Dialoge: „Neuer Ordner“ ist ein Eingabedialog mit Textfeld. Die
//  Rückfrage vor dem Löschen und Fehlermeldungen laufen über je einen
//  Kanal (siehe Dialogs.swift).
//
//  Abgrenzung: Anlegen, Löschen und Verschieben übernimmt der Aufrufer
//  (`onCreateFolder`, `onDeleteFolder`, `onDropMessages`); den Ordnerbaum
//  liefert der FolderCatalog.
//
//  Abhängigkeiten: SwiftUI, FolderCatalog, FolderNode, FolderLabel, Dialogs,
//  AccountStatusBadges.
//

import SwiftUI

/// Inhalt der Ordnerleiste.
struct FolderSidebarView: View {
    /// Eingerichtete Postfächer.
    let accounts: [MailAccount]
    /// Postfächer, deren Abruf auf diesem Gerät ausgeschaltet ist.
    var pausedAccountIDs: Set<UUID> = []
    /// Postfächer, deren Anmeldung abgelaufen ist.
    var signInRequiredIDs: Set<UUID> = []
    /// Postfächer, deren letzter Abruf den Server nicht erreichte.
    var unreachableIDs: Set<UUID> = []
    /// Ordnerbäume der Postfächer.
    let catalog: FolderCatalog
    /// Aufgeklappte Postfächer. Liegt beim Aufrufer, damit der Zustand
    /// das Schließen der Leiste übersteht – aber nicht einen App-Neustart.
    @Binding var expandedAccounts: Set<UUID>
    /// Gewählte Ansicht.
    @Binding var selection: MailboxSelection
    /// Anzahl ungelesener Mails der Posteingänge (Zahl an „Ungelesen“).
    var unreadCount: Int = 0
    /// Anzahl gekennzeichneter Mails (Zahl an „Mit Kennzeichnung“).
    var flaggedCount: Int = 0
    /// Legt einen Ordner an: Postfach, Server-Pfad des Elternordners
    /// (`nil` = oberste Ebene) und eingegebener Name.
    let onCreateFolder: (MailAccount, String?, String) async throws -> Void
    /// Löscht einen leeren Ordner und liefert das Ergebnis der Prüfung.
    let onDeleteFolder: (MailAccount, FolderNode) async throws -> FolderDeletion.Outcome
    /// Schließt die Leiste.
    let onClose: () -> Void
    /// Auf einen Ordner gezogene Mails (Kennungen) verschieben; `nil` = die
    /// Leiste nimmt nichts an (einblendbare Leiste, die die Liste verdeckt).
    var onDropMessages: ((MailAccount, FolderNode, [String]) -> Void)? = nil

    /// Offener Dialog „Neuer Ordner“.
    @State private var creation: FolderCreationRequest?
    /// Eingegebener Name im Dialog „Neuer Ordner“.
    @State private var newFolderName = ""
    /// Postfach, in dem gerade ein Ordner angelegt oder gelöscht wird.
    @State private var busyAccountID: UUID?
    /// Einziger Meldungskanal der Leiste.
    @State private var activeAlert: AlertItem?
    /// Einziger Rückfragekanal der Leiste.
    @State private var activeConfirmation: ConfirmationRequest?

    /// Aufbau: feste Einträge, Postfach-Abschnitte, Dialoge.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                collectionRow(.allInboxes)
                collectionRow(.unread, badge: unreadCount)
                collectionRow(.flagged, badge: flaggedCount)
                collectionRow(.spam)

                Divider()
                    .padding(.vertical, 8)

                if accounts.isEmpty {
                    Text("Kein Postfach eingerichtet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(accounts) { account in
                        AccountFolderSection(
                            account: account,
                            isPaused: pausedAccountIDs.contains(account.id),
                            needsSignIn: signInRequiredIDs.contains(account.id),
                            isUnreachable: unreachableIDs.contains(account.id),
                            state: catalog.state(for: account.id),
                            isBusy: busyAccountID == account.id,
                            isExpanded: expansionBinding(for: account.id),
                            selection: selection,
                            onSelect: { node in
                                select(.folder(
                                    accountID: account.id,
                                    path: node.id,
                                    displayName: node.name
                                ))
                            },
                            onNewFolder: { parent in
                                beginCreation(in: account, under: parent)
                            },
                            onDeleteFolder: { node in
                                confirmDeletion(of: node, in: account)
                            },
                            onRetry: { Task { await catalog.retry(account) } },
                            onDropMessages: onDropMessages.map { drop in
                                { (node: FolderNode, ids: [String]) in drop(account, node, ids) }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .refreshable {
            await catalog.reload(accounts, paused: pausedAccountIDs)
        }
        .task {
            await catalog.loadIfNeeded(accounts, paused: pausedAccountIDs)
        }
        .alert(
            creation?.title ?? "",
            isPresented: Binding(
                get: { creation != nil },
                set: { if !$0 { creation = nil } }
            ),
            presenting: creation
        ) { request in
            TextField("Name", text: $newFolderName)
            Button("Abbrechen", role: .cancel) {}
            Button("Anlegen") { create(request) }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { request in
            Text(request.location)
        }
        .confirmationRequest($activeConfirmation)
        .alertItem($activeAlert)
    }

    // MARK: - Ordner anlegen

    /// Öffnet den Dialog „Neuer Ordner“, sofern im Postfach nichts läuft.
    ///
    /// - Parameters:
    ///   - account: Postfach.
    ///   - parent: Übergeordneter Ordner, `nil` = oberste Ebene.
    private func beginCreation(in account: MailAccount, under parent: FolderNode?) {
        guard busyAccountID == nil else { return }
        newFolderName = ""
        creation = FolderCreationRequest(account: account, parent: parent)
    }

    /// Legt den Ordner über den Aufrufer an und lädt danach den Baum neu.
    ///
    /// - Parameter request: Postfach und Ort aus dem Dialog.
    private func create(_ request: FolderCreationRequest) {
        let name = newFolderName
        busyAccountID = request.account.id
        Task { @MainActor in
            defer { busyAccountID = nil }
            do {
                try await onCreateFolder(request.account, request.parent?.id, name)
                expandedAccounts.insert(request.account.id)
                await catalog.retry(request.account)
            } catch {
                activeAlert = .failure("Ordner nicht angelegt", error)
            }
        }
    }

    // MARK: - Ordner löschen

    /// Fragt vor dem Löschen eines Ordners nach, sofern im Postfach nichts läuft.
    ///
    /// - Parameters:
    ///   - node: Zu löschender Ordner.
    ///   - account: Postfach des Ordners.
    private func confirmDeletion(of node: FolderNode, in account: MailAccount) {
        guard busyAccountID == nil else { return }
        activeConfirmation = ConfirmationRequest(
            title: "„\(node.name)“ löschen?",
            message: "Gelöscht wird nur, wenn der Ordner leer ist. Das lässt sich nicht rückgängig machen.",
            confirmLabel: "Löschen"
        ) {
            delete(node, in: account)
        }
    }

    /// Löscht den Ordner über den Aufrufer.
    ///
    /// Verarbeitung: Wurde nicht gelöscht (enthält Mails, hat Unterordner,
    /// …), erklärt eine Meldung den Grund. Außer bei „enthält Mails“ ist
    /// die angezeigte Liste veraltet und wird neu geladen.
    ///
    /// - Parameters:
    ///   - node: Zu löschender Ordner.
    ///   - account: Postfach des Ordners.
    private func delete(_ node: FolderNode, in account: MailAccount) {
        busyAccountID = account.id
        Task { @MainActor in
            defer { busyAccountID = nil }
            do {
                let outcome = try await onDeleteFolder(account, node)
                if let message = outcome.userMessage {
                    activeAlert = AlertItem(title: "Ordner nicht gelöscht", message: message)
                }
                // Außer bei „enthält Mails“ ist die angezeigte Liste
                // veraltet – auch bei „gibt es nicht mehr“ oder
                // „hat inzwischen Unterordner“.
                if case .notEmpty = outcome {} else {
                    await catalog.retry(account)
                }
            } catch {
                activeAlert = .failure("Ordner nicht gelöscht", error)
            }
        }
    }

    /// Zeile einer Sammelansicht; Titel und Symbol kommen aus der Ansicht.
    ///
    /// - Parameters:
    ///   - view: Sammelansicht.
    ///   - badge: Zahl rechts; 0 bzw. `nil` = keine.
    /// - Returns: Die Zeile.
    private func collectionRow(_ view: MailboxSelection, badge: Int? = nil) -> some View {
        SidebarRow(
            title: view.title,
            systemImage: view.systemImage,
            badge: badge,
            isSelected: selection == view,
            action: { select(view) }
        )
    }

    /// Wählt eine Ansicht und schließt die Leiste.
    ///
    /// - Parameter newSelection: Gewählte Ansicht.
    private func select(_ newSelection: MailboxSelection) {
        selection = newSelection
        onClose()
    }

    /// Bindung „aufgeklappt“ für ein Postfach.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: Bindung an die Menge der aufgeklappten Postfächer.
    private func expansionBinding(for accountID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedAccounts.contains(accountID) },
            set: { isExpanded in
                if isExpanded {
                    expandedAccounts.insert(accountID)
                } else {
                    expandedAccounts.remove(accountID)
                }
            }
        )
    }
}

// MARK: - Postfach-Abschnitt

/// Abschnitt eines Postfachs: Kopfzeile zum Auf- und Zuklappen und
/// darunter der Ordnerbaum bzw. Lade- und Fehlerzustand.
private struct AccountFolderSection: View {
    /// Postfach.
    let account: MailAccount
    /// `true`, wenn der Abruf des Postfachs auf diesem Gerät ausgeschaltet ist.
    var isPaused = false
    /// `true`, wenn die Anmeldung des Postfachs abgelaufen ist.
    var needsSignIn = false
    /// `true`, wenn der letzte Abruf des Postfachs den Server nicht erreichte.
    var isUnreachable = false
    /// Ladezustand des Ordnerbaums.
    let state: FolderCatalog.State
    /// Eine Aktion im Postfach läuft (etwa: Ordner wird angelegt).
    var isBusy = false
    /// Abschnitt aufgeklappt.
    @Binding var isExpanded: Bool
    /// Gewählte Ansicht (für die Markierung des Ordners).
    let selection: MailboxSelection
    /// Ordner gewählt.
    let onSelect: (FolderNode) -> Void
    /// Dialog „Neuer Ordner“ öffnen; `nil` = oberste Ebene.
    let onNewFolder: (FolderNode?) -> Void
    /// Löschen eines Ordners angefragt.
    let onDeleteFolder: (FolderNode) -> Void
    /// Laden nach einem Fehler erneut versuchen.
    let onRetry: () -> Void
    /// Auf einen Ordner gezogene Mails verschieben; `nil` = keine Annahme.
    var onDropMessages: ((FolderNode, [String]) -> Void)? = nil

    /// Aufbau: Kopfzeile, bei aufgeklapptem Abschnitt der Inhalt.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                content
                    .padding(.bottom, 6)
            }
        }
    }

    /// Hinweise der Kennzeichen als ein Text; `nil` = keiner.
    private var statusSummary: String? {
        AccountStatusBadges.summary(needsSignIn: needsSignIn, isUnreachable: isUnreachable, isPaused: isPaused)
    }

    /// Kopfzeile: Pfeil, Farbpunkt, Kennzeichen (Anmeldung abgelaufen,
    /// nicht erreichbar, Abruf aus), Name, Ladeanzeige; Kontextmenü
    /// „Neuer Ordner …“. Die Hinweise der Kennzeichen stehen auch im
    /// Tooltip und in der VoiceOver-Beschreibung der ganzen Zeile – deren
    /// eigene Beschreibung würde sie sonst verdecken.
    private var header: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
                Circle()
                    .fill(account.colorHex.map { Color(hex: $0) } ?? Color.secondary)
                    .frame(width: 8, height: 8)
                AccountStatusBadges(
                    needsSignIn: needsSignIn,
                    isUnreachable: isUnreachable,
                    isPaused: isPaused,
                    font: .subheadline
                )
                Text(account.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if state == .loading || isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Neuer Ordner …", systemImage: "folder.badge.plus") {
                onNewFolder(nil)
            }
        }
        .accountStatusHelp(statusSummary)
        .accessibilityLabel(statusSummary.map { "Postfach \(account.displayName), \($0)" } ?? "Postfach \(account.displayName)")
        .accessibilityValue(isExpanded ? "aufgeklappt" : "zugeklappt")
    }

    /// Prüft, ob ein Ordner die gewählte Ansicht ist.
    ///
    /// - Parameter node: Ordner.
    /// - Returns: `true`, wenn gewählt.
    private func isFolderSelected(_ node: FolderNode) -> Bool {
        if case .folder(let id, let path, _) = selection {
            return id == account.id && path == node.id
        }
        return false
    }

    /// Löschen nur bei gewöhnlichen, wählbaren Ordnern; Sonderordner
    /// bekommen den Eintrag gar nicht.
    ///
    /// - Parameter node: Ordner.
    /// - Returns: Eintrag im Kontextmenü (verborgen, ausgegraut, aktiv).
    private func deletionOption(for node: FolderNode) -> FolderRow.DeletionOption {
        guard node.role == .regular, node.isSelectable else { return .hidden }
        if node.hasChildren { return .disabled("Löschen (enthält Unterordner)") }
        return .enabled { onDeleteFolder(node) }
    }

    /// Inhalt je nach Ladezustand: Hinweis, Fehler mit „Erneut versuchen“
    /// oder der eingerückte Ordnerbaum.
    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            Text("Ordner werden geladen …")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, FolderRow.baseIndent)
                .padding(.vertical, 6)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Ordner konnten nicht geladen werden.")
                    .font(.footnote)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Erneut versuchen", action: onRetry)
                    .font(.footnote)
            }
            .padding(.leading, FolderRow.baseIndent)
            .padding(.vertical, 6)

        case .loaded(let tree):
            if tree.isEmpty {
                Text("Keine Ordner gefunden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, FolderRow.baseIndent)
                    .padding(.vertical, 6)
            } else {
                let accountColor = account.colorHex.map { Color(hex: $0) } ?? Color.secondary
                ForEach(tree.indented()) { entry in
                    FolderRow(
                        entry: entry,
                        accountColor: accountColor,
                        isSelected: isFolderSelected(entry.node),
                        onSelect: { onSelect(entry.node) },
                        onNewSubfolder: { onNewFolder(entry.node) },
                        deletion: deletionOption(for: entry.node),
                        onDrop: onDropMessages.map { drop in
                            { (ids: [String]) in drop(entry.node, ids) }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Ordnerzeile

/// Eine Ordnerzeile. Wählbare Ordner reagieren auf Tipp; reine
/// Container (`\Noselect`) erscheinen abgeschwächt und sind nicht tippbar.
private struct FolderRow: View {
    /// Ordner mit Einrückungstiefe.
    let entry: IndentedFolder
    /// Farbe des Postfachs (Markierung des gewählten Ordners).
    let accountColor: Color
    /// Ordner ist die gewählte Ansicht.
    var isSelected = false
    /// Ordner gewählt.
    let onSelect: () -> Void
    /// „Neuer Unterordner …“ gewählt.
    let onNewSubfolder: () -> Void
    /// Eintrag „Löschen …“ im Kontextmenü.
    var deletion: DeletionOption = .hidden
    /// Auf den Ordner gezogene Mails (Kennungen) verschieben; `nil` = der
    /// Ordner nimmt nichts an.
    var onDrop: (([String]) -> Void)? = nil

    /// Eine gezogene Mail schwebt über dem Ordner (Hervorhebung).
    @State private var isDropTargeted = false

    /// Darstellung des Eintrags „Löschen …“.
    enum DeletionOption {
        /// Kein Eintrag (Sonderordner).
        case hidden
        /// Sichtbar, aber ausgegraut – mit Grund im Titel.
        case disabled(String)
        /// Aktiv, mit auszuführender Aktion.
        case enabled(() -> Void)
    }

    /// Einrückung der obersten Ordnerebene unter dem Postfachnamen –
    /// bündig mit dem Farbpunkt des Postfachs.
    static let baseIndent: CGFloat = 32
    /// Zusätzliche Einrückung je Unterordner-Ebene.
    static let levelIndent: CGFloat = 18

    /// Aufbau: Markierung, Ordnername, Kontextmenü.
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if isSelected {
                    Circle()
                        .fill(accountColor)
                        .frame(width: 6, height: 6)
                } else {
                    Color.clear.frame(width: 6, height: 6)
                }
                FolderLabel(node: entry.node, isEnabled: entry.node.isSelectable)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.leading, Self.baseIndent - 16 + CGFloat(entry.depth) * Self.levelIndent)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.25))
                } else if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.node.isSelectable)
        // Reine Container nehmen keine Mails auf.
        .modifier(MessageDropTarget(
            onDrop: entry.node.isSelectable ? onDrop : nil,
            isTargeted: $isDropTargeted
        ))
        .contextMenu {
            Button("Neuer Unterordner …", systemImage: "folder.badge.plus",
                   action: onNewSubfolder)
            switch deletion {
            case .hidden:
                EmptyView()
            case .disabled(let title):
                Button(title, systemImage: "trash", role: .destructive) {}
                    .disabled(true)
            case .enabled(let action):
                Button("Löschen …", systemImage: "trash", role: .destructive, action: action)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(entry.depth > 0 ? "Unterordner, Ebene \(entry.depth + 1)" : "")
    }
}

// MARK: - Mails auf einen Ordner ziehen

/// Macht eine Ordnerzeile zum Ziel für gezogene Mails.
///
/// Verarbeitung: Angenommen werden nur Ziehvorgänge aus Mailwerk selbst
/// (`localSession`); Text aus anderen Apps wird übergangen. Gezogen wird
/// die Kennung einer Mail; welche Kennungen gültig sind, prüft der
/// Aufrufer (MessageSelection.dropTargets). Die Hervorhebung beim
/// Darüberschweben setzt `onDropSessionUpdated` voraus (ab iOS 27); unter
/// iOS 26 funktioniert das Ablegen, nur ohne Hervorhebung.
private struct MessageDropTarget: ViewModifier {
    /// Verschiebt die gezogenen Mails; `nil` = kein Ziel.
    let onDrop: (([String]) -> Void)?
    /// Eine gezogene Mail schwebt über der Zeile.
    @Binding var isTargeted: Bool

    /// Zeile mit oder ohne Drop-Ziel.
    ///
    /// - Parameter content: Ordnerzeile.
    /// - Returns: Zeile, die gezogene Mails annimmt, bzw. unverändert.
    @ViewBuilder
    func body(content: Content) -> some View {
        if let onDrop {
            if #available(iOS 27.0, macOS 26.0, *) {
                accepting(content, onDrop: onDrop)
                    .onDropSessionUpdated { session in
                        switch session.phase {
                        case .entering, .active:
                            isTargeted = true
                        default:
                            isTargeted = false
                        }
                    }
            } else {
                accepting(content, onDrop: onDrop)
            }
        } else {
            content
        }
    }

    /// Nimmt gezogene Kennungen an, sofern sie aus der App stammen.
    ///
    /// - Parameters:
    ///   - content: Ordnerzeile.
    ///   - onDrop: Verschiebt die gezogenen Mails.
    /// - Returns: Zeile als Drop-Ziel.
    private func accepting(_ content: Content, onDrop: @escaping ([String]) -> Void) -> some View {
        content.dropDestination(for: String.self) { ids, session in
            isTargeted = false
            guard session.localSession != nil else { return }
            MainActor.assumeIsolated { onDrop(ids) }
        }
    }
}

// MARK: - Zeile „Alle Eingänge“

/// Eine auswählbare Zeile der Leiste. Die gewählte Ansicht wird
/// zurückhaltend mit der Akzentfarbe hinterlegt.
struct SidebarRow: View {
    /// Beschriftung.
    let title: String
    /// SF-Symbol.
    let systemImage: String
    /// Zahl rechts (z. B. gekennzeichnete Mails); `nil` = keine.
    var badge: Int? = nil
    /// Zeile ist die gewählte Ansicht.
    var isSelected = false
    /// Tipp auf die Zeile.
    let action: () -> Void

    /// Aufbau: Symbol, Titel, Zahl, Hinterlegung bei Auswahl.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Dialog „Neuer Ordner“

/// Wo ein neuer Ordner angelegt werden soll.
private struct FolderCreationRequest: Identifiable {
    /// Postfach.
    let account: MailAccount
    /// Übergeordneter Ordner, `nil` = oberste Ebene des Postfachs.
    let parent: FolderNode?

    /// Kennung für SwiftUI.
    var id: String { "\(account.id)|\(parent?.id ?? "")" }

    /// Titel des Dialogs.
    var title: String {
        parent == nil ? "Neuer Ordner" : "Neuer Unterordner"
    }

    /// Ort des neuen Ordners für den Dialogtext.
    var location: String {
        if let parent {
            return "In „\(parent.name)“ (\(account.displayName))"
        }
        return "Auf oberster Ebene von \(account.displayName)"
    }
}
