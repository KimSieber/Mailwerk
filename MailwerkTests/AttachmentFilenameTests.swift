//
//  AttachmentFilenameTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Endung von Anhängen ohne Dateiendung
//  (AttachmentFilename) – angehängt nur, wenn eine bekannte fehlt und der
//  Typ eine kennt.
//

import Foundation
import Testing
@testable import Mailwerk

struct AttachmentFilenameTests {

    /// Fehlende Endung: Die zum Typ passende wird angehängt.
    @Test func appendsExtensionFromType() {
        #expect(AttachmentFilename.completed("Kundendokumente", contentType: "application/pdf") == "Kundendokumente.pdf")
    }

    /// Typangabe mit Parametern und in anderer Schreibweise.
    @Test func readsTypeWithParameters() {
        #expect(AttachmentFilename.completed("Beleg", contentType: "application/pdf; name=\"Beleg\"") == "Beleg.pdf")
        #expect(AttachmentFilename.completed("Beleg", contentType: "Application/PDF") == "Beleg.pdf")
    }

    /// Bekannte Endung bleibt – auch in Großbuchstaben und auch, wenn sie
    /// nicht zum Typ passt.
    @Test func keepsKnownExtension() {
        #expect(AttachmentFilename.completed("Rechnung.pdf", contentType: "application/pdf") == "Rechnung.pdf")
        #expect(AttachmentFilename.completed("Scan.PDF", contentType: "application/pdf") == "Scan.PDF")
        #expect(AttachmentFilename.completed("Foto.jpg", contentType: "application/pdf") == "Foto.jpg")
    }

    /// Ein Punkt im Namen ist noch keine Endung.
    @Test func unknownSuffixGetsExtension() {
        #expect(AttachmentFilename.completed("Rechnung 2026.10", contentType: "application/pdf") == "Rechnung 2026.10.pdf")
    }

    /// Ohne bekannte Endung zum Typ bleibt der Name unverändert.
    @Test func unknownTypeKeepsName() {
        #expect(AttachmentFilename.completed("Datei", contentType: "application/x-mailwerk-unbekannt") == "Datei")
        #expect(AttachmentFilename.completed("Datei", contentType: "") == "Datei")
    }
}
