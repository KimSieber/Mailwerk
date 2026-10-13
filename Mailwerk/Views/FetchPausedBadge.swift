//
//  FetchPausedBadge.swift
//  Mailwerk
//
//  Zweck: Kennzeichen „Abruf ausgeschaltet“ vor dem Namen eines Postfachs –
//  ein orangefarbener Kreis mit weißem Pause-Zeichen. Einheitlich in der
//  Postfachliste und in der Ordnerleiste.
//
//  Abgrenzung: Schalter und Speichern → AccountStore; Verwendung →
//  AccountListView, FolderSidebarView.
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

/// Orangefarbenes Pause-Zeichen für Postfächer mit ausgeschaltetem Abruf.
struct FetchPausedBadge: View {
    /// Schriftgröße, an der sich das Zeichen ausrichtet (wie der Name daneben).
    var font: Font = .subheadline

    /// Ausgefülltes Pause-Symbol: weiße Balken auf orangefarbenem Kreis.
    var body: some View {
        Image(systemName: "pause.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .orange)
            .font(font)
            .help("Abruf ausgeschaltet")
            .accessibilityLabel("Abruf ausgeschaltet")
    }
}

// MARK: - Vorschau

#Preview {
    HStack(spacing: 6) {
        FetchPausedBadge(font: .headline)
        Text("Posteo").font(.headline)
    }
    .padding()
}
