//
//  MessageSort.swift
//  Mailwerk
//
//  Zweck: Sortierung der Nachrichtenliste – Feld (Von, Betreff, Datum,
//  Größe) und Richtung. Grundstellung ist „Datum, absteigend“ (neueste
//  oben). Eine andere Sortierung gilt nur für die gerade gezeigte Ansicht:
//  Das ViewModel setzt sie beim Wechsel der Ansicht zurück, und sie wird
//  nicht gespeichert – nach dem Beenden der App gilt wieder die
//  Grundstellung.
//
//  „Von“ sortiert nach der Person, die die Zeile zeigt: in Gesendet und
//  Entwürfen der erste Empfänger, sonst der Absender (MessageRowParty).
//  Texte werden wie im Finder verglichen (ohne Groß-/Kleinschreibung,
//  Zahlen nach ihrem Wert). Bei Gleichstand entscheidet das Datum
//  (neueste zuerst), danach die Cache-ID – so ist die Reihenfolge immer
//  eindeutig und springt beim Neuladen nicht.
//
//  Abgrenzung: Reine Logik; Auswahl im Sortiermenü in InboxView.
//
//  Abhängigkeiten: MessageListItem, MessageRowParty.
//

import Foundation

/// Sortierung der Nachrichtenliste.
struct MessageSort: Equatable {

    /// Wonach sortiert wird.
    enum Field: CaseIterable, Identifiable {
        /// Absender bzw. in Gesendet/Entwürfen Empfänger.
        case person
        /// Betreff.
        case subject
        /// Datum der Nachricht.
        case date
        /// Größe der Nachricht.
        case size

        /// Kennung für SwiftUI.
        var id: Self { self }

        /// Bezeichnung im Menü.
        ///
        /// - Parameter showsRecipients: `true` in Gesendet und Entwürfen.
        /// - Returns: „Von“ bzw. „An“, „Betreff“, „Datum“, „Größe“.
        func title(showsRecipients: Bool) -> String {
            switch self {
            case .person:  return showsRecipients ? "An" : "Von"
            case .subject: return "Betreff"
            case .date:    return "Datum"
            case .size:    return "Größe"
            }
        }
    }

    /// Feld, nach dem sortiert wird.
    var field: Field
    /// `true` = aufsteigend (A–Z, älteste bzw. kleinste zuerst).
    var ascending: Bool

    /// Grundstellung: Datum, absteigend (neueste oben).
    static let standard = MessageSort(field: .date, ascending: false)

    /// `true`, wenn die Sortierung von der Grundstellung abweicht.
    var isStandard: Bool { self == Self.standard }

    /// Sortiert Listeneinträge.
    ///
    /// Verarbeitung: Ermittelt je Eintrag einmal den Vergleichswert und
    /// sortiert danach. Gleiche Werte ordnet das Datum (neueste zuerst),
    /// dann die Cache-ID. Einträge ohne Datum stehen bei „Datum“ immer am
    /// Ende, unabhängig von der Richtung.
    ///
    /// - Parameters:
    ///   - items: Listeneinträge.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Sortierte Einträge.
    func sorted(_ items: [MessageListItem], showsRecipients: Bool) -> [MessageListItem] {
        let keyed: [(item: MessageListItem, text: String)] = items.map { item in
            switch field {
            case .person:
                let party = MessageRowParty.make(for: item, showsRecipients: showsRecipients)
                return (item, party.name ?? party.address ?? "")
            case .subject:
                return (item, item.subject)
            case .date, .size:
                return (item, "")
            }
        }
        return keyed.sorted { lhs, rhs in
            precedes(lhs.item, lhs.text, rhs.item, rhs.text)
        }.map(\.item)
    }

    /// Vergleicht zwei Einträge nach Feld, Richtung und Gleichstandsregel.
    ///
    /// - Parameters:
    ///   - a: Erster Eintrag.
    ///   - aText: Vergleichstext des ersten Eintrags (Von, Betreff).
    ///   - b: Zweiter Eintrag.
    ///   - bText: Vergleichstext des zweiten Eintrags.
    /// - Returns: `true`, wenn `a` vor `b` steht.
    private func precedes(_ a: MessageListItem, _ aText: String, _ b: MessageListItem, _ bText: String) -> Bool {
        switch field {
        case .person, .subject:
            let order = aText.localizedStandardCompare(bText)
            if order != .orderedSame {
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        case .size:
            if a.sizeBytes != b.sizeBytes {
                return ascending ? a.sizeBytes < b.sizeBytes : a.sizeBytes > b.sizeBytes
            }
        case .date:
            switch (a.date, b.date) {
            case let (x?, y?) where x != y:
                return ascending ? x < y : x > y
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return a.id < b.id
        }
        return Self.newestFirst(a, b)
    }

    /// Gleichstandsregel: neueste zuerst, Einträge ohne Datum zuletzt,
    /// dann nach Cache-ID.
    ///
    /// - Parameters:
    ///   - a: Erster Eintrag.
    ///   - b: Zweiter Eintrag.
    /// - Returns: `true`, wenn `a` vor `b` steht.
    private static func newestFirst(_ a: MessageListItem, _ b: MessageListItem) -> Bool {
        switch (a.date, b.date) {
        case let (x?, y?) where x != y:
            return x > y
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return a.id < b.id
        }
    }
}
