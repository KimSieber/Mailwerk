//
//  OutgoingMailOriginTests.swift
//  MailwerkTests
//
//  Zweck: Tests für `OutgoingMail.Origin(composeKind:original:)` aus
//  MailSendService.swift. Sichert ab, dass der Bezug auf die Originalmail
//  ihren Ordner mitführt – Antworten und Weiterleiten aus Spam- oder
//  Benutzerordnern dürfen nicht eine Mail im Posteingang markieren.
//

import Foundation
import Testing
@testable import Mailwerk

/// Läuft auf dem MainActor, da die App-Typen im Projekt standardmäßig
/// MainActor-isoliert sind (Default Actor Isolation).
@MainActor
struct OutgoingMailOriginTests {

    private let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Testhilfe: gecachte Nachricht mit frei wählbarem Ordner und UID.
    private func message(folder: String, uid: UInt32 = 42) -> CachedMessage {
        CachedMessage(
            id: CachedMessage.makeID(accountID: accountID, folder: folder, uid: uid),
            accountID: accountID,
            accountDisplayName: "Test",
            folder: folder,
            uid: uid,
            subject: "Betreff",
            from: "Anna Muster <anna@example.org>",
            to: "kim@example.org",
            date: Date(),
            isUnread: false,
            isFlagged: false,
            isAnswered: false,
            isForwarded: false,
            totalSizeBytes: 1000,
            hasAttachments: false,
            textBody: "Text",
            htmlBody: nil,
            fetchedAt: Date(),
            headers: CachedMessageHeaders()
        )
    }

    /// Antwort aus dem Spam-Ordner: Bezug trägt Ordner, UID, Postfach und Cache-ID des Originals.
    @Test func replyCarriesFolderOfOriginal() throws {
        let original = message(folder: "Junk", uid: 7)
        let origin = try #require(OutgoingMail.Origin(composeKind: .reply, original: original))

        #expect(origin.kind == .replied)
        #expect(origin.folder == "Junk")
        #expect(origin.uid == 7)
        #expect(origin.accountID == accountID)
        #expect(origin.cachedMessageID == original.id)
    }

    /// „Allen antworten“ wird wie Antworten als beantwortet markiert.
    @Test func replyAllIsReplied() throws {
        let origin = try #require(
            OutgoingMail.Origin(composeKind: .replyAll, original: message(folder: "INBOX"))
        )
        #expect(origin.kind == .replied)
        #expect(origin.folder == "INBOX")
    }

    /// Weiterleiten aus einem Unterordner: Pfad mit Trennzeichen bleibt unverändert.
    @Test func forwardCarriesNestedFolderPath() throws {
        let origin = try #require(
            OutgoingMail.Origin(composeKind: .forward, original: message(folder: "INBOX.Rechnungen"))
        )
        #expect(origin.kind == .forwarded)
        #expect(origin.folder == "INBOX.Rechnungen")
    }

    /// Neue Mail hat keinen Bezug, auch wenn eine Nachricht übergeben wird.
    @Test func newMailHasNoOrigin() {
        #expect(OutgoingMail.Origin(composeKind: .new, original: message(folder: "INBOX")) == nil)
    }

    /// Ohne Originalnachricht entsteht kein Bezug.
    @Test func missingOriginalHasNoOrigin() {
        #expect(OutgoingMail.Origin(composeKind: .reply, original: nil) == nil)
    }
}
