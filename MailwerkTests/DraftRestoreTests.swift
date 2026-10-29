//
//  DraftRestoreTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Weiterbearbeiten eines Entwurfs – Zitat-Text aus
//  dem Textteil (DraftFormat.quotedText), Art und Bezug zur Originalmail
//  aus dem Datenblock (ComposeViewModel) und HTML-Signatur mit Logo aus
//  dem Entwurf (HTMLSignatureBlock).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests zum Wiederherstellen eines Entwurfs.
@MainActor
struct DraftRestoreTests {

    /// Der Rest hinter eigenem Text und Leerzeile ist das Zitat – auch mit CRLF vom Server.
    @Test func quotedTextFollowsOwnText() {
        let own = "Hallo\n\nKim"
        #expect(DraftFormat.quotedText(draftText: "Hallo\n\nKim\n\n> Frage?", ownText: own) == "> Frage?")
        #expect(DraftFormat.quotedText(draftText: "Hallo\r\n\r\nKim\r\n\r\n> Frage?", ownText: own) == "> Frage?")
    }

    /// Passt der Anfang nicht oder fehlt das Zitat, gibt es kein Ergebnis.
    @Test func quotedTextNeedsMatchingStart() {
        #expect(DraftFormat.quotedText(draftText: "Anderer Text\n\n> Frage?", ownText: "Hallo") == nil)
        #expect(DraftFormat.quotedText(draftText: "Hallo\n\n  ", ownText: "Hallo") == nil)
        #expect(DraftFormat.quotedText(draftText: nil, ownText: "Hallo") == nil)
    }

    /// Art und Bezug aus dem Datenblock ergeben die Markierung nach dem Versand.
    @Test func originFromDraftMetadata() throws {
        let draftOrigin = DraftMetadata.Origin(cachedMessageID: "a-INBOX-7", accountID: UUID(), folder: "INBOX", uid: 7)
        for kind in [DraftMetadata.Kind.new, .reply, .replyAll, .forward] {
            #expect(ComposeViewModel.draftKind(ComposeViewModel.composeKind(kind)) == kind)
        }
        let replied = try #require(ComposeViewModel.origin(kind: .reply, draft: draftOrigin))
        #expect(replied.kind == .replied)
        #expect(replied.folder == "INBOX" && replied.uid == 7 && replied.cachedMessageID == "a-INBOX-7")
        #expect(ComposeViewModel.origin(kind: .forward, draft: draftOrigin)?.kind == .forwarded)
        #expect(ComposeViewModel.origin(kind: .new, draft: draftOrigin) == nil)
        #expect(ComposeViewModel.origin(kind: .reply, draft: nil) == nil)
    }

    /// Das Logo einer HTML-Signatur kommt aus dem Entwurf zurück und behält seine Content-ID.
    @Test func htmlSignatureLogoFromDraft() {
        let logo = CachedAttachment(
            id: "m-2", messageID: "m", filename: "logo.png", contentType: "image/png",
            sizeBytes: 3, data: Data([1, 2, 3]), contentID: "logo-1@mailwerk", isInline: true
        )
        let block = HTMLSignatureBlock(restoredHTML: "<td><img src=\"cid:logo-1@mailwerk\">Max</td>", images: [logo])
        #expect(block.displayHTML.contains("src=\"data:image/png;base64,AQID\""))
        #expect(block.sendHTML == "<td><img src=\"cid:logo-1@mailwerk\">Max</td>")
        #expect(block.attachments.first?.contentID == "logo-1@mailwerk")

        let plain = HTMLSignatureBlock(restoredHTML: "<p>Max</p>", images: [logo])
        #expect(plain.logoAttachment == nil && plain.displayHTML == "<p>Max</p>")
    }
}
