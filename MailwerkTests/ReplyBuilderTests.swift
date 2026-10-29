//
//  ReplyBuilderTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Vorbelegung von Antworten, Allen antworten,
//  Weiterleiten und neuen Mails – Betreff, Empfänger, Postfach,
//  Threading-Header und Zitat (Text und HTML).
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
    private let ownAddresses: Set<String> = ["kim@example.com", "kim@sieber-bw.de"]

    /// Testhilfe: Originalmail mit wählbaren Kopfdaten und Inhalten.
    private func message(
        from: String = "Anna Muster <anna@example.org>",
        to: [String] = ["Kim Sieber <kim@example.com>"],
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

    /// Testhilfe: Vorbelegung mit festem Standard-Postfach und eigenen Adressen.
    private func prefill(_ kind: ComposeKind, _ original: CachedMessage?) -> ComposePrefill {
        ReplyBuilder.prefill(
            kind: kind,
            original: original,
            defaultAccountID: defaultAccountID,
            ownAddresses: ownAddresses
        )
    }

    // MARK: - Betreff

    /// Antwort-Betreff: Präfixe werden zu genau einem Re: zusammengefasst.
    @Test("Antwort-Betreff: Präfixe werden zu genau einem Re: zusammengefasst",
          arguments: ["Hallo", "Re: Hallo", "AW: Re: Hallo", "RE[2]: Hallo", "Aw:Hallo", "  re : Hallo"])
    func replySubject(input: String) {
        #expect(ReplyBuilder.replySubject(input) == "Re: Hallo")
    }

    /// Weiterleitungs-Betreff.
    @Test("Weiterleitungs-Betreff",
          arguments: zip(["Hallo", "WG: Hallo", "Fwd: Hallo", "Re: Hallo"],
                         ["Fwd: Hallo", "Fwd: Hallo", "Fwd: Hallo", "Fwd: Re: Hallo"]))
    func forwardSubject(input: String, expected: String) {
        #expect(ReplyBuilder.forwardSubject(input) == expected)
    }

    /// Platzhalter für fehlenden Betreff wird nicht übernommen.
    @Test("Platzhalter für fehlenden Betreff wird nicht übernommen")
    func missingSubjectPlaceholder() {
        #expect(ReplyBuilder.replySubject("(kein Betreff)") == "Re: ")
    }

    // MARK: - Empfänger

    /// Antworten geht an den Absender.
    @Test("Antworten geht an den Absender")
    func replyGoesToSender() {
        let result = prefill(.reply, message())
        #expect(result.to == [MailAddress(name: "Anna Muster", address: "anna@example.org")])
        #expect(result.cc.isEmpty)
    }

    /// Antworten bevorzugt Reply-To.
    @Test("Antworten bevorzugt Reply-To")
    func replyPrefersReplyTo() {
        let result = prefill(.reply, message(replyTo: ["Liste <liste@example.org>"]))
        #expect(result.to.map(\.address) == ["liste@example.org"])
    }

    /// Allen antworten: eigene Adressen und Doppelte entfallen, Cc bleibt Cc.
    @Test("Allen antworten: eigene Adressen und Doppelte entfallen, Cc bleibt Cc")
    func replyAll() {
        let original = message(
            to: ["Kim Sieber <Kim@Example.com>", "Bob <bob@example.org>"],
            cc: ["carol@example.org", "BOB@example.org", "kim@sieber-bw.de"]
        )
        let result = prefill(.replyAll, original)
        #expect(result.to.map(\.normalizedAddress) == ["anna@example.org", "bob@example.org"])
        #expect(result.cc.map(\.normalizedAddress) == ["carol@example.org"])
    }

    /// Allen antworten auf eigene Mail: An-Feld bleibt nicht leer.
    @Test("Allen antworten auf eigene Mail: An-Feld bleibt nicht leer")
    func replyAllToOwnMessage() {
        let original = message(
            from: "Kim Sieber <kim@example.com>",
            to: ["kim@sieber-bw.de"],
            cc: ["carol@example.org"]
        )
        let result = prefill(.replyAll, original)
        #expect(result.to.map(\.address) == ["carol@example.org"])
        #expect(result.cc.isEmpty)
    }

    /// Komma im Namen trennt keine Adresse.
    @Test("Komma im Namen trennt keine Adresse")
    func commaInDisplayName() {
        let original = message(from: "\"Sieber, Kim\" <kim.sieber@example.org>")
        let result = prefill(.reply, original)
        #expect(result.to == [MailAddress(name: "Sieber, Kim", address: "kim.sieber@example.org")])
    }

    // MARK: - Postfach

    /// Neue Mail nutzt das Standard-Postfach, Antwort das Postfach des Originals.
    @Test("Neue Mail nutzt das Standard-Postfach, Antwort das Postfach des Originals")
    func accountSelection() {
        #expect(prefill(.new, nil).accountID == defaultAccountID)
        #expect(prefill(.reply, message()).accountID == accountID)
        #expect(prefill(.forward, message()).accountID == accountID)
    }

    /// Neue Mail ohne Standard-Postfach: kein Absender vorbelegt.
    @Test("Neue Mail ohne Standard-Postfach: kein Absender vorbelegt")
    func newMailWithoutDefault() {
        let result = ReplyBuilder.prefill(
            kind: .new, original: nil, defaultAccountID: nil, ownAddresses: ownAddresses
        )
        #expect(result == ComposePrefill())
    }

    // MARK: - Threading

    /// References: bestehende Kette + Message-ID des Originals.
    @Test("References: bestehende Kette + Message-ID des Originals")
    func threadingWithReferences() {
        let result = prefill(.reply, message(references: "<a@x> <b@x>"))
        #expect(result.inReplyTo == "<orig@example.org>")
        #expect(result.references == "<a@x> <b@x> <orig@example.org>")
    }

    /// References: Fallback auf In-Reply-To des Originals.
    @Test("References: Fallback auf In-Reply-To des Originals")
    func threadingFallbackToInReplyTo() {
        let result = prefill(.reply, message(inReplyTo: "<a@x>"))
        #expect(result.references == "<a@x> <orig@example.org>")
    }

    /// Ohne Message-ID keine Threading-Header.
    @Test("Ohne Message-ID keine Threading-Header")
    func threadingWithoutMessageID() {
        let result = prefill(.reply, message(messageID: nil))
        #expect(result.inReplyTo == nil)
        #expect(result.references == nil)
    }

    /// Weiterleiten: keine Empfänger, keine Threading-Header, Kopfblock vorhanden.
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

    /// Text-Zitat mit > und Kopfzeile.
    @Test("Text-Zitat mit > und Kopfzeile")
    func textQuote() {
        let text = prefill(.reply, message()).quotedText ?? ""
        #expect(text.contains("schrieb Anna Muster <anna@example.org>:"))
        #expect(text.contains("> Zeile 1\n> Zeile 2"))
    }

    /// Reiner Text wird im HTML-Zitat maskiert.
    @Test("Reiner Text wird im HTML-Zitat maskiert")
    func textIsEscapedInHTMLQuote() {
        let html = prefill(.reply, message(text: "<b>fett</b> & Co")).quotedHTML ?? ""
        #expect(html.contains("&lt;b&gt;fett&lt;/b&gt; &amp; Co"))
        #expect(!html.contains("<b>fett"))
    }

    /// HTML-Zitat: nur die Hüllen-Tags entfallen, aller Inhalt bleibt unverändert.
    @Test("HTML-Zitat: nur die Hüllen-Tags entfallen, aller Inhalt bleibt unverändert")
    func htmlQuoteKeepsContentUnchanged() {
        let body = """
            <style>td{color:#333}</style><p class="x" style="color:red">Hallo</p>\
            <img src="https://example.org/bild.png"><a href="https://example.org">Link</a>
            """
        let original = message(html: """
            <!DOCTYPE html><html><head><title>Kopf</title><style>p{color:red}</style></head>
            <body bgcolor="#fff">\(body)</body></html>
            """)
        let html = prefill(.reply, original).quotedHTML ?? ""
        #expect(html.contains(body))
        #expect(html.contains("<style>p{color:red}</style>"))
        #expect(!html.localizedCaseInsensitiveContains("<head"))
        #expect(!html.localizedCaseInsensitiveContains("<body"))
        #expect(!html.localizedCaseInsensitiveContains("<html"))
        #expect(!html.localizedCaseInsensitiveContains("<!DOCTYPE"))
    }

    /// HTML-Zitat ohne body: nur die Hüllen-Tags entfallen.
    @Test("HTML-Zitat ohne body: nur die Hüllen-Tags entfallen")
    func htmlQuoteWithoutBodyTag() {
        let original = message(html: """
            <html><head><style>p{color:red}</style></head><p>Hallo</p><div>Welt</div></html>
            """)
        #expect(ReplyBuilder.originalBodyHTML(original)
                == "<style>p{color:red}</style><p>Hallo</p><div>Welt</div>")
    }

    /// Fragment mit eingebettetem Dokument: Inhalt davor und danach bleibt erhalten.
    @Test("Fragment mit eingebettetem Dokument: Inhalt davor und danach bleibt erhalten")
    func htmlQuoteKeepsContentAroundEmbeddedDocument() {
        let original = message(html: """
            <table><tr><td><img src="https://example.org/logo" alt="Logo"></td></tr></table>\
            <p><!DOCTYPE html><html><head></head><body><p>Liebe/r Kim,</p></body></html>\
            <img src="https://example.org/logo" alt="Logo klein"></p><table><tr><td>Fragen?</td></tr></table>
            """)
        #expect(ReplyBuilder.originalBodyHTML(original) == """
            <table><tr><td><img src="https://example.org/logo" alt="Logo"></td></tr></table>\
            <p><p>Liebe/r Kim,</p>\
            <img src="https://example.org/logo" alt="Logo klein"></p><table><tr><td>Fragen?</td></tr></table>
            """)
    }

    /// Nur-HTML-Mail: Text-Zitat wird aus dem HTML gewonnen.
    @Test("Nur-HTML-Mail: Text-Zitat wird aus dem HTML gewonnen")
    func textFromHTML() {
        let original = message(text: nil, html: "<p>Erste&nbsp;Zeile</p><p>Zweite</p>")
        let text = prefill(.reply, original).quotedText ?? ""
        #expect(text.contains("> Erste Zeile"))
        #expect(text.contains("> Zweite"))
    }
}
