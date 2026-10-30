//
//  SheetHeaderBar.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 27.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Einheitliche Kopfleisten und Kreisknöpfe des Mac.
//
//  - `HeaderCircleButton`: Kreisknopf 32 × 32 pt mit Symbol – grau mit
//    Symbol in Textfarbe (Abbrechen, Zurück, Zusatzaktionen) oder in der
//    Akzentfarbe mit weißem Symbol (Suchen, Sichern/Fertig, Senden).
//    Während einer Aktion zeigt er einen Kreisel; ausgegraut, solange die
//    Aktion nicht möglich ist. Jeder Knopf trägt Tooltip (`help`) und
//    VoiceOver-Beschriftung.
//  - `HeaderCircleLabel`: dasselbe Aussehen als Beschriftung eines Menüs
//    (Sortieren, Einstellungen, Antworten, Aktionsmenü).
//  - `SheetHeaderBar`: feste Kopfleiste eines Sheets – links ✕ bzw. „<“,
//    mittig der Titel, rechts ✓ bzw. Senden und ggf. weitere Kreise; auf
//    Nebelblau mit feiner Trennlinie unten (`HeaderBottomLine`).
//  - `macSheetHeader(…)`: hängt die Kopfleiste auf dem Mac oben an ein
//    Sheet (nicht mitscrollend); auf iPhone/iPad wirkungslos – dort
//    bleiben die Leisten des Systems.
//
//  Tastatur: ✕ und „<“ reagieren auf Esc, ✓ auf Return (wo Return
//  bisher bestätigte), Senden auf ⌘Return – die Kürzel gibt der Aufrufer
//  mit.
//
//  Die Bausteine nutzen keine plattformeigenen Schnittstellen und
//  übersetzen deshalb auch in den Teilen-Erweiterungen.
//
//  Abgrenzung: Kopf der Mailliste → MacListHeaderBar; Kopf der
//  Mailansicht → MacDetailHeaderBar.
//
//  Abhängigkeiten: SwiftUI, AppTheme.
//

import SwiftUI

// MARK: - Kreisknopf

/// Aussehen eines Kreisknopfs.
enum HeaderCircleStyle {
    /// Grauer Kreis, Symbol in Textfarbe.
    case plain
    /// Kreis in der Akzentfarbe, Symbol weiß.
    case accent
}

/// Maße der Kreisknöpfe – an einer Stelle, damit alle Leisten gleich wirken.
enum HeaderCircleMetrics {
    /// Durchmesser eines Kreisknopfs in Punkt.
    static let diameter: CGFloat = 32
    /// Deckkraft der Textfarbe für den grauen Kreis.
    static let plainOpacity: Double = 0.09
}

/// Aussehen eines Kreisknopfs: Kreis mit Symbol bzw. Kreisel.
///
/// Auch als Beschriftung eines Menüs verwendbar (Sortieren, Einstellungen,
/// Antworten, Aktionsmenü).
struct HeaderCircleLabel: View {
    /// SF-Symbol.
    let systemImage: String
    /// Grau oder Akzentfarbe.
    var style: HeaderCircleStyle = .plain
    /// `true` = Kreisel statt Symbol.
    var isBusy = false

    /// Kreis mit Symbol bzw. Kreisel.
    var body: some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(style == .accent ? Color.white : nil)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(style == .accent ? Color.white : Color.primary)
            }
        }
        .frame(width: HeaderCircleMetrics.diameter, height: HeaderCircleMetrics.diameter)
        .background(background, in: Circle())
        .contentShape(Circle())
    }

    /// Füllung des Kreises.
    private var background: Color {
        switch style {
        case .plain:  return Color.primary.opacity(HeaderCircleMetrics.plainOpacity)
        case .accent: return Color.accentColor
        }
    }
}

/// Kreisknopf 32 × 32 pt mit Tooltip, VoiceOver-Beschriftung und optionalem
/// Tastaturkürzel.
struct HeaderCircleButton: View {
    /// Beschriftung für VoiceOver.
    let title: String
    /// SF-Symbol.
    let systemImage: String
    /// Grau oder Akzentfarbe.
    var style: HeaderCircleStyle = .plain
    /// Tooltip; `nil` = Beschriftung.
    var help: String? = nil
    /// `true` = Kreisel statt Symbol; der Knopf löst dann nichts aus.
    var isBusy = false
    /// `false` = ausgegraut.
    var isEnabled = true
    /// Tastaturkürzel; `nil` = keins.
    var shortcut: KeyboardShortcut? = nil
    /// Aktion.
    let action: () -> Void

    /// Knopf mit Kreis.
    var body: some View {
        Button {
            guard !isBusy else { return }
            action()
        } label: {
            HeaderCircleLabel(systemImage: systemImage, style: style, isBusy: isBusy)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .disabled(!isEnabled)
        .opacity(isEnabled || isBusy ? 1 : 0.4)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

extension HeaderCircleButton {
    /// ✕ – Abbrechen bzw. Schließen (Esc).
    ///
    /// - Parameters:
    ///   - title: Beschriftung, z. B. „Abbrechen“ oder „Schließen“.
    ///   - action: Aktion.
    /// - Returns: Grauer Kreis mit `xmark`.
    static func cancel(_ title: String = "Abbrechen", action: @escaping () -> Void) -> HeaderCircleButton {
        HeaderCircleButton(
            title: title, systemImage: "xmark", help: "\(title) (Esc)",
            shortcut: .cancelAction, action: action
        )
    }

    /// „<“ – zurück aus einer Unteransicht (Esc).
    ///
    /// - Parameter action: Aktion, meist `dismiss()`.
    /// - Returns: Grauer Kreis mit `chevron.left`.
    static func back(action: @escaping () -> Void) -> HeaderCircleButton {
        HeaderCircleButton(
            title: "Zurück", systemImage: "chevron.left", help: "Zurück (Esc)",
            shortcut: .cancelAction, action: action
        )
    }

    /// ✓ – Sichern bzw. Fertig (Return).
    ///
    /// - Parameters:
    ///   - title: Beschriftung, z. B. „Sichern“ oder „Fertig“.
    ///   - isEnabled: `false` = ausgegraut.
    ///   - usesReturn: `true` = Return löst aus.
    ///   - action: Aktion.
    /// - Returns: Blauer Kreis mit `checkmark`.
    static func confirm(
        _ title: String,
        isEnabled: Bool = true,
        usesReturn: Bool = true,
        action: @escaping () -> Void
    ) -> HeaderCircleButton {
        HeaderCircleButton(
            title: title, systemImage: "checkmark", style: .accent,
            help: usesReturn ? "\(title) (↩)" : title,
            isBusy: false, isEnabled: isEnabled,
            shortcut: usesReturn ? .defaultAction : nil, action: action
        )
    }

    /// Senden – blauer Kreis mit Papierflieger (⌘Return).
    ///
    /// - Parameters:
    ///   - isEnabled: `false` = ausgegraut.
    ///   - isBusy: `true` = Kreisel.
    ///   - action: Aktion.
    /// - Returns: Blauer Kreis mit `paperplane.fill`.
    static func send(isEnabled: Bool, isBusy: Bool, action: @escaping () -> Void) -> HeaderCircleButton {
        HeaderCircleButton(
            title: "Senden", systemImage: "paperplane.fill", style: .accent,
            help: "Senden (⌘↩)", isBusy: isBusy, isEnabled: isEnabled,
            shortcut: KeyboardShortcut(.return, modifiers: .command), action: action
        )
    }
}

// MARK: - Kopfleiste eines Sheets

/// Feste Kopfleiste eines Sheets: links ✕ bzw. „<“, mittig der Titel,
/// rechts ✓ bzw. Senden und ggf. weitere Kreise.
struct SheetHeaderBar<Leading: View, Trailing: View>: View {
    /// Titel in der Mitte.
    let title: String
    /// Knöpfe links.
    @ViewBuilder let leading: () -> Leading
    /// Knöpfe rechts.
    @ViewBuilder let trailing: () -> Trailing

    /// Höhe der Leiste in Punkt.
    static var height: CGFloat { 52 }

    /// Leiste auf Nebelblau mit Trennlinie unten.
    ///
    /// Verarbeitung: Der Titel steht unabhängig von den Knöpfen genau in
    /// der Mitte; reicht der Platz nicht, wird er gekürzt.
    var body: some View {
        HStack(spacing: AppSpacing.regular) {
            HStack(spacing: AppSpacing.regular) { leading() }
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: AppSpacing.regular) { trailing() }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, AppSpacing.large)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(AppTheme.background)
        .overlay(alignment: .bottom) { HeaderBottomLine() }
    }
}

/// Feine waagerechte Trennlinie am unteren Rand einer Kopfleiste.
///
/// Bewusst kein `Divider`: In einer Überlagerung (`overlay`) einer HStack
/// übernimmt ein Divider deren Richtung und wird zum senkrechten Strich
/// mitten durch die Leiste.
struct HeaderBottomLine: View {
    /// Linie über die volle Breite, 1 pt hoch.
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Hängt auf dem Mac eine feste Kopfleiste oben an ein Sheet und legt
    /// Nebelblau hinter den ganzen Inhalt; auf iPhone/iPad unverändert.
    ///
    /// Verarbeitung: Als `safeAreaInset` scrollt die Leiste nicht mit; der
    /// Inhalt darunter bleibt vollständig scrollbar.
    ///
    /// - Parameters:
    ///   - title: Titel in der Mitte.
    ///   - leading: Knöpfe links (✕ bzw. „<“).
    ///   - trailing: Knöpfe rechts (✓, Senden, weitere Kreise).
    /// - Returns: Ansicht mit Kopfleiste (Mac).
    @ViewBuilder
    func macSheetHeader<Leading: View, Trailing: View>(
        _ title: String,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        #if os(macOS)
        self
            .safeAreaInset(edge: .top, spacing: 0) {
                SheetHeaderBar(title: title, leading: leading, trailing: trailing)
            }
            .background(AppTheme.background.ignoresSafeArea())
        #else
        self
        #endif
    }
}
