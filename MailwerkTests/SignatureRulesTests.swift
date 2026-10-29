//
//  SignatureRulesTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Regeln rund um Signaturen (SignatureRules,
//  SignatureItem).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für SignatureRules.
struct SignatureRulesTests {

    /// Testhilfe: Signatur mit Zeitpunkt.
    private func item(_ account: UUID, html: String = "<p>Gruß</p>", at seconds: TimeInterval) -> SignatureItem {
        SignatureItem(
            accountID: account, kind: .simple, html: html,
            logoData: nil, logoMimeType: nil,
            modifiedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    /// Bei mehreren Datensätzen je Postfach gilt der neueste.
    @Test("Je Postfach gilt der neueste Datensatz")
    func newestPerAccount() {
        let a = UUID(), b = UUID()
        let result = SignatureRules.byAccount([
            item(a, html: "<p>alt</p>", at: 10),
            item(a, html: "<p>neu</p>", at: 20),
            item(b, at: 5)
        ])
        #expect(result.count == 2)
        #expect(result[a]?.html == "<p>neu</p>")
    }

    /// Der Platzhalter wird in allen Schreibweisen erkannt und ersetzt.
    @Test("Logo-Platzhalter: erkennen und ersetzen")
    func placeholder() {
        #expect(SignatureRules.containsLogo("<img src=\"logo\">"))
        #expect(SignatureRules.containsLogo("<IMG width=150 SRC='logo'>"))
        #expect(SignatureRules.containsLogo("<img src=logo>"))
        #expect(!SignatureRules.containsLogo("<img src=\"logo.png\">"))
        #expect(!SignatureRules.containsLogo("<p>Mein logo</p>"))

        let html = "<p>A</p><img src=\"logo\" width=\"150\"><img src=logo>"
        let replaced = SignatureRules.replacingLogo(in: html, with: "cid:x@mailwerk")
        #expect(replaced == "<p>A</p><img src=\"cid:x@mailwerk\" width=\"150\"><img src=\"cid:x@mailwerk\">")
    }

    /// Eine Signatur ohne Text und ohne Logo gilt als leer.
    @Test("Leere Signatur wird erkannt")
    func emptySignature() {
        let account = UUID()
        #expect(item(account, html: "<p><br></p>", at: 0).isEmpty)
        #expect(item(account, html: "  ", at: 0).isEmpty)
        #expect(!item(account, html: "<p>Gruß</p>", at: 0).isEmpty)
        var withLogo = item(account, html: "", at: 0)
        withLogo.logoData = Data([1])
        #expect(!withLogo.isEmpty)
    }

    /// Nur-Text einer HTML-Signatur: Zeilen ohne Bilder und Tabellen-Markup.
    @Test("Nur-Text einer HTML-Signatur")
    func plainText() {
        let html = "<table><tr><td><img src=\"logo\"></td><td><b>Max Muster</b><br>Tel. 0711 123</td></tr></table>"
        #expect(SignatureRules.plainText(fromHTML: html) == "Max Muster\nTel. 0711 123")
    }

    /// Erzeugtes HTML wird nach Absätzen und Listen umbrochen.
    @Test("Lesbarer Code: Umbruch nach Absätzen und Listen")
    func readable() {
        #expect(SignatureRules.readableHTML("<p>A</p><ul><li>B</li></ul><p>C</p>") == "<p>A</p>\n<ul><li>B</li></ul>\n<p>C</p>")
    }
}
