//
//  FolderSidebarView.swift
//  Mailwerk
//
//  Inhalt der Ordnerleiste. Oben „Alle Eingänge“ – die aktuelle Ansicht,
//  ein Tipp darauf schließt die Leiste. Darunter je Postfach ein
//  aufklappbarer Abschnitt mit dem Ordnerbaum.
//
//  v0.1.7d: Ordner sind auswählbar – Tipp zeigt den Ordnerinhalt.
//  Unterordner sind immer sichtbar und nur durch Einrückung erkennbar;
//  auf- und zuklappen lassen sich nur die Postfächer.
//
//  v0.1.8a: Langes Drücken (Mac: Rechtsklick) öffnet ein Kontextmenü –
//  am Postfach „Neuer Ordner …“, an einem Ordner „Neuer Unterordner …“
//  und bei gewöhnlichen Ordnern „Löschen …“. Sonderordner lassen sich
//  nicht löschen; bei Unterordnern ist der Eintrag ausgegraut. Ob ein
//  Ordner Mails enthält, prüft erst der Server unmittelbar vor dem Löschen.
//  Anlegen und Löschen übernimmt der Aufrufer (`onCreateFolder`,
//  `onDeleteFolder`).
//

import SwiftUI

struct FolderSidebarView: View {
    let accounts: [MailAccount]
    let catalog: FolderCatalog
    /// Aufgeklappte Postfächer. Liegt beim Aufrufer, damit der Zustand
    /// das Schließen der Leiste übersteht – aber nicht einen App-Neustart.
    @Binding var expandedAccounts: Set<UUID>
    @Binding var selection: MailboxSelection
    var flaggedCount: Int = 0
    /// Legt einen Ordner an: Postfach, Server-Pfad des Elternordners
    /// (`nil` = oberste Ebene) und eingegebener Name.
    let onCreateFolder: (MailAccount, String?, String) async throws -> Void
    /// Löscht einen leeren Ordner und liefert das Ergebnis der Prüfung.
    let onDeleteFolder: (MailAccount, FolderNode) async throws -> FolderDeletion.Outcome
    let onClose: () -> Void

    /// Offener Dialog „Neuer Ordner“.
    @State private var creation: FolderCreationRequest?
    @State private var newFolderName = ""
    /// Offene Rückfrage „Ordner löschen?“.
    @State private var deletion: FolderDeletionRequest?
    /// Postfach, in dem gerade ein Ordner angelegt oder gelöscht wird.
    @State private var busyAccountID: UUID?
    /// Meldung nach einer gescheiterten Aktion.
    @State private var failure: FolderActionFailure?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SidebarRow(
                    title: "Alle Eingänge",
                    systemImage: "tray.2",
                    isSelected: selection == .allInboxes,
                    action: { select(.allInboxes) }
                )

                SidebarRow(
                    title: "Mit Kennzeichnung",
                    systemImage: "flag",
                    badge: flaggedCount > 0 ? flaggedCount : nil,
                    isSelected: selection == .flagged,
                    action: { select(.flagged) }
                )

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
                            state: catalog.state(for: account.id),
                            isBusy: busyAccountID == account.id,
                            canDeleteFolders: account.imapPort == MailActionService.folderDeletionPort,
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
                                guard busyAccountID == nil else { return }
                                deletion = FolderDeletionRequest(account: account, node: node)
                            },
                            onRetry: { Task { await catalog.retry(account) } }
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .refreshable {
            await catalog.reload(accounts)
        }
        .task {
            await catalog.loadIfNeeded(accounts)
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
        .alert(
            deletion.map { "„\($0.node.name)“ löschen?" } ?? "",
            isPresented: Binding(
                get: { deletion != nil },
                set: { if !$0 { deletion = nil } }
            ),
            presenting: deletion
        ) { request in
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { delete(request) }
        } message: { _ in
            Text("Gelöscht wird nur, wenn der Ordner leer ist. Das lässt sich nicht rückgängig machen.")
        }
        .alert(
            failure?.title ?? "",
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            ),
            presenting: failure
        ) { _ in
            Button("OK") { failure = nil }
        } message: { failure in
            Text(failure.message)
        }
    }

    // MARK: - Ordner anlegen

    private func beginCreation(in account: MailAccount, under parent: FolderNode?) {
        guard busyAccountID == nil else { return }
        newFolderName = ""
        creation = FolderCreationRequest(account: account, parent: parent)
    }

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
                failure = FolderActionFailure(title: "Ordner nicht angelegt", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Ordner löschen

    private func delete(_ request: FolderDeletionRequest) {
        busyAccountID = request.account.id
        Task { @MainActor in
            defer { busyAccountID = nil }
            do {
                let outcome = try await onDeleteFolder(request.account, request.node)
                if let message = outcome.userMessage {
                    failure = FolderActionFailure(title: "Ordner nicht gelöscht", message: message)
                }
                // Außer bei „enthält Mails“ ist die angezeigte Liste
                // veraltet – auch bei „gibt es nicht mehr“ oder
                // „hat inzwischen Unterordner“.
                if case .notEmpty = outcome {} else {
                    await catalog.retry(request.account)
                }
            } catch {
                failure = FolderActionFailure(title: "Ordner nicht gelöscht", message: error.localizedDescription)
            }
        }
    }

    private func select(_ newSelection: MailboxSelection) {
        selection = newSelection
        onClose()
    }

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

private struct AccountFolderSection: View {
    let account: MailAccount
    let state: FolderCatalog.State
    /// Eine Aktion im Postfach läuft (etwa: Ordner wird angelegt).
    var isBusy = false
    /// Der eigene Lösch-Weg arbeitet nur mit Port 993.
    var canDeleteFolders = true
    @Binding var isExpanded: Bool
    let selection: MailboxSelection
    let onSelect: (FolderNode) -> Void
    /// Dialog „Neuer Ordner“ öffnen; `nil` = oberste Ebene.
    let onNewFolder: (FolderNode?) -> Void
    let onDeleteFolder: (FolderNode) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                content
                    .padding(.bottom, 6)
            }
        }
    }

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
        .accessibilityLabel("Postfach \(account.displayName)")
        .accessibilityValue(isExpanded ? "aufgeklappt" : "zugeklappt")
    }

    private func isFolderSelected(_ node: FolderNode) -> Bool {
        if case .folder(let id, let path, _) = selection {
            return id == account.id && path == node.id
        }
        return false
    }

    /// Löschen nur bei gewöhnlichen, wählbaren Ordnern; Sonderordner
    /// bekommen den Eintrag gar nicht.
    private func deletionOption(for node: FolderNode) -> FolderRow.DeletionOption {
        guard node.role == .regular, node.isSelectable else { return .hidden }
        if !canDeleteFolders { return .disabled("Löschen (nur über Port 993)") }
        if node.hasChildren { return .disabled("Löschen (enthält Unterordner)") }
        return .enabled { onDeleteFolder(node) }
    }

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
                        deletion: deletionOption(for: entry.node)
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
    let entry: IndentedFolder
    let accountColor: Color
    var isSelected = false
    let onSelect: () -> Void
    let onNewSubfolder: () -> Void
    var deletion: DeletionOption = .hidden

    enum DeletionOption {
        case hidden
        /// Sichtbar, aber ausgegraut – mit Grund im Titel.
        case disabled(String)
        case enabled(() -> Void)
    }

    /// Einrückung der obersten Ordnerebene unter dem Postfachnamen –
    /// bündig mit dem Farbpunkt des Postfachs.
    static let baseIndent: CGFloat = 32
    /// Zusätzliche Einrückung je Unterordner-Ebene.
    static let levelIndent: CGFloat = 18

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
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.node.isSelectable)
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

// MARK: - Zeile „Alle Eingänge“

/// Eine auswählbare Zeile der Leiste. Die gewählte Ansicht wird
/// zurückhaltend mit der Akzentfarbe hinterlegt.
struct SidebarRow: View {
    let title: String
    let systemImage: String
    var badge: Int? = nil
    var isSelected = false
    let action: () -> Void

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
    let account: MailAccount
    /// Übergeordneter Ordner, `nil` = oberste Ebene des Postfachs.
    let parent: FolderNode?

    var id: String { "\(account.id)|\(parent?.id ?? "")" }

    var title: String {
        parent == nil ? "Neuer Ordner" : "Neuer Unterordner"
    }

    var location: String {
        if let parent {
            return "In „\(parent.name)“ (\(account.displayName))"
        }
        return "Auf oberster Ebene von \(account.displayName)"
    }
}

// MARK: - Rückfrage „Ordner löschen“ und Fehlermeldung

private struct FolderDeletionRequest: Identifiable {
    let account: MailAccount
    let node: FolderNode

    var id: String { "\(account.id)|\(node.id)" }
}

private struct FolderActionFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
