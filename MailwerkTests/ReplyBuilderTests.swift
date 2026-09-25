//
//  ReplyBuilderTests.swift
//  MailwerkTests
//
//  Tests für die Vorbelegung von Antworten, Allen antworten,
//  Weiterleiten und neuen Mails.
//

import Foundation
import Testing
@testable import Mailwerk

/// Läuft auf dem MainActor, da die App-Typen im Projekt standardmäßig
/// MainActor-isoliert sind (Default Actor Isolation).
@MainActor
struct ReplyBuilderTests {

    private let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let defaultAccountID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let ownAddresses: Set<String> = ["kim@ordinum.com", "kim@sieber-bw.de"]

    private func message(
        from: String = "Anna Muster <anna@example.org>",
        to: [String] = ["Kim Sieber <kim@ordinum.com>"],
        cc: [String] = [],
        replyTo: [String] = [],
        subject: String = "Hallo",
        text: String? = "Zeile 1\nZeile 2",
        html: String? = nil,
        messageID: String? = "<orig@example.org>",
        inReplyTo: String? = nil,
        references: String? = nil
    ) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: accountID, folder: "INBOX", uid: 42),
            accountID: accountID,
            accountDisplayName: "Test",
            folder: "INBOX",
            uid: 42,
            subject: subject,
            from: from,
            to: to.joined(separator: ", "),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isUnread: false,
            isFlagged: false,
            isAnswered: false,
            isForwarded: false,
            totalSizeBytes: 0,
            hasAttachments: false,
            textBody: text,
            htmlBody: html,
            fetchedAt: Date(),
            headers: CachedMessageHeaders(
                toList: to,
                ccList: cc,
                replyToList: replyTo,
                rfcMessageID: messageID,
                rfcInReplyTo: inReplyTo,
                rfcReferences: references
            )
        )
    }

    private func prefill(_ kind: ComposeKind, _ original: CachedMessage?) -> ComposePrefill {
        ReplyBuilder.prefill(
            kind: kind,
            original: original,
            defaultAccountID: defaultAccountID,
            ownAddresses: ownAddresses
        )
    }

    // MARK: - Betreff

    @Test("Antwort-Betreff: Präfixe werden zu genau einem Re: zusammengefasst",
          arguments: ["Hallo", "Re: Hallo", "AW: Re: Hallo", "RE[2]: Hallo", "Aw:Hallo", "  re : Hallo"])
    func replySubject(input: String) {
        #expect(ReplyBuilder.replySubject(input) == "Re: Hallo")
    }

    @Test("Weiterleitungs-Betreff",
          arguments: zip(["Hallo", "WG: Hallo", "Fwd: Hallo", "Re: Hallo"],
                         ["Fwd: Hallo", "Fwd: Hallo", "Fwd: Hallo", "Fwd: Re: Hallo"]))
    func forwardSubject(input: String, expected: String) {
        #expect(ReplyBuilder.forwardSubject(input) == expected)
    }

    @Test("Platzhalter für fehlenden Betreff wird nicht übernommen")
    func missingSubjectPlaceholder() {
        #expect(ReplyBuilder.replySubject("(kein Betreff)") == "Re: ")
    }

    // MARK: - Empfänger

    @Test("Antworten geht an den Absender")
    func replyGoesToSender() {
        let result = prefill(.reply, message())
        #expect(result.to == [MailAddress(name: "Anna Muster", address: "anna@example.org")])
        #expect(result.cc.isEmpty)
    }

    @Test("Antworten bevorzugt Reply-To")
    func replyPrefersReplyTo() {
        let result = prefill(.reply, message(replyTo: ["Liste <liste@example.org>"]))
        #expect(result.to.map(\.address) == ["liste@example.org"])
    }

    @Test("Allen antworten: eigene Adressen und Doppelte entfallen, Cc bleibt Cc")
    func replyAll() {
        let original = message(
            to: ["Kim Sieber <Kim@Ordinum.com>", "Bob <bob@example.org>"],
            cc: ["carol@example.org", "BOB@example.org", "kim@sieber-bw.de"]
        )
        let result = prefill(.replyAll, original)
        #expect(result.to.map(\.normalizedAddress) == ["anna@example.org", "bob@example.org"])
        #expect(result.cc.map(\.normalizedAddress) == ["carol@example.org"])
    }

    @Test("Allen antworten auf eigene Mail: An-Feld bleibt nicht leer")
    func replyAllToOwnMessage() {
        let original = message(
            from: "Kim Sieber <kim@ordinum.com>",
            to: ["kim@sieber-bw.de"],
            cc: ["carol@example.org"]
        )
        let result = prefill(.replyAll, original)
        #expect(result.to.map(\.address) == ["carol@example.org"])
        #expect(result.cc.isEmpty)
    }

    @Test("Komma im Namen trennt keine Adresse")
    func commaInDisplayName() {
        let original = message(from: "\"Sieber, Kim\" <kim.sieber@example.org>")
        let result = prefill(.reply, original)
        #expect(result.to == [MailAddress(name: "Sieber, Kim", address: "kim.sieber@example.org")])
    }

    // MARK: - Postfach

    @Test("Neue Mail nutzt das Standard-Postfach, Antwort das Postfach des Originals")
    func accountSelection() {
        #expect(prefill(.new, nil).accountID == defaultAccountID)
        #expect(prefill(.reply, message()).accountID == accountID)
        #expect(prefill(.forward, message()).accountID == accountID)
    }

    @Test("Neue Mail ohne Standard-Postfach: kein Absender vorbelegt")
    func newMailWithoutDefault() {
        let result = ReplyBuilder.prefill(
            kind: .new, original: nil, defaultAccountID: nil, ownAddresses: ownAddresses
        )
        #expect(result == ComposePrefill())
    }

    // MARK: - Threading

    @Test("References: bestehende Kette + Message-ID des Originals")
    func threadingWithReferences() {
        let result = prefill(.reply, message(references: "<a@x> <b@x>"))
        #expect(result.inReplyTo == "<orig@example.org>")
        #expect(result.references == "<a@x> <b@x> <orig@example.org>")
    }

    @Test("References: Fallback auf In-Reply-To des Originals")
    func threadingFallbackToInReplyTo() {
        let result = prefill(.reply, message(inReplyTo: "<a@x>"))
        #expect(result.references == "<a@x> <orig@example.org>")
    }

    @Test("Ohne Message-ID keine Threading-Header")
    func threadingWithoutMessageID() {
        let result = prefill(.reply, message(messageID: nil))
        #expect(result.inReplyTo == nil)
        #expect(result.references == nil)
    }

    @Test("Weiterleiten: keine Empfänger, keine Threading-Header, Kopfblock vorhanden")
    func forward() {
        let result = prefill(.forward, message())
        #expect(result.to.isEmpty && result.cc.isEmpty)
        #expect(result.inReplyTo == nil && result.references == nil)
        #expect(result.subject == "Fwd: Hallo")
        #expect(result.quotedText?.contains("Weitergeleitete Nachricht") == true)
        #expect(result.quotedText?.contains("Zeile 1") == true)
    }

    // MARK: - Zitat

    @Test("Text-Zitat mit > und Kopfzeile")
    func textQuote() {
        let text = prefill(.reply, message()).quotedText ?? ""
        #expect(text.contains("schrieb Anna Muster <anna@example.org>:"))
        #expect(text.contains("> Zeile 1\n> Zeile 2"))
    }

    @Test("Reiner Text wird im HTML-Zitat maskiert")
    func textIsEscapedInHTMLQuote() {
        let html = prefill(.reply, message(text: "<b>fett</b> & Co")).quotedHTML ?? ""
        #expect(html.contains("&lt;b&gt;fett&lt;/b&gt; &amp; Co"))
        #expect(!html.contains("<b>fett"))
    }

    @Test("HTML-Zitat: nur Body-Inhalt, ohne Skripte, Stylesheets und Event-Handler")
    func htmlIsSanitized() {
        let original = message(html: """
            <html><head><style>p{color:red}</style></head>
            <body onload="evil()"><p onclick="evil()">Hallo</p>\
            <script>alert(1)</script><a href="javascript:evil()">Link</a></body></html>
            """)
        let html = prefill(.reply, original).quotedHTML ?? ""
        #expect(html.contains("<p>Hallo</p>"))
        #expect(!html.localizedCaseInsensitiveContains("<script"))
        #expect(!html.contains("<style"))
        #expect(!html.contains("onclick"))
        #expect(!html.contains("onload"))
        #expect(!html.contains("javascript:"))
    }

    @Test("Nur-HTML-Mail: Text-Zitat wird aus dem HTML gewonnen")
    func textFromHTML() {
        let original = message(text: nil, html: "<p>Erste&nbsp;Zeile</p><p>Zweite</p>")
        let text = prefill(.reply, original).quotedText ?? ""
        #expect(text.contains("> Erste Zeile"))
        #expect(text.contains("> Zweite"))
    }
}
