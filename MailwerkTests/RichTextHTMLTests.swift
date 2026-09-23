//
//  RichTextHTMLTests.swift
//  Mailwerk
//
//  Created by Kim Sieber on 22.09.26.
//


//
//  RichTextHTMLTests.swift
//  MailwerkTests
//
//  Tests für die Umwandlung des formatierten Texts in HTML und Nur-Text.
//

import Foundation
import Testing
@testable import Mailwerk

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
struct RichTextHTMLTests {

    // MARK: - Hilfen

    private func attributed(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text,
            attributes: RichTextController.defaultAttributes
        )
    }

    private func listParagraphStyle(_ style: RichTextListStyle) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.textLists = [NSTextList(markerFormat: style.markerFormat, options: 0)]
        paragraph.headIndent = 24
        return paragraph
    }

    // MARK: - Absätze

    @Test("Absätze werden zu <p>")
    func paragraphs() {
        let html = RichTextHTML.html(from: attributed("Hallo\nWelt"))
        #expect(html == "<p>Hallo</p><p>Welt</p>")
    }

    @Test("Leerzeile bleibt als Abstand erhalten")
    func emptyLine() {
        let html = RichTextHTML.html(from: attributed("Hallo\n\nWelt"))
        #expect(html == "<p>Hallo</p><p><br></p><p>Welt</p>")
    }

    @Test("Sonderzeichen werden maskiert")
    func escaping() {
        let html = RichTextHTML.html(from: attributed("5 < 7 & <b>fett</b>"))
        #expect(html == "<p>5 &lt; 7 &amp; &lt;b&gt;fett&lt;/b&gt;</p>")
    }

    // MARK: - Zeichenformate

    @Test("Fett und kursiv werden zu Inline-Styles")
    func boldAndItalic() {
        let text = attributed("Hallo Welt")
        let bold = RichTextController.defaultFont.togglingTrait(.bold)
        text.addAttribute(.font, value: bold, range: NSRange(location: 6, length: 4))
        let html = RichTextHTML.html(from: text)
        #expect(html == "<p>Hallo <span style=\"font-weight:bold\">Welt</span></p>")
    }

    @Test("Unterstreichung wird übernommen")
    func underline() {
        let text = attributed("Hallo")
        text.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 5)
        )
        #expect(RichTextHTML.html(from: text).contains("text-decoration:underline"))
    }

    @Test("Normalgröße erzeugt keine Angabe, abweichende Größen schon")
    func fontSizes() {
        #expect(!RichTextHTML.html(from: attributed("Hallo")).contains("font-size"))

        let text = attributed("Hallo")
        let large = RichTextController.defaultFont.withSize(RichTextSize.large.rawValue)
        text.addAttribute(.font, value: large, range: NSRange(location: 0, length: 5))
        #expect(RichTextHTML.html(from: text).contains("font-size:20px"))
    }

    @Test("Standardfarbe erzeugt keine Angabe, andere Farben schon")
    func colors() {
        #expect(!RichTextHTML.html(from: attributed("Hallo")).contains("color:"))

        let text = attributed("Hallo")
        text.addAttribute(
            .foregroundColor,
            value: PlatformColor.red,
            range: NSRange(location: 0, length: 5)
        )
        #expect(RichTextHTML.html(from: text).contains("color:#ff0000"))
    }

    @Test("Links werden zu <a href>")
    func links() {
        let text = attributed("Mailwerk")
        text.addAttribute(
            .link,
            value: URL(string: "https://example.org/x?a=1&b=2")!,
            range: NSRange(location: 0, length: 8)
        )
        let html = RichTextHTML.html(from: text)
        #expect(html.contains("<a href=\"https://example.org/x?a=1&amp;b=2\">Mailwerk</a>"))
    }

    // MARK: - Listen

    @Test("Aufzählung wird zu <ul>, nummerierte Liste zu <ol>")
    func lists() {
        let text = attributed("Eins\nZwei\nText")
        text.addAttribute(
            .paragraphStyle,
            value: listParagraphStyle(.bulleted),
            range: NSRange(location: 0, length: 9)   // beide Listenzeilen
        )
        #expect(RichTextHTML.html(from: text) == "<ul><li>Eins</li><li>Zwei</li></ul><p>Text</p>")

        let numbered = attributed("Eins\nZwei")
        numbered.addAttribute(
            .paragraphStyle,
            value: listParagraphStyle(.numbered),
            range: NSRange(location: 0, length: 9)
        )
        #expect(RichTextHTML.html(from: numbered) == "<ol><li>Eins</li><li>Zwei</li></ol>")
    }

    // MARK: - Nur-Text

    @Test("Nur-Text: Aufzählungszeichen und Nummerierung werden ausgeschrieben")
    func plainTextLists() {
        let text = attributed("Eins\nZwei\nText")
        text.addAttribute(
            .paragraphStyle,
            value: listParagraphStyle(.numbered),
            range: NSRange(location: 0, length: 9)
        )
        #expect(RichTextHTML.plainText(from: text) == "1. Eins\n2. Zwei\nText")
    }

    @Test("Nur-Text behält Absätze und maskiert nichts")
    func plainTextParagraphs() {
        let text = attributed("5 < 7\n\nEnde")
        #expect(RichTextHTML.plainText(from: text) == "5 < 7\n\nEnde")
    }
}