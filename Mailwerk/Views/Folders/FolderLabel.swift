//
//  FolderLabel.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 30.09.2026
//  Geändert: 30.10.2026
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
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: node.role.systemImage)
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            Text(node.name)
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .lineLimit(1)
        }
    }
}
