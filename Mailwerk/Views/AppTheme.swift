//
//  AppTheme.swift
//  Mailwerk
//
//  Zweck: Erscheinungsbild der App an einer Stelle – die getönte
//  Hintergrundfläche (hell Nebelblau, dunkel Nachtblau) und die Farbe der
//  Karten darauf (Listenzeilen, Formularabschnitte, Mailinhalt,
//  Schreibfläche). Dazu zwei Modifier, mit denen die Ansichten die Farben
//  übernehmen:
//  - `appBackground()` blendet den Systemhintergrund von Listen,
//    Formularen und Scrollbereichen aus und legt die Fläche darunter;
//  - `cardRowBackground(isSelected:isOpened:)` färbt die Zeilen einer
//    Liste bzw. eines Formularabschnitts als Karte, ausgewählte Zeilen
//    leicht getönt, die geöffnete Mail hellblau.
//
//  Die Farbwerte stehen als reine Daten in `AppThemePalette` und lassen
//  sich so ohne Oberfläche prüfen. Hell bleiben die Karten weiß (bester
//  Kontrast für Text); dunkel sind sie eine helle Stufe des Nachtblaus,
//  damit Fläche und Karte eine Farbfamilie bilden.
//
//  Abgrenzung: Der Inhalt einer Mail und die Schreibflächen bekommen
//  keine Tönung, sondern liegen auf der Kartenfarbe – Mails sollen so
//  aussehen wie beim Empfänger. Gläserne Elemente (Symbolleisten, Knöpfe)
//  bleiben Apple-Standard und nehmen die Fläche von selbst auf.
//
//  Abhängigkeiten: SwiftUI, UIKit (iOS) bzw. AppKit (macOS),
//  PlatformColor (RichTextEditor).
//

import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Farbwerte

/// Farbwerte des Erscheinungsbilds als 0xRRGGBB, je für hell und dunkel.
nonisolated enum AppThemePalette {
    /// Farbe für hellen und dunklen Modus.
    nonisolated struct Pair: Equatable, Sendable {
        /// Wert im hellen Modus (0xRRGGBB).
        let light: UInt32
        /// Wert im dunklen Modus (0xRRGGBB).
        let dark: UInt32
    }

    /// Getönte Fläche hinter Listen, Formularen und Ansichten.
    static let background = Pair(light: 0xDFE5F5, dark: 0x121827)
    /// Karten auf der Fläche: Zeilen, Abschnitte, Mailinhalt, Schreibfläche.
    static let card = Pair(light: 0xFFFFFF, dark: 0x1C2438)

    /// Zerlegt einen Farbwert in seine Anteile.
    ///
    /// - Parameter rgb: Farbwert 0xRRGGBB.
    /// - Returns: Rot, Grün und Blau jeweils von 0 bis 1.
    static func components(_ rgb: UInt32) -> (red: Double, green: Double, blue: Double) {
        (
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// Farbwert als Text „#RRGGBB“ (für Protokoll und Tests).
    ///
    /// - Parameter rgb: Farbwert 0xRRGGBB.
    /// - Returns: Text in Großbuchstaben mit führendem „#“.
    static func hex(_ rgb: UInt32) -> String {
        String(format: "#%06X", rgb & 0xFFFFFF)
    }
}

// MARK: - Farben

/// Farben des Erscheinungsbilds; passen sich hell/dunkel selbst an.
nonisolated enum AppTheme {
    /// Getönte Fläche hinter Listen, Formularen und Ansichten.
    static let background = dynamicColor(AppThemePalette.background)
    /// Kartenfarbe für Zeilen, Abschnitte, Mailinhalt und Schreibfläche.
    static let card = dynamicColor(AppThemePalette.card)

    /// Farbe, die je nach Erscheinungsbild den hellen oder dunklen Wert zeigt.
    ///
    /// Verarbeitung: Über die dynamische Systemfarbe der Plattform – so
    /// wechselt sie ohne Neuaufbau der Ansicht, wenn hell/dunkel umschaltet.
    ///
    /// - Parameter pair: Farbwerte für hell und dunkel.
    /// - Returns: Farbe für SwiftUI.
    private static func dynamicColor(_ pair: AppThemePalette.Pair) -> Color {
        #if os(iOS)
        let color = UIColor { traits in
            platformColor(traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        }
        return Color(uiColor: color)
        #else
        let color = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return platformColor(isDark ? pair.dark : pair.light)
        }
        return Color(nsColor: color)
        #endif
    }

    /// Plattformfarbe zu einem Farbwert.
    ///
    /// - Parameter rgb: Farbwert 0xRRGGBB.
    /// - Returns: Deckende Farbe im sRGB-Farbraum.
    private static func platformColor(_ rgb: UInt32) -> PlatformColor {
        let parts = AppThemePalette.components(rgb)
        #if os(iOS)
        return UIColor(red: parts.red, green: parts.green, blue: parts.blue, alpha: 1)
        #else
        return NSColor(srgbRed: parts.red, green: parts.green, blue: parts.blue, alpha: 1)
        #endif
    }
}

// MARK: - Bausteine

/// Hintergrund einer Listenzeile: Kartenfarbe, ausgewählt leicht getönt.
///
/// Eine eigene Zeilenfarbe ersetzt die Auswahlfarbe des Systems; die
/// Tönung für ausgewählte Zeilen übernimmt deshalb diese Ansicht. Die
/// geöffnete Mail (Spaltenlayout des iPad) ist hellblau hinterlegt – in
/// der Akzentfarbe wie die gewählte Ansicht der Ordnerleiste daneben, nur
/// etwas kräftiger, weil die Karte weiß ist.
struct CardRowBackground: View {
    /// Die Zeile ist ausgewählt (Auswahlmodus).
    var isSelected = false
    /// Die Zeile ist die geöffnete Mail (Spaltenlayout).
    var isOpened = false

    /// Deckkraft der Akzentfarbe für die geöffnete Mail.
    private static let openedOpacity = 0.16

    /// Kartenfarbe, bei Auswahl mit der Füllfarbe des Systems, bei der
    /// geöffneten Mail mit hellem Akzentblau darüber.
    var body: some View {
        AppTheme.card
            .overlay {
                if isSelected {
                    Rectangle().fill(.fill)
                } else if isOpened {
                    Rectangle().fill(Color.accentColor.opacity(Self.openedOpacity))
                }
            }
    }
}

extension View {
    /// Getönte Fläche hinter der Ansicht.
    ///
    /// Verarbeitung: Blendet den Systemhintergrund von Listen, Formularen
    /// und Scrollbereichen aus und legt die Fläche bis unter die Ränder
    /// (Statusleiste, Symbolleisten) darunter.
    ///
    /// - Returns: Ansicht mit getönter Fläche.
    func appBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
    }

    /// Kartenfarbe für Listenzeilen bzw. alle Zeilen eines Abschnitts.
    ///
    /// - Parameters:
    ///   - isSelected: Zeile ist ausgewählt (leicht getönt).
    ///   - isOpened: Zeile ist die geöffnete Mail (hellblau).
    /// - Returns: Zeile(n) mit Kartenhintergrund.
    func cardRowBackground(isSelected: Bool = false, isOpened: Bool = false) -> some View {
        listRowBackground(CardRowBackground(isSelected: isSelected, isOpened: isOpened))
    }
}
