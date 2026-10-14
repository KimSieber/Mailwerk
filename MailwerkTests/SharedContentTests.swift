//
//  SharedContentTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Regeln geteilter Inhalte (SharedContent,
//  SharedContentRules): Betreff aus dem Seitentitel, Reihenfolge des
//  Texts, Dateinamen.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für SharedContent und SharedContentRules.
struct SharedContentTests {

    /// Testhilfe: Web-Link.
    private let link = URL(string: "https://www.example.org/artikel")!

    /// Seitentitel wird nur mit Link zum Betreff, getrimmt.
    @Test("Betreff: Seitentitel nur bei geteiltem Link")
    func subjectOnlyWithLink() {
        var content = SharedContent(title: "  Ein Artikel  ")
        #expect(content.subject == nil)
        content.links = [link]
        #expect(content.subject == "Ein Artikel")
    }

    /// Mehrzeilige, leere oder überlange Überschriften sind kein Betreff.
    @Test("Betreff: mehrzeilig, leer oder zu lang → kein Betreff")
    func subjectRejectsOddTitles() {
        #expect(SharedContent(links: [link], title: "Zeile 1\nZeile 2").subject == nil)
        #expect(SharedContent(links: [link], title: "   ").subject == nil)
        #expect(SharedContent(links: [link], title: String(repeating: "x", count: 201)).subject == nil)
    }

    /// Erst Texte, dann Links; leere Texte und Texte gleich einem Link entfallen.
    @Test("Text: Texte vor Links, ohne Leeres und doppelte Links")
    func bodyParts() {
        let content = SharedContent(
            texts: ["  Hallo  ", "", link.absoluteString],
            links: [link]
        )
        #expect(content.bodyParts == [.text("Hallo"), .link(link)])
    }

    /// Leer heißt: weder Anhang noch Text noch Link.
    @Test("Leer: nur ohne Anhang, Text und Link")
    func isEmpty() {
        #expect(SharedContent(title: "Titel").isEmpty)
        #expect(!SharedContent(texts: ["x"]).isEmpty)
        #expect(!SharedContent(attachments: [SharedAttachment(filename: "a", mimeType: "text/plain", data: Data())]).isEmpty)
    }

    /// Endung wird nur ergänzt, wenn der Name noch keine hat.
    @Test("Dateiname: Endung ergänzen, Ersatzname, keine Pfadzeichen")
    func filename() {
        #expect(SharedContentRules.filename(suggested: "IMG_0001", fileExtension: "jpeg", fallback: "Foto") == "IMG_0001.jpeg")
        #expect(SharedContentRules.filename(suggested: "Bericht.pdf", fileExtension: "pdf", fallback: "Dokument") == "Bericht.pdf")
        #expect(SharedContentRules.filename(suggested: nil, fileExtension: "vcf", fallback: "Kontakt") == "Kontakt.vcf")
        #expect(SharedContentRules.filename(suggested: " ", fileExtension: nil, fallback: "Anhang") == "Anhang")
        #expect(SharedContentRules.filename(suggested: "a/b:c", fileExtension: "txt", fallback: "Anhang") == "a-b-c.txt")
    }

    /// Wiederholte Namen bekommen eine laufende Nummer vor der Endung.
    @Test("Dateinamen: gleiche Namen werden nummeriert")
    func uniqueFilenames() {
        let names = SharedContentRules.uniqueFilenames(["Foto.jpeg", "foto.jpeg", "Foto.jpeg", "Kontakt", "Kontakt"])
        #expect(names == ["Foto.jpeg", "foto 2.jpeg", "Foto 3.jpeg", "Kontakt", "Kontakt 2"])
    }
}
