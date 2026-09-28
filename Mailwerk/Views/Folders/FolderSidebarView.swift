//
//  FolderSidebarView.swift
//  Mailwerk
//
//  Inhalt der Ordnerleiste. Oben „Alle Eingänge“ – die aktuelle Ansicht,
//  ein Tipp darauf schließt die Leiste. Darunter je Postfach ein
//  aufklappbarer Abschnitt mit dem Ordnerbaum.
//
//  v0.1.7a: nur Anzeige. Ordner sind noch nicht auswählbar.
//  Unterordner sind immer sichtbar und nur durch Einrückung erkennbar;
//  auf- und zuklappen lassen sich nur die Postfächer.
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
    let onClose: () -> Void

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
                            isExpanded: expansionBinding(for: account.id),
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
    @Binding var isExpanded: Bool
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
                if state == .loading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Postfach \(account.displayName)")
        .accessibilityValue(isExpanded ? "aufgeklappt" : "zugeklappt")
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
                ForEach(tree.indented()) { entry in
                    FolderRow(entry: entry)
                }
            }
        }
    }
}

// MARK: - Ordnerzeile

/// Eine Ordnerzeile. In v0.1.7a reine Anzeige ohne Aktion.
/// Reine Container (`\Noselect`) erscheinen abgeschwächt.
private struct FolderRow: View {
    let entry: IndentedFolder

    /// Einrückung der obersten Ordnerebene unter dem Postfachnamen –
    /// bündig mit dem Farbpunkt des Postfachs.
    static let baseIndent: CGFloat = 32
    /// Zusätzliche Einrückung je Unterordner-Ebene.
    static let levelIndent: CGFloat = 18

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.node.role.systemImage)
                .foregroundStyle(entry.node.isSelectable ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            Text(entry.node.name)
                .foregroundStyle(entry.node.isSelectable ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.leading, Self.baseIndent + CGFloat(entry.depth) * Self.levelIndent)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
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
