//
//  LinkInput.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 12.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Prüft und ergänzt eine eingegebene Link-Adresse für den Editor
//  (Knopf „Link“). Erlaubt sind Web-Adressen und E-Mail-Adressen:
//  - „www.beispiel.de“ → „https://www.beispiel.de“
//  - „name@beispiel.de“ → „mailto:name@beispiel.de“
//  - vollständige http-, https- und mailto-Adressen bleiben, wie sie sind.
//  Andere Schemata (z. B. javascript:, file:) werden abgelehnt.
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Setzen des Links im Text → RichTextController; Eingabedialog
//  → FormattingToolbar.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Prüfung und Ergänzung von Link-Adressen.
nonisolated enum LinkInput {
    /// Schema eines Mail-Links.
    static let mailtoPrefix = "mailto:"

    /// Wandelt eine Eingabe in ein gültiges Link-Ziel.
    ///
    /// Verarbeitung: Leerraum außen entfällt; Leerraum innen macht die
    /// Eingabe ungültig. Ohne Schema entscheidet das „@“: mit „@“ (und ohne
    /// „/“) eine E-Mail-Adresse, sonst eine Web-Adresse, die einen Punkt im
    /// Namen braucht.
    ///
    /// - Parameter input: Eingabe des Nutzers.
    /// - Returns: Link-Ziel oder `nil`, wenn die Eingabe ungültig ist.
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let lower = trimmed.lowercased()

        if lower.hasPrefix(mailtoPrefix) {
            return isEmailAddress(String(trimmed.dropFirst(mailtoPrefix.count))) ? trimmed : nil
        }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return hasValidHost(trimmed) ? trimmed : nil
        }

        // Anderes Schema (z. B. „javascript:“) ablehnen; ein Doppelpunkt
        // hinter dem Namen (Port) ist erlaubt.
        if let colon = trimmed.firstIndex(of: ":") {
            let beforeColon = trimmed[..<colon]
            if !beforeColon.contains(".") { return nil }
        }

        if trimmed.contains("@"), !trimmed.contains("/") {
            return isEmailAddress(trimmed) ? "mailto:" + trimmed : nil
        }
        let web = "https://" + trimmed
        return hasValidHost(web) ? web : nil
    }

    /// Anzeigetext zu einem Link-Ziel, z. B. für die Vorbelegung im Dialog
    /// oder als eingefügter Text.
    ///
    /// - Parameter link: Link-Ziel.
    /// - Returns: Ziel ohne „mailto:“.
    static func displayText(for link: String) -> String {
        link.lowercased().hasPrefix(mailtoPrefix) ? String(link.dropFirst(mailtoPrefix.count)) : link
    }

    /// Einfache Prüfung einer E-Mail-Adresse: genau ein „@“, Name davor,
    /// Domain mit Punkt dahinter.
    ///
    /// - Parameter text: Adresse.
    /// - Returns: `true`, wenn sie plausibel ist.
    private static func isEmailAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// Prüft, ob eine Web-Adresse einen Rechnernamen mit Punkt hat.
    ///
    /// - Parameter text: Vollständige Adresse.
    /// - Returns: `true`, wenn gültig.
    private static func hasValidHost(_ text: String) -> Bool {
        guard let host = URLComponents(string: text)?.host, host.contains(".") else { return false }
        return !host.hasPrefix(".") && !host.hasSuffix(".")
    }
}
