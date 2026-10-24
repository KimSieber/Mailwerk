//
//  MailAddress.swift
//  Mailwerk
//
//  Zweck: Eine einzelne E-Mail-Adresse mit optionalem Namen – das
//  Empfänger-Modell für Composer, ReplyBuilder und Versand.
//
//  Unabhängig von SwiftMail-Typen, damit Logik und Tests ohne
//  Mail-Bibliothek auskommen; nur Zerlegen und Umwandeln für den Versand
//  nutzen SwiftMail. Adressen werden ohne Groß-/Kleinschreibung verglichen.
//
//  Nebenläufigkeit: `nonisolated` und `Sendable` – reine Werte bzw. reine
//  Logik ohne Bezug zur Oberfläche. So kann die Ablage (MessageStore) sie
//  auch außerhalb des Hauptthreads nutzen (v0.2.3b).
//
//  Abgrenzung: Eingabe mehrerer Empfänger → RecipientInput; Adressen für
//  die Filterlisten → FilterAddress.
//
//  Abhängigkeiten: Foundation, SwiftMail (EmailAddress, isValidEmail),
//  MailAccount (Namensbereinigung).
//

import Foundation
import SwiftMail

/// Eine E-Mail-Adresse mit optionalem Namen.
nonisolated struct MailAddress: Hashable, Identifiable, Sendable {
    /// Anzeigename; `nil`, wenn keiner angegeben ist.
    let name: String?
    /// Adresse ohne Leerraum an den Rändern.
    let address: String

    /// Kennung für SwiftUI-Listen: die Adresse in Kleinschreibung.
    var id: String { normalizedAddress }

    /// Für Vergleiche: Adressen sind in der Praxis nicht case-sensitiv.
    var normalizedAddress: String { address.lowercased() }

    /// Legt eine Adresse an.
    ///
    /// - Parameters:
    ///   - name: Anzeigename; leer wird zu `nil`.
    ///   - address: Adresse; Leerraum an den Rändern entfällt.
    init(name: String? = nil, address: String) {
        self.name = MailAccount.normalized(name)
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Zerlegt eine formatierte Adresse wie `Kim Sieber <kim@ordinum.com>`,
    /// `"Sieber, Kim" <kim@ordinum.com>` oder `kim@ordinum.com`.
    ///
    /// - Parameter raw: Formatierte Adresse.
    /// - Returns: Adresse oder `nil`, wenn sie ungültig ist.
    init?(parsing raw: String) {
        guard let parsed = SwiftMail.EmailAddress(raw) else { return nil }
        self.init(name: parsed.name, address: parsed.address)
        guard isValid else { return nil }
    }

    /// `true`, wenn die Adresse formal gültig ist.
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
