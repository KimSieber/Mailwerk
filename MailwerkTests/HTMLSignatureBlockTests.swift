//
//  HTMLSignatureBlockTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die HTML-Signatur beim Verfassen (HTMLSignatureBlock).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für HTMLSignatureBlock.
@MainActor
struct HTMLSignatureBlockTests {

    /// Testhilfe: HTML-Signatur mit oder ohne Logo.
    private func signature(_ html: String, logo: Data? = Data([1, 2, 3])) -> SignatureItem {
        SignatureItem(
            accountID: UUID(), kind: .html, html: html,
            logoData: logo, logoMimeType: logo == nil ? nil : "image/png", modifiedAt: Date()
        )
    }

    /// Anzeige mit data:, Versand mit cid: und Logo als Inline-Teil.
    @Test("Logo: Anzeige als data:, Versand als cid: mit Inline-Teil")
    func logoForDisplayAndSending() throws {
        let block = HTMLSignatureBlock(signature: signature("<td><img src=\"logo\" width=\"120\">Max</td>"))
        let logo = try #require(block.logoAttachment)
        let contentID = try #require(logo.contentID)

        #expect(block.displayHTML.contains("src=\"data:image/png;base64,AQID\""))
        #expect(block.sendHTML == "<td><img src=\"cid:\(contentID)\" width=\"120\">Max</td>")
        #expect(block.attachments == [logo])
    }

    /// Geänderter Text bleibt, ein gelöschtes Logo geht nicht mehr mit.
    @Test("Änderungen: Text bleibt, gelöschtes Logo entfällt als Anhang")
    func edits() {
        var block = HTMLSignatureBlock(signature: signature("<p>Max</p><img src=\"logo\">"))
        block.editedHTML = "<p>Max Muster</p>"
        #expect(block.sendHTML == "<p>Max Muster</p>")
        #expect(block.attachments.isEmpty)
        #expect(block.plainText == "Max Muster")
    }

    /// Ohne Platzhalter oder ohne Logo-Daten entsteht kein Inline-Teil.
    @Test("Ohne Platzhalter oder Logo kein Inline-Teil")
    func withoutLogo() {
        #expect(HTMLSignatureBlock(signature: signature("<p>Max</p>")).attachments.isEmpty)
        #expect(HTMLSignatureBlock(signature: signature("<img src=\"logo\">", logo: nil)).attachments.isEmpty)
    }
}
