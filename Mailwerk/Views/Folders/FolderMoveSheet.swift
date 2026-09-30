//
//  FolderMoveSheet.swift
//  Mailwerk
//
//  Dialog „In Ordner verschieben“ (v0.1.8c): der Ordnerbaum des Postfachs
//  der Mail – mit derselben Anzeige wie die Seitenleiste (`FolderLabel`,
//  `FolderTreeBuilder`), damit Ordner wiedererkennbar sind.
//
//  - Der gespeicherte Baum erscheint sofort, im Hintergrund wird vom
//    Server aktualisiert. Scheitert das, bleibt der gespeicherte Baum.
//  - Nicht wählbar: der aktuelle Ordner der Mail und reine Container.
//  - Offline bleibt der Dialog offen und meldet, dass Verschieben nicht
//    möglich ist. Verschoben wird nur zwischen Ordnern desselben Postfachs.
//

import SwiftUI

struct FolderMoveSheet: View {
    let account: MailAccount
    /// Server-Pfad des Ordners, in dem die Mail liegt.
    let currentFolder: String
    let accountStore: AccountStore
    /// Gewähltes Ziel (Server-Pfad); der Dialog schließt sich danach selbst.
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var tree: [FolderNode]?
    @State private var isRefreshing = false
    @State private var loadError: String?
    @State private var showOfflineNotice = false

    private let network = NetworkMonitor.shared

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("In Ordner verschieben")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
        }
        .macSheetFrame(.list)
        .task { await load() }
        .alert("Keine Verbindung", isPresented: $showOfflineNotice) {
            Button("OK") {}
        } message: {
            Text("Verschieben ist nur mit Verbindung zum Server möglich.")
        }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        if let tree {
            List(tree.indented()) { entry in
                row(entry)
            }
        } else if let loadError {
            ContentUnavailableView {
                Label("Ordner konnten nicht geladen werden", systemImage: "folder.badge.questionmark")
            } description: {
                Text(loadError)
            } actions: {
                Button("Erneut versuchen") { Task { await load() } }
            }
        } else {
            ProgressView("Ordner werden geladen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ entry: IndentedFolder) -> some View {
        let isTarget = entry.node.isMoveTarget(from: currentFolder)
        return Button {
            select(entry.node)
        } label: {
            HStack(spacing: 0) {
                FolderLabel(node: entry.node, isEnabled: isTarget)
                Spacer(minLength: 8)
                if entry.node.id == currentFolder {
                    Text("aktuell")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, CGFloat(entry.depth) * 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isTarget)
        .accessibilityHint(entry.depth > 0 ? "Unterordner, Ebene \(entry.depth + 1)" : "")
    }

    // MARK: - Aktionen

    private func select(_ node: FolderNode) {
        guard network.isOnline else {
            showOfflineNotice = true
            return
        }
        onSelect(node.id)
        dismiss()
    }

    /// Gespeicherter Baum sofort, danach Server. Fehler nur ohne Baum.
    private func load() async {
        if tree == nil, let listing = MessageStore.shared.folderListing(accountID: account.id) {
            tree = FolderTreeBuilder.build(listing: listing, configuredSpamFolder: account.spamFolder)
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        loadError = nil

        do {
            tree = try await MailActionService.fetchFolderTree(for: account, accountStore: accountStore)
        } catch where error is CancellationError || Task.isCancelled {
            // Dialog geschlossen – nichts zu tun.
        } catch {
            print("⚠️ [\(account.displayName)] Ordnerliste für Verschieben: \(error.localizedDescription)")
            if tree == nil { loadError = error.localizedDescription }
        }
    }
}
