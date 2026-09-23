//
//  MailAddress.swift
//  Mailwerk
//
//  Created by Kim Sieber on 21.09.26.
//


//
//  MailAddress.swift
//  Mailwerk
//
//  Eine einzelne E-Mail-Adresse mit optionalem Namen – das Empfänger-Modell
//  für Composer, ReplyBuilder und Versand. Unabhängig von SwiftMail-Typen,
//  damit Logik und Tests ohne Mail-Bibliothek auskommen.
//

import Foundation
import SwiftMail

struct MailAddress: Hashable, Identifiable {
    let name: String?
    let address: String

    var id: String { normalizedAddress }

    /// Für Vergleiche: Adressen sind in der Praxis nicht case-sensitiv.
    var normalizedAddress: String { address.lowercased() }

    init(name: String? = nil, address: String) {
        self.name = MailAccount.normalized(name)
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Zerlegt eine formatierte Adresse wie `Kim Sieber <kim@ordinum.com>`,
    /// `"Sieber, Kim" <kim@ordinum.com>` oder `kim@ordinum.com`.
    /// Liefert nil bei ungültigen Adressen.
    init?(parsing raw: String) {
        guard let parsed = SwiftMail.EmailAddress(raw) else { return nil }
        self.init(name: parsed.name, address: parsed.address)
        guard isValid else { return nil }
    }

    var isValid: Bool { address.isValidEmail() }

    /// Anzeige in der Oberfläche, z. B. "Kim Sieber <kim@ordinum.com>".
    var displayString: String {
        guard let name else { return address }
        return "\(name) <\(address)>"
    }

    /// Umwandlung für den Versand über SwiftMail.
    var emailAddress: SwiftMail.EmailAddress {
        SwiftMail.EmailAddress(name: name, address: address)
    }
}