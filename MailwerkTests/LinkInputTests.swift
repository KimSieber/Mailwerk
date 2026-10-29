//
//  LinkInputTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Prüfung eingegebener Link-Adressen (LinkInput).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für LinkInput.
struct LinkInputTests {

    /// Web-Adresse ohne Schema erhält https://.
    @Test("Web-Adresse ohne Schema erhält https://")
    func webWithoutScheme() {
        #expect(LinkInput.normalize("www.beispiel.de") == "https://www.beispiel.de")
        #expect(LinkInput.normalize("  beispiel.de/kontakt ") == "https://beispiel.de/kontakt")
    }

    /// Vollständige Adressen bleiben unverändert.
    @Test("Vollständige Adressen bleiben unverändert")
    func fullAddresses() {
        #expect(LinkInput.normalize("http://beispiel.de") == "http://beispiel.de")
        #expect(LinkInput.normalize("https://beispiel.de/a?b=1") == "https://beispiel.de/a?b=1")
        #expect(LinkInput.normalize("mailto:name@beispiel.de") == "mailto:name@beispiel.de")
    }

    /// E-Mail-Adresse erhält mailto:.
    @Test("E-Mail-Adresse erhält mailto:")
    func email() {
        #expect(LinkInput.normalize("name@beispiel.de") == "mailto:name@beispiel.de")
    }

    /// Ungültige Eingaben und fremde Schemata werden abgelehnt.
    @Test("Ungültiges und fremde Schemata werden abgelehnt")
    func invalid() {
        #expect(LinkInput.normalize("") == nil)
        #expect(LinkInput.normalize("kein link") == nil)
        #expect(LinkInput.normalize("javascript:alert(1)") == nil)
        #expect(LinkInput.normalize("file:///etc/passwd") == nil)
        #expect(LinkInput.normalize("name@beispiel") == nil)
        #expect(LinkInput.normalize("beispiel") == nil)
    }

    /// Anzeigetext lässt mailto: weg.
    @Test("Anzeigetext lässt mailto: weg")
    func display() {
        #expect(LinkInput.displayText(for: "mailto:a@b.de") == "a@b.de")
        #expect(LinkInput.displayText(for: "https://b.de") == "https://b.de")
    }
}
