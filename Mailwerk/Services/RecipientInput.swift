//
//  RecipientInput.swift
//  Mailwerk
//
//  Created by Kim Sieber on 22.09.26.
//


//
//  RecipientInput.swift
//  Mailwerk
//
//  Zerlegt Tastatureingaben in Empfängeradressen. Reine Logik ohne UI,
//  vollständig durch RecipientInputTests abgedeckt.
//

import Foundation

enum RecipientInput {

    /// Zeichen, die eine Adresse abschließen.
    static let separators: Set<Character> = [",", ";", "\n"]

    /// Zerlegt die Eingabe an Trennzeichen, die außerhalb von
    /// Anführungszeichen und spitzen Klammern stehen. So bleibt
    /// `"Sieber, Kim" <kim@example.org>` eine einzige Adresse.
    /// - Returns: die abgeschlossenen Adressen und den noch offenen Rest
    static func split(_ text: String) -> (addresses: [MailAddress], remainder: String) {
        var addresses: [MailAddress] = []
        var current = ""
        var inQuotes = false
        var inAngles = false

        for character in text {
            switch character {
            case "\"":
                inQuotes.toggle()
                current.append(character)
            case "<" where !inQuotes:
                inAngles = true
                current.append(character)
            case ">" where !inQuotes:
                inAngles = false
                current.append(character)
            case let c where separators.contains(c) && !inQuotes && !inAngles:
                if let address = address(from: current) { addresses.append(address) }
                current = ""
            default:
                current.append(character)
            }
        }
        return (addresses, current)
    }

    /// Wandelt einen Eingabe-Abschnitt in eine Adresse um.
    /// Unvollständige Eingaben werden als ungültige Adresse zurückgegeben,
    /// damit der Nutzer sie als roten Chip sieht statt sie zu verlieren.
    static func address(from token: String) -> MailAddress? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return MailAddress(parsing: trimmed) ?? MailAddress(address: trimmed)
    }

    /// Hängt Adressen an und entfernt dabei Doppelte (unabhängig von Groß-/Kleinschreibung).
    static func appending(
        _ additions: [MailAddress],
        to existing: [MailAddress]
    ) -> [MailAddress] {
        var seen = Set(existing.map(\.normalizedAddress))
        return existing + additions.filter { seen.insert($0.normalizedAddress).inserted }
    }
}