//
//  FilterAddress.swift
//  Mailwerk
//
//  Normalisierte Absenderadresse für den Spamfilter: kleingeschrieben,
//  ohne Anzeigename, mit exakter Domain. Bewusst toleranter als die
//  Adressprüfung beim Versand – auch ungewöhnliche Absender
//  (z. B. `bounce=123@…`) müssen sich blockieren lassen. Geprüft wird
//  daher nur die Struktur, nicht die Zeichenauswahl des lokalen Teils.
//
//  `nonisolated`, weil der Filterlauf außerhalb des Main-Actors arbeitet.
//

import Foundation
import SwiftMail

nonisolated struct FilterAddress: Hashable {

    /// Vollständige Adresse, kleingeschrieben.
    let address: String

    /// Alles nach dem `@`, kleingeschrieben. Vergleich immer exakt:
    /// `firma.de` trifft weder `mail.firma.de` noch `evil-firma.de`.
    let domain: String

    /// Zeichen, die im lokalen Teil nicht vorkommen dürfen. Alles andere
    /// bleibt erlaubt, damit auch ungewöhnliche Absender filterbar sind.
    private static let forbiddenInLocalPart: Set<Character> = ["<", ">", ",", ";", "\"", "\\", "@"]

    /// Normalisiert eine einzelne Adresse (Listeneingabe, ohne Anzeigename).
    /// Liefert nil bei unbrauchbarer Eingabe.
    init?(normalizing raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
        else { return nil }

        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let localPart = String(parts[0])
        guard !localPart.isEmpty,
              !localPart.contains(where: { Self.forbiddenInLocalPart.contains($0) }),
              let domain = Self.normalizedDomain(String(parts[1]))
        else { return nil }

        self.address = "\(localPart)@\(domain)"
        self.domain = domain
    }

    /// Ermittelt den Absender aus einem `From`-Header.
    /// Bei mehreren Adressen zählt die erste.
    static func sender(fromHeader raw: String) -> FilterAddress? {
        // Der Header endet nicht mit einem Trennzeichen: Steht nur eine
        // Adresse darin, liefert `tokens` sie als offenen Rest.
        let parts = RecipientInput.tokens(raw)
        let first = (parts.tokens.first ?? parts.remainder).trimmingCharacters(in: .whitespacesAndNewlines)

        // Anzeigenamen und Klammern entfernt der Adressparser von SwiftMail.
        // Scheitert er (etwa bei `bounce=123@…`), zählt der Abschnitt selbst.
        let candidate = SwiftMail.EmailAddress(first)?.address ?? first
        return FilterAddress(normalizing: candidate)
    }

    /// Normalisiert eine Domain-Eingabe. Akzeptiert auch die Portal-Schreibweise
    /// `*@firma.de`. Liefert nil bei unbrauchbarer Eingabe.
    static func normalizedDomain(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if value.hasPrefix("*@") {
            value.removeFirst(2)
        } else if value.hasPrefix("@") {
            value.removeFirst()
        }

        // Ein abschließender Punkt bezeichnet dieselbe Domain (absolute Schreibweise).
        while value.hasSuffix(".") { value.removeLast() }

        guard isValidDomain(value) else { return nil }
        return value
    }

    /// Mindestens zwei Abschnitte, jeder aus Buchstaben, Ziffern und Bindestrichen,
    /// der letzte nur aus Buchstaben.
    private static func isValidDomain(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253 else { return false }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        for label in labels {
            guard !label.isEmpty, label.count <= 63,
                  label.first != "-", label.last != "-",
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return false }
        }

        guard let tld = labels.last, tld.count >= 2, tld.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return false
        }
        return true
    }
}
