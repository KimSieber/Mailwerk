//
//  PlatformSheetSize.swift
//  Mailwerk
//
//  Mindestgröße für Sheets auf macOS.
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

import SwiftUI

/// Größenklassen für Sheets auf macOS.
enum MacSheetSize {
    /// Eingabemasken, z. B. Postfach anlegen oder bearbeiten.
    case form
    /// Listen, z. B. Postfächer, Spam-Einstellungen, Ordnerauswahl.
    case list
    /// Mail verfassen.
    case composer

    var width: CGFloat {
        switch self {
        case .form:     return 460
        case .list:     return 480
        case .composer: return 720
        }
    }

    var height: CGFloat {
        switch self {
        case .form:     return 560
        case .list:     return 560
        case .composer: return 640
        }
    }
}

extension View {

    /// Gibt dem Sheet auf macOS eine feste Mindestgröße.
    /// Auf allen anderen Plattformen wirkungslos.
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
}
