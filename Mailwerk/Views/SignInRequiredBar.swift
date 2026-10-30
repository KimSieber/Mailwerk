//
//  SignInRequiredBar.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 17.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Schmaler Hinweis über der Mailliste, wenn die Anmeldung eines
//  Postfachs abgelaufen ist: „Anmeldung für ‚…‘ abgelaufen – Neu
//  anmelden“. Ein Tipp auf die Leiste öffnet direkt das Anmeldefenster
//  des Anbieters, ohne Umweg über die Einstellungen. Die Leiste bleibt,
//  bis die Anmeldung erneuert ist; während der Anmeldung zeigt sie eine
//  Ladeanzeige.
//
//  Abgrenzung: Wann sie erscheint und was der Tipp auslöst → InboxView;
//  Zustand → OAuthSignInState.
//
//  Abhängigkeiten: SwiftUI, SignInRequiredBadge.
//

import SwiftUI

/// Hinweisleiste „Anmeldung abgelaufen – Neu anmelden“.
struct SignInRequiredBar: View {
    /// Bezeichnung des Postfachs.
    let accountName: String
    /// Anmeldung läuft gerade.
    var isRenewing = false
    /// Öffnet das Anmeldefenster.
    let onRenew: () -> Void

    /// Ganze Leiste als Knopf: Warnzeichen, Text, „Neu anmelden“.
    var body: some View {
        Button(action: onRenew) {
            HStack(spacing: AppSpacing.regular) {
                SignInRequiredBadge(font: .subheadline)
                Text("Anmeldung für „\(accountName)“ abgelaufen")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: AppSpacing.xSmall)
                if isRenewing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Neu anmelden")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, AppSpacing.xLarge)
            .padding(.vertical, AppSpacing.regular)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRenewing)
        .accessibilityHint("Öffnet die Anmeldeseite des Anbieters")
    }
}

// MARK: - Vorschau

#Preview {
    VStack(spacing: 0) {
        SignInRequiredBar(accountName: "Outlook", onRenew: {})
        SignInRequiredBar(accountName: "Outlook", isRenewing: true, onRenew: {})
    }
}
