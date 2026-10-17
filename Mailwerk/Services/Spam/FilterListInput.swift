//
//  FilterListInput.swift
//  Mailwerk
//
//  Zweck: Zerlegt eine Eingabe für die Listenpflege in einzelne Einträge.
//  Erlaubt sind mehrere Angaben auf einmal, getrennt durch Komma,
//  Semikolon, Zeilenumbruch oder Leerzeichen – so lässt sich eine
//  Sammlung von Absendern in einem Rutsch eintragen.
//
//  Reine Logik, deshalb `nonisolated`.
//
//  Abgrenzung: Eingabefeld → FilterListView; Normalisieren einzelner Werte
//  → FilterAddress.
//
//  Abhängigkeiten: Foundation, FilterAddress, FilterEntryKind, RecipientInput.
//

import Foundation

/// Ein erkannter Eintrag aus der Eingabe.
nonisolated struct FilterListInputEntry: Hashable, Sendable {
    /// Normalisierter Wert.
    let value: String
    /// Adresse oder Domain.
    let kind: FilterEntryKind
}

/// Zerlegung einer Listeneingabe.
nonisolated enum FilterListInput {

    /// Ergebnis der Zerlegung.
    struct Result: Equatable {
        /// Erkannte Einträge in Eingabereihenfolge, ohne Doppelte.
        var entries: [FilterListInputEntry] = []
        /// Abschnitte, aus denen sich nichts Brauchbares lesen ließ.
        var invalid: [String] = []

        /// Leeres Ergebnis.
        static let empty = Result()
    }

    /// Zerlegt eine Eingabe in Einträge.
    ///
    /// Verarbeitung: Erkennt je Abschnitt selbst, ob es eine Adresse oder
    /// eine Domain ist: `*@firma.de` und `firma.de` werden zur Domain, alles
    /// mit `@` zur Adresse – auch in der Form `Anna Muster <anna@firma.de>`.
    ///
    /// - Parameter text: Eingabe.
    /// - Returns: Erkannte Einträge ohne Doppelte und unbrauchbare Abschnitte.
    static func parse(_ text: String) -> Result {
        var result = Result()
        var seen = Set<FilterListInputEntry>()

        for token in tokens(in: text) {
            guard let entry = entry(from: token) else {
                result.invalid.append(token)
                continue
            }
            if seen.insert(entry).inserted {
                result.entries.append(entry)
            }
        }
        return result
    }

    // MARK: - Intern

    /// Trennt an Komma, Semikolon und Zeilenumbruch – mit demselben
    /// Zerleger wie die Empfängereingabe, damit ein Komma innerhalb von
    /// Anführungszeichen (`"Muster, Anna" <anna@firma.de>`) nicht trennt.
    /// Abschnitte ohne Anzeigenamen werden zusätzlich an Leerzeichen geteilt.
    ///
    /// - Parameter text: Eingabe.
    /// - Returns: Nicht leere Abschnitte.
    private static func tokens(in text: String) -> [String] {
        let parts = RecipientInput.tokens(text)
        return (parts.tokens + [parts.remainder])
            .flatMap { part -> [String] in
                part.contains("<") || part.contains("\"")
                    ? [part]
                    : part.components(separatedBy: .whitespacesAndNewlines)
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Erkennt einen Eintrag in einem Abschnitt.
    ///
    /// - Parameter token: Abschnitt.
    /// - Returns: Eintrag oder `nil`, wenn nichts Brauchbares darin steht.
    private static func entry(from token: String) -> FilterListInputEntry? {
        if token.hasPrefix("*@") || token.hasPrefix("@") {
            return FilterAddress.normalizedDomain(token)
                .map { FilterListInputEntry(value: $0, kind: .domain) }
        }
        if token.contains("@") {
            return FilterAddress.sender(fromHeader: token)
                .map { FilterListInputEntry(value: $0.address, kind: .address) }
        }
        return FilterAddress.normalizedDomain(token)
            .map { FilterListInputEntry(value: $0, kind: .domain) }
    }
}
