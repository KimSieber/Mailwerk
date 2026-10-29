//
//  HeaderPerson.swift
//  Mailwerk
//
//  Zweck: Eine Person im Kopf der Mailansicht (Von, An, Kopie, Antwort an)
//  – zerlegt aus der formatierten Adresse der Mail in Namen und Adresse.
//  Grundlage für die antippbaren Namen samt Menü (Adresse kopieren,
//  Suchen, Kontaktkarte, Neue E-Mail).
//
//  „Antwort an“ wird nur gezeigt, wenn es vom Absender abweicht (wie in
//  Apple Mail) – sonst wäre es eine doppelte Zeile ohne Information.
//
//  Abgrenzung: Darstellung und Menü → MessageDetailHeader; Kontaktkarte →
//  ContactCardView.
//
//  Abhängigkeiten: MailAddress (Zerlegen formatierter Adressen),
//  SearchPerson (Marke für die Suche).
//

import Foundation

/// Eine Person im Kopf der Mailansicht.
struct HeaderPerson: Identifiable, Hashable {
    /// Anzeigename; `nil`, wenn die Mail keinen nennt.
    let name: String?
    /// Adresse, wie sie in der Mail steht (ohne Leerraum an den Rändern).
    let address: String

    /// Kennung: die Adresse in Kleinschreibung.
    var id: String { address.lowercased() }

    /// Text im Kopf der Mail: Name, sonst Adresse.
    var title: String { name ?? address }

    /// Marke für die Suche nach Mails von und an diese Person.
    var searchPerson: SearchPerson {
        SearchPerson(name: name, address: address.lowercased())
    }

    /// Legt eine Person an.
    ///
    /// - Parameters:
    ///   - name: Anzeigename; leer wird zu `nil`.
    ///   - address: Adresse.
    init(name: String?, address: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Zerlegt eine formatierte Adresse wie `Kim Sieber <kim@example.org>`.
    ///
    /// Verarbeitung: Lässt sich die Adresse nicht zerlegen (fehlerhafte
    /// Mail), bleibt der Text als Adresse erhalten – die Person erscheint
    /// trotzdem und lässt sich kopieren.
    ///
    /// - Parameter raw: Formatierte Adresse.
    init(raw: String) {
        if let parsed = MailAddress(parsing: raw) {
            self.init(name: parsed.name, address: parsed.address)
        } else {
            self.init(name: nil, address: raw)
        }
    }

    /// Personen aus einer Liste formatierter Adressen; leere Einträge und
    /// doppelte Adressen entfallen, die Reihenfolge bleibt.
    ///
    /// - Parameter raws: Formatierte Adressen.
    /// - Returns: Personen in der Reihenfolge der Mail.
    static func list(_ raws: [String]) -> [HeaderPerson] {
        var seen = Set<String>()
        return raws
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { HeaderPerson(raw: $0) }
            .filter { seen.insert($0.id).inserted }
    }

    /// Personen für „Antwort an“ – nur, wenn sie vom Absender abweichen.
    ///
    /// - Parameters:
    ///   - replyTo: Formatierte Adressen aus Reply-To.
    ///   - sender: Formatierte Adresse des Absenders.
    /// - Returns: Personen oder leer, wenn Reply-To fehlt oder nur den
    ///   Absender selbst nennt.
    static func replyTo(_ replyTo: [String], sender: String) -> [HeaderPerson] {
        let people = list(replyTo)
        let senderID = HeaderPerson(raw: sender).id
        guard !people.isEmpty, people.map(\.id) != [senderID] else { return [] }
        return people
    }
}
