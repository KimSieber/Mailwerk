//
//  FolderMoveSheet.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 30.09.2026
//  Geändert: 31.10.2026
//
//  Zweck: Dialog „In Ordner verschieben“ – der Ordnerbaum des Postfachs
//  der Mail mit derselben Anzeige wie die Seitenleiste (`FolderLabel`,
//  `FolderTreeBuilder`), damit Ordner wiedererkennbar sind.
//
//  - Der gespeicherte Baum erscheint sofort, im Hintergrund wird vom
//    Server aktualisiert. Scheitert das, bleibt der gespeicherte Baum.
//  - Nicht wählbar: der aktuelle Ordner der Mail und reine Container.
//  - Offline bleibt der Dialog offen und meldet, dass Verschieben nicht
//    möglich ist. Verschoben wird nur zwischen Ordnern desselben Postfachs.
//  - Getönte Fläche mit Zeilen als Karten wie in der ganzen App (AppTheme).
//  - Mac: feste Kopfleiste oben mit ✕ (SheetHeaderBar) statt
//    Symbolleiste.
//
//  Abgrenzung: Das Verschieben selbst → MessageActions (Aufrufer);
//  Ordnerliste → MailActionService.
//
//  Abhängigkeiten: SwiftUI, MailActionService, MessageStore,
//  FolderTreeBuilder, FolderLabel, NetworkMonitor, Dialogs, AppTheme,
//  SheetHeaderBar, Log.
//

import SwiftUI
import os

/// Auswahl des Zielordners beim Verschieben einer Mail.
struct FolderMoveSheet: View {
    /// Postfach der Mail.
    let account: MailAccount
    /// Server-Pfad des Ordners, in dem die Mail liegt.
    let currentFolder: String
    /// Quelle für die Zugangsdaten.
    let accountStore: AccountStore
    /// Gewähltes Ziel (Server-Pfad); der Dialog schließt sich danach selbst.
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Ordnerbaum; `nil`, solange keiner vorliegt.
    @State private var tree: [FolderNode]?
    /// Abruf vom Server läuft.
    @State private var isRefreshing = false
    /// Fehlertext, wenn weder gespeicherter noch frischer Baum vorliegt.
    @State private var loadError: String?
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?

    /// Netzzustand (online/offline).
    private let network = NetworkMonitor.shared

    /// Ordnerbaum mit „Abbrechen“; lädt beim Erscheinen.
    var body: some View {
        NavigationStack {
            content
                .appBackground()
                .navigationTitle("In Ordner verschieben")
                // Mac: feste Kopfleiste mit ✕ statt Symbolleiste.
                .macSheetHeader("In Ordner verschieben") {
                    HeaderCircleButton.cancel { dismiss() }
                } trailing: {
                    EmptyView()
                }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() }
                    }
                }
                #endif
        }
        .macSheetFrame(.list)
        .task { await load() }
        .alertItem($activeAlert)
    }

    // MARK: - Inhalt

    /// Baum, Fehlerhinweis mit „Erneut versuchen“ oder Ladeanzeige.
    @ViewBuilder
    private var content: some View {
        if let tree {
            List(tree.indented()) { entry in
                row(entry)
                    .cardRowBackground()
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

    /// Zeile eines Ordners; nicht wählbare Ordner sind gesperrt.
    ///
    /// - Parameter entry: Ordner mit Einrücktiefe.
    /// - Returns: Die Zeile.
    private func row(_ entry: IndentedFolder) -> some View {
        let isTarget = entry.node.isMoveTarget(from: currentFolder)
        return Button {
            select(entry.node)
        } label: {
            HStack(spacing: 0) {
                FolderLabel(node: entry.node, isEnabled: isTarget)
                Spacer(minLength: AppSpacing.regular)
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

    /// Übernimmt den gewählten Ordner und schließt den Dialog.
    ///
    /// Verarbeitung: Offline bleibt der Dialog offen, eine Meldung erklärt
    /// den Grund.
    ///
    /// - Parameter node: Gewählter Ordner.
    private func select(_ node: FolderNode) {
        guard network.isOnline else {
            activeAlert = AlertItem(
                title: "Keine Verbindung",
                message: "Verschieben ist nur mit Verbindung zum Server möglich."
            )
            return
        }
        onSelect(node.id)
        dismiss()
    }

    /// Lädt den Ordnerbaum.
    ///
    /// Verarbeitung: Gespeicherter Baum sofort, danach vom Server. Ein
    /// Fehler erscheint nur, wenn es keinen Baum gibt.
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
            Log.view.error("⚠️ [\(account.displayName, privacy: .private)] Ordnerliste für Verschieben: \(error.localizedDescription, privacy: .public)")
            if tree == nil { loadError = error.localizedDescription }
        }
    }
}
