//
//  MessageOpenPreparationTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Aufbereitung beim Öffnen einer Mail
//  (MessageOpenPreparation.content, Prüfbericht P-11): eingesetzte
//  eingebettete Bilder, sichtbare Anhänge, Mail ohne HTML.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für MessageOpenPreparation.
@MainActor
struct MessageOpenPreparationTests {

    // MARK: - Hilfen

    /// Testhilfe: Mail mit Text- und/oder HTML-Teil.
    private func message(text: String? = nil, html: String? = nil) -> CachedMessage {
        CachedMessage(
            id: "a-INBOX-1", accountID: UUID(), accountDisplayName: "Test", folder: "INBOX", uid: 1,
            subject: "Hallo", from: "anna@example.org", to: "max@example.org", date: nil,
            isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
            totalSizeBytes: 1_024, hasAttachments: true, textBody: text, htmlBody: html,
            fetchedAt: Date(), headers: CachedMessageHeaders()
        )
    }

    /// Testhilfe: eingebettetes Bild mit Content-ID.
    private func inlineImage(_ contentID: String, data: Data? = Data([0x89, 0x50])) -> CachedAttachment {
        CachedAttachment(
            id: "a-INBOX-1-\(contentID)", messageID: "a-INBOX-1", filename: "\(contentID).png",
            contentType: "image/png", sizeBytes: 2, data: data, contentID: contentID, isInline: true
        )
    }

    /// Testhilfe: gewöhnlicher Anhang.
    private func fileAttachment(_ name: String) -> CachedAttachment {
        CachedAttachment(
            id: "a-INBOX-1-\(name)", messageID: "a-INBOX-1", filename: name,
            contentType: "application/pdf", sizeBytes: 10, data: Data([1, 2, 3])
        )
    }

    // MARK: - Tests

    /// Ein angesprochenes Bild wird eingesetzt und erscheint nicht in der Anhangliste.
    @Test("Angesprochenes Bild wird eingesetzt und nicht als Anhang gezeigt")
    func resolvesReferencedImage() {
        let mail = message(html: #"<p>Hi</p><img src="cid:logo1">"#)
        let pdf = fileAttachment("Rechnung.pdf")
        let content = MessageOpenPreparation.content(for: mail, attachments: [inlineImage("logo1"), pdf])
        #expect(content.resolvedHTML?.contains("data:image/png;base64,") == true)
        #expect(content.resolvedHTML?.contains("cid:logo1") == false)
        #expect(content.visibleAttachments.map(\.id) == [pdf.id])
        #expect(content.attachments.count == 2)
    }

    /// Ein nicht angesprochenes Inline-Bild bleibt als Anhang sichtbar.
    @Test("Nicht angesprochenes Inline-Bild bleibt in der Anhangliste")
    func keepsUnreferencedInlineImage() {
        let mail = message(html: "<p>Ohne Bild</p>")
        let image = inlineImage("foto")
        let content = MessageOpenPreparation.content(for: mail, attachments: [image])
        #expect(content.visibleAttachments.map(\.id) == [image.id])
    }

    /// Mail ohne HTML: kein aufbereitetes HTML, Anhänge unverändert sichtbar.
    @Test("Mail ohne HTML: kein HTML, alle Anhänge sichtbar")
    func textOnlyMail() {
        let mail = message(text: "Nur Text")
        let pdf = fileAttachment("Plan.pdf")
        let content = MessageOpenPreparation.content(for: mail, attachments: [pdf])
        #expect(content.resolvedHTML == nil)
        #expect(content.visibleAttachments.map(\.id) == [pdf.id])
    }

    /// Ohne Anhänge bleibt das HTML unverändert.
    @Test("Ohne Anhänge bleibt das HTML unverändert")
    func htmlWithoutAttachments() {
        let html = "<p>Hallo</p>"
        let content = MessageOpenPreparation.content(for: message(html: html), attachments: [])
        #expect(content.resolvedHTML == html)
        #expect(content.visibleAttachments.isEmpty)
    }
}
