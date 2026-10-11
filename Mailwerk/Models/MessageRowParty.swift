//
//  MessageRowParty.swift
//  Mailwerk
//
//  Zweck: Wen eine Zeile der Mailliste zeigt – in Posteingang und Ordnern
//  den Absender, in Gesendet und Entwürfen den ersten Empfänger (bei
//  mehreren mit „+n“). Liefert dazu die Texte der Namenszeile, die
//  Initialen und eine feste Farbe für den Platzhalter.
//
//  Die Farbe wird aus der Adresse abgeleitet, damit derselbe Absender
//  immer dieselbe Farbe hat – auf allen Geräten und nach jedem Neustart.
//  Deshalb eine eigene, feste Prüfsumme (FNV-1a) statt `hashValue`, der
//  bei jedem Programmstart anders ausfällt.
//
//  Abgrenzung: Darstellung der Zeile → MessageRow; Kreis mit Initialen
//  bzw. Bild → SenderAvatarView; ob ein Bild gezeigt werden darf →
//  SpamClassifier.allowsSenderImage.
//
//  Abhängigkeiten: MessageListItem, MailAddress (Zerlegen formatierter
//  Adressen), AccountColor (Anzahl der Farben).
//

import Foundation

/// Die in einer Listenzeile gezeigte Person samt Texten und Platzhalter.
struct MessageRowParty: Equatable {
    /// Anzeigename; `nil`, wenn keiner angegeben ist.
    let name: String?
    /// E-Mail-Adresse; `nil`, wenn sich keine auswerten lässt.
    let address: String?
    /// Weitere Empfänger über den gezeigten hinaus (nur Gesendet/Entwürfe).
    let additionalCount: Int

    /// Ersatztext, wenn weder Name noch Adresse vorliegen.
    static let unknownTitle = "(unbekannt)"

    // MARK: - Ermitteln

    /// Ermittelt die gezeigte Person einer Mail.
    ///
    /// Verarbeitung: Für Gesendet und Entwürfe zählt der erste Empfänger,
    /// sonst der Absender. Formatierte Adressen werden zerlegt; lässt sich
    /// eine nicht als Adresse lesen, bleibt der Text als Name stehen.
    ///
    /// - Parameters:
    ///   - item: Listeneintrag.
    ///   - showsRecipients: `true` in Gesendet und Entwürfen.
    /// - Returns: Gezeigte Person.
    static func make(for item: MessageListItem, showsRecipients: Bool) -> MessageRowParty {
        if showsRecipients {
            let recipients = item.recipients.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard let first = recipients.first else {
                return MessageRowParty(name: nil, address: nil, additionalCount: 0)
            }
            return parse(first, additionalCount: recipients.count - 1)
        }
        return parse(item.from, additionalCount: 0)
    }

    /// Zerlegt eine formatierte Adresse wie `Anna Muster <anna@example.org>`.
    ///
    /// Verarbeitung: Ein Name, der nur die Adresse wiederholt, entfällt –
    /// sonst stünde sie zweimal in der Zeile.
    ///
    /// - Parameters:
    ///   - raw: Formatierte Adresse.
    ///   - additionalCount: Weitere Empfänger.
    /// - Returns: Gezeigte Person.
    private static func parse(_ raw: String, additionalCount: Int) -> MessageRowParty {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = MailAddress(parsing: trimmed) else {
            return MessageRowParty(
                name: trimmed.isEmpty ? nil : trimmed,
                address: nil,
                additionalCount: additionalCount
            )
        }
        let name = parsed.name.flatMap {
            $0.caseInsensitiveCompare(parsed.address) == .orderedSame ? nil : $0
        }
        return MessageRowParty(name: name, address: parsed.address, additionalCount: additionalCount)
    }

    // MARK: - Texte der Namenszeile

    /// Fett gesetzter Text: der Name, sonst die Adresse.
    var title: String {
        name ?? address ?? Self.unknownTitle
    }

    /// Kleiner grauer Zusatz: die Adresse (nur wenn ein Name dasteht) und
    /// ggf. „+n“ für weitere Empfänger; `nil`, wenn nichts dazukommt.
    var subtitle: String? {
        var parts: [String] = []
        if name != nil, let address { parts.append(address) }
        if additionalCount > 0 { parts.append("+\(additionalCount)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Platzhalter

    /// Bis zu zwei Initialen: erster und letzter Wortanfang des Namens,
    /// ohne Namen der erste Buchstabe der Adresse; leer, wenn nichts passt.
    var initials: String {
        if let name {
            let letters = name
                .split(whereSeparator: { $0.isWhitespace })
                .compactMap { word in word.first(where: { $0.isLetter }) }
            if let first = letters.first {
                let last = letters.count > 1 ? String(letters[letters.count - 1]) : ""
                return (String(first) + last).uppercased()
            }
        }
        if let letter = address?.first(where: { $0.isLetter || $0.isNumber }) {
            return String(letter).uppercased()
        }
        return ""
    }

    /// Fester Farbindex des Platzhalters in `AccountColor.allCases`.
    ///
    /// Verarbeitung: FNV-1a über die kleingeschriebene Adresse (ersatzweise
    /// den Namen), Rest der Division durch die Anzahl der Farben.
    var colorIndex: Int {
        let key = (address ?? name ?? "").lowercased()
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(AccountColor.allCases.count))
    }
}
