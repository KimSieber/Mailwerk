//
//  ColorPickerGrid.swift
//  Mailwerk
//
//  Created by Kim Sieber on 20.09.26.
//


//
//  ColorPickerGrid.swift
//  Mailwerk
//

import SwiftUI

/// Grid aus farbigen Kreisen zur Auswahl einer Account-Farbe.
/// `selection` ist `nil`, wenn keine Farbe gewählt ist (= kein Streifen in der Inbox).
struct ColorPickerGrid: View {
    @Binding var selection: AccountColor?

    private let columns = Array(
        repeating: GridItem(.fixed(44), spacing: 8),
        count: 6
    )
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            // "Keine Farbe"-Option
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

            // Farbkreise
            ForEach(AccountColor.allCases, id: \.rawValue) { color in
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
        .padding(.vertical, 4)
    }
    
}
