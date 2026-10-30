//
//  FlowLayout.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 23.09.2026
//  Geändert: 11.10.2026
//
//  Zweck: Einfaches Layout, das seine Elemente von links nach rechts
//  anordnet und bei Platzmangel umbricht. Wird für die Adress-Chips
//  gebraucht.
//
//  Abgrenzung: Adressfeld → RecipientField.
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

/// Fließendes Layout mit Zeilenumbruch.
struct FlowLayout: Layout {
    /// Abstand zwischen Elementen einer Zeile.
    var spacing: CGFloat = 6
    /// Abstand zwischen den Zeilen.
    var lineSpacing: CGFloat = 6

    /// Benötigte Größe für die vorgeschlagene Breite.
    ///
    /// - Parameters:
    ///   - proposal: Vorgeschlagene Größe.
    ///   - subviews: Elemente.
    ///   - cache: Nicht verwendet.
    /// - Returns: Breite der längsten Zeile und Höhe aller Zeilen.
    nonisolated func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(into: CGFloat.zero) { result, row in
            result += row.height
        } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    /// Setzt die Elemente zeilenweise, je Zeile vertikal mittig.
    ///
    /// - Parameters:
    ///   - bounds: Verfügbarer Bereich.
    ///   - proposal: Vorgeschlagene Größe.
    ///   - subviews: Elemente.
    ///   - cache: Nicht verwendet.
    nonisolated func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    // MARK: - Umbruch berechnen

    /// Ein Element mit Index und gemessener Größe.
    private struct Item {
        let index: Int
        let size: CGSize
    }

    /// Eine Zeile mit ihren Elementen, Breite und Höhe.
    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Verteilt die Elemente auf Zeilen.
    ///
    /// Verarbeitung: Kein Element wird breiter als die Zeile – sonst ragt
    /// z. B. ein langer Adress-Chip über den Rand hinaus.
    ///
    /// - Parameters:
    ///   - subviews: Elemente.
    ///   - maxWidth: Verfügbare Breite.
    /// - Returns: Zeilen.
    private nonisolated func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            let measured = subviews[index].sizeThatFits(
                ProposedViewSize(width: maxWidth, height: nil)
            )
            // Kein Element darf breiter als die Zeile werden – sonst ragt
            // z. B. ein langer Adress-Chip über den Rand hinaus.
            let size = CGSize(width: min(measured.width, maxWidth), height: measured.height)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty && needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(index: index, size: size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
