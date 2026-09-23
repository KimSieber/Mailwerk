//
//  RichTextHTML.swift
//  Mailwerk
//
//  Created by Kim Sieber on 22.09.26.
//


//
//  RichTextHTML.swift
//  Mailwerk
//
//  Wandelt den formatierten Text des Editors in HTML und in eine
//  Nur-Text-Fassung um. Beide Teile gehen als multipart/alternative raus.
//
//  Erzeugt bewusst schlankes HTML mit Inline-Styles – das stellen alle
//  gängigen Mail-Programme zuverlässig dar. Nutzertext wird durchgehend
//  maskiert, damit daraus kein Markup entstehen kann.
//
//  Unterstützt genau die Formate des Editors: Fett, Kursiv, Unterstrichen,
//  Schriftgröße, Textfarbe, Aufzählung, nummerierte Liste und Links.
//

import Foundation

#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum RichTextHTML {

    // MARK: - HTML

    static func html(from attributed: NSAttributedString) -> String {
        let blocks = blocks(of: attributed)
        var result = ""
        var index = 0

        while index < blocks.count {
            if let style = blocks[index].listStyle {
                var items: [String] = []
                while index < blocks.count, blocks[index].listStyle == style {
                    items.append("<li>\(inlineHTML(of: attributed, in: blocks[index].range))</li>")
                    index += 1
                }
                let tag = style == .numbered ? "ol" : "ul"
                result += "<\(tag)>\(items.joined())</\(tag)>"
            } else {
                let content = inlineHTML(of: attributed, in: blocks[index].range)
                result += "<p>\(content.isEmpty ? "<br>" : content)</p>"
                index += 1
            }
        }
        return result
    }

    // MARK: - Nur-Text

    static func plainText(from attributed: NSAttributedString) -> String {
        let text = attributed.string as NSString
        var lines: [String] = []
        var number = 1
        var previousStyle: RichTextListStyle?

        for block in blocks(of: attributed) {
            let content = text.substring(with: block.range)
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

    // MARK: - Absätze

    private struct Block {
        let range: NSRange
        let listStyle: RichTextListStyle?
    }

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

    private static func inlineHTML(of attributed: NSAttributedString, in range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        let text = attributed.string as NSString
        var result = ""

        attributed.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
            let raw = text.substring(with: subRange)
            guard !raw.isEmpty else { return }
            var piece = ReplyBuilder.escapeHTML(raw)

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

            if !styles.isEmpty {
                piece = "<span style=\"\(styles.joined(separator: ";"))\">\(piece)</span>"
            }
            if let link = linkURL(attributes[.link]) {
                piece = "<a href=\"\(ReplyBuilder.escapeHTML(link))\">\(piece)</a>"
            }
            result += piece
        }
        return result
    }

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