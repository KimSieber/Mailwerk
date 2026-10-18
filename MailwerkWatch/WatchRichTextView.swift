//
//  WatchRichTextView.swift
//  MailwerkWatch
//
//  Zweck: Zeigt den HTML-Inhalt einer Mail auf der Watch. watchOS hat keine
//  Web-Ansicht; das HTML wird deshalb in einfache Bausteine zerlegt
//  (HTMLRichTextParser) und mit SwiftUI gesetzt: Absätze, Fett, Kursiv,
//  Unterstrichen, Links, Aufzählungen, nummerierte Listen und Bilder.
//  Tabellenlayouts (Newsletter) werden dabei flach; der Text bleibt.
//
//  Bewusst ohne Textfarben und Schriftgrößen der Mail: Auf dem dunklen
//  Grund der Watch wären dunkle Farben unlesbar. Große Schrift wird fett.
//
//  Bilder:
//  - eingebettet als `data:` – immer, ohne Netzzugriff;
//  - extern (http/https) – nur nach Freigabe (`allowsRemoteContent`), wie
//    in der App: sofort bei vertrauenswürdigem Absender, sonst per Knopf;
//  - Anhänge im Text (`cid:`) kommen nicht auf die Watch und entfallen.
//
//  Abgrenzung: Einlesen → HTMLRichTextParser; Freigabe → WatchMailDetailView.
//
//  Abhängigkeiten: SwiftUI, UIKit (UIImage), HTMLRichTextParser
//  (RichTextDocument).
//

import SwiftUI
import UIKit

/// Ein darstellbarer Abschnitt des Inhalts.
nonisolated enum WatchRichTextBlock: Equatable, Sendable {
    /// Ein Absatz als formatierter Text.
    case text(AttributedString)
    /// Ein Bild mit Quelle und gewünschter Breite (CSS-Pixel), ggf. mit Link.
    case image(source: String, width: Int?, link: URL?)
    /// Leerzeile zwischen Absätzen.
    case spacer
}

/// Zeigt einen eingelesenen HTML-Inhalt.
struct WatchRichTextView: View {
    /// Abschnitte des Inhalts.
    let blocks: [WatchRichTextBlock]
    /// `true`, wenn externe Bilder geladen werden dürfen.
    let allowsRemoteContent: Bool

    /// Abschnitte untereinander.
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(text)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .image(let source, let width, let link):
                    WatchMailImage(source: source, width: width, link: link, allowsRemoteContent: allowsRemoteContent)
                case .spacer:
                    Spacer().frame(height: 4)
                }
            }
        }
    }

    // MARK: - Aufbereiten

    /// Zerlegt ein eingelesenes Dokument in darstellbare Abschnitte.
    ///
    /// Verarbeitung: Textabschnitte einer Zeile werden zu einem Absatz
    /// verbunden; ein Bild beendet den Absatz. Listen erhalten „•“ bzw. die
    /// laufende Nummer. Mehrere Leerzeilen hintereinander werden zu einer.
    ///
    /// - Parameter document: Eingelesenes HTML.
    /// - Returns: Abschnitte.
    nonisolated static func blocks(from document: RichTextDocument) -> [WatchRichTextBlock] {
        var blocks: [WatchRichTextBlock] = []
        var number = 0
        for line in document.lines {
            if line.list == .numbered { number += 1 } else { number = 0 }
            var paragraph = AttributedString()
            switch line.list {
            case .bulleted: paragraph.append(AttributedString("• "))
            case .numbered: paragraph.append(AttributedString("\(number). "))
            case nil: break
            }
            var hasText = false
            for run in line.runs {
                switch run {
                case .text(let text, let style):
                    paragraph.append(attributed(text, style: style))
                    hasText = hasText || !text.trimmingCharacters(in: .whitespaces).isEmpty
                case .image(let source, let width, let link):
                    if hasText { blocks.append(.text(paragraph)) }
                    paragraph = AttributedString()
                    hasText = false
                    blocks.append(.image(source: source, width: width, link: link.flatMap(URL.init(string:))))
                }
            }
            if hasText {
                blocks.append(.text(paragraph))
            } else if line.runs.isEmpty, blocks.last != .spacer, !blocks.isEmpty {
                blocks.append(.spacer)
            }
        }
        while blocks.last == .spacer { blocks.removeLast() }
        return blocks
    }

    /// `true`, wenn der Inhalt externe Bilder enthält (Knopf „Bilder laden“).
    ///
    /// - Parameter blocks: Abschnitte.
    /// - Returns: `true` bei mindestens einem Bild über http oder https.
    nonisolated static func hasRemoteImages(_ blocks: [WatchRichTextBlock]) -> Bool {
        blocks.contains { block in
            guard case .image(let source, _, _) = block else { return false }
            return WatchMailImage.isRemote(source)
        }
    }

    /// Formatierter Text eines Abschnitts.
    ///
    /// - Parameters:
    ///   - text: Text.
    ///   - style: Format aus dem HTML.
    /// - Returns: Text mit Fett, Kursiv, Unterstrichen und Link.
    nonisolated private static func attributed(_ text: String, style: RichTextStyle) -> AttributedString {
        var part = AttributedString(text)
        var font = Font.footnote
        if style.bold || (style.fontSizePx ?? 0) >= 20 { font = font.bold() }
        if style.italic { font = font.italic() }
        part.font = font
        if style.underline { part.underlineStyle = Text.LineStyle.single }
        if let link = style.link, let url = URL(string: link) {
            part.link = url
        }
        return part
    }
}

/// Ein Bild im Inhalt einer Mail.
struct WatchMailImage: View {
    /// Quelle wie im HTML.
    let source: String
    /// Gewünschte Breite in CSS-Pixeln; `nil` = volle Breite.
    let width: Int?
    /// Link des Bilds; `nil` = keiner.
    let link: URL?
    /// `true`, wenn externe Bilder geladen werden dürfen.
    let allowsRemoteContent: Bool

    /// Bild, Platzhalter beim Laden oder nichts.
    var body: some View {
        if let image = Self.embeddedImage(source) {
            linked(Image(uiImage: image).resizable().scaledToFit())
        } else if allowsRemoteContent, Self.isRemote(source), let url = URL(string: source) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    linked(image.resizable().scaledToFit())
                } else if phase.error == nil {
                    ProgressView()
                }
            }
        }
    }

    /// Begrenzt die Breite und hinterlegt ggf. den Link.
    ///
    /// - Parameter image: Bild.
    /// - Returns: Bild in passender Breite, bei einem Link antippbar.
    @ViewBuilder
    private func linked(_ image: some View) -> some View {
        let sized = image.frame(maxWidth: width.map { CGFloat($0) } ?? .infinity, alignment: .leading)
        if let link {
            Link(destination: link) { sized }
                .buttonStyle(.plain)
        } else {
            sized
        }
    }

    /// `true` für Bilder über http oder https.
    ///
    /// - Parameter source: Quelle.
    /// - Returns: `true` bei einem externen Bild.
    nonisolated static func isRemote(_ source: String) -> Bool {
        let lower = source.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://")
    }

    /// Eingebettetes Bild aus einer `data:`-Adresse.
    ///
    /// - Parameter source: Quelle.
    /// - Returns: Bild oder `nil`, wenn die Quelle keine lesbare `data:`-Adresse ist.
    private static func embeddedImage(_ source: String) -> UIImage? {
        guard source.lowercased().hasPrefix("data:"),
              let comma = source.firstIndex(of: ","),
              source[..<comma].lowercased().contains(";base64"),
              let data = Data(base64Encoded: String(source[source.index(after: comma)...]), options: .ignoreUnknownCharacters)
        else { return nil }
        return UIImage(data: data)
    }
}
