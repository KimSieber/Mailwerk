//
//  SignatureComposeTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Einsetzen und Austauschen der einfachen Signatur
//  im Mailtext (SignatureEditing.replacingSignature, markedSignature) und
//  für das Zerlegen beim Entwurf (split).
//

import Foundation
import Testing
@testable import Mailwerk

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Tests für das Einsetzen der Signatur beim Verfassen.
@MainActor
struct SignatureComposeTests {

    /// Testhilfe: Text mit Standardformat.
    private func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: RichTextController.defaultAttributes)
    }

    /// Testhilfe: markierte Signatur aus Text.
    private func signature(_ text: String) -> NSAttributedString {
        SignatureEditing.markedSignature(html: "<p>\(text)</p>", logoData: nil)
    }

    /// Leerer Text: oben schreiben, Leerzeile, dann die Signatur.
    @Test("Leerer Text: zwei Leerzeilen, dann die Signatur")
    func emptyBody() {
        let result = SignatureEditing.replacingSignature(signature("Gruß Max"), in: plain(""))
        #expect(result.text.string == "\n\nGruß Max")
        #expect(!result.hadSignature)
    }

    /// Vorhandener Text: Signatur nach einer Leerzeile angefügt.
    @Test("Vorhandener Text: Signatur nach Leerzeile")
    func existingText() {
        let result = SignatureEditing.replacingSignature(signature("Gruß Max"), in: plain("Hallo"))
        #expect(result.text.string == "Hallo\n\nGruß Max")
    }

    /// Wechsel: die alte Signatur wird ersetzt, auch wenn sie geändert wurde.
    @Test("Wechsel: geänderte Signatur wird ersetzt, eigener Text bleibt")
    func replaceEdited() {
        let first = SignatureEditing.replacingSignature(signature("Gruß Max"), in: plain("Hallo")).text
        let edited = NSMutableAttributedString(attributedString: first)
        let range = (edited.string as NSString).range(of: "Max")
        edited.replaceCharacters(in: range, with: NSAttributedString(
            string: "Maximilian",
            attributes: edited.attributes(at: range.location, effectiveRange: nil)
        ))
        let result = SignatureEditing.replacingSignature(signature("Viele Grüße, Team"), in: edited)
        #expect(result.hadSignature)
        #expect(result.text.string == "Hallo\n\nViele Grüße, Team")
    }

    /// Zerlegen für Entwürfe: Text davor, Signatur, Text danach.
    @Test("Zerlegen an der Signatur: davor, Signatur, danach")
    func splitAtSignature() {
        let body = NSMutableAttributedString(
            attributedString: SignatureEditing.replacingSignature(signature("Gruß"), in: plain("Hallo")).text
        )
        body.append(plain("\nPS"))
        let split = SignatureEditing.split(body)
        #expect(split.before.string == "Hallo\n\n")
        #expect(split.signature?.string == "Gruß")
        #expect(split.after.string == "\nPS")

        let none = SignatureEditing.split(plain("Nur Text"))
        #expect(none.signature == nil)
        #expect(none.before.string == "Nur Text")
    }

    /// Ohne neue Signatur wird die alte entfernt; ohne Markierung bleibt alles.
    @Test("Entfernen und unmarkierter Text")
    func removeAndUnmarked() {
        let withSignature = SignatureEditing.replacingSignature(signature("Gruß"), in: plain("Hallo")).text
        let removed = SignatureEditing.replacingSignature(nil, in: withSignature)
        #expect(removed.hadSignature)
        #expect(removed.text.string == "Hallo\n\n")

        let untouched = SignatureEditing.replacingSignature(nil, in: plain("Hallo"))
        #expect(!untouched.hadSignature)
        #expect(untouched.text.string == "Hallo")
    }
}
