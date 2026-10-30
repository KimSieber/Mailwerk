//
//  PlatformInputModifiers.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 27.09.2026
//  Geändert: 11.10.2026
//
//  Zweck: Einheitliche Eingabe-Einstellungen für Textfelder auf allen
//  Plattformen. Automatische Großschreibung und Tastaturtypen gibt es nur
//  auf iOS, iPadOS und visionOS. Auf macOS entfallen sie, statt den Build
//  zu brechen.
//
//  Neue Felder für Adressen, Hostnamen, Benutzernamen oder Ports bitte
//  über diese Modifier einrichten, nicht mit eigenen `#if`-Blöcken.
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

extension View {

    /// Freitext ohne automatische Großschreibung und ohne Autokorrektur,
    /// z. B. für Hostnamen und Benutzernamen.
    ///
    /// - Returns: Feld mit diesen Einstellungen.
    func plainTextInput() -> some View {
        #if os(macOS)
        return self.autocorrectionDisabled()
        #else
        return self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #endif
    }

    /// Wie `plainTextInput()`, zusätzlich mit E-Mail-Tastatur.
    ///
    /// - Returns: Feld mit diesen Einstellungen.
    func emailInput() -> some View {
        #if os(macOS)
        return self.plainTextInput()
        #else
        return self
            .plainTextInput()
            .keyboardType(.emailAddress)
        #endif
    }

    /// Ziffernfeld, z. B. für Portnummern.
    ///
    /// - Returns: Feld mit Zifferntastatur (auf macOS unverändert).
    func numberInput() -> some View {
        #if os(macOS)
        return self
        #else
        return self.keyboardType(.numberPad)
        #endif
    }
}
