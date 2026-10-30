//
//  FetchPausedBadge.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 13.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Kennzeichen „Abruf ausgeschaltet“ vor dem Namen eines Postfachs –
//  ein orangefarbener Kreis mit weißem Pause-Zeichen. Einheitlich in der
//  Postfachliste und in der Ordnerleiste.
//
//  Abgrenzung: Schalter und Speichern → AccountStore; Verwendung →
//  AccountStatusBadges (Postfachliste, Ordnerleiste).
//
//  Abhängigkeiten: SwiftUI, AccountStatusBadges (Hinweistext).
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
            #if os(iOS)
            // Tooltip für Maus/Trackpad am iPad. Auf dem Mac erklärt die
            // Sprechblase beim Darüberfahren (AccountStatusBadges).
            .help(AccountStatusBadges.pausedText)
            #endif
            .accessibilityLabel(AccountStatusBadges.pausedText)
    }
}

// MARK: - Vorschau

#Preview {
    HStack(spacing: AppSpacing.small) {
        FetchPausedBadge(font: .headline)
        Text("Posteo").font(.headline)
    }
    .padding()
}
