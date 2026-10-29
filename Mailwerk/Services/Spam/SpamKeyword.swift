//
//  SpamKeyword.swift
//  Mailwerk
//
//  Zweck: Eigene IMAP-Keywords des Spamfilters. Sie liegen auf dem Server
//  und halten den Verarbeitungsstand für alle Geräte gemeinsam fest.
//
//  `nonisolated`, weil der Filterlauf außerhalb des Main-Actors arbeitet.
//
//  Abgrenzung: Setzen der Keywords → SpamFilterService.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// IMAP-Keywords des Spamfilters.
nonisolated enum SpamKeyword {

    /// Mail wurde vom Filter verarbeitet, unabhängig vom Ergebnis.
    static let checked = "$MailwerkChecked"

    /// Mail wurde durch die Blacklist als Spam erkannt.
    static let blacklisted = "$MailwerkBlacklisted"

    /// Zeichen, die ein IMAP-Atom nicht enthalten darf (RFC 3501 `atom-specials`),
    /// ergänzt um die `resp-specials`. Steuerzeichen und alles außerhalb von
    /// ASCII sind ebenfalls unzulässig.
    private static let forbidden: Set<Character> = [
        "(", ")", "{", " ", "%", "*", "\"", "\\", "]"
    ]

    /// Prüft, ob ein Keyword ein gültiges IMAP-Atom ist (RFC 3501).
    ///
    /// Verarbeitung: SwiftMail ersetzt ungültige Keywords ohne Fehlermeldung
    /// durch `CUSTOM`. Ein Tippfehler in einer Konstante bliebe sonst
    /// unbemerkt; die Tests prüfen deshalb beide Konstanten hiermit.
    ///
    /// - Parameter keyword: Keyword.
    /// - Returns: `true`, wenn es nur zulässige ASCII-Zeichen enthält.
    static func isValidAtom(_ keyword: String) -> Bool {
        guard !keyword.isEmpty else { return false }
        return keyword.unicodeScalars.allSatisfy { scalar in
            guard scalar.isASCII, scalar.value > 0x1F, scalar.value != 0x7F else { return false }
            return !forbidden.contains(Character(scalar))
        }
    }
}
