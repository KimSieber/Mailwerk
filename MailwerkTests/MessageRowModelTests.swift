//
//  MessageRowModelTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das vorberechnete Zeilenmodell der Mailliste
//  (MessageRowModel, v0.2.3c): gleiche Regeln wie bisher für Person,
//  Absenderbild und Spam-Hinweis.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für `MessageRowModel`.
@MainActor
struct MessageRowModelTests {

    /// Testhilfe: Listeneintrag mit Absender und Spam-Befund.
    private func item(
        uid: UInt32 = 1,
        from: String = "Anna Muster <anna@example.org>",
        recipients: [String] = ["Max Müller <max@example.org>"],
        verdict: SpamHeaderVerdict? = SpamHeaderVerdict(isSpam: false, score: 1.0)
    ) -> MessageListItem {
        MessageListItem(
            id: "a-INBOX-\(uid)", accountID: UUID(), folder: "INBOX", uid: uid,
            subject: "Betreff", from: from, recipients: recipients, date: nil,
            isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
            hasAttachments: false, sizeBytes: 0, spamVerdict: verdict
        )
    }

    /// Testhilfe: Eingaben mit wählbaren Listen.
    private func inputs(lists: FilterLists?, showsRecipients: Bool = false) -> MessageRowModel.Inputs {
        MessageRowModel.Inputs(showsRecipients: showsRecipients, lists: lists, scoreLimit: 5.0)
    }

    /// Ohne gelesene Listen weder Bild noch Hinweis; die Person steht trotzdem fest.
    @Test("Ohne Listen kein Bild und kein Hinweis")
    func withoutListsNoImageNoMark() {
        let model = MessageRowModel.make(for: item(), inputs: inputs(lists: nil))
        #expect(!model.showsImage)
        #expect(model.spamMark == nil)
        #expect(model.party.address == "anna@example.org")
    }

    /// Unauffällige Mail: Bild erlaubt, kein Hinweis – wie bisher im ViewModel.
    @Test("Unauffällige Mail zeigt ein Bild")
    func cleanMailShowsImage() {
        let model = MessageRowModel.make(for: item(), inputs: inputs(lists: .empty))
        #expect(model.showsImage == SpamClassifier.allowsSenderImage(
            sender: FilterAddress.sender(fromHeader: "Anna Muster <anna@example.org>"),
            verdict: SpamHeaderVerdict(isSpam: false, score: 1.0),
            lists: .empty, scoreLimit: 5.0
        ))
        #expect(model.spamMark == nil)
    }

    /// Spam laut Server: kein Bild, Hinweis „[SPAM]“.
    @Test("Spam zeigt kein Bild und den Hinweis")
    func spamShowsMark() {
        let model = MessageRowModel.make(
            for: item(verdict: SpamHeaderVerdict(isSpam: true, score: 9.0)),
            inputs: inputs(lists: .empty)
        )
        #expect(!model.showsImage)
        #expect(model.spamMark == "[SPAM]")
    }

    /// In Gesendet zeigt die Zeile den Empfänger.
    @Test("Gesendet zeigt den Empfänger")
    func sentShowsRecipient() {
        let model = MessageRowModel.make(for: item(), inputs: inputs(lists: .empty, showsRecipients: true))
        #expect(model.party.address == "max@example.org")
    }

    /// makeAll liefert je Cache-ID ein Modell.
    @Test("makeAll liefert je Mail ein Modell")
    func makeAllKeysByID() {
        let items = [item(uid: 1), item(uid: 2)]
        let models = MessageRowModel.makeAll(for: items, inputs: inputs(lists: .empty))
        #expect(Set(models.keys) == ["a-INBOX-1", "a-INBOX-2"])
    }
}
