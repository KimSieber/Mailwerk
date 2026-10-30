//
//  HTMLRichTextParser.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 13.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Liest HTML fehlertolerant in ein schlichtes Textmodell ein –
//  Zeilen mit formatierten Textabschnitten und Bildern. Grundlage, um
//  gespeichertes HTML wieder im Editor zu bearbeiten (Signaturen, Entwürfe).
//
//  Abgebildet wird genau das, was der Editor kann: Absätze und
//  Zeilenumbrüche, Fett, Kursiv, Unterstrichen, Schriftgröße, Textfarbe,
//  Links (nur http, https, mailto), Aufzählung, nummerierte Liste und
//  Bilder. Alles andere (Tabellen, Schriftarten, Abstände, Ausrichtung,
//  verschachtelte Listen …) fällt weg; der Text darin bleibt erhalten.
//  `RichTextDocument.isLossless` meldet, ob dabei etwas verloren ging.
//
//  Fehlertolerant: Kein Tag wird vorausgesetzt, nicht geschlossene oder
//  falsch verschachtelte Tags werden hingenommen, unbekannte übersprungen.
//  Inhalte von `script`, `style`, `title` und Kommentare werden nie Text.
//  Aus dem HTML entsteht nie ausführbares Markup: Das Ergebnis ist reiner
//  Text mit Formatangaben.
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Umsetzung in formatierten Text des Editors → RichTextImport;
//  Rückweg Editor → HTML → RichTextHTML.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

// MARK: - Textmodell

/// Zeichenformat eines Textabschnitts.
nonisolated struct RichTextStyle: Equatable {
    /// Fett.
    var bold = false
    /// Kursiv.
    var italic = false
    /// Unterstrichen.
    var underline = false
    /// Schriftgröße in CSS-Pixeln; `nil` = Standardgröße.
    var fontSizePx: Double?
    /// Textfarbe als „#rrggbb“; `nil` = Standardfarbe.
    var colorHex: String?
    /// Link-Ziel (nur http, https, mailto); `nil` = kein Link.
    var link: String?
}

/// Ein Abschnitt einer Zeile: Text mit einheitlichem Format oder ein Bild.
nonisolated enum RichTextRun: Equatable {
    /// Text mit seinem Format.
    case text(String, RichTextStyle)
    /// Bild mit Quelle (wie im HTML, z. B. „cid:…“, „data:…“, „logo“),
    /// gewünschter Breite in Punkt und optionalem Link.
    case image(source: String, width: Int?, link: String?)
}

/// Eine Zeile (ein Absatz im Editor).
nonisolated struct RichTextLine: Equatable {
    /// Listenart der Zeile; `nil` = gewöhnlicher Absatz.
    var list: RichTextDocument.ListKind?
    /// Abschnitte der Zeile in ihrer Reihenfolge.
    var runs: [RichTextRun] = []
}

/// Eingelesenes HTML als Zeilen.
nonisolated struct RichTextDocument: Equatable {
    /// Listenart einer Zeile.
    enum ListKind: Equatable { case bulleted, numbered }

    /// Zeilen in ihrer Reihenfolge.
    var lines: [RichTextLine]
    /// `true`, wenn das HTML nichts enthielt, das beim Einlesen wegfiel.
    var isLossless: Bool
}

// MARK: - Einlesen

/// Fehlertolerantes Einlesen von HTML in das Textmodell.
nonisolated enum HTMLRichTextParser {

    // MARK: Maße wie im Browser

    /// Grundschriftgröße des Browsers in Pixeln (`medium`, `1rem`).
    static let defaultFontSizePx: Double = 16
    /// Pixel je typografischem Punkt (CSS: 1pt = 4/3 px).
    static let pixelsPerPoint: Double = 4.0 / 3.0
    /// Bezugswert von Prozentangaben.
    static let percentBase: Double = 100
    /// Ab diesem `font-weight` gilt Text als fett (CSS: 600 = semibold).
    static let minimumBoldWeight = 600
    /// Längste benannte Entität samt „#“-Zahlform, die noch gesucht wird.
    static let maxEntityLength = 12
    /// CSS-Schlüsselwörter für Schriftgrößen in Pixeln.
    static let cssKeywordSizes: [String: Double] = [
        "xx-small": 9, "x-small": 10, "small": 13, "medium": 16,
        "large": 18, "x-large": 24, "xx-large": 32
    ]
    /// Größen des alten `<font size="1…7">` in Pixeln.
    static let fontTagSizes: [Int: Double] = [1: 10, 2: 13, 3: 16, 4: 18, 5: 24, 6: 32, 7: 48]

    /// Liest HTML ein.
    ///
    /// Verarbeitung: Zerlegt das HTML zeichenweise in Tags und Text. Tags
    /// steuern Absätze und Formate über einen Stapel offener Elemente;
    /// Text wird wie im Browser zusammengefasst (Leerraum → ein Leerzeichen)
    /// und von Entitäten befreit.
    ///
    /// - Parameter html: Beliebiges HTML, auch ein vollständiges Dokument
    ///   oder fehlerhaftes Markup.
    /// - Returns: Zeilen samt Angabe, ob etwas wegfiel.
    static func parse(_ html: String) -> RichTextDocument {
        var builder = Builder()
        let chars = Array(html)
        var index = 0
        var textStart = 0

        while index < chars.count {
            guard chars[index] == "<" else { index += 1; continue }

            if textStart < index {
                builder.text(String(chars[textStart..<index]))
            }
            index = consumeMarkup(chars, at: index, into: &builder)
            textStart = index
        }
        if textStart < chars.count {
            builder.text(String(chars[textStart..<chars.count]))
        }
        return builder.finish()
    }

    /// Verarbeitet, was an einem „<“ beginnt: Kommentar oder Doctype
    /// überspringen, Tag auswerten, Inhalt von `script`/`style`/…
    /// überspringen – oder das „<“ als Text übernehmen, wenn kein Tag folgt.
    ///
    /// - Parameters:
    ///   - chars: Zeichen des HTML.
    ///   - index: Position des „<“.
    ///   - builder: Aufbau des Dokuments.
    /// - Returns: Position, an der das Zerlegen weitergeht.
    private static func consumeMarkup(_ chars: [Character], at index: Int, into builder: inout Builder) -> Int {
        if let end = skipSpecial(chars, from: index) { return end }
        guard let tag = readTag(chars, from: index) else {
            // Kein Tag – das „<“ ist gewöhnlicher Text
            builder.text("<")
            return index + 1
        }
        if !tag.isClosing, rawTextElements.contains(tag.name) {
            if tag.name == "style" { builder.isLossless = false }
            return skipRawText(chars, from: tag.end, name: tag.name)
        }
        builder.handle(tag)
        return tag.end
    }

    // MARK: Zerlegen

    /// Ein gelesenes Tag.
    struct Tag {
        /// Name in Kleinbuchstaben.
        let name: String
        /// `true` für ein schließendes Tag (`</p>`).
        let isClosing: Bool
        /// Attribute mit Namen in Kleinbuchstaben; Werte ohne Entitäten.
        let attributes: [String: String]
        /// Position direkt hinter dem Tag.
        let end: Int
    }

    /// Elemente, deren Inhalt nie Text wird.
    private static let rawTextElements: Set<String> = ["script", "style", "title", "textarea", "noscript", "template"]

    /// Überspringt Kommentare, Doctype und Verarbeitungsanweisungen.
    ///
    /// - Parameters:
    ///   - chars: Zeichen des HTML.
    ///   - index: Position des „<“.
    /// - Returns: Position dahinter oder `nil`, wenn dort nichts davon steht.
    private static func skipSpecial(_ chars: [Character], from index: Int) -> Int? {
        let commentOpen = "<!--", commentClose = "-->"
        if matches(chars, at: index, commentOpen) {
            var i = index + commentOpen.count
            while i < chars.count, !matches(chars, at: i, commentClose) { i += 1 }
            return min(i + commentClose.count, chars.count)
        }
        if matches(chars, at: index, "<!") || matches(chars, at: index, "<?") {
            var i = index + "<!".count
            while i < chars.count, chars[i] != ">" { i += 1 }
            return min(i + 1, chars.count)
        }
        return nil
    }

    /// Liest ein Tag samt Attributen.
    ///
    /// Verarbeitung: Werte in doppelten, einfachen oder ohne
    /// Anführungszeichen; ein „>“ innerhalb von Anführungszeichen beendet
    /// das Tag nicht. Fehlt das schließende „>“, reicht das Tag bis zum Ende.
    ///
    /// - Parameters:
    ///   - chars: Zeichen des HTML.
    ///   - index: Position des „<“.
    /// - Returns: Tag oder `nil`, wenn kein Tag-Name folgt.
    private static func readTag(_ chars: [Character], from index: Int) -> Tag? {
        var i = index + 1
        var isClosing = false
        if i < chars.count, chars[i] == "/" { isClosing = true; i += 1 }

        var name = ""
        while i < chars.count, chars[i].isLetter || chars[i].isNumber {
            name.append(chars[i]); i += 1
        }
        guard !name.isEmpty, name.first?.isLetter == true else { return nil }

        var attributes: [String: String] = [:]
        while i < chars.count, chars[i] != ">" {
            if chars[i].isWhitespace || chars[i] == "/" { i += 1; continue }
            let attribute = readAttribute(chars, from: i)
            i = attribute.end
            if !attribute.name.isEmpty {
                attributes[attribute.name.lowercased()] = decodeEntities(attribute.value)
            } else if i < chars.count, chars[i] != ">" {
                i += 1   // unerwartetes Zeichen überspringen
            }
        }
        return Tag(
            name: name.lowercased(),
            isClosing: isClosing,
            attributes: attributes,
            end: min(i + 1, chars.count)
        )
    }

    /// Liest ein Attribut eines Tags: Name und, falls ein „=“ folgt, Wert.
    ///
    /// - Parameters:
    ///   - chars: Zeichen des HTML.
    ///   - index: Position des ersten Zeichens des Namens.
    /// - Returns: Name (ggf. leer), Rohwert (ohne Entitäten-Auflösung) und
    ///   Position dahinter.
    private static func readAttribute(_ chars: [Character], from index: Int) -> (name: String, value: String, end: Int) {
        var i = index
        var name = ""
        while i < chars.count, !chars[i].isWhitespace, chars[i] != "=", chars[i] != ">", chars[i] != "/" {
            name.append(chars[i]); i += 1
        }
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        guard i < chars.count, chars[i] == "=" else { return (name, "", i) }
        i += 1
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        let value = readAttributeValue(chars, from: i)
        return (name, value.text, value.end)
    }

    /// Liest einen Attributwert – in doppelten, einfachen oder ohne
    /// Anführungszeichen. Ein „>“ innerhalb von Anführungszeichen beendet
    /// den Wert nicht.
    ///
    /// - Parameters:
    ///   - chars: Zeichen des HTML.
    ///   - index: Position des ersten Zeichens des Werts.
    /// - Returns: Rohwert und Position dahinter.
    private static func readAttributeValue(_ chars: [Character], from index: Int) -> (text: String, end: Int) {
        var i = index
        var value = ""
        if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
            let quote = chars[i]; i += 1
            while i < chars.count, chars[i] != quote { value.append(chars[i]); i += 1 }
            if i < chars.count { i += 1 }
        } else {
            while i < chars.count, !chars[i].isWhitespace, chars[i] != ">" {
                value.append(chars[i]); i += 1
            }
        }
        return (value, i)
    }

    /// Überspringt den Inhalt eines Elements wie `script` bis zu seinem
    /// schließenden Tag.
    ///
    /// - Parameters:
    ///   - chars: Zeichen des HTML.
    ///   - index: Position hinter dem öffnenden Tag.
    ///   - name: Name des Elements.
    /// - Returns: Position hinter dem schließenden Tag (bzw. Ende).
    private static func skipRawText(_ chars: [Character], from index: Int, name: String) -> Int {
        var i = index
        let closing = "</" + name
        while i < chars.count {
            if chars[i] == "<", matches(chars, at: i, closing, caseInsensitive: true) {
                while i < chars.count, chars[i] != ">" { i += 1 }
                return min(i + 1, chars.count)
            }
            i += 1
        }
        return chars.count
    }

    /// Prüft, ob an einer Position eine bestimmte Zeichenfolge steht.
    ///
    /// - Parameters:
    ///   - chars: Zeichen.
    ///   - index: Startposition.
    ///   - text: Gesuchte Zeichenfolge.
    ///   - caseInsensitive: Groß-/Kleinschreibung ignorieren.
    /// - Returns: `true` bei Übereinstimmung.
    private static func matches(
        _ chars: [Character], at index: Int, _ text: String, caseInsensitive: Bool = false
    ) -> Bool {
        let needle = Array(text)
        guard index + needle.count <= chars.count else { return false }
        for offset in 0..<needle.count {
            let a = chars[index + offset], b = needle[offset]
            if caseInsensitive ? a.lowercased() != b.lowercased() : a != b { return false }
        }
        return true
    }

    // MARK: Entitäten

    /// Benannte Entitäten, die in Mails und Signaturen vorkommen.
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "shy": "", "auml": "ä", "ouml": "ö", "uuml": "ü",
        "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß", "euro": "€",
        "copy": "©", "reg": "®", "trade": "™", "ndash": "–", "mdash": "—",
        "hellip": "…", "laquo": "«", "raquo": "»", "bdquo": "„", "ldquo": "“",
        "rdquo": "”", "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "middot": "·",
        "bull": "•", "deg": "°", "times": "×", "eacute": "é", "egrave": "è",
        "agrave": "à", "aacute": "á", "ccedil": "ç", "para": "¶", "sect": "§"
    ]

    /// Löst Entitäten auf (`&amp;`, `&#228;`, `&#xE4;`, benannte).
    ///
    /// Verarbeitung: Unbekannte oder fehlerhafte Entitäten bleiben als Text
    /// stehen, wie im Browser.
    ///
    /// - Parameter text: Text mit Entitäten.
    /// - Returns: Text ohne Entitäten.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let afterAmp = rest.index(after: amp)
            guard let semicolon = rest[afterAmp...].prefix(Self.maxEntityLength).firstIndex(of: ";") else {
                result += "&"; rest = rest[afterAmp...]; continue
            }
            let name = String(rest[afterAmp..<semicolon])
            if let decoded = decodeEntity(name) {
                result += decoded
                rest = rest[rest.index(after: semicolon)...]
            } else {
                result += "&"; rest = rest[afterAmp...]
            }
        }
        result += rest
        return result
    }

    /// Wert einer einzelnen Entität.
    ///
    /// - Parameter name: Inhalt zwischen „&“ und „;“.
    /// - Returns: Zeichen oder `nil`, wenn unbekannt.
    private static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value: UInt32?
            if digits.first == "x" || digits.first == "X" {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits)
            }
            guard let value, value > 0, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[name]
    }

    // MARK: Werte

    /// Farbnamen, die in einfachen Signaturen vorkommen.
    private static let namedColors: [String: String] = [
        "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000",
        "blue": "#0000ff", "orange": "#ffa500", "purple": "#800080", "gray": "#808080",
        "grey": "#808080", "navy": "#000080", "maroon": "#800000", "teal": "#008080",
        "silver": "#c0c0c0", "yellow": "#ffff00", "darkgray": "#a9a9a9", "darkgrey": "#a9a9a9"
    ]

    /// Wandelt eine CSS-Farbe in „#rrggbb“.
    ///
    /// - Parameter value: „#abc“, „#aabbcc“, „rgb(…)“, „rgba(…)“ oder ein
    ///   gängiger Farbname.
    /// - Returns: Farbe oder `nil`, wenn sie nicht erkannt wird.
    static func parseColor(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespaces).lowercased()
        if raw.hasPrefix("#") {
            let hex = String(raw.dropFirst())
            guard hex.allSatisfy(\.isHexDigit) else { return nil }
            if hex.count == 3 { return "#" + hex.map { "\($0)\($0)" }.joined() }
            if hex.count == 6 { return "#" + hex }
            return nil
        }
        if raw.hasPrefix("rgb") {
            guard let open = raw.firstIndex(of: "("), let close = raw.firstIndex(of: ")"),
                  open < close else { return nil }
            let parts = raw[raw.index(after: open)..<close]
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .prefix(3)
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 3 else { return nil }
            let clamped = parts.map { Int(max(0, min(255, $0.rounded()))) }
            return String(format: "#%02x%02x%02x", clamped[0], clamped[1], clamped[2])
        }
        return namedColors[raw]
    }

    /// Wandelt eine CSS-Schriftgröße in Pixel.
    ///
    /// - Parameters:
    ///   - value: z. B. „13px“, „10pt“, „1.2em“, „120%“, „small“.
    ///   - parent: Größe des umgebenden Texts in Pixeln.
    /// - Returns: Größe in Pixeln oder `nil`, wenn nicht erkannt.
    static func parseFontSize(_ value: String, parent: Double) -> Double? {
        let raw = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let size = Self.cssKeywordSizes[raw] { return size }
        /// Zahl vor einer Einheit, z. B. „12“ aus „12px“.
        ///
        /// - Parameter suffix: Einheit („px“, „pt“ …).
        /// - Returns: Zahl, wenn der Wert auf die Einheit endet, sonst `nil`.
        func number(_ suffix: String) -> Double? {
            raw.hasSuffix(suffix) ? Double(raw.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)) : nil
        }
        if let px = number("px") { return px }
        if let pt = number("pt") { return pt * Self.pixelsPerPoint }
        if let em = number("rem") { return em * Self.defaultFontSizePx }
        if let em = number("em") { return em * parent }
        if let percent = number("%") { return percent / Self.percentBase * parent }
        return Double(raw)
    }

    /// Größe des alten `<font size="…">` in Pixeln (wie im Browser).
    ///
    /// - Parameter value: „1“ … „7“.
    /// - Returns: Größe oder `nil`.
    static func fontTagSize(_ value: String) -> Double? {
        Int(value.trimmingCharacters(in: .whitespaces)).flatMap { Self.fontTagSizes[$0] }
    }

    /// Prüft ein Link-Ziel.
    ///
    /// - Parameter href: Wert des Attributs `href`.
    /// - Returns: Ziel, wenn es mit http:, https: oder mailto: beginnt; sonst `nil`.
    static func safeLink(_ href: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:"),
              !trimmed.contains(where: \.isWhitespace) else { return nil }
        return trimmed
    }

    /// Breitenangabe eines Bildes in Punkt.
    ///
    /// - Parameter value: z. B. „150“ oder „150px“.
    /// - Returns: Breite oder `nil`.
    static func parseWidth(_ value: String?) -> Int? {
        guard var raw = value?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        if raw.hasSuffix("px") { raw = String(raw.dropLast("px".count)) }
        guard let number = Double(raw.trimmingCharacters(in: .whitespaces)), number > 0 else { return nil }
        return Int(number.rounded())
    }

    // MARK: - Aufbau der Zeilen

    /// Baut aus Tags und Text die Zeilen auf.
    private struct Builder {
        /// Ein offenes Element mit dem Format, das in ihm gilt.
        struct Frame {
            /// Name des Elements.
            let name: String
            /// Format innerhalb des Elements.
            let style: RichTextStyle
        }

        /// Fertige Zeilen.
        var lines: [RichTextLine] = []
        /// Angefangene Zeile; `nil` = noch keine.
        var current: RichTextLine?
        /// Stapel der offenen Elemente.
        var frames: [Frame] = []
        /// Bleibt `true`, solange nichts wegfällt.
        var isLossless = true

        /// Elemente, die einen eigenen Absatz bilden.
        static let blockElements: Set<String> = [
            "p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6",
            "blockquote", "table", "tr", "td", "th", "tbody", "thead", "tfoot",
            "caption", "pre", "section", "article", "header", "footer", "center",
            "address", "dl", "dt", "dd", "figure", "figcaption", "nav", "main",
            "aside", "form", "fieldset", "hr"
        ]
        /// Elemente ohne Inhalt und ohne schließendes Tag.
        static let voidElements: Set<String> = [
            "br", "img", "hr", "meta", "link", "input", "wbr", "col", "area", "base", "source"
        ]
        /// Elemente, die das Modell verlustfrei abbildet.
        static let supportedElements: Set<String> = [
            "html", "head", "body", "meta", "title", "p", "div", "br", "span",
            "b", "strong", "i", "em", "u", "a", "ul", "ol", "li", "img", "font"
        ]
        /// Attribute, die nichts Sichtbares tragen oder ausgewertet werden.
        static let harmlessAttributes: Set<String> = [
            "style", "href", "src", "width", "height", "alt", "title", "color",
            "size", "class", "id", "lang", "dir", "name", "target", "rel",
            "border", "charset", "content", "http-equiv", "xmlns"
        ]

        /// Format an der aktuellen Stelle.
        var style: RichTextStyle { frames.last?.style ?? RichTextStyle() }

        // MARK: Tags

        /// Verarbeitet ein Tag.
        ///
        /// - Parameter tag: Gelesenes Tag.
        mutating func handle(_ tag: Tag) {
            if !Self.supportedElements.contains(tag.name) { isLossless = false }
            if tag.isClosing { close(tag.name); return }

            for name in tag.attributes.keys where !Self.harmlessAttributes.contains(name) {
                isLossless = false
            }

            switch tag.name {
            case "br":
                closeLine(force: true)
                return
            case "img":
                image(tag)
                return
            case "hr":
                closeLine(force: false)
                return
            case "li":
                closeImplicitly("li")
            case "p":
                closeImplicitly("p")
            case "ul", "ol":
                if frames.contains(where: { $0.name == "ul" || $0.name == "ol" }) { isLossless = false }
            default:
                break
            }

            if Self.blockElements.contains(tag.name) { closeLine(force: false) }
            guard !Self.voidElements.contains(tag.name) else { return }
            frames.append(Frame(name: tag.name, style: style(for: tag)))
        }

        /// Schließt ein Element.
        ///
        /// Verarbeitung: Gesucht wird das zuletzt geöffnete Element dieses
        /// Namens; es und alle darin noch offenen werden geschlossen. Ein
        /// schließendes Tag ohne offenes Element wird übergangen.
        ///
        /// - Parameter name: Name des Elements.
        mutating func close(_ name: String) {
            if Self.blockElements.contains(name) { closeLine(force: false) }
            guard let index = frames.lastIndex(where: { $0.name == name }) else { return }
            frames.removeSubrange(index...)
        }

        /// Schließt ein noch offenes gleichnamiges Element, bevor ein neues
        /// beginnt (`<li>` ohne `</li>`, `<p>` ohne `</p>`).
        ///
        /// Verarbeitung: Nur innerhalb der aktuellen Liste bzw. des aktuellen
        /// Blocks – ein `<li>` einer äußeren Liste bleibt offen.
        ///
        /// - Parameter name: „li“ oder „p“.
        mutating func closeImplicitly(_ name: String) {
            let barriers: Set<String> = name == "li" ? ["ul", "ol"] : ["div", "li", "td", "th", "blockquote"]
            for index in frames.indices.reversed() {
                if barriers.contains(frames[index].name) { return }
                if frames[index].name == name {
                    closeLine(force: false)
                    frames.removeSubrange(index...)
                    return
                }
            }
        }

        /// Format innerhalb eines neu geöffneten Elements.
        ///
        /// - Parameter tag: Öffnendes Tag.
        /// - Returns: Format aus dem umgebenden Format, der Bedeutung des
        ///   Elements und seinem `style`-Attribut.
        mutating func style(for tag: Tag) -> RichTextStyle {
            var result = style
            switch tag.name {
            case "b", "strong", "h1", "h2", "h3", "h4", "h5", "h6", "th":
                result.bold = true
            case "i", "em":
                result.italic = true
            case "u", "ins":
                result.underline = true
            case "a":
                if let href = tag.attributes["href"] {
                    if let link = HTMLRichTextParser.safeLink(href) {
                        result.link = link
                    } else {
                        isLossless = false
                    }
                }
            case "font":
                if let color = tag.attributes["color"].flatMap(HTMLRichTextParser.parseColor) {
                    result.colorHex = color
                }
                if let size = tag.attributes["size"].flatMap(HTMLRichTextParser.fontTagSize) {
                    result.fontSizePx = size
                }
                if tag.attributes["face"] != nil { isLossless = false }
            default:
                break
            }
            if let css = tag.attributes["style"] { apply(css: css, to: &result) }
            return result
        }

        /// Wertet ein `style`-Attribut aus.
        ///
        /// - Parameters:
        ///   - css: Inhalt des Attributs, z. B. „font-weight:bold;color:#f00“.
        ///   - result: Format, das angepasst wird.
        mutating func apply(css: String, to result: inout RichTextStyle) {
            for declaration in css.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let property = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = parts[1].replacingOccurrences(of: "!important", with: "")
                    .trimmingCharacters(in: .whitespaces).lowercased()
                guard !value.isEmpty else { continue }

                switch property {
                case "font-weight":
                    if value == "bold" || value == "bolder" { result.bold = true }
                    else if let weight = Int(value) { result.bold = weight >= HTMLRichTextParser.minimumBoldWeight }
                    else if value == "normal" || value == "lighter" { result.bold = false }
                case "font-style":
                    result.italic = value == "italic" || value == "oblique"
                case "text-decoration", "text-decoration-line":
                    result.underline = value.contains("underline")
                    if value.contains("line-through") || value.contains("overline") { isLossless = false }
                case "font-size":
                    let parent = result.fontSizePx ?? HTMLRichTextParser.defaultFontSizePx
                    if let size = HTMLRichTextParser.parseFontSize(value, parent: parent) {
                        result.fontSizePx = size
                    } else {
                        isLossless = false
                    }
                case "color":
                    if let color = HTMLRichTextParser.parseColor(value) {
                        result.colorHex = color
                    } else {
                        isLossless = false
                    }
                default:
                    isLossless = false
                }
            }
        }

        /// Fügt ein Bild in die aktuelle Zeile ein.
        ///
        /// Verarbeitung: Die Breite kommt aus dem Attribut `width` oder aus
        /// `style="width:…"`. Bilder ohne Quelle fallen weg.
        ///
        /// - Parameter tag: `img`-Tag.
        mutating func image(_ tag: Tag) {
            let source = (tag.attributes["src"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { isLossless = false; return }
            var width = HTMLRichTextParser.parseWidth(tag.attributes["width"])
            if width == nil, let css = tag.attributes["style"] {
                for declaration in css.split(separator: ";") {
                    let parts = declaration.split(separator: ":", maxSplits: 1)
                    if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "width" {
                        width = HTMLRichTextParser.parseWidth(String(parts[1]))
                    }
                }
            }
            let link = style.link
            openLine()
            current?.runs.append(.image(source: source, width: width, link: link))
        }

        // MARK: Text

        /// Fügt Text an.
        ///
        /// Verarbeitung: Leerraum wird zu einem Leerzeichen zusammengefasst;
        /// am Zeilenanfang und nach einem Leerzeichen entfällt er. Danach
        /// werden Entitäten aufgelöst (ein `&nbsp;` bleibt so erhalten).
        /// Gleich formatierter Text wird zu einem Abschnitt zusammengefasst.
        ///
        /// - Parameter raw: Text, wie er im HTML steht.
        mutating func text(_ raw: String) {
            var collapsed = ""
            var lastWasSpace = false
            for character in raw {
                if character == " " || character == "\n" || character == "\t" || character == "\r" || character == "\u{0C}" {
                    if !lastWasSpace { collapsed.append(" ") }
                    lastWasSpace = true
                } else {
                    collapsed.append(character)
                    lastWasSpace = false
                }
            }
            var decoded = HTMLRichTextParser.decodeEntities(collapsed)
            if endsWithSpace || current == nil || current?.runs.isEmpty == true {
                while decoded.first == " " { decoded.removeFirst() }
            }
            guard !decoded.isEmpty else { return }

            openLine()
            let style = self.style
            guard var line = current else { return }
            if case .text(let previous, let previousStyle)? = line.runs.last, previousStyle == style {
                line.runs[line.runs.count - 1] = .text(previous + decoded, style)
            } else {
                line.runs.append(.text(decoded, style))
            }
            current = line
        }

        /// `true`, wenn die aktuelle Zeile mit einem Leerzeichen endet.
        var endsWithSpace: Bool {
            if case .text(let text, _)? = current?.runs.last { return text.hasSuffix(" ") }
            return false
        }

        // MARK: Zeilen

        /// Beginnt eine Zeile, falls noch keine angefangen ist.
        ///
        /// Verarbeitung: Die Listenart ergibt sich aus dem innersten offenen
        /// `li` und der Liste darüber (`ol` = nummeriert, sonst Aufzählung).
        mutating func openLine() {
            guard current == nil else { return }
            current = RichTextLine(list: listKind())
        }

        /// Listenart an der aktuellen Stelle.
        ///
        /// - Returns: Listenart oder `nil` außerhalb eines `li`.
        func listKind() -> RichTextDocument.ListKind? {
            guard let item = frames.lastIndex(where: { $0.name == "li" }) else { return nil }
            let list = frames[..<item].last { $0.name == "ul" || $0.name == "ol" }
            return list?.name == "ol" ? .numbered : .bulleted
        }

        /// Schließt die angefangene Zeile ab.
        ///
        /// Verarbeitung: Leerzeichen am Zeilenende entfallen. Eine leere
        /// Zeile entsteht nur durch einen Zeilenumbruch (`force`), nicht
        /// durch einen leeren Block.
        ///
        /// - Parameter force: `true` für `<br>` – auch eine leere Zeile zählt.
        mutating func closeLine(force: Bool) {
            if current == nil, force { openLine() }
            guard var line = current else { return }
            current = nil
            if case .text(var text, let style)? = line.runs.last {
                while text.last == " " { text.removeLast() }
                if text.isEmpty { line.runs.removeLast() } else { line.runs[line.runs.count - 1] = .text(text, style) }
            }
            guard force || !line.runs.isEmpty else { return }
            lines.append(line)
        }

        /// Schließt ab und liefert das Ergebnis.
        ///
        /// - Returns: Eingelesenes Dokument.
        mutating func finish() -> RichTextDocument {
            closeLine(force: false)
            return RichTextDocument(lines: lines, isLossless: isLossless)
        }
    }
}
