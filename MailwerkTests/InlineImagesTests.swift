//
//  InlineImagesTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Regeln zu eingebetteten Bildern (InlineImages) –
//  Content-IDs vereinheitlichen, angesprochene Bilder im HTML finden,
//  sichtbare Anhangliste, fehlende Bilder erkennen und `cid:`-Verweise
//  durch `data:`-Adressen ersetzen.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct InlineImagesTests {

    /// Testhilfe: Anhang bzw. eingebettetes Bild einer Mail.
    private func part(
        _ section: String,
        type: String = "image/png",
        data: Data? = Data([1, 2, 3]),
        contentID: String? = nil,
        isInline: Bool = false
    ) -> CachedAttachment {
        CachedAttachment(
            id: "mail-\(section)", messageID: "mail", filename: "datei-\(section)",
            contentType: type, sizeBytes: data?.count ?? 0, data: data,
            contentID: contentID, isInline: isInline
        )
    }

    /// Klammern, Leerraum, Prozent-Kodierung und Großschreibung spielen keine Rolle.
    @Test func normalizesContentIDs() {
        #expect(InlineImages.normalizedContentID(" <Logo@Example.org> ") == "logo@example.org")
        #expect(InlineImages.normalizedContentID("logo%40example.org") == "logo@example.org")
        #expect(InlineImages.storedContentID("<Logo@Example.org>") == "Logo@Example.org")
        #expect(InlineImages.storedContentID("<>") == nil)
        #expect(InlineImages.storedContentID(nil) == nil)
    }

    /// Verweise in src, CSS und mit unterschiedlichen Anführungszeichen werden gefunden.
    @Test func findsReferencedContentIDs() {
        let html = #"<img src="cid:a@x"><img src='CID:B@x'><td style="background:url(cid:c@x)">"#
        #expect(InlineImages.referencedContentIDs(in: html) == ["a@x", "b@x", "c@x"])
        #expect(InlineImages.referencedContentIDs(in: nil).isEmpty)
    }

    /// Angesprochene Bilder verschwinden aus der Anhangliste, nicht angesprochene bleiben.
    @Test func visibleAttachmentsHideReferencedImages() {
        let attachments = [
            part("2", type: "application/pdf"),
            part("3", contentID: "logo@x", isInline: true),
            part("4", contentID: "foto@x", isInline: true)
        ]
        let visible = InlineImages.visibleAttachments(attachments, html: #"<img src="cid:logo@x">"#)
        #expect(visible.map(\.id) == ["mail-2", "mail-4"])
        #expect(InlineImages.referencedImages(attachments, html: #"<img src="cid:logo@x">"#).map(\.id) == ["mail-3"])
    }

    /// Fehlend: Bild ohne Daten oder Verweis ohne Eintrag; vollständig geladen: nichts fehlt.
    @Test func detectsMissingImages() {
        let html = #"<img src="cid:logo@x">"#
        #expect(InlineImages.hasMissingImages([], html: html))
        #expect(InlineImages.hasMissingImages([part("2", data: nil, contentID: "logo@x", isInline: true)], html: html))
        #expect(!InlineImages.hasMissingImages([part("2", contentID: "<logo@x>", isInline: true)], html: html))
        #expect(!InlineImages.hasMissingImages([], html: "<p>ohne Bilder</p>"))
    }

    /// Bilder werden als data:-Adresse eingesetzt, unbekannte Verweise und Nicht-Bilder bleiben.
    @Test func resolvesOnlyKnownImages() {
        let html = #"<img src="cid:logo@x"><img src="cid:fehlt@x"><img src="cid:text@x">"#
        let resolved = InlineImages.resolve(html, images: [
            part("2", type: "image/png; name=logo.png", contentID: "<logo@x>", isInline: true),
            part("3", type: "text/html", contentID: "text@x", isInline: true)
        ])
        #expect(resolved.contains(#"src="data:image/png;base64,AQID""#))
        #expect(resolved.contains("cid:fehlt@x"))
        #expect(resolved.contains("cid:text@x"))
        #expect(!resolved.contains("cid:logo@x"))
    }

    /// Echte Anhänge werden nie eingesetzt, auch wenn ihre Content-ID passt.
    @Test func ignoresRegularAttachments() {
        let html = #"<img src="cid:logo@x">"#
        #expect(InlineImages.resolve(html, images: [part("2", contentID: "logo@x", isInline: false)]) == html)
    }
}
