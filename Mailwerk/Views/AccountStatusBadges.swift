//
//  AccountStatusBadges.swift
//  Mailwerk
//
//  Zweck: Die Kennzeichen eines Postfachs vor seinem Namen, einheitlich
//  in der Postfachliste und in der Ordnerleiste – in fester Reihenfolge:
//  - rot: Anmeldung abgelaufen (SignInRequiredBadge),
//  - gelb: Postfach nicht erreichbar (FetchFailedBadge),
//  - orange: Abruf ausgeschaltet (FetchPausedBadge).
//
//  Erklärung der Zeichen:
//  - iPad mit Maus/Trackpad: Tooltip beim Darüberfahren. Jedes
//    Zeichen trägt ihn selbst; zusätzlich liefert `summary` alle
//    zutreffenden Hinweise als einen Text für den Tooltip der ganzen
//    Zeile und deren VoiceOver-Beschreibung. Nötig, weil die Zeilen Knöpfe
//    sind: Ein Knopf fasst seinen Inhalt zu einem Element zusammen, und
//    die Ordnerleiste gibt dem Postfachkopf eine eigene Beschreibung, die
//    die Hinweise der Zeichen sonst verdecken würde.
//  - Mac: Statt des knappen, verzögerten System-Tooltips öffnet
//    sich beim Darüberfahren nach kurzer Pause (0,25 s) dieselbe
//    Sprechblase wie auf iOS – Titel und erklärender Text, identisch auf
//    allen Plattformen. Verlässt der Mauszeiger das Zeichen, schließt sie
//    sich; ein Klick auf das Zeichen öffnet sie ebenfalls (ohne die Zeile
//    auszulösen). Der Tooltip der ganzen Zeile entfällt dort.
//  - iPhone/iPad per Finger: Ein Tipp auf ein Zeichen öffnet eine kleine
//    Sprechblase (Popover) mit Titel und Erklärung – Apples übliche Form
//    für „Was bedeutet das?“ auf Touch-Geräten. Der Tipp auf das Zeichen
//    geht dem Tipp auf die Zeile vor: Das Postfach klappt nicht auf, die
//    Bearbeitung öffnet sich nicht. Die Tippfläche ist größer als das
//    Zeichen, damit es sich gut treffen lässt.
//
//  Abgrenzung: Zustände → OAuthSignInState, AccountFetchState,
//  AccountStore (Abruf an/aus).
//
//  Abhängigkeiten: SwiftUI, SignInRequiredBadge, FetchFailedBadge,
//  FetchPausedBadge.
//

import SwiftUI

/// Kennzeichen eines Postfachs in fester Reihenfolge.
struct AccountStatusBadges: View {
    /// Anmeldung abgelaufen (rot).
    var needsSignIn = false
    /// Letzter Abruf erreichte den Server nicht (gelb).
    var isUnreachable = false
    /// Abruf auf diesem Gerät ausgeschaltet (orange).
    var isPaused = false
    /// Schriftgröße, an der sich die Zeichen ausrichten.
    var font: Font = .subheadline

    /// Hinweistext „Anmeldung abgelaufen“.
    static let signInText = "Anmeldung abgelaufen"
    /// Hinweistext „Postfach nicht erreichbar“.
    static let unreachableText = "Postfach nicht erreichbar"
    /// Hinweistext „Abruf ausgeschaltet“.
    static let pausedText = "Abruf ausgeschaltet"

    /// Erklärung zu „Anmeldung abgelaufen“ (Sprechblase).
    static let signInExplanation = "Der Anbieter verlangt eine neue Anmeldung. Bis dahin werden keine Mails abgerufen. Neu anmelden über die Leiste über der Mailliste oder unter „Postfach bearbeiten“."
    /// Erklärung zu „Postfach nicht erreichbar“ (Sprechblase).
    static let unreachableExplanation = "Der letzte Abruf hat den Mailserver nicht erreicht. Die Mails auf diesem Gerät bleiben sichtbar. Beim nächsten erfolgreichen Abruf verschwindet das Zeichen."
    /// Erklärung zu „Abruf ausgeschaltet“ (Sprechblase).
    static let pausedExplanation = "Dieses Postfach wird auf diesem Gerät nicht über „Alle Eingänge“ abgerufen. Einschalten in der Postfachliste der Einstellungen (Schalter „Abruf“)."

    /// Die zutreffenden Zeichen nebeneinander, jedes mit Erklärung.
    var body: some View {
        if needsSignIn {
            SignInRequiredBadge(font: font)
                .badgeExplanation(title: Self.signInText, message: Self.signInExplanation)
        }
        if isUnreachable {
            FetchFailedBadge(font: font)
                .badgeExplanation(title: Self.unreachableText, message: Self.unreachableExplanation)
        }
        if isPaused {
            FetchPausedBadge(font: font)
                .badgeExplanation(title: Self.pausedText, message: Self.pausedExplanation)
        }
    }

    /// Alle zutreffenden Hinweise als ein Text, in der Reihenfolge der
    /// Zeichen.
    ///
    /// - Parameters:
    ///   - needsSignIn: Anmeldung abgelaufen.
    ///   - isUnreachable: Postfach nicht erreichbar.
    ///   - isPaused: Abruf ausgeschaltet.
    /// - Returns: z. B. „Anmeldung abgelaufen, Abruf ausgeschaltet“; `nil`,
    ///   wenn nichts zutrifft.
    static func summary(needsSignIn: Bool, isUnreachable: Bool, isPaused: Bool) -> String? {
        let texts = [
            needsSignIn ? signInText : nil,
            isUnreachable ? unreachableText : nil,
            isPaused ? pausedText : nil,
        ].compactMap { $0 }
        return texts.isEmpty ? nil : texts.joined(separator: ", ")
    }
}

// MARK: - Sprechblase

/// Inhalt der Sprechblase: Titel und Erklärung – auf allen Plattformen
/// gleich.
private struct BadgeExplanationBubble: View {
    /// Titel, z. B. „Postfach nicht erreichbar“.
    let title: String
    /// Erklärender Satz.
    let message: String

    /// Titel fett, darunter die Erklärung.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(idealWidth: 280, maxWidth: 320, alignment: .leading)
    }
}

/// Öffnet zu einem Zeichen eine Sprechblase mit Titel und Erklärung – auf
/// iOS per Tipp, auf dem Mac beim Darüberfahren (oder Klick).
private struct BadgeExplanation: ViewModifier {
    /// Titel der Sprechblase, z. B. „Postfach nicht erreichbar“.
    let title: String
    /// Erklärender Satz.
    let message: String

    /// Sprechblase sichtbar.
    @State private var isShowing = false
    #if os(macOS)
    /// Wartet nach dem Darüberfahren kurz, bevor die Sprechblase erscheint.
    @State private var hoverTask: Task<Void, Never>?

    /// Wartezeit, bis die Sprechblase beim Darüberfahren erscheint.
    private static let hoverDelay: Duration = .milliseconds(250)
    #endif

    /// Größere Tippfläche, Tipp mit Vorrang vor der Zeile, Popover.
    ///
    /// Verarbeitung: `highPriorityGesture` setzt sich gegen den Knopf der
    /// Zeile durch. Die Tippfläche wächst um 8 Punkt je Seite, ohne die
    /// Anordnung zu ändern (Innenabstand, Form, negativer Innenabstand).
    /// `presentationCompactAdaptation(.popover)` hält die Sprechblase auch
    /// auf dem iPhone klein, statt ein Blatt über den Bildschirm zu legen.
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .padding(8)
            .contentShape(Rectangle())
            .padding(-8)
            .highPriorityGesture(TapGesture().onEnded { isShowing = true })
            .popover(isPresented: $isShowing) {
                BadgeExplanationBubble(title: title, message: message)
                    .presentationCompactAdaptation(.popover)
            }
        #else
        content
            .onHover { hoverChanged($0) }
            .highPriorityGesture(TapGesture().onEnded { isShowing = true })
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                BadgeExplanationBubble(title: title, message: message)
            }
        #endif
    }

    #if os(macOS)
    /// Mauszeiger kommt bzw. geht (Mac).
    ///
    /// Verarbeitung: Beim Darüberfahren erscheint die Sprechblase nach
    /// `hoverDelay` – bloßes Überstreichen öffnet sie so nicht. Verlässt der
    /// Zeiger das Zeichen, wird ein ausstehendes Öffnen verworfen und die
    /// Sprechblase geschlossen.
    ///
    /// - Parameter isHovering: `true`, solange der Zeiger darüber steht.
    private func hoverChanged(_ isHovering: Bool) {
        hoverTask?.cancel()
        hoverTask = nil
        guard isHovering else {
            isShowing = false
            return
        }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: Self.hoverDelay)
            guard !Task.isCancelled else { return }
            isShowing = true
        }
    }
    #endif
}

extension View {
    /// Erklärung eines Kennzeichens per Tipp (iOS) bzw. beim Darüberfahren
    /// (Mac).
    ///
    /// - Parameters:
    ///   - title: Titel der Sprechblase.
    ///   - message: Erklärender Satz.
    /// - Returns: Zeichen mit Sprechblase.
    fileprivate func badgeExplanation(title: String, message: String) -> some View {
        modifier(BadgeExplanation(title: title, message: message))
    }

    /// Tooltip mit den Hinweisen eines Postfachs – nur, wenn einer zutrifft.
    /// Auf dem Mac entfällt er: Dort erklären die Zeichen sich selbst per
    /// Sprechblase beim Darüberfahren.
    ///
    /// - Parameter summary: Text aus `AccountStatusBadges.summary`.
    /// - Returns: Ansicht mit bzw. ohne Tooltip.
    @ViewBuilder
    func accountStatusHelp(_ summary: String?) -> some View {
        #if os(macOS)
        self
        #else
        if let summary {
            help(summary)
        } else {
            self
        }
        #endif
    }
}

// MARK: - Vorschau

#Preview {
    HStack(spacing: 6) {
        AccountStatusBadges(needsSignIn: true, isUnreachable: true, isPaused: true, font: .headline)
        Text("Postfach").font(.headline)
    }
    .padding()
}
