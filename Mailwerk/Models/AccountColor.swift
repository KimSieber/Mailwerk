//
//  AccountColor.swift
//  Mailwerk
//

import SwiftUI

/// Vordefinierte Farbpalette für die Account-Kennzeichnung in der Inbox.
/// Der `rawValue` ist der persistierte Hex-String.
enum AccountColor: String, CaseIterable, Identifiable, Codable {
    case blue      = "#378ADD"
    case teal      = "#1D9E75"
    case green     = "#639922"
    case coral     = "#D85A30"
    case red       = "#E24B4A"
    case pink      = "#D4537E"
    case purple    = "#7F77DD"
    case amber     = "#EF9F27"
    case brown     = "#8B6914"
    case slate     = "#5F5E5A"
    case navy      = "#185FA5"
    case magenta   = "#993556"

    var id: String { rawValue }

    /// Deutscher Anzeigename für den Farbwähler.
    var displayName: String {
        switch self {
        case .blue:    return "Blau"
        case .teal:    return "Türkis"
        case .green:   return "Grün"
        case .coral:   return "Koralle"
        case .red:     return "Rot"
        case .pink:    return "Rosa"
        case .purple:  return "Violett"
        case .amber:   return "Bernstein"
        case .brown:   return "Braun"
        case .slate:   return "Schiefer"
        case .navy:    return "Marine"
        case .magenta: return "Magenta"
        }
    }

    /// SwiftUI-Color aus dem Hex-Wert.
    var color: Color {
        Color(hex: rawValue)
    }

    /// Erzeugt eine `AccountColor` aus einem gespeicherten Hex-String.
    /// Gibt `nil` zurück, wenn der Hex-Wert keiner bekannten Farbe entspricht.
    static func from(hex: String?) -> AccountColor? {
        guard let hex else { return nil }
        return AccountColor(rawValue: hex)
    }
}

// MARK: - Color+Hex

extension Color {
    /// Initialisiert eine Color aus einem Hex-String (z. B. "#378ADD").
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let scanner = Scanner(string: cleaned)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8)  & 0xFF) / 255.0,
            blue:  Double( rgb        & 0xFF) / 255.0
        )
    }
}
