//
//  WatchSnapshotBuilderTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Aufbau der Lieferungen an die Apple Watch
//  (WatchSnapshotBuilder) – aufbereiteter Mailkopf, Absenderbild
//  (Kontaktbild vor Logo, Freemail ohne Logo), Begrenzung des Inhalts,
//  Anhänge ohne eingebettete Bilder.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct WatchSnapshotBuilderTests {

    /// Testhilfe: Listeneintrag.
    private func item(from: String = "Anna Muster <Anna@News.Example.com>") -> MessageListItem {
        MessageListItem(
            id: "a-INBOX-1", accountID: UUID(), folder: "INBOX", uid: 1,
            subject: "Hallo", from: from, recipients: ["max@example.org"],
            date: Date(timeIntervalSince1970: 1_000), isUnread: true, isFlagged: false,
            isAnswered: false, isForwarded: false, hasAttachments: true, sizeBytes: 2_048,
            spamVerdict: SpamHeaderVerdict(isSpam: false, score: 2.5)
        )
    }

    /// Testhilfe: vollständige Mail.
    private func message(html: String?, text: String?) -> CachedMessage {
        var headers = CachedMessageHeaders()
        headers.ccList = ["Erika <erika@example.org>"]
        return CachedMessage(
            id: "a-INBOX-1", accountID: UUID(), accountDisplayName: "Test", folder: "INBOX", uid: 1,
            subject: "Hallo", from: "anna@example.org", to: "max@example.org", date: nil,
            isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
            totalSizeBytes: 1_024, hasAttachments: true, textBody: text, htmlBody: html,
            fetchedAt: Date(), headers: headers
        )
    }

    /// Der Kopf kommt fertig aufbereitet: Name, Adresse, Initialen,
    /// Absender für die Filterlisten in Kleinschreibung.
    @Test func mailCarriesPreparedHeader() {
        let mail = WatchSnapshotBuilder.mail(from: item(), box: .inbox, colorHex: "#378ADD", avatarKey: nil)
        #expect(mail.senderTitle == "Anna Muster")
        #expect(mail.senderAddress == "Anna@News.Example.com")
        #expect(mail.filterAddress == "anna@news.example.com")
        #expect(mail.initials == "AM")
        #expect(mail.accountColorHex == "#378ADD")
        #expect(mail.verdict == WatchVerdict(SpamHeaderVerdict(isSpam: false, score: 2.5)))
        #expect(mail.hasAttachments)
        #expect(mail.sender?.domain == "news.example.com")
    }

    /// Kontaktbild vor Logo; ohne beides kein Bild.
    @Test func avatarKeyPrefersContactImage() {
        let address = "Anna@Firma.de"
        #expect(WatchSnapshotBuilder.avatarKey(forAddress: address, hasContactImage: { _ in true }, hasLogo: { _ in true })
                == "contact:anna@firma.de")
        #expect(WatchSnapshotBuilder.avatarKey(forAddress: address, hasContactImage: { _ in false }, hasLogo: { _ in true })
                == "logo:firma.de")
        #expect(WatchSnapshotBuilder.avatarKey(forAddress: address, hasContactImage: { _ in false }, hasLogo: { _ in false }) == nil)
        #expect(WatchSnapshotBuilder.avatarKey(forAddress: nil, hasContactImage: { _ in true }, hasLogo: { _ in true }) == nil)
    }

    /// Freemail-Adressen bekommen kein Logo.
    @Test func freemailGetsNoLogo() {
        #expect(WatchSnapshotBuilder.avatarKey(forAddress: "x@gmail.com", hasContactImage: { _ in false }, hasLogo: { _ in true }) == nil)
    }

    /// Zu großes HTML entfällt, der Text bleibt; Kopie-Empfänger kommen mit.
    @Test func oversizedHTMLIsDropped() {
        let html = String(repeating: "a", count: WatchSnapshotBuilder.maxHTMLBytes + 1)
        let body = WatchSnapshotBuilder.body(from: message(html: html, text: "Text"), attachments: [])
        #expect(body.html == nil)
        #expect(body.text == "Text")
        #expect(body.cc == ["Erika <erika@example.org>"])
    }

    /// Anhänge nur als Name und Größe; eingebettete Bilder des HTML fehlen.
    @Test func attachmentsWithoutInlineImages() {
        let html = #"<p>Logo <img src="cid:logo1"></p>"#
        let attachments = [
            CachedAttachment(id: "a-1", messageID: "a-INBOX-1", filename: "Plan.pdf", contentType: "application/pdf",
                             sizeBytes: 4_096, data: nil),
            CachedAttachment(id: "a-2", messageID: "a-INBOX-1", filename: "logo.png", contentType: "image/png",
                             sizeBytes: 512, data: nil, contentID: "logo1", isInline: true)
        ]
        let body = WatchSnapshotBuilder.body(from: message(html: html, text: nil), attachments: attachments)
        #expect(body.html == html)
        #expect(body.attachments == [WatchAttachment(name: "Plan.pdf", sizeBytes: 4_096)])
    }

    /// Kürzen auf eine Byte-Grenze zerteilt kein Zeichen.
    @Test func truncationKeepsWholeCharacters() {
        #expect(WatchSnapshotBuilder.truncated("Grüße", maxBytes: 3) == "Gr…")
        #expect(WatchSnapshotBuilder.truncated("Grüße", maxBytes: 100) == "Grüße")
    }
}
