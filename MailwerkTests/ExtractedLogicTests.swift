//
//  ExtractedLogicTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die reine Logik, die in v0.3.1b (Teil 3) aus Diensten
//  herausgelöst wurde: Ordnerliste (MailboxListing), Kontaktvorschläge
//  (ContactSuggestionService.rank), eingebettete Bilder
//  (InlineImageLoader.tasks) und die gemeinsame HTML-Maskierung
//  (HTMLEscaping).
//

import Foundation
import SwiftMail
import Testing
@testable import Mailwerk

/// Tests für MailboxListing, rank, InlineImageLoader.tasks und HTMLEscaping.
@MainActor
struct ExtractedLogicTests {

    // MARK: - MailboxListing

    /// Testhilfe: Ordner laut Server.
    private func entry(_ path: String, _ use: MailFolder.SpecialUse? = nil) -> MailboxListing.Entry {
        MailboxListing.Entry(path: path, delimiter: "/", specialUse: use, isSelectable: true)
    }

    /// Sonderordner zuerst, dann alphabetisch; Posteingang nur auf Wunsch.
    @Test("Ordnerliste: Reihenfolge und Posteingang")
    func mailboxOrder() {
        let entries = [entry("INBOX"), entry("Zeug"), entry("Archiv/alt"), entry("Trash", .trash), entry("Sent", .sent)]
        let folders = MailboxListing.folders(from: entries, includeInbox: false)
        #expect(folders.map(\.id) == ["Sent", "Trash", "Archiv/alt", "Zeug"])
        #expect(folders.first { $0.id == "Archiv/alt" }?.name == "alt")
        #expect(MailboxListing.folders(from: entries, includeInbox: true).contains { $0.id == "INBOX" })
    }

    /// Ohne Trennzeichen ist der ganze Pfad der Name.
    @Test("Anzeigename ohne Trennzeichen")
    func displayNameFlat() {
        #expect(MailboxListing.displayName(path: "A.B", delimiter: nil) == "A.B")
        #expect(MailboxListing.displayName(path: "A.B", delimiter: ".") == "B")
    }

    /// Erster passender Sonderordner in fester Rangfolge.
    @Test("Sonderordner aus Attributen")
    func specialUse() {
        #expect(MailboxListing.specialUse(matching: { $0 == .junk || $0 == .archive }) == .junk)
        #expect(MailboxListing.specialUse(matching: { _ in false }) == nil)
    }

    // MARK: - ContactSuggestionService.rank

    /// Nur gültige, passende Adressen; Doppelte entfallen; Wortanfang zuerst.
    @Test("Kontaktvorschläge: Auswahl und Reihenfolge")
    func rankSuggestions() {
        let contacts: [(name: String, addresses: [String])] = [
            (name: "Zora Müller", addresses: ["anna.z@example.com"]),
            (name: "Anna Schmidt", addresses: ["anna@example.com", "ANNA@example.com", "kaputt"]),
            (name: "Bernd", addresses: ["bernd@example.com"])
        ]
        let result = ContactSuggestionService.rank(contacts, query: "anna", limit: 10)
        #expect(result.map(\.address) == ["anna@example.com", "anna.z@example.com"])
        #expect(ContactSuggestionService.rank(contacts, query: "anna", limit: 1).count == 1)
    }

    // MARK: - InlineImageLoader.tasks

    /// Geladen wird nur ein angesprochenes Bild ohne Daten.
    @Test("Eingebettete Bilder: Ladebedarf")
    func inlineImageTasks() {
        let plan = MessageContentPlan(
            structure: [
                MessageContentPlan.part(section: "1", contentType: "text/html"),
                MessageContentPlan.part(section: "2", contentType: "image/png", disposition: "inline", filename: "a.png", contentId: "<a@x>"),
                MessageContentPlan.part(section: "3", contentType: "image/png", disposition: "inline", filename: "b.png", contentId: "<b@x>")
            ],
            totalSize: 0, threshold: 0
        )
        let tasks = InlineImageLoader.tasks(
            for: plan, messageID: "m", existing: [],
            referenced: [InlineImages.normalizedContentID("a@x")]
        )
        #expect(tasks.map(\.needsData) == [true, false])
        #expect(tasks.map(\.entry.id) == ["m-2", "m-3"])
    }

    // MARK: - HTMLEscaping

    /// Alle fünf Zeichen werden maskiert, `&` nicht doppelt.
    @Test("HTML-Maskierung")
    func escaping() {
        #expect(HTMLEscaping.escaped(#"<a href="x">Tom & 'Jerry'</a>"#)
                == "&lt;a href=&quot;x&quot;&gt;Tom &amp; &#39;Jerry&#39;&lt;/a&gt;")
    }
}
