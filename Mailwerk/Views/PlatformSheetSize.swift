//
//  PlatformSheetSize.swift
//  Mailwerk
//
//  Zweck: Mindestgröße für Sheets auf macOS.
//
//  Unter macOS richtet sich ein Sheet nach der Größe seines Inhalts.
//  `List` und `Form` melden keine eigene Höhe – das Sheet schrumpft dann
//  auf Titel- und Symbolleiste zusammen, die Einträge bleiben unsichtbar.
//  Unter iOS und iPadOS füllen Sheets den Bildschirm; dort bleibt alles,
//  wie es ist.
//
//  Jede View, die als Sheet angezeigt wird, setzt diesen Modifier an ihre
//  äußerste Ebene (direkt an den `NavigationStack`). Die Maße stehen nur
//  hier, damit alle Sheets einheitlich wirken.
//
//  Formulare: `macGroupedForm()` stellt Formulare auf dem
//  Mac auf den gruppierten Stil um – Abschnitte als abgerundete Karten,
//  Beschriftung links, Wert rechts, wie unter iOS. Der Standardstil des
//  Mac (`.columns`) setzt Beschriftungen rechtsbündig in eine schmale
//  Spalte und kürzt sie („…re-Obergrenze“).
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

/// Größenklassen für Sheets auf macOS.
enum MacSheetSize {
    /// Eingabemasken, z. B. Postfach anlegen oder bearbeiten.
    case form
    /// Listen, z. B. Postfächer, Ordnerauswahl, Whitelist/Blacklist.
    case list
    /// Kompakte Einstellungen, z. B. Spamfilter (520 × 600 pt – Inhalt
    /// passt ohne Scrollen).
    case compact
    /// Mail verfassen.
    case composer

    /// Mindestbreite in Punkten.
    var width: CGFloat {
        switch self {
        case .form:     return 500
        case .list:     return 520
        case .compact:  return 520
        case .composer: return 760
        }
    }

    /// Mindesthöhe in Punkten.
    var height: CGFloat {
        switch self {
        case .form:     return 600
        case .list:     return 600
        case .compact:  return 600
        case .composer: return 680
        }
    }
}

extension View {

    /// Gibt dem Sheet auf macOS eine feste Mindestgröße; auf allen anderen
    /// Plattformen wirkungslos.
    ///
    /// - Parameter size: Größenklasse.
    /// - Returns: Ansicht mit Mindestgröße.
    func macSheetFrame(_ size: MacSheetSize) -> some View {
        #if os(macOS)
        return self.frame(
            minWidth: size.width, idealWidth: size.width,
            minHeight: size.height, idealHeight: size.height
        )
        #else
        return self
        #endif
    }

    /// Stellt ein Formular auf dem Mac auf den gruppierten Stil um
    /// (Abschnitte als Karten, Beschriftung links, Wert rechts); auf allen
    /// anderen Plattformen wirkungslos – dort ist das ohnehin der Stil.
    ///
    /// - Returns: Formular im gruppierten Stil (Mac).
    func macGroupedForm() -> some View {
        #if os(macOS)
        return self.formStyle(.grouped)
        #else
        return self
        #endif
    }
}
