//
//  DraftFormatTests.swift
//  MailwerkTests
//
//  Zweck: Tests für Aufbau und Zerlegung des Entwurfs-HTML (DraftFormat).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für DraftFormat.
struct DraftFormatTests {

    /// Testhilfe: Entwurf einer Antwort mit allen Teilen.
    private func replyParts() -> DraftParts {
        DraftParts(
            metadata: DraftMetadata(
                kind: .reply,
                bcc: ["Max <max@beispiel.de>"],
                origin: .init(cachedMessageID: "a-INBOX-7", accountID: UUID(), folder: "INBOX", uid: 7),
                inReplyTo: "<abc@beispiel.de>",
                references: "<abc@beispiel.de>",
                signature: .html
            ),
            textBefore: "<p>Hallo</p><p><br></p>",
            signature: "<table><tr><td>Max</td></tr></table>",
            textAfter: "",
            quote: "<blockquote><p>Frage?</p></blockquote>"
        )
    }

    /// Hin- und Rückweg ergeben dieselben Teile.
    @Test("Hin- und Rückweg: alle Teile und Daten bleiben gleich")
    func roundTrip() {
        let parts = replyParts()
        #expect(DraftFormat.parse(DraftFormat.html(parts)) == parts)
    }

    /// Die Reihenfolge im HTML entspricht der gesendeten Mail.
    @Test("Reihenfolge: Text, Signatur, Text danach, Zitat")
    func order() throws {
        let html = DraftFormat.html(replyParts())
        let text = try #require(html.range(of: "Hallo"))
        let signature = try #require(html.range(of: "<table>"))
        let quote = try #require(html.range(of: "Frage?"))
        #expect(text.lowerBound < signature.lowerBound)
        #expect(signature.lowerBound < quote.lowerBound)
    }

    /// Neue Mail ohne Signatur und Zitat.
    @Test("Neue Mail ohne Signatur und Zitat")
    func simpleNewMail() {
        let parts = DraftParts(
            metadata: DraftMetadata(kind: .new),
            textBefore: "<p>Notiz</p>", signature: nil, textAfter: "", quote: nil
        )
        let parsed = DraftFormat.parse(DraftFormat.html(parts))
        #expect(parsed == parts)
        #expect(parsed?.metadata.origin == nil)
    }

    /// Fremde Entwürfe (ohne Datenblock) werden nicht zerlegt.
    @Test("Fremder Entwurf ohne Datenblock ergibt nil")
    func foreignDraft() {
        #expect(DraftFormat.parse("<p>Im Webmail geschrieben</p>") == nil)
        #expect(DraftFormat.parse("<!--mailwerk-entwurf:daten kaputt-->") == nil)
    }
}
