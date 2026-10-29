//
//  FetchFailedBadge.swift
//  Mailwerk
//
//  Zweck: Kennzeichen „Postfach nicht erreichbar“ vor dem Namen eines
//  Postfachs – ein gelbes Warndreieck mit schwarzem Ausrufezeichen.
//  Gegenstück zum roten „Anmeldung abgelaufen“ (SignInRequiredBadge) und
//  zum orangefarbenen Pause-Zeichen (FetchPausedBadge).
//
//  Abgrenzung: Zustand → AccountFetchState; Verwendung →
//  AccountStatusBadges (Postfachliste, Ordnerleiste).
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

/// Gelbes Warnzeichen für Postfächer, deren letzter Abruf den Server
/// nicht erreicht hat.
struct FetchFailedBadge: View {
    /// Schriftgröße, an der sich das Zeichen ausrichtet (wie der Name daneben).
    var font: Font = .subheadline

    /// Ausgefülltes Warndreieck: schwarzes Ausrufezeichen auf gelbem Grund.
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, .yellow)
            .font(font)
            #if os(iOS)
            // Tooltip für Maus/Trackpad am iPad. Auf dem Mac erklärt die
            // Sprechblase beim Darüberfahren (AccountStatusBadges).
            .help(AccountStatusBadges.unreachableText)
            #endif
            .accessibilityLabel(AccountStatusBadges.unreachableText)
    }
}

// MARK: - Vorschau

#Preview {
    HStack(spacing: 6) {
        FetchFailedBadge(font: .headline)
        Text("GMX").font(.headline)
    }
    .padding()
}
