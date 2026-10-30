//
//  SelectionActionBar.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 12.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Schwebende Befehlsleiste am unteren Rand im Auswahlmodus der
//  Liste – vier Symbole ohne Text in einer Glas-Kapsel: Kennzeichnung,
//  Gelesen/Ungelesen, Verschieben, Löschen. Unten, weil das iPhone so mit
//  einer Hand bedienbar bleibt; der Platz ist sonst für die Suche
//  vorgesehen.
//
//  Die Symbole von Kennzeichnung und Gelesen zeigen, was der Tipp bei der
//  aktuellen Auswahl bewirkt (siehe MessageSelection). Jeder Knopf hat eine
//  ausführliche Bezeichnung für VoiceOver und Sprachsteuerung; bei sehr
//  großer Schrift zeigt iOS sie beim Gedrückthalten vergrößert an.
//
//  Abgrenzung: Regeln der Auswahl → MessageSelection; Ausführung →
//  InboxViewModel; Beschriftungen → MessageMenuLabels.
//
//  Abhängigkeiten: SwiftUI, MessageMenuLabels.
//

import SwiftUI

/// Befehlsleiste für ausgewählte Mails.
struct SelectionActionBar: View {
    /// Eintrag Kennzeichnung passend zur Auswahl.
    let flagEntry: MessageMenuLabels.Entry
    /// Eintrag Gelesen/Ungelesen passend zur Auswahl.
    let readEntry: MessageMenuLabels.Entry
    /// `false` = Auswahl leer; alle Knöpfe gesperrt.
    let hasSelection: Bool
    /// `false` = Auswahl aus mehreren Postfächern; Verschieben gesperrt.
    let canMove: Bool
    /// Kennzeichnung umschalten.
    let onFlag: () -> Void
    /// Gelesen-Status umschalten.
    let onRead: () -> Void
    /// Zielordner wählen.
    let onMove: () -> Void
    /// Löschen (mit Rückfrage).
    let onDelete: () -> Void

    /// Vier Symbole in einer schwebenden Glas-Kapsel.
    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            barButton(flagEntry, isEnabled: hasSelection, action: onFlag)
            barButton(readEntry, isEnabled: hasSelection, action: onRead)
            barButton(
                MessageMenuLabels.move,
                isEnabled: hasSelection && canMove,
                action: onMove
            )
            barButton(
                Self.deleteEntry,
                tint: .red,
                isEnabled: hasSelection,
                action: onDelete
            )
        }
        .padding(.horizontal, AppSpacing.regular)
        .padding(.vertical, AppSpacing.xSmall)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.bottom, AppSpacing.regular)
    }

    /// Löschen in der Leiste: Papierkorb-Symbol, Bezeichnung wie im Menü.
    private static let deleteEntry = MessageMenuLabels.Entry(
        title: "Löschen", systemImage: "trash", accessibility: "Ausgewählte Mails löschen"
    )

    /// Ein Knopf der Leiste: nur Symbol, ausführliche Bezeichnung für
    /// Bedienungshilfen.
    ///
    /// - Parameters:
    ///   - entry: Symbol und Bezeichnung.
    ///   - tint: Farbe des Symbols; `nil` = Standardfarbe.
    ///   - isEnabled: `false` = gesperrt und abgeblendet.
    ///   - action: Ausgelöste Aktion.
    /// - Returns: Knopf.
    private func barButton(
        _ entry: MessageMenuLabels.Entry,
        tint: Color? = nil,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: entry.systemImage)
                .font(.title3)
                .foregroundStyle(tint ?? Color.primary)
                .frame(width: 56, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(entry.accessibility)
        #if os(iOS)
        .accessibilityShowsLargeContentViewer {
            Label(entry.accessibility, systemImage: entry.systemImage)
        }
        #endif
    }
}
