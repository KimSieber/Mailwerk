//
//  PlatformInputModifiers.swift
//  Mailwerk
//
//  Einheitliche Eingabe-Einstellungen für Textfelder auf allen Plattformen.
//  Automatische Großschreibung und Tastaturtypen gibt es nur auf iOS,
//  iPadOS und visionOS. Auf macOS entfallen sie, statt den Build zu brechen.
//
//  Neue Felder für Adressen, Hostnamen, Benutzernamen oder Ports bitte
//  über diese Modifier einrichten, nicht mit eigenen `#if`-Blöcken.
//

import SwiftUI

extension View {

    /// Freitext ohne automatische Großschreibung und ohne Autokorrektur,
    /// z. B. für Hostnamen und Benutzernamen.
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
    func numberInput() -> some View {
        #if os(macOS)
        return self
        #else
        return self.keyboardType(.numberPad)
        #endif
    }
}
