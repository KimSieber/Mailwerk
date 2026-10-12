//
//  MessageContentPlanTests.swift
//  MailwerkTests
//
//  Zweck: Tests für MessageContentPlan – aus der Struktur einer Mail
//  werden nur Text und HTML der Mail selbst geladen; Anhänge und
//  eingebettete Bilder getrennt erkannt, Teile weitergeleiteter Mails
//  nicht geladen; Anhang-Inhalte nur bis zur Schwelle; Text und HTML
//  werden aus den Rohdaten korrekt dekodiert; Folgen aus Text-, HTML- und
//  Bildteilen (Apple Mail) werden vollständig und in Reihenfolge
//  zusammengesetzt.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageContentPlanTests {

    /// Text, HTML und PDF-Anhang: geladen werden nur Text und HTML.
    @Test func alternativeWithAttachment() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1.1", contentType: "text/plain; charset=utf-8"),
                MessageContentPlan.part(section: "1.2", contentType: "text/html; charset=utf-8"),
                MessageContentPlan.part(section: "2", contentType: "application/pdf",
                                        disposition: "attachment", filename: "Rechnung.pdf", size: 120_000)
            ],
            totalSize: 200_000, threshold: 5_000_000
        )
        #expect(plan.bodySections == ["1.1", "1.2"])
        #expect(plan.attachmentSections == ["2"])
    }

    /// Eingebettetes Bild (cid): weder Text noch Anhang, sondern eingebettetes Bild.
    @Test func inlineImageIsSeparateFromAttachments() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1", contentType: "text/html; charset=utf-8"),
                MessageContentPlan.part(section: "2", contentType: "image/png",
                                        disposition: "inline", filename: "logo.png", contentId: "<logo@x>")
            ],
            totalSize: 50_000, threshold: 5_000_000
        )
        #expect(plan.bodySections == ["1"])
        #expect(plan.attachmentSections.isEmpty)
        #expect(plan.inlineImageSections == ["2"])
    }

    /// Bild als echter Anhang zählt nicht als eingebettet; Bilder weitergeleiteter Mails auch nicht.
    @Test func inlineImagesExcludeAttachmentsAndForwardedParts() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1", contentType: "text/html; charset=utf-8"),
                MessageContentPlan.part(section: "2", contentType: "image/jpeg",
                                        disposition: "attachment", filename: "Foto.jpg"),
                MessageContentPlan.part(section: "3", contentType: "image/jpeg",
                                        disposition: "inline", filename: "IMG_1.jpg"),
                MessageContentPlan.part(section: "4", contentType: "message/rfc822",
                                        disposition: "attachment", filename: "Weitergeleitet.eml"),
                MessageContentPlan.part(section: "4.2", contentType: "image/png",
                                        disposition: "inline", contentId: "<alt@x>")
            ],
            totalSize: 80_000, threshold: 5_000_000
        )
        #expect(plan.attachmentSections.contains("2"))
        #expect(plan.inlineImageSections == ["3"])
    }

    /// Weitergeleitete Mail: nur als Anhang geführt, ihr Text wird nicht geladen.
    @Test func forwardedMessageBodiesAreNotLoaded() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1", contentType: "text/plain; charset=utf-8"),
                MessageContentPlan.part(section: "2", contentType: "message/rfc822",
                                        disposition: "attachment", filename: "Weitergeleitet.eml"),
                MessageContentPlan.part(section: "2.1", contentType: "text/plain; charset=utf-8"),
                MessageContentPlan.part(section: "2.2", contentType: "text/html; charset=utf-8")
            ],
            totalSize: 80_000, threshold: 5_000_000
        )
        #expect(plan.bodySections == ["1"])
        #expect(plan.attachmentSections == ["2"])
    }

    /// Anhang-Inhalte werden bis einschließlich der Schwelle mitgeladen, darüber nicht.
    @Test func attachmentDataOnlyUpToThreshold() {
        let parts = [MessageContentPlan.part(section: "1", contentType: "text/plain")]
        #expect(MessageContentPlan(structure: parts, totalSize: 5_000_000, threshold: 5_000_000).loadsAttachmentData)
        #expect(!MessageContentPlan(structure: parts, totalSize: 5_000_001, threshold: 5_000_000).loadsAttachmentData)
    }

    /// Text in Base64 und HTML in Quoted-Printable werden korrekt dekodiert.
    @Test func bodiesAreDecoded() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1.1", contentType: "text/plain; charset=utf-8",
                                        encoding: "base64"),
                MessageContentPlan.part(section: "1.2", contentType: "text/html; charset=utf-8",
                                        encoding: "quoted-printable")
            ],
            totalSize: 1_000, threshold: 5_000_000
        )
        let bodies = plan.bodies(withData: [
            "1.1": Data("Hallo Welt".utf8).base64EncodedData(),
            "1.2": Data("<p>Gr=C3=BC=C3=9Fe</p>".utf8)
        ])
        #expect(bodies.text == "Hallo Welt")
        #expect(bodies.html == "<p>Grüße</p>")
    }

    /// Mail nur mit Text: kein HTML, keine Anhänge.
    @Test func plainTextOnly() {
        let plan = MessageContentPlan(
            structure: [MessageContentPlan.part(section: "1", contentType: "text/plain; charset=utf-8")],
            totalSize: 500, threshold: 5_000_000
        )
        #expect(plan.bodySections == ["1"])
        #expect(plan.attachmentSections.isEmpty)
        let bodies = plan.bodies(withData: ["1": Data("Nur Text".utf8)])
        #expect(bodies.text == "Nur Text")
        #expect(bodies.html == nil)
    }

    /// Apple Mail „Text – Bild – Text“ ohne HTML: alle Texte, Bild dazwischen per cid.
    @Test func textSequenceWithImage() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1", contentType: "text/plain; charset=us-ascii"),
                MessageContentPlan.part(section: "2", contentType: "image/jpeg",
                                        disposition: "inline", encoding: "base64", filename: "IMG_1496.jpeg"),
                MessageContentPlan.part(section: "3", contentType: "text/plain; charset=us-ascii")
            ],
            totalSize: 6_000_000, threshold: 5_000_000
        )
        #expect(plan.layout == .textSequence)
        #expect(plan.bodySections == ["1", "3"])
        #expect(plan.inlineImageSections == ["2"])
        let bodies = plan.bodies(withData: [
            "1": Data("Hier steht ein Bild: <a>".utf8),
            "3": Data("Und dies ist das Ende.".utf8)
        ])
        let html = bodies.html ?? ""
        let image = html.range(of: #"<img src="cid:teil-2@mailwerk">"#)
        let end = html.range(of: "Und dies ist das Ende.")
        #expect(html.contains("Hier steht ein Bild: &lt;a&gt;"))
        #expect(image != nil && end != nil && image!.lowerBound < end!.lowerBound)
        #expect(bodies.text == "Hier steht ein Bild: <a>\nUnd dies ist das Ende.")
    }

    /// Apple Mail „HTML – Bild – HTML“: beide HTML-Teile, Bild an seiner Stelle.
    @Test func htmlSequenceWithImage() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1", contentType: "text/plain; charset=utf-8"),
                MessageContentPlan.part(section: "2.1", contentType: "text/html; charset=utf-8"),
                MessageContentPlan.part(section: "2.2", contentType: "image/jpeg",
                                        disposition: "inline", filename: "IMG.jpeg"),
                MessageContentPlan.part(section: "2.3", contentType: "text/html; charset=utf-8")
            ],
            totalSize: 1_000, threshold: 5_000_000
        )
        #expect(plan.layout == .htmlSequence)
        #expect(plan.bodySections == ["1", "2.1", "2.3"])
        let bodies = plan.bodies(withData: [
            "1": Data("Text".utf8),
            "2.1": Data("<p>Anfang</p>".utf8),
            "2.3": Data("<p>Ende</p>".utf8)
        ])
        #expect(bodies.html == "<p>Anfang</p>\n" + #"<img src="cid:teil-2.2@mailwerk">"# + "\n<p>Ende</p>")
        #expect(bodies.text == "Text")
    }

    /// Bilder, die das HTML schon per cid anspricht, werden nicht zusätzlich eingesetzt.
    @Test func htmlSequenceKeepsReferencedImages() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1", contentType: "text/html; charset=utf-8"),
                MessageContentPlan.part(section: "2", contentType: "image/png",
                                        disposition: "inline", contentId: "<logo@x>"),
                MessageContentPlan.part(section: "3", contentType: "text/html; charset=utf-8")
            ],
            totalSize: 1_000, threshold: 5_000_000
        )
        let bodies = plan.bodies(withData: [
            "1": Data(#"<img src="cid:logo@x">"#.utf8),
            "3": Data("<p>Ende</p>".utf8)
        ])
        #expect(bodies.html == #"<img src="cid:logo@x">"# + "\n<p>Ende</p>")
    }

    /// Gewöhnliche Mail mit cid-Logo bleibt beim ersten Text- und HTML-Teil.
    @Test func relatedMailStaysSingle() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1.1", contentType: "text/plain; charset=utf-8"),
                MessageContentPlan.part(section: "1.2", contentType: "text/html; charset=utf-8"),
                MessageContentPlan.part(section: "2", contentType: "image/png",
                                        disposition: "inline", contentId: "<logo@x>")
            ],
            totalSize: 1_000, threshold: 5_000_000
        )
        #expect(plan.layout == .single)
        #expect(plan.bodySections == ["1.1", "1.2"])
    }

    /// Content-ID eines Bilds: eigene ohne Klammern, sonst aus der Abschnittsnummer.
    @Test func contentIDForImages() {
        #expect(MessageContentPlan.contentID(for: MessageContentPlan.part(
            section: "2", contentType: "image/png", contentId: "<logo@x>")) == "logo@x")
        #expect(MessageContentPlan.contentID(for: MessageContentPlan.part(
            section: "1.3", contentType: "image/png")) == "teil-1.3@mailwerk")
    }
}
