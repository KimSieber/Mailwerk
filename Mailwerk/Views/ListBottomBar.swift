//
//  ListBottomBar.swift
//  Mailwerk
//
//  Zweck: Untere Leiste der Mailliste auf iPhone/iPad – bewusst eigene
//  Gestaltung als Markenzeichen von Mailwerk: eine Glas-Kapsel mit
//  Sortieren (links) und Neue Mail (rechts), in der Mitte die Suche als
//  großer Kreis in der Akzentfarbe (Mailwerk-Blau). Alle Flächen nutzen
//  den Glas-Effekt des Systems (Lichtkante und Wölbung in Hell und
//  Dunkel); die Kreise sind interaktiv.
//
//  Die Suche selbst bleibt das Suchfeld des Systems: Der Kreis öffnet es
//  nur. Es steht oben unter dem Titel, die Tastatur unten – so bleibt die
//  Bedienung einhändig. Solange gesucht wird, blendet die Liste diese
//  Leiste aus. Im Auswahlmodus ersetzt die Befehlsleiste
//  (SelectionActionBar) diese Leiste.
//
//  Abgrenzung: Inhalt des Sortiermenüs, Verfassen und Suche → InboxView;
//  Mac → Symbolleiste in InboxView.
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

/// Maße der unteren Leiste.
enum ListBottomBarMetrics {
    /// Platz für den Suchkreis in der Mitte (etwas höher als die Kapsel).
    static let searchDiameter: CGFloat = 66
    /// Breite und Höhe der Glas-Kapsel.
    static let capsuleSize = CGSize(width: 224, height: 58)
    /// Größe des Lupen-Symbols im Suchkreis.
    static let searchSymbolFrame: CGFloat = 40
    /// Größe der Symbole links und rechts.
    static let sideSymbolSize: CGFloat = 22
}

/// Untere Leiste der Mailliste: Sortieren, Suche, Neue Mail.
struct ListBottomBar<Sort: View>: View {
    /// Sortiermenü (links); liefert die Liste, weil es ihre Sortierung kennt.
    private let sort: Sort
    /// `false` = Neue Mail gesperrt (kein Postfach eingerichtet).
    private let isComposeEnabled: Bool
    /// Öffnet das Suchfeld.
    private let onSearch: () -> Void
    /// Öffnet das Verfassen-Fenster.
    private let onCompose: () -> Void

    /// Legt die Leiste an.
    ///
    /// - Parameters:
    ///   - isComposeEnabled: `false` = Neue Mail gesperrt.
    ///   - onSearch: Öffnet das Suchfeld.
    ///   - onCompose: Öffnet das Verfassen-Fenster.
    ///   - sort: Sortiermenü für den linken Platz.
    init(
        isComposeEnabled: Bool,
        onSearch: @escaping () -> Void,
        onCompose: @escaping () -> Void,
        @ViewBuilder sort: () -> Sort
    ) {
        self.isComposeEnabled = isComposeEnabled
        self.onSearch = onSearch
        self.onCompose = onCompose
        self.sort = sort()
    }

    /// Kapsel mit den seitlichen Knöpfen, darüber der Suchkreis.
    ///
    /// Verarbeitung: Kapsel und Kreis sind zwei getrennte Glasflächen –
    /// zu einer verschmolzen, würde der Kreis auf die Höhe der Kapsel
    /// beschnitten. Der Kreis ist Apples kräftiger Glasknopf
    /// (`glassProminent`) in der Akzentfarbe: klare Kante, Glanz in Hell und
    /// Dunkel.
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sort
                    .frame(width: 64, height: 54)
                Spacer(minLength: ListBottomBarMetrics.searchDiameter)
                Button(action: onCompose) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: ListBottomBarMetrics.sideSymbolSize, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 64, height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isComposeEnabled)
                .opacity(isComposeEnabled ? 1 : 0.35)
                .accessibilityLabel("Neue Nachricht")
            }
            .padding(.horizontal, 8)
            .frame(width: ListBottomBarMetrics.capsuleSize.width, height: ListBottomBarMetrics.capsuleSize.height)
            .glassEffect(.regular.interactive(), in: Capsule())

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(
                        width: ListBottomBarMetrics.searchSymbolFrame,
                        height: ListBottomBarMetrics.searchSymbolFrame
                    )
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .tint(Color.accentColor)
            .accessibilityLabel("Suchen")
        }
        .frame(height: ListBottomBarMetrics.searchDiameter + 4)
        .padding(.bottom, 6)
    }
}

/// Symbol des Sortiermenüs in der unteren Leiste: in Grundstellung wie die
/// anderen Symbole, bei abweichender Sortierung weiß auf einem Kreis in der
/// Akzentfarbe – so ist jederzeit erkennbar, dass die Liste nicht nach
/// Datum steht.
struct SortBarLabel: View {
    /// `true` = Sortierung weicht von „Datum, absteigend“ ab.
    let isChanged: Bool

    /// Symbol, bei Abweichung hervorgehoben.
    var body: some View {
        if isChanged {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.accentColor, in: Circle())
                .frame(width: 64, height: 54)
                .contentShape(Rectangle())
                .accessibilityLabel("Sortieren, geändert")
        } else {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: ListBottomBarMetrics.sideSymbolSize, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 64, height: 54)
                .contentShape(Rectangle())
                .accessibilityLabel("Sortieren")
        }
    }
}
