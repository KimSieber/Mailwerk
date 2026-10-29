//
//  RichTextImportTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Rückweg HTML → Editor (RichTextImport) und für
//  Bilder im Editor (MailImageAttachment, RichTextHTML).
//

import Foundation
import Testing
@testable import Mailwerk

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Tests für RichTextImport und Bilder im Editor.
@MainActor
struct RichTextImportTests {

    /// Testhilfe: 1×1-Pixel-PNG.
    private static let pngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    /// Testhilfe: Bild für den Editor.
    private func testImage(width: CGFloat = 150) -> MailImageAttachment? {
        Data(base64Encoded: Self.pngBase64).flatMap { MailImageAttachment.make(from: $0, displayWidth: width) }
    }

    /// Testhilfe: HTML → Editor → HTML.
    private func roundTrip(_ html: String) -> String {
        RichTextHTML.html(from: RichTextImport.attributedString(fromHTML: html).text)
    }

    /// Absätze und Leerzeilen überstehen den Rückweg unverändert.
    @Test("Rückweg: Absätze und Leerzeile unverändert")
    func roundTripParagraphs() {
        let html = "<p>Hallo</p><p><br></p><p>Welt</p>"
        #expect(roundTrip(html) == html)
    }

    /// Zeichenformate und Links überstehen den Rückweg unverändert.
    @Test("Rückweg: Fett, Größe, Farbe, Unterstrichen und Link unverändert")
    func roundTripFormats() {
        let html = "<p>Gruß <span style=\"font-weight:bold;font-size:20px\">Max</span> "
            + "<span style=\"text-decoration:underline;color:#ff0000\">rot</span> "
            + "<a href=\"https://example.org\">Web</a></p>"
        #expect(roundTrip(html) == html)
    }

    /// Listen überstehen den Rückweg unverändert.
    @Test("Rückweg: Listen unverändert")
    func roundTripLists() {
        let html = "<ul><li>Eins</li><li>Zwei</li></ul><ol><li>Drei</li></ol><p>Text</p>"
        #expect(roundTrip(html) == html)
    }

    /// Eigenes HTML gilt als verlustfrei, eine Tabelle nicht.
    @Test("Verlustfrei-Angabe: eigenes HTML ja, Tabelle nein")
    func lossless() {
        #expect(RichTextImport.attributedString(fromHTML: "<p><b>x</b></p>").isLossless)
        #expect(!RichTextImport.attributedString(fromHTML: "<table><tr><td>x</td></tr></table>").isLossless)
        #expect(!RichTextImport.attributedString(fromHTML: "<p style=\"font-size:30px\">x</p>").isLossless)
    }

    /// data:-Bilder werden gelesen, andere Quellen über die Zuordnung.
    @Test("Bilder: data:-Adresse und Zuordnung über Platzhalter")
    func importImages() {
        let dataHTML = "<p><img src=\"data:image/png;base64,\(Self.pngBase64)\" width=\"40\"></p>"
        let fromData = RichTextImport.attributedString(fromHTML: dataHTML)
        #expect(RichTextHTML.images(in: fromData.text).count == 1)

        let logo = testImage()
        let fromPlaceholder = RichTextImport.attributedString(fromHTML: "<p><img src=\"logo\"></p>") { source, _ in
            source == "logo" ? logo : nil
        }
        #expect(RichTextHTML.images(in: fromPlaceholder.text).first?.contentID == logo?.contentID)

        let missing = RichTextImport.attributedString(fromHTML: "<p><img src=\"cid:fehlt\"></p>")
        #expect(!missing.isLossless)
    }

    /// Ein Bild wird als <img> mit cid: und Breite ausgegeben und als
    /// Inline-Teil geliefert; im Nur-Text entfällt es.
    @Test("Bild: <img> mit cid: und Breite, Inline-Teil, nicht im Nur-Text")
    func exportImage() throws {
        let image = try #require(testImage(width: 150))
        let text = NSMutableAttributedString(string: "Logo ", attributes: RichTextController.defaultAttributes)
        text.append(NSAttributedString(attachment: image))

        let html = RichTextHTML.html(from: text)
        #expect(html.contains("<img src=\"cid:\(image.contentID)\" width=\"150\""))
        #expect(RichTextHTML.html(from: text, imageSource: { _ in "logo" }).contains("src=\"logo\""))

        let parts = RichTextHTML.images(in: text)
        #expect(parts.count == 1)
        #expect(parts.first?.contentID == image.contentID)
        #expect(parts.first?.mimeType == "image/png")

        #expect(RichTextHTML.plainText(from: text) == "Logo ")
    }

    /// Ein vom System eingefügtes Bild wird zu einem versendbaren Bild.
    @Test("Eingefügtes Systembild wird aufbereitet")
    func normalizePastedImage() throws {
        let data = try #require(Data(base64Encoded: Self.pngBase64))
        let pasted = NSTextAttachment(data: data, ofType: "public.png")
        let storage = NSTextStorage(attributedString: NSAttributedString(attachment: pasted))

        #expect(EditorImages.normalize(storage))
        let value = storage.attribute(.attachment, at: 0, effectiveRange: nil)
        #expect(value is MailImageAttachment)
        #expect(!EditorImages.normalize(storage))   // zweiter Durchgang ändert nichts
    }
}
