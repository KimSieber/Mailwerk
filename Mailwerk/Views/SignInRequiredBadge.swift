//
//  SignInRequiredBadge.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 17.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Kennzeichen „Anmeldung abgelaufen“ vor dem Namen eines
//  Postfachs – ein roter Kreis mit weißem Ausrufezeichen. Einheitlich in
//  der Postfachliste, der Ordnerleiste, unter „Postfach bearbeiten“ und in
//  der Hinweisleiste über der Mailliste; Gegenstück zum orangefarbenen
//  Pause-Zeichen (FetchPausedBadge).
//
//  Abgrenzung: Zustand → OAuthSignInState; Verwendung → AccountStatusBadges
//  (Postfachliste, Ordnerleiste), EditAccountView, SignInRequiredBar.
//
//  Abhängigkeiten: SwiftUI, AccountStatusBadges (Hinweistext).
//

import SwiftUI

/// Rotes Warnzeichen für Postfächer, deren Anmeldung abgelaufen ist.
struct SignInRequiredBadge: View {
    /// Schriftgröße, an der sich das Zeichen ausrichtet (wie der Name daneben).
    var font: Font = .subheadline

    /// Ausgefülltes Ausrufezeichen: weiß auf rotem Kreis.
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .red)
            .font(font)
            #if os(iOS)
            // Tooltip für Maus/Trackpad am iPad. Auf dem Mac erklärt die
            // Sprechblase beim Darüberfahren (AccountStatusBadges).
            .help(AccountStatusBadges.signInText)
            #endif
            .accessibilityLabel(AccountStatusBadges.signInText)
    }
}

// MARK: - Vorschau

#Preview {
    HStack(spacing: AppSpacing.small) {
        SignInRequiredBadge(font: .headline)
        Text("Outlook").font(.headline)
    }
    .padding()
}
