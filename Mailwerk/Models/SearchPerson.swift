//
//  SearchPerson.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 15.10.2026
//  Geändert: 16.10.2026
//
//  Zweck: Personen für die Namensvorschläge der Suche. Quelle sind die
//  Adressen (Von, An, Cc) der Mails im Suchbereich – vorgeschlagen wird
//  nur, wer dort tatsächlich vorkommt. Je Adresse ein Vorschlag (eine
//  Person mit zwei Adressen erscheint zweimal), alphabetisch nach Name,
//  ohne Namen nach Adresse. Eine gewählte Person wird zur Marke im
//  Suchfeld und findet alle Mails von und an diese Adresse.
//
//  Abgrenzung: Lesen der Adressen im MessageStore, Anzeige in InboxView.
//
//  Abhängigkeiten: MailAddress (Zerlegen formatierter Adressen).
//

import Foundation

/// Eine vorschlagbare Person (eine Adresse).
struct SearchPerson: Identifiable, Hashable {
    /// Anzeigename; `nil`, wenn keiner bekannt ist.
    let name: String?
    /// E-Mail-Adresse in Kleinschreibung.
    let address: String

    /// Kennung: die Adresse.
    var id: String { address }

    /// Text der Marke im Suchfeld: Name, sonst Adresse.
    var title: String { name ?? address }

    /// Höchstzahl der gezeigten Vorschläge.
    static let suggestionLimit = 12

    /// Personen aus formatierten Adressen.
    ///
    /// Verarbeitung: Zerlegt jede Adresse, fasst gleiche Adressen (ohne
    /// Groß-/Kleinschreibung) zusammen und übernimmt den ersten bekannten
    /// Namen. Unlesbare Einträge entfallen. Sortiert wird alphabetisch
    /// nach `title` (wie im Finder), bei Gleichstand nach Adresse.
    ///
    /// - Parameter rawAddresses: Formatierte Adressen, z. B.
    ///   `Anna Muster <anna@example.org>`.
    /// - Returns: Personen, alphabetisch.
    static func collect(from rawAddresses: [String]) -> [SearchPerson] {
        var names: [String: String?] = [:]
        for raw in Set(rawAddresses) {
            guard let parsed = MailAddress(parsing: raw) else { continue }
            let key = parsed.normalizedAddress
            if let known = names[key], known != nil { continue }
            names[key] = parsed.name
        }
        return names
            .map { SearchPerson(name: $0.value, address: $0.key) }
            .sorted { lhs, rhs in
                let order = lhs.title.localizedStandardCompare(rhs.title)
                return order == .orderedSame ? lhs.address < rhs.address : order == .orderedAscending
            }
    }

    /// Vorschläge zu einer Eingabe.
    ///
    /// Verarbeitung: Trifft, wenn Name oder Adresse die Eingabe enthalten
    /// (ohne Groß-/Kleinschreibung und Akzente). Leerraum am Rand der
    /// Eingabe zählt hier nicht. Die alphabetische Reihenfolge bleibt.
    ///
    /// - Parameters:
    ///   - people: Alle Personen des Suchbereichs.
    ///   - text: Eingabe im Suchfeld.
    ///   - limit: Höchstzahl.
    /// - Returns: Passende Personen; leer ohne Eingabe.
    static func suggestions(
        from people: [SearchPerson],
        matching text: String,
        limit: Int = suggestionLimit
    ) -> [SearchPerson] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Array(people.lazy.filter { person in
            person.address.range(of: needle, options: options) != nil
                || (person.name?.range(of: needle, options: options) != nil)
        }.prefix(limit))
    }
}
