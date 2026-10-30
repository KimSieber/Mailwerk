//
//  RichTextHTML.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 23.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Wandelt den formatierten Text des Editors in HTML und in eine
//  Nur-Text-Fassung um. Beide Teile gehen als multipart/alternative raus.
//
//  Erzeugt bewusst schlankes HTML mit Inline-Styles – das stellen alle
//  gängigen Mail-Programme zuverlässig dar. Nutzertext wird durchgehend
//  maskiert, damit daraus kein Markup entstehen kann.
//
//  Unterstützt genau die Formate des Editors: Fett, Kursiv, Unterstrichen,
//  Schriftgröße, Textfarbe, Aufzählung, nummerierte Liste, Links und
//  Bilder. Bilder (`MailImageAttachment`) werden als `<img>` mit Breite und
//  Höhe ausgegeben; ihre Quelle ist beim Versand `cid:<Content-ID>`
//  (`images(in:)` liefert die passenden Inline-Teile), für das HTML einer
//  Signatur ihr Platzhalter. Der Rückweg HTML → Editor liegt in
//  RichTextImport.
//
//  Abgrenzung: Editor und Formatierung → RichTextEditor, RichTextController;
//  Zusammenbau der Mail → ComposeViewModel.
//
//  Abhängigkeiten: Foundation, UIKit bzw. AppKit, RichTextListStyle,
//  RichTextSize, RichTextController, HTMLEscaping (Maskierung),
//  MailImageAttachment, OutgoingAttachment.
//

import Foundation

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Umwandlung des Editor-Inhalts in HTML und Text.
enum RichTextHTML {

    /// Zeichen, das im Text für einen Anhang (Bild) steht.
    static let attachmentCharacter = "\u{FFFC}"

    /// Quelle eines Bildes im erzeugten HTML.
    ///
    /// Parameter: Bild im Editor. Ergebnis: Wert für `src`; `nil` = das
    /// Bild entfällt im HTML (z. B. ein Bild ohne Platzhalter in einer
    /// Signatur).
    typealias ImageSource = (MailImageAttachment) -> String?

    /// Quelle beim Versand: die Content-ID des Inline-Teils.
    static let cidSource: ImageSource = { "cid:" + $0.contentID }

    // MARK: - HTML

    /// HTML-Fassung des Editor-Inhalts.
    ///
    /// Verarbeitung: Jede Zeile ist ein Absatz; aufeinanderfolgende
    /// Listenzeilen gleicher Art werden zu `<ul>` bzw. `<ol>` zusammengefasst,
    /// leere Absätze als `<br>` erhalten.
    ///
    /// - Parameters:
    ///   - attributed: Formatierter Text des Editors.
    ///   - imageSource: Quelle der Bilder im HTML; Standard `cid:`.
    /// - Returns: HTML-Inhalt ohne Dokument-Hülle.
    static func html(
        from attributed: NSAttributedString,
        imageSource: ImageSource = cidSource
    ) -> String {
        let blocks = blocks(of: attributed)
        var result = ""
        var index = 0

        while index < blocks.count {
            if let style = blocks[index].listStyle {
                var items: [String] = []
                while index < blocks.count, blocks[index].listStyle == style {
                    items.append("<li>\(inlineHTML(of: attributed, in: blocks[index].range, imageSource: imageSource))</li>")
                    index += 1
                }
                let tag = style == .numbered ? "ol" : "ul"
                result += "<\(tag)>\(items.joined())</\(tag)>"
            } else {
                let content = inlineHTML(of: attributed, in: blocks[index].range, imageSource: imageSource)
                result += "<p>\(content.isEmpty ? "<br>" : content)</p>"
                index += 1
            }
        }
        return result
    }

    // MARK: - Nur-Text

    /// Nur-Text-Fassung des Editor-Inhalts.
    ///
    /// Verarbeitung: Aufzählungen mit „•“, nummerierte Listen mit
    /// fortlaufender Nummer je Liste. Bilder entfallen.
    ///
    /// - Parameter attributed: Formatierter Text des Editors.
    /// - Returns: Text für den Textteil der Mail.
    static func plainText(from attributed: NSAttributedString) -> String {
        let text = attributed.string as NSString
        var lines: [String] = []
        var number = 1
        var previousStyle: RichTextListStyle?

        for block in blocks(of: attributed) {
            let content = text.substring(with: block.range)
                .replacingOccurrences(of: attachmentCharacter, with: "")
            switch block.listStyle {
            case .bulleted:
                lines.append("• " + content)
            case .numbered:
                if previousStyle != .numbered { number = 1 }
                lines.append("\(number). " + content)
                number += 1
            case nil:
                lines.append(content)
            }
            previousStyle = block.listStyle
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Bilder

    /// Inline-Teile für die Bilder im Text.
    ///
    /// Verarbeitung: Jedes Bild einmal (gleiche Content-ID nur einmal),
    /// in der Reihenfolge im Text, mit fortlaufendem Dateinamen.
    ///
    /// - Parameter attributed: Formatierter Text des Editors.
    /// - Returns: Inline-Teile mit Content-ID.
    static func images(in attributed: NSAttributedString) -> [OutgoingAttachment] {
        var result: [OutgoingAttachment] = []
        var seen: Set<String> = []
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length), options: []
        ) { value, _, _ in
            guard let image = value as? MailImageAttachment, seen.insert(image.contentID).inserted else { return }
            result.append(OutgoingAttachment(
                filename: image.filename(number: result.count + 1),
                mimeType: image.mimeType,
                data: image.imageData,
                contentID: image.contentID
            ))
        }
        return result
    }

    /// HTML eines Bildes.
    ///
    /// - Parameters:
    ///   - image: Bild im Editor.
    ///   - imageSource: Quelle im HTML.
    /// - Returns: `<img>` mit Quelle, Breite und Höhe; leer, wenn die
    ///   Quelle `nil` ist.
    private static func imageHTML(_ image: MailImageAttachment, imageSource: ImageSource) -> String {
        guard let rawSource = imageSource(image) else { return "" }
        let width = Int(image.bounds.width.rounded())
        let height = Int(image.bounds.height.rounded())
        let source = HTMLEscaping.escaped(rawSource)
        return "<img src=\"\(source)\" width=\"\(width)\" height=\"\(height)\" alt=\"\">"
    }

    // MARK: - Absätze

    /// Ein Absatz: Bereich im Text und Listenart.
    private struct Block {
        /// Bereich der Zeile ohne Zeilenumbruch.
        let range: NSRange
        /// Listenart; `nil` für gewöhnliche Absätze.
        let listStyle: RichTextListStyle?
    }

    /// Zerlegt den Text an Zeilenumbrüchen in Absätze.
    ///
    /// - Parameter attributed: Formatierter Text.
    /// - Returns: Absätze in ihrer Reihenfolge.
    private static func blocks(of attributed: NSAttributedString) -> [Block] {
        var blocks: [Block] = []
        var location = 0

        for line in attributed.string.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let range = NSRange(location: location, length: length)
            blocks.append(Block(range: range, listStyle: listStyle(of: attributed, at: range)))
            location += length + 1   // +1 für den Zeilenumbruch
        }
        return blocks
    }

    /// Listenart eines Absatzes aus seinem Absatzstil.
    ///
    /// - Parameters:
    ///   - attributed: Formatierter Text.
    ///   - range: Bereich des Absatzes.
    /// - Returns: Listenart oder `nil`.
    private static func listStyle(
        of attributed: NSAttributedString,
        at range: NSRange
    ) -> RichTextListStyle? {
        guard attributed.length > 0, range.location < attributed.length else { return nil }
        let paragraph = attributed.attribute(
            .paragraphStyle, at: range.location, effectiveRange: nil
        ) as? NSParagraphStyle
        return RichTextListStyle.from(markerFormat: paragraph?.textLists.first?.markerFormat)
    }

    // MARK: - Zeichenformate

    /// HTML der Zeichenformate eines Bereichs.
    ///
    /// Verarbeitung: Je Abschnitt gleicher Formatierung ein maskierter Text,
    /// bei Bedarf in `<span style>` (fett, kursiv, Größe, Unterstreichung,
    /// Farbe) und `<a href>`. Standardgröße und Standardfarbe erzeugen keinen
    /// Stil. Ein Bild wird zu `<img>` (ein Link darum bleibt); andere
    /// Anhänge entfallen.
    ///
    /// - Parameters:
    ///   - attributed: Formatierter Text.
    ///   - range: Bereich eines Absatzes.
    ///   - imageSource: Quelle der Bilder im HTML.
    /// - Returns: HTML des Bereichs.
    private static func inlineHTML(
        of attributed: NSAttributedString,
        in range: NSRange,
        imageSource: ImageSource
    ) -> String {
        guard range.length > 0 else { return "" }
        let text = attributed.string as NSString
        var result = ""

        attributed.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
            let raw = text.substring(with: subRange)
            guard !raw.isEmpty else { return }
            if attributes[.attachment] != nil {
                result += attachmentHTML(raw, attributes: attributes, imageSource: imageSource)
            } else {
                result += textHTML(raw, attributes: attributes)
            }
        }
        return result
    }

    /// HTML eines Abschnitts mit Anhang: ein Bild wird zu `<img>` (je
    /// Anhangszeichen eins, ein Link darum bleibt); andere Anhänge entfallen.
    ///
    /// - Parameters:
    ///   - raw: Text des Abschnitts (Anhangszeichen).
    ///   - attributes: Attribute des Abschnitts.
    ///   - imageSource: Quelle der Bilder im HTML.
    /// - Returns: HTML des Abschnitts; leer bei anderen Anhängen.
    private static func attachmentHTML(
        _ raw: String,
        attributes: [NSAttributedString.Key: Any],
        imageSource: ImageSource
    ) -> String {
        guard let image = attributes[.attachment] as? MailImageAttachment else { return "" }
        let count = raw.components(separatedBy: attachmentCharacter).count - 1
        let piece = String(repeating: imageHTML(image, imageSource: imageSource), count: count)
        return linked(piece, attributes: attributes)
    }

    /// HTML eines Textabschnitts: maskierter Text, bei Bedarf in
    /// `<span style>` und `<a href>`.
    ///
    /// - Parameters:
    ///   - raw: Text des Abschnitts.
    ///   - attributes: Attribute des Abschnitts.
    /// - Returns: HTML des Abschnitts.
    private static func textHTML(_ raw: String, attributes: [NSAttributedString.Key: Any]) -> String {
        var piece = HTMLEscaping.escaped(raw)
        let styles = cssStyles(of: attributes)
        if !styles.isEmpty {
            piece = "<span style=\"\(styles.joined(separator: ";"))\">\(piece)</span>"
        }
        return linked(piece, attributes: attributes)
    }

    /// CSS-Angaben der Zeichenformate: fett, kursiv, Größe, Unterstreichung,
    /// Farbe. Standardgröße und Standardfarbe erzeugen keine Angabe.
    ///
    /// - Parameter attributes: Attribute eines Abschnitts.
    /// - Returns: CSS-Angaben, z. B. „font-weight:bold“.
    private static func cssStyles(of attributes: [NSAttributedString.Key: Any]) -> [String] {
        var styles: [String] = []
        if let font = attributes[.font] as? PlatformFont {
            let traits = font.fontDescriptor.symbolicTraits
            #if os(iOS)
            if traits.contains(.traitBold) { styles.append("font-weight:bold") }
            if traits.contains(.traitItalic) { styles.append("font-style:italic") }
            #else
            if traits.contains(.bold) { styles.append("font-weight:bold") }
            if traits.contains(.italic) { styles.append("font-style:italic") }
            #endif
            if abs(font.pointSize - RichTextSize.normal.rawValue) > 0.5 {
                styles.append("font-size:\(Int(font.pointSize.rounded()))px")
            }
        }
        if (attributes[.underlineStyle] as? Int ?? 0) != 0 {
            styles.append("text-decoration:underline")
        }
        if let color = attributes[.foregroundColor] as? PlatformColor,
           let hex = color.mwHexRGB,
           hex != RichTextController.defaultTextColor.mwHexRGB {
            styles.append("color:\(hex)")
        }
        return styles
    }

    /// Legt einen Link um ein HTML-Stück, falls der Abschnitt einen trägt.
    ///
    /// - Parameters:
    ///   - piece: HTML-Stück; leer bleibt leer.
    ///   - attributes: Attribute des Abschnitts.
    /// - Returns: Stück, ggf. in `<a href>`.
    private static func linked(_ piece: String, attributes: [NSAttributedString.Key: Any]) -> String {
        guard !piece.isEmpty, let link = linkURL(attributes[.link]) else { return piece }
        return "<a href=\"\(HTMLEscaping.escaped(link))\">\(piece)</a>"
    }

    /// Link-Ziel aus dem Attribut `.link`.
    ///
    /// - Parameter value: Wert des Attributs (URL oder Zeichenkette).
    /// - Returns: Link als Text oder `nil`.
    private static func linkURL(_ value: Any?) -> String? {
        switch value {
        case let url as URL:       return url.absoluteString
        case let string as String: return string
        default:                   return nil
        }
    }
}

// MARK: - Farbwerte

extension PlatformColor {
    /// Farbe als "#rrggbb", oder nil, wenn sie sich nicht in RGB umrechnen lässt.
    var mwHexRGB: String? {
        #if os(iOS)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #else
        guard let converted = usingColorSpace(.sRGB) else { return nil }
        let red = converted.redComponent
        let green = converted.greenComponent
        let blue = converted.blueComponent
        #endif
        let value = (Int(red * 255) << 16) | (Int(green * 255) << 8) | Int(blue * 255)
        return String(format: "#%06x", value)
    }
}
