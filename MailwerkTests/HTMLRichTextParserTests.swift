//
//  HTMLRichTextParserTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das fehlertolerante Einlesen von HTML in das
//  Textmodell (HTMLRichTextParser).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für HTMLRichTextParser.
struct HTMLRichTextParserTests {

    /// Testhilfe: Text aller Zeilen, Zeilen mit „|“ getrennt.
    private func plain(_ html: String) -> String {
        HTMLRichTextParser.parse(html).lines.map { line in
            line.runs.map { run -> String in
                switch run {
                case .text(let text, _): return text
                case .image(let source, _, _): return "[\(source)]"
                }
            }.joined()
        }.joined(separator: "|")
    }

    /// Testhilfe: Format des ersten Textabschnitts der ersten Zeile.
    private func firstStyle(_ html: String) -> RichTextStyle? {
        for line in HTMLRichTextParser.parse(html).lines {
            for run in line.runs { if case .text(_, let style) = run { return style } }
        }
        return nil
    }

    /// Eigenes Editor-HTML wird zeilengleich und verlustfrei eingelesen.
    @Test("Eigenes Editor-HTML: Absätze, Leerzeile, verlustfrei")
    func ownParagraphs() {
        let document = HTMLRichTextParser.parse("<p>Hallo</p><p><br></p><p>Welt</p>")
        #expect(plain("<p>Hallo</p><p><br></p><p>Welt</p>") == "Hallo||Welt")
        #expect(document.isLossless)
    }

    /// Zeilenumbrüche, div-Blöcke und Text ohne Block ergeben Zeilen.
    @Test("br, div und loser Text ergeben Zeilen")
    func lineBreaks() {
        #expect(plain("Erste<br>Zweite") == "Erste|Zweite")
        #expect(plain("<div>A</div><div>B</div>") == "A|B")
        #expect(plain("<p>A<br><br>B</p>") == "A||B")
        #expect(plain("<p>Ende<br></p>") == "Ende")
    }

    /// Leerraum wird wie im Browser zusammengefasst, &nbsp; bleibt.
    @Test("Leerraum wird zusammengefasst, geschütztes Leerzeichen bleibt")
    func whitespace() {
        #expect(plain("<p>\n  Max   Mustermann \n</p>") == "Max Mustermann")
        #expect(plain("<p>A&nbsp;&nbsp;B</p>") == "A\u{00A0}\u{00A0}B")
        #expect(plain("<p><b>Fett</b> normal</p>") == "Fett normal")
    }

    /// Entitäten werden aufgelöst, unbekannte bleiben stehen.
    @Test("Entitäten werden aufgelöst")
    func entities() {
        #expect(plain("<p>5 &lt; 7 &amp; M&uuml;ller &#8364; &#x20AC; &foo;</p>") == "5 < 7 & Müller € € &foo;")
    }

    /// Fett, kursiv und unterstrichen über Tags und Styles.
    @Test("Fett, kursiv, unterstrichen über Tags und Styles")
    func characterFormats() {
        #expect(firstStyle("<b>x</b>")?.bold == true)
        #expect(firstStyle("<strong><em>x</em></strong>")?.italic == true)
        #expect(firstStyle("<u>x</u>")?.underline == true)
        let style = firstStyle("<span style=\"font-weight:bold;font-style:italic;text-decoration:underline\">x</span>")
        #expect(style?.bold == true && style?.italic == true && style?.underline == true)
        #expect(firstStyle("<b><span style=\"font-weight:normal\">x</span></b>")?.bold == false)
    }

    /// Schriftgröße und Farbe in den gängigen Schreibweisen.
    @Test("Schriftgröße und Farbe werden erkannt")
    func sizeAndColor() {
        #expect(firstStyle("<span style=\"font-size:20px\">x</span>")?.fontSizePx == 20)
        #expect(firstStyle("<span style=\"font-size:15pt\">x</span>")?.fontSizePx == 20)
        #expect(firstStyle("<font size=\"2\">x</font>")?.fontSizePx == 13)
        #expect(firstStyle("<span style=\"color:#F00\">x</span>")?.colorHex == "#ff0000")
        #expect(firstStyle("<span style=\"color: rgb(0, 128, 255)\">x</span>")?.colorHex == "#0080ff")
        #expect(firstStyle("<font color=\"navy\">x</font>")?.colorHex == "#000080")
    }

    /// Nur http-, https- und mailto-Links werden übernommen.
    @Test("Links: nur http, https und mailto")
    func links() {
        #expect(firstStyle("<a href=\"https://example.org\">x</a>")?.link == "https://example.org")
        #expect(firstStyle("<a href=\"mailto:a@b.de\">x</a>")?.link == "mailto:a@b.de")
        let unsafe = HTMLRichTextParser.parse("<a href=\"javascript:alert(1)\">x</a>")
        #expect(firstStyle("<a href=\"javascript:alert(1)\">x</a>")?.link == nil)
        #expect(!unsafe.isLossless)
    }

    /// Listen erhalten ihre Art; <li> ohne </li> wird hingenommen.
    @Test("Listen: Art je Zeile, fehlendes </li> wird hingenommen")
    func lists() {
        let document = HTMLRichTextParser.parse("<ul><li>Eins<li>Zwei</ul><ol><li>Drei</li></ol><p>Text</p>")
        #expect(document.lines.map(\.list) == [.bulleted, .bulleted, .numbered, nil])
        #expect(document.isLossless)
        #expect(!HTMLRichTextParser.parse("<ul><li>A<ul><li>B</li></ul></li></ul>").isLossless)
    }

    /// Bilder mit Quelle, Breite und Link.
    @Test("Bilder: Quelle, Breite und Link")
    func images() {
        let document = HTMLRichTextParser.parse("<p>Gruß<br><a href=\"https://firma.de\"><img src=\"logo\" width=\"150\"></a></p>")
        #expect(document.lines.count == 2)
        #expect(document.lines[1].runs == [.image(source: "logo", width: 150, link: "https://firma.de")])
        let styled = HTMLRichTextParser.parse("<img src='cid:a@b' style='width: 120px'>")
        #expect(styled.lines.first?.runs == [.image(source: "cid:a@b", width: 120, link: nil)])
    }

    /// Tabellen und fremde Styles: Text bleibt, Ergebnis ist verlustbehaftet.
    @Test("Tabellen: Text bleibt, Ergebnis gilt als verlustbehaftet")
    func tables() {
        let html = "<table><tr><td style=\"width:100px\">Max</td><td align=\"right\">Tel. 123</td></tr></table>"
        let document = HTMLRichTextParser.parse(html)
        #expect(plain(html) == "Max|Tel. 123")
        #expect(!document.isLossless)
    }

    /// Kommentare, Kopfbereich, Skripte und Styles werden nie Text.
    @Test("Kommentare, head, script und style werden nie Text")
    func ignoredContent() {
        let html = "<!DOCTYPE html><html><head><title>T</title><style>p{color:red}</style></head><body><!-- x --><p>Text</p><script>alert(1)</script></body></html>"
        #expect(plain(html) == "Text")
        #expect(!HTMLRichTextParser.parse(html).isLossless)   // Stylesheet fällt weg
    }

    /// Kaputtes Markup führt weder zum Absturz noch zu Textverlust.
    @Test("Fehlerhaftes Markup wird hingenommen")
    func brokenMarkup() {
        #expect(plain("<p>A < B</p>") == "A < B")
        #expect(plain("<b>offen<i>und</b> weiter") == "offenund weiter")
        #expect(plain("</div>Text<p") == "Text")
        #expect(plain("<span title=\"a>b\">x</span>") == "x")
        #expect(plain("") == "")
    }
}
