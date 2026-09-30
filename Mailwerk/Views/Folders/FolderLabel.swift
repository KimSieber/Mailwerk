//
//  FolderLabel.swift
//  Mailwerk
//
//  Symbol und Name einer Ordnerzeile – gemeinsamer Baustein für die
//  Seitenleiste und den Verschieben-Dialog (v0.1.8c). So sehen Ordner
//  überall gleich aus und bleiben wiedererkennbar.
//

import SwiftUI

struct FolderLabel: View {
    let node: FolderNode
    /// Ausgegraut, wenn der Ordner an dieser Stelle nicht wählbar ist.
    var isEnabled = true

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
