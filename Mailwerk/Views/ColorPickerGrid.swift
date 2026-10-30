//
//  ColorPickerGrid.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 20.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Raster aus Farbkreisen zur Wahl der Postfach-Farbe, dazu die
//  Option „Keine Farbe“ (kein Streifen in der Liste).
//
//  Abgrenzung: Farbpalette → AccountColor; Formulare → AddAccountView,
//  EditAccountView.
//
//  Abhängigkeiten: SwiftUI, AccountColor.
//

import SwiftUI

/// Grid aus farbigen Kreisen zur Auswahl einer Account-Farbe.
/// `selection` ist `nil`, wenn keine Farbe gewählt ist (= kein Streifen in der Inbox).
struct ColorPickerGrid: View {
    /// Gewählte Farbe; `nil` = keine Farbe.
    @Binding var selection: AccountColor?

    /// Sechs Spalten fester Breite.
    private let columns = Array(
        repeating: GridItem(.fixed(44), spacing: AppSpacing.regular),
        count: 6
    )
    
    /// Option „Keine Farbe“ und je Farbe ein Kreis mit Häkchen bei Auswahl.
    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.large) {
            noColorOption
            ForEach(AccountColor.allCases, id: \.rawValue) { color in
                colorOption(color)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }

    /// Umrandeter Kreis für „Keine Farbe“: Häkchen bei Auswahl, sonst ein
    /// Strich.
    private var noColorOption: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1)
                .frame(width: 36, height: 36)
            if selection == nil {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "minus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Circle())
        .onTapGesture { selection = nil }
        .accessibilityLabel("Keine Farbe")
    }

    /// Gefüllter Kreis einer Farbe, mit Häkchen bei Auswahl.
    ///
    /// - Parameter color: Darzustellende Farbe.
    /// - Returns: Antippbarer Farbkreis.
    private func colorOption(_ color: AccountColor) -> some View {
        ZStack {
            Circle()
                .fill(color.color)
                .frame(width: 36, height: 36)
            if selection == color {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Circle())
        .onTapGesture { selection = color }
        .accessibilityLabel(color.displayName)
    }
}
