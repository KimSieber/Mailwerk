//
//  MailPrintFormatterTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die HTML-Fassung einer Mail zum Drucken und Teilen –
//  Maskierung, Textmails, Anhangliste, Dateiname aus dem Betreff und
//  temporäre Datei zum Teilen.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MailPrintFormatterTests {

    /// Testhilfe: Textmail ohne HTML-Teil.
    private func message(subject: String, text: String) -> CachedMessage {
        let account = UUID()
        return CachedMessage(
            id: CachedMessage.makeID(accountID: account, folder: "INBOX", uid: 1),
            accountID: account,
            accountDisplayName: "Test",
            folder: "INBOX",
            uid: 1,
            subject: subject,
            from: "Anna <anna@example.org>",
            to: "kim@example.org",
            date: nil,
            isUnread: false,
            isFlagged: false,
            isAnswered: false,
            isForwarded: false,
            totalSizeBytes: 1_024,
            hasAttachments: false,
            textBody: text,
            htmlBody: nil,
            fetchedAt: Date(),
            headers: CachedMessageHeaders()
        )
    }

    /// Kopfdaten und Textmail werden maskiert; die Textmail steht in `<pre>`.
    @Test func escapesHeaderAndPlainText() {
        let html = MailPrintFormatter.html(for: message(subject: "A < B", text: "x & y"))
        #expect(html.contains("Anna &lt;anna@example.org&gt;"))
        #expect(html.contains("A &lt; B"))
        #expect(html.contains("<pre>x &amp; y</pre>"))
    }

    /// Ohne Anhänge gibt es keine Anhangliste.
    @Test func noAttachmentSectionWithoutAttachments() {
        let html = MailPrintFormatter.html(for: message(subject: "Hallo", text: "Text"))
        #expect(!html.contains("Anlagen ("))
    }

    /// Dateiname: „/“ und „:“ ersetzt, leerer Betreff ergibt „Mail“.
    @Test func filenameFromSubject() {
        #expect(MailPrintFormatter.filename(forSubject: " Re: a/b ") == "Re- a-b")
        #expect(MailPrintFormatter.filename(forSubject: "  ") == "Mail")
    }

    /// Die Datei zum Teilen trägt den Betreff als Namen und enthält das HTML.
    @Test func writesTemporaryHTMLFile() throws {
        let url = try MailPrintFormatter.writeTemporaryFile(for: message(subject: "Teilen-Test", text: "Inhalt"))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent == "Teilen-Test.html")
        #expect(try String(contentsOf: url, encoding: .utf8).contains("<pre>Inhalt</pre>"))
    }
}
