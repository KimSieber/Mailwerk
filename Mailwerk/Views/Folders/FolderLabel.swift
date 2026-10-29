//
//  FolderLabel.swift
//  Mailwerk
//
//  Zweck: Symbol und Name einer Ordnerzeile – gemeinsamer Baustein für die
//  Seitenleiste und den Verschieben-Dialog. So sehen Ordner überall gleich
//  aus und bleiben wiedererkennbar.
//
//  Abgrenzung: Seitenleiste → FolderSidebarView; Verschieben →
//  FolderMoveSheet.
//
//  Abhängigkeiten: SwiftUI, FolderNode.
//

import SwiftUI

/// Symbol und Name eines Ordners.
struct FolderLabel: View {
    /// Angezeigter Ordner.
    let node: FolderNode
    /// Ausgegraut, wenn der Ordner an dieser Stelle nicht wählbar ist.
    var isEnabled = true

    /// Symbol der Rolle und Name, ausgegraut, wenn nicht wählbar.
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: node.role.systemImage)
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            Text(node.name)
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .lineLimit(1)
        }
    }
}
