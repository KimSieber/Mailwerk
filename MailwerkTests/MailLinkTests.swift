//
//  MailLinkTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Behandlung getippter Links in HTML-Mails und das
//  Zerlegen von mailto:-Links.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für MailLinkAction und MailtoLink.
@MainActor
struct MailLinkTests {

    /// Testhilfe: Aktion für einen Link als Text.
    private func action(_ string: String) -> MailLinkAction {
        MailLinkAction(url: URL(string: string)!)
    }

    // MARK: - Einordnung

    /// Web-Links öffnen extern.
    @Test func webLinksOpenExternally() {
        #expect(action("https://example.org/a") == .openExternally(URL(string: "https://example.org/a")!))
        #expect(action("http://example.org") == .openExternally(URL(string: "http://example.org")!))
    }

    /// Telefon-Links öffnen extern.
    @Test func phoneLinksOpenExternally() {
        #expect(action("tel:+49711123") == .openExternally(URL(string: "tel:+49711123")!))
    }

    /// Das Schema wird ohne Groß-/Kleinschreibung erkannt.
    @Test func schemeIsCaseInsensitive() {
        #expect(action("HTTPS://example.org") == .openExternally(URL(string: "HTTPS://example.org")!))
    }

    /// Gefährliche Schemata werden nicht geöffnet.
    @Test func dangerousSchemesAreIgnored() {
        #expect(action("javascript:alert(1)") == .ignore)
        #expect(action("file:///etc/passwd") == .ignore)
        #expect(action("data:text/html,hi") == .ignore)
    }

    /// mailto: öffnet eine neue Mail.
    @Test func mailtoOpensCompose() {
        guard case .compose(let link) = action("mailto:kim@example.org") else {
            Issue.record("mailto nicht erkannt"); return
        }
        #expect(link.to == ["kim@example.org"])
    }

    /// Ein leerer mailto:-Link wird übergangen.
    @Test func emptyMailtoIsIgnored() {
        #expect(action("mailto:") == .ignore)
    }

    // MARK: - mailto zerlegen

    /// mailto: mit mehreren Empfängern.
    @Test func mailtoWithSeveralRecipients() {
        let link = MailtoLink(url: URL(string: "mailto:a@x.de,b@x.de")!)
        #expect(link?.to == ["a@x.de", "b@x.de"])
    }

    /// mailto: mit An, Cc, Bcc, Betreff und Text.
    @Test func mailtoWithAllFields() {
        let link = MailtoLink(url: URL(string:
            "mailto:a@x.de?cc=c@x.de&bcc=d@x.de&subject=Hallo%20Welt&body=Zeile%201%0AZeile%202")!)
        #expect(link?.to == ["a@x.de"])
        #expect(link?.cc == ["c@x.de"])
        #expect(link?.bcc == ["d@x.de"])
        #expect(link?.subject == "Hallo Welt")
        #expect(link?.body == "Zeile 1\nZeile 2")
    }

    /// Das Feld `to` ergänzt die Empfänger aus dem Pfad.
    @Test func mailtoToFieldIsAddedToPath() {
        let link = MailtoLink(url: URL(string: "mailto:a@x.de?to=b@x.de")!)
        #expect(link?.to == ["a@x.de", "b@x.de"])
    }

    /// Feldnamen werden ohne Groß-/Kleinschreibung erkannt.
    @Test func mailtoKeysAreCaseInsensitive() {
        let link = MailtoLink(url: URL(string: "mailto:a@x.de?Subject=Test")!)
        #expect(link?.subject == "Test")
    }

    /// Ein „+“ bleibt ein Pluszeichen.
    @Test func mailtoPlusStaysPlus() {
        let link = MailtoLink(url: URL(string: "mailto:kim+news@x.de")!)
        #expect(link?.to == ["kim+news@x.de"])
    }

    /// Eine prozentkodierte Adresse wird dekodiert.
    @Test func mailtoEncodedAddress() {
        let link = MailtoLink(url: URL(string: "mailto:kim%40x.de")!)
        #expect(link?.to == ["kim@x.de"])
    }

    /// Ein mailto:-Link nur mit Betreff ist gültig.
    @Test func mailtoOnlySubjectIsValid() {
        let link = MailtoLink(url: URL(string: "mailto:?subject=Nur%20Betreff")!)
        #expect(link?.to == [])
        #expect(link?.subject == "Nur Betreff")
    }

    /// Unbekannte Felder werden übergangen.
    @Test func unknownFieldsAreIgnored() {
        let link = MailtoLink(url: URL(string: "mailto:a@x.de?x-foo=bar")!)
        #expect(link?.to == ["a@x.de"])
        #expect(link?.subject == nil)
    }
}
