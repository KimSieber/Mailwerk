//
//  AppThemeTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Farbwerte des Erscheinungsbilds (AppThemePalette).
//

import Testing
@testable import Mailwerk

struct AppThemeTests {

    /// Fläche und Karten haben die festgelegten Werte für hell und dunkel.
    @Test func paletteHasAgreedValues() {
        #expect(AppThemePalette.hex(AppThemePalette.background.light) == "#DFE5F5")
        #expect(AppThemePalette.hex(AppThemePalette.background.dark) == "#121827")
        #expect(AppThemePalette.hex(AppThemePalette.card.light) == "#FFFFFF")
        #expect(AppThemePalette.hex(AppThemePalette.card.dark) == "#1C2438")
    }

    /// Zerlegung in Anteile: 0xDFE5F5 ergibt 223/229/245 von 255.
    @Test func componentsSplitRGB() {
        let parts = AppThemePalette.components(0xDFE5F5)
        #expect(parts.red == 223.0 / 255)
        #expect(parts.green == 229.0 / 255)
        #expect(parts.blue == 245.0 / 255)
    }
}
