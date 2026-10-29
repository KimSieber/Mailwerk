//
//  CloudSearchSymbol.swift
//  Mailwerk
//
//  Zweck: Zusammengesetztes Symbol „Wolke mit Lupe“ für den Knopf „Auf
//  dem Server weitersuchen“ – auf allen Plattformen.
//
//  Aufbau: SF-Symbol `cloud`, unten rechts überlagert von
//  `magnifyingglass`. Die Lupe ist bewusst etwas größer als bei einer
//  üblichen Plakette (rund 62 % der Wolkengröße statt etwa 50 %) und durch
//  einen schmalen Rand in der Farbe des Untergrunds (Karte) von der Wolke
//  freigestellt, damit beide lesbar bleiben. Die Größe folgt der
//  Schriftgröße (Dynamic Type); die Farbe erbt das Symbol vom Text der
//  Zeile (`foregroundStyle` des Aufrufers).
//
//  Abhängigkeiten: SwiftUI, AppTheme.
//

import SwiftUI

/// Symbol „Wolke mit Lupe“.
struct CloudSearchSymbol: View {
    /// Grundgröße der Wolke; wächst mit der Schriftgröße.
    @ScaledMetric(relativeTo: .body) private var cloudSize: CGFloat = 19

    /// Anteil der Lupe an der Wolkengröße.
    private static let glassRatio: CGFloat = 0.62
    /// Breite der Freistellung um die Lupe in Punkt.
    private static let knockout: CGFloat = 1.5

    /// Wolke mit überlagerter Lupe.
    var body: some View {
        let glassSize = cloudSize * Self.glassRatio
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "cloud")
                .font(.system(size: cloudSize, weight: .regular))
                .frame(width: cloudSize * 1.3, height: cloudSize * 1.1, alignment: .topLeading)
            Image(systemName: "magnifyingglass")
                .font(.system(size: glassSize, weight: .bold))
                .padding(Self.knockout)
                .background(AppTheme.card, in: Circle())
        }
        .accessibilityHidden(true)
    }
}
