//
//  MessageContentPlanTests.swift
//  MailwerkTests
//
//  Zweck: Tests für MessageContentPlan – aus der Struktur einer Mail
//  werden nur Text und HTML der Mail selbst geladen; Anhänge erkannt,
//  eingebettete Bilder und Teile weitergeleiteter Mails nicht geladen;
//  Anhang-Inhalte nur bis zur Schwelle; Text und HTML werden aus den
//  Rohdaten korrekt dekodiert.
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

    /// Eingebettetes Bild (cid): weder Text noch Anhang, wird nicht geladen.
    @Test func inlineImageIsNotLoaded() {
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
}
