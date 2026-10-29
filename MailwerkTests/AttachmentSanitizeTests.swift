//
//  AttachmentSanitizeTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Dateinamen-Bereinigung in AttachmentManager.
//  Sichert ab, dass Pfadtrennzeichen und versteckte Dateien nicht
//  aus dem Temp-Verzeichnis ausbrechen können (K3).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct AttachmentSanitizeTests {

    /// Normaler Dateiname bleibt unverändert.
    @Test func normalFilenameIsUnchanged() {
        #expect(AttachmentManager.sanitizedFilename("Rechnung.pdf") == "Rechnung.pdf")
    }

    /// Pfad-Traversal mit „../" wird auf den letzten Bestandteil reduziert.
    @Test func pathTraversalIsStripped() {
        #expect(AttachmentManager.sanitizedFilename("../../Library/Caches/payload") == "payload")
    }

    /// Absoluter Unix-Pfad wird auf den letzten Bestandteil reduziert.
    @Test func absolutePathIsStripped() {
        #expect(AttachmentManager.sanitizedFilename("/etc/passwd") == "passwd")
    }

    /// Backslash-Pfade (Windows) werden ebenfalls behandelt.
    @Test func backslashPathIsStripped() {
        #expect(AttachmentManager.sanitizedFilename("C:\\Users\\evil\\payload.exe") == "payload.exe")
    }

    /// Führende Punkte werden entfernt (keine versteckten Dateien).
    @Test func leadingDotsAreRemoved() {
        #expect(AttachmentManager.sanitizedFilename(".hidden") == "hidden")
        #expect(AttachmentManager.sanitizedFilename("..htaccess") == "htaccess")
    }

    /// Leerer Name ergibt „Anhang".
    @Test func emptyNameBecomesFallback() {
        #expect(AttachmentManager.sanitizedFilename("") == "Anhang")
    }

    /// Nur Punkte und Pfadtrennzeichen ergibt „Anhang".
    @Test func onlyDotsAndSlashesBecomesFallback() {
        #expect(AttachmentManager.sanitizedFilename("../../..") == "Anhang")
    }

    /// Dateiname mit Leerzeichen bleibt erhalten.
    @Test func filenameWithSpacesIsKept() {
        #expect(AttachmentManager.sanitizedFilename("Mein Dokument (2).pdf") == "Mein Dokument (2).pdf")
    }

    /// Unicode-Dateinamen bleiben erhalten.
    @Test func unicodeFilenameIsKept() {
        #expect(AttachmentManager.sanitizedFilename("Ölwechsel-Rechnung.pdf") == "Ölwechsel-Rechnung.pdf")
    }
}
