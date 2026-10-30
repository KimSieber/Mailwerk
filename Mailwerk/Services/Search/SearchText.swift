//
//  SearchText.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 15.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Bereitet den Inhalt einer Nachricht für den Suchindex auf und
//  bildet aus einer Eingabe den Suchausdruck. Regeln:
//  - Text: der Textteil; fehlt er, der HTML-Teil ohne Tags, Stilangaben
//    und Skripte, mit aufgelösten Zeichen-Entitäten. Höchstens
//    `maxBodyLength` Zeichen.
//  - Personen: eine Zeile je Adresse aus Von, An und Cc im Format
//    `Name <adresse>`, die Adresse in Kleinschreibung. So findet eine
//    gewählte Person über `<adresse>` genau diese Adresse und nicht eine
//    längere, die sie nur enthält.
//  - Texte werden in die zusammengesetzte Unicode-Form gebracht (NFC):
//    Ein „ä“ aus zwei Zeichen (z. B. vom Mac) und eines aus einem Zeichen
//    finden sich gegenseitig.
//  - Gesucht wird als Teilzeichenfolge ab drei Zeichen, Leerzeichen
//    zählen mit, Groß-/Kleinschreibung zählt nicht (FTS5 „trigram“).
//
//  Leistung: Die regulären Ausdrücke werden einmalig kompiliert
//  (`compiledPatterns`). Sehr lange HTML-Teile werden vor der Aufbereitung
//  auf `maxHTMLLength` Zeichen begrenzt – indiziert werden ohnehin nur
//  `maxBodyLength` Zeichen. Wird dabei ein Block (z. B. `<style>`)
//  abgeschnitten, bleibt höchstens überflüssiger Text im Index.
//
//  Nebenläufigkeit: `nonisolated` und `Sendable` – reine Werte bzw. reine
//  Logik ohne Bezug zur Oberfläche. So kann die Ablage (MessageStore) sie
//  auch außerhalb des Hauptthreads nutzen (v0.2.3b).
//
//  Abgrenzung: Reine Aufbereitung ohne Datenbankzugriff; Speichern und
//  Abfragen im MessageStore. Die HTML-Aufbereitung dient nur der Suche –
//  sie ist fehlertolerant und muss keine gültige Darstellung liefern.
//
//  Abhängigkeiten: Foundation, MailAddress (Zerlegen formatierter Adressen).
//

import Foundation

/// Aufbereitung von Nachrichten und Eingaben für die Suche.
nonisolated enum SearchText {

    /// Inhalt eines Eintrags im Suchindex.
    struct Entry: Equatable, Sendable {
        /// Betreff.
        let subject: String
        /// Personen, eine Zeile je Adresse (`Name <adresse>`).
        let people: String
        /// Text der Nachricht.
        let body: String
        /// Namen der Anhänge, eine Zeile je Anhang.
        let attachments: String
    }

    /// Mindestlänge einer Sucheingabe in Zeichen (Leerzeichen zählen mit).
    static let minimumQueryLength = 3

    /// Höchstlänge des indizierten Textes in Zeichen. Begrenzt die Größe
    /// des Index bei sehr langen Mails (z. B. Newsletter, Protokolle).
    static let maxBodyLength = 50_000

    /// Höchstlänge des HTML-Teils in Zeichen, der aufbereitet wird. Ein
    /// Vielfaches von `maxBodyLength`, weil Tags und Stilangaben wegfallen.
    static let maxHTMLLength = 400_000

    /// Feste Muster der HTML-Aufbereitung, in der Reihenfolge ihrer Anwendung.
    private static let commentPattern = "<!--[\\s\\S]*?-->"
    private static let headPattern = "<head[\\s>][\\s\\S]*?</head\\s*>"
    private static let stylePattern = "<style[\\s>][\\s\\S]*?</style\\s*>"
    private static let scriptPattern = "<script[\\s>][\\s\\S]*?</script\\s*>"
    private static let blockEndPattern = "<(br|/p|/div|/td|/th|/tr|/li|/h[1-6])\\b[^>]*>"
    private static let tagPattern = "<[^>]*>"
    private static let whitespacePattern = "\\s+"
    private static let entityPattern = "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z]{2,8});"

    /// Einmalig kompilierte reguläre Ausdrücke je Muster (ohne
    /// Groß-/Kleinschreibung). Zuvor wurde jeder Ausdruck bei jedem Aufruf
    /// neu kompiliert – beim Nachtragen des Suchindex tausendfach.
    private static let compiledPatterns: [String: NSRegularExpression] = {
        let patterns = [
            commentPattern, headPattern, stylePattern, scriptPattern,
            blockEndPattern, tagPattern, whitespacePattern, entityPattern,
        ]
        var result: [String: NSRegularExpression] = [:]
        for pattern in patterns {
            result[pattern] = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        return result
    }()

    // MARK: - Inhalt

    /// Text einer Nachricht für den Index.
    ///
    /// Verarbeitung: Der Textteil hat Vorrang, weil er den Inhalt ohne
    /// Auszeichnung enthält; nur ohne ihn wird der HTML-Teil aufbereitet –
    /// vorher auf `maxHTMLLength` Zeichen begrenzt. Das Ergebnis wird auf
    /// `maxBodyLength` Zeichen gekürzt.
    ///
    /// - Parameters:
    ///   - text: Textteil der Nachricht.
    ///   - html: HTML-Teil der Nachricht.
    /// - Returns: Durchsuchbarer Text (NFC), leer ohne Inhalt.
    static func body(text: String?, html: String?) -> String {
        let source: String
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source = text
        } else if let html, !html.isEmpty {
            // Sehr lange HTML-Teile vorab kürzen (siehe Dateikopf).
            let limited = html.utf16.count > maxHTMLLength ? String(html.prefix(maxHTMLLength)) : html
            source = plainText(fromHTML: limited)
        } else {
            return ""
        }
        return String(normalized(source).prefix(maxBodyLength))
    }

    /// Personen einer Nachricht für den Index.
    ///
    /// Verarbeitung: Jede formatierte Adresse wird zerlegt und als
    /// `Name <adresse>` bzw. `<adresse>` geschrieben; die Adresse in
    /// Kleinschreibung. Lässt sich ein Eintrag nicht als Adresse lesen,
    /// bleibt der Text unverändert (er ist dann zumindest per Freitext
    /// auffindbar).
    ///
    /// - Parameters:
    ///   - from: Absender als formatierte Adresse.
    ///   - to: Empfänger (An).
    ///   - cc: Empfänger (Cc).
    /// - Returns: Eine Zeile je Adresse.
    static func people(from: String, to: [String], cc: [String]) -> String {
        ([from] + to + cc)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { raw in
                guard let address = MailAddress(parsing: raw) else { return normalized(raw) }
                return personLine(name: address.name, address: address.address)
            }
            .joined(separator: "\n")
    }

    /// Zeile einer Person im Index.
    ///
    /// - Parameters:
    ///   - name: Anzeigename; `nil` = keiner.
    ///   - address: E-Mail-Adresse.
    /// - Returns: `Name <adresse>` bzw. `<adresse>`, Adresse in Kleinschreibung.
    static func personLine(name: String?, address: String) -> String {
        let bracketed = addressToken(address)
        guard let name, !name.isEmpty else { return bracketed }
        return normalized(name) + " " + bracketed
    }

    /// Adresse in der Form, in der sie im Index steht: `<adresse>` in
    /// Kleinschreibung.
    ///
    /// - Parameter address: E-Mail-Adresse.
    /// - Returns: Adresse in spitzen Klammern.
    static func addressToken(_ address: String) -> String {
        "<" + address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + ">"
    }

    /// Entfernt die HTML-Auszeichnung für die Suche.
    ///
    /// Verarbeitung: Kopfbereich, Stilangaben, Skripte und Kommentare
    /// fallen samt Inhalt weg; Zeilen- und Blockenden werden zu
    /// Leerzeichen, damit Wörter benachbarter Zellen oder Absätze nicht
    /// zusammenwachsen; übrige Tags fallen weg; Zeichen-Entitäten werden
    /// aufgelöst und Leerraum zusammengefasst. Fehlerhaftes HTML führt
    /// höchstens zu überflüssigem Text, nie zu einem Fehler.
    ///
    /// - Parameter html: HTML-Text.
    /// - Returns: Reiner Text.
    static func plainText(fromHTML html: String) -> String {
        var text = html
        for pattern in [commentPattern, headPattern, stylePattern, scriptPattern] {
            text = replacing(pattern, in: text, with: " ")
        }
        text = replacing(blockEndPattern, in: text, with: " ")
        text = replacing(tagPattern, in: text, with: "")
        text = decodeEntities(text)
        text = replacing(whitespacePattern, in: text, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Eingabe

    /// `true`, wenn eine Eingabe lang genug für die Textsuche ist.
    ///
    /// - Parameter query: Eingabe im Suchfeld, unverändert.
    /// - Returns: `true` ab `minimumQueryLength` Zeichen (Leerzeichen zählen mit).
    static func isSearchable(_ query: String) -> Bool {
        query.count >= minimumQueryLength
    }

    /// Suchausdruck für FTS5.
    ///
    /// Verarbeitung: Die Eingabe wird unverändert (samt Leerzeichen am
    /// Rand) als Phrase in Anführungszeichen gesetzt; Anführungszeichen in
    /// der Eingabe werden verdoppelt. So gelten Sonderzeichen wie `-`, `*`
    /// oder `:` als Text und nicht als Befehl. Eine gewählte Person wird
    /// als `<adresse>` in der Spalte `people` gesucht. Beides zusammen muss
    /// zutreffen.
    ///
    /// - Parameters:
    ///   - query: Eingabe im Suchfeld; zu kurz = ohne Textbedingung.
    ///   - address: Adresse der gewählten Person; `nil` = keine.
    /// - Returns: Ausdruck für `MATCH`; `nil`, wenn keine Bedingung bleibt.
    static func matchExpression(query: String, address: String?) -> String? {
        var parts: [String] = []
        if let address, !address.isEmpty {
            parts.append("people : " + phrase(addressToken(address)))
        }
        if isSearchable(query) {
            parts.append(phrase(normalized(query)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " AND ")
    }

    // MARK: - Helfer

    /// Setzt einen Text als FTS5-Phrase in Anführungszeichen.
    ///
    /// - Parameter text: Text.
    /// - Returns: `"text"` mit verdoppelten inneren Anführungszeichen.
    private static func phrase(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Zusammengesetzte Unicode-Form (NFC).
    ///
    /// - Parameter text: Text.
    /// - Returns: Text in NFC.
    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// Ersetzt alle Treffer eines regulären Ausdrucks (ohne
    /// Groß-/Kleinschreibung).
    ///
    /// Verarbeitung: Feste Muster kommen vorkompiliert aus
    /// `compiledPatterns`; andere werden bei Bedarf kompiliert.
    ///
    /// - Parameters:
    ///   - pattern: Regulärer Ausdruck.
    ///   - text: Text.
    ///   - replacement: Ersatz.
    /// - Returns: Text mit Ersetzungen; unverändert bei ungültigem Ausdruck.
    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = compiledPatterns[pattern]
                ?? (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    /// Häufige benannte Entitäten; Zahl-Entitäten werden allgemein aufgelöst.
    private static let namedEntities: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü",
        "szlig": "ß", "euro": "€", "ndash": "–", "mdash": "—", "hellip": "…",
        "bdquo": "„", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’",
        "eacute": "é", "egrave": "è", "aacute": "á", "agrave": "à", "copy": "©",
        "reg": "®", "shy": "",
    ]

    /// Löst Zeichen-Entitäten auf (`&amp;`, `&#228;`, `&#xE4;`).
    ///
    /// Verarbeitung: Unbekannte Entitäten bleiben stehen.
    ///
    /// - Parameter text: Text mit Entitäten.
    /// - Returns: Text mit aufgelösten Entitäten.
    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"), let regex = compiledPatterns[entityPattern] else { return text }
        let nsText = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: last, length: match.range.location - last))
            let name = nsText.substring(with: match.range(at: 1))
            result += entity(name) ?? nsText.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        result += nsText.substring(from: last)
        return result
    }

    /// Zeichen zu einer Entität.
    ///
    /// - Parameter name: Name bzw. Zahl ohne `&` und `;`.
    /// - Returns: Zeichen oder `nil`, wenn unbekannt bzw. ungültig.
    private static func entity(_ name: String) -> String? {
        let code: UInt32?
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            code = UInt32(name.dropFirst(2), radix: 16)
        } else if name.hasPrefix("#") {
            code = UInt32(name.dropFirst())
        } else {
            return namedEntities[name]
        }
        guard let code, let scalar = Unicode.Scalar(code) else { return nil }
        return String(scalar)
    }
}
