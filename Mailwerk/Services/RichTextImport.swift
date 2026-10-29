//
//  RichTextImport.swift
//  Mailwerk
//
//  Zweck: Holt HTML zurück in den formatierten Editor – Gegenstück zu
//  RichTextHTML. Gebraucht für Signaturen (gespeichertes HTML wieder
//  bearbeiten) und Entwürfe.
//
//  Ablauf: HTMLRichTextParser liest das HTML fehlertolerant in Zeilen;
//  daraus entsteht Text mit genau den Attributen, die der Editor selbst
//  setzt (Schrift in den drei Größen, Fett, Kursiv, Unterstrichen, Farbe,
//  Link, Listen-Absatzstil, Bilder als `MailImageAttachment`). So ergibt
//  eigenes Editor-HTML nach dem Rückweg wieder dasselbe HTML.
//
//  Schriftgrößen werden auf die nächste der drei Editorgrößen gerundet.
//  Bilder: `data:`-Adressen werden direkt gelesen, alle anderen Quellen
//  (z. B. „cid:…“ oder der Logo-Platzhalter) über eine übergebene
//  Zuordnung; Bilder ohne Treffer fallen weg.
//
//  Abgrenzung: Einlesen des HTML → HTMLRichTextParser; Editor →
//  RichTextEditor; Rückweg nach HTML → RichTextHTML.
//
//  Abhängigkeiten: Foundation, UIKit bzw. AppKit, HTMLRichTextParser,
//  RichTextController, RichTextSize, RichTextListStyle, MailImageAttachment.
//

import Foundation

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Umwandlung von HTML in formatierten Text des Editors.
enum RichTextImport {

    /// Ergebnis der Umwandlung.
    struct Result {
        /// Formatierter Text für den Editor.
        let text: NSAttributedString
        /// `true`, wenn nichts wegfiel (keine Tabellen, unbekannten Formate,
        /// fehlenden Bilder, gerundeten Schriftgrößen).
        let isLossless: Bool
    }

    /// Zuordnung einer Bildquelle zu einem Bild im Editor.
    ///
    /// Parameter: Quelle wie im HTML (z. B. „logo“, „cid:…“) und gewünschte
    /// Breite in Punkt (`nil` = keine Angabe). Ergebnis: Bild oder `nil`.
    typealias ImageResolver = (_ source: String, _ width: Int?) -> MailImageAttachment?

    /// Wandelt HTML in formatierten Text.
    ///
    /// - Parameters:
    ///   - html: Beliebiges HTML.
    ///   - images: Zuordnung für Bildquellen, die keine `data:`-Adresse sind.
    /// - Returns: Text samt Angabe, ob etwas wegfiel.
    static func attributedString(
        fromHTML html: String,
        images: ImageResolver = { _, _ in nil }
    ) -> Result {
        attributedString(from: HTMLRichTextParser.parse(html), images: images)
    }

    /// Wandelt eingelesene Zeilen in formatierten Text.
    ///
    /// Verarbeitung: Zeilen werden mit Zeilenumbrüchen verbunden; der
    /// Umbruch gehört zur Zeile davor und erhält deren Absatzstil (wie beim
    /// Umschalten einer Liste im Editor).
    ///
    /// - Parameters:
    ///   - document: Eingelesene Zeilen.
    ///   - images: Zuordnung für Bildquellen.
    /// - Returns: Text samt Angabe, ob etwas wegfiel.
    static func attributedString(
        from document: RichTextDocument,
        images: ImageResolver = { _, _ in nil }
    ) -> Result {
        let result = NSMutableAttributedString()
        var isLossless = document.isLossless

        for (index, line) in document.lines.enumerated() {
            let start = result.length
            for run in line.runs {
                switch run {
                case .text(let text, let style):
                    let (attributes, exact) = self.attributes(for: style)
                    if !exact { isLossless = false }
                    result.append(NSAttributedString(string: text, attributes: attributes))
                case .image(let source, let width, let link):
                    guard let image = resolveImage(source: source, width: width, images: images) else {
                        isLossless = false
                        continue
                    }
                    let piece = NSMutableAttributedString(attachment: image)
                    var attributes = RichTextController.defaultAttributes
                    if let link, let url = URL(string: link) { attributes[.link] = url }
                    piece.addAttributes(attributes, range: NSRange(location: 0, length: piece.length))
                    result.append(piece)
                }
            }
            if index < document.lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: RichTextController.defaultAttributes))
            }
            if let list = line.list {
                let range = NSRange(location: start, length: result.length - start)
                if range.length > 0 {
                    result.addAttribute(.paragraphStyle, value: paragraphStyle(for: list), range: range)
                } else {
                    // Leere letzte Listenzeile: Absatzstil über die Eingabe
                    isLossless = false
                }
            }
        }
        return Result(text: result, isLossless: isLossless)
    }

    // MARK: - Formate

    /// Attribute eines Textabschnitts.
    ///
    /// - Parameter style: Format aus dem HTML.
    /// - Returns: Attribute und `false`, wenn die Schriftgröße gerundet werden musste.
    static func attributes(for style: RichTextStyle) -> ([NSAttributedString.Key: Any], Bool) {
        var attributes = RichTextController.defaultAttributes
        var exact = true

        var size = RichTextSize.normal
        if let pixels = style.fontSizePx {
            size = RichTextSize.allCases.min { abs($0.rawValue - pixels) < abs($1.rawValue - pixels) } ?? .normal
            exact = abs(size.rawValue - pixels) < 0.5
        }
        var font = RichTextController.defaultFont.withSize(size.rawValue)
        if style.bold { font = font.togglingTrait(.bold) }
        if style.italic { font = font.togglingTrait(.italic) }
        attributes[.font] = font

        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let hex = style.colorHex, let color = color(hex: hex) { attributes[.foregroundColor] = color }
        if let link = style.link, let url = URL(string: link) { attributes[.link] = url }
        return (attributes, exact)
    }

    /// Absatzstil einer Listenzeile – derselbe, den der Editor beim
    /// Umschalten einer Liste setzt.
    ///
    /// - Parameter list: Listenart.
    /// - Returns: Absatzstil mit Liste und Einzug.
    static func paragraphStyle(for list: RichTextDocument.ListKind) -> NSParagraphStyle {
        let style: RichTextListStyle = list == .numbered ? .numbered : .bulleted
        let paragraph = NSMutableParagraphStyle()
        paragraph.textLists = [NSTextList(markerFormat: style.markerFormat, options: 0)]
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 24
        return paragraph
    }

    /// Farbe aus „#rrggbb“.
    ///
    /// - Parameter hex: Farbwert.
    /// - Returns: Farbe oder `nil` bei ungültigem Wert.
    static func color(hex: String) -> PlatformColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        return PlatformColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    // MARK: - Bilder

    /// Sucht das Bild zu einer Quelle.
    ///
    /// Verarbeitung: `data:`-Adressen (Base64) werden selbst gelesen, alle
    /// anderen Quellen über die Zuordnung.
    ///
    /// - Parameters:
    ///   - source: Quelle wie im HTML.
    ///   - width: Breite in Punkt aus dem HTML.
    ///   - images: Zuordnung des Aufrufers.
    /// - Returns: Bild oder `nil`.
    private static func resolveImage(
        source: String, width: Int?, images: ImageResolver
    ) -> MailImageAttachment? {
        if source.lowercased().hasPrefix("data:") {
            guard let comma = source.firstIndex(of: ","),
                  source[..<comma].lowercased().hasSuffix(";base64"),
                  let data = Data(base64Encoded: String(source[source.index(after: comma)...]),
                                  options: .ignoreUnknownCharacters)
            else { return nil }
            return MailImageAttachment.make(from: data, displayWidth: width.map { CGFloat($0) })
        }
        return images(source, width)
    }
}
