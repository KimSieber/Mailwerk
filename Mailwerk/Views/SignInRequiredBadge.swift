//
//  SignInRequiredBadge.swift
//  Mailwerk
//
//  Zweck: Kennzeichen „Anmeldung abgelaufen“ vor dem Namen eines
//  Postfachs – ein roter Kreis mit weißem Ausrufezeichen. Einheitlich in
//  der Postfachliste, der Ordnerleiste, unter „Postfach bearbeiten“ und in
//  der Hinweisleiste über der Mailliste; Gegenstück zum orangefarbenen
//  Pause-Zeichen (FetchPausedBadge).
//
//  Abgrenzung: Zustand → OAuthSignInState; Verwendung → AccountListView,
//  FolderSidebarView, EditAccountView, SignInRequiredBar.
//
//  Abhängigkeiten: SwiftUI.
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
            .help("Anmeldung abgelaufen")
            .accessibilityLabel("Anmeldung abgelaufen")
    }
}

// MARK: - Vorschau

#Preview {
    HStack(spacing: 6) {
        SignInRequiredBadge(font: .headline)
        Text("Outlook").font(.headline)
    }
    .padding()
}
