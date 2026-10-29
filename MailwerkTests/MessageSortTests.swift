//
//  MessageSortTests.swift
//  MailwerkTests
//
//  Zweck: Tests für MessageSort – Felder, Richtung, Gleichstand,
//  Empfänger in Gesendet/Entwürfen und Grundstellung.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageSortTests {

    /// Testhilfe: Listeneintrag mit Absender, Empfänger, Betreff, Datum und Größe.
    private func item(
        _ id: String,
        from: String = "a@example.org",
        to: [String] = [],
        subject: String = "Betreff",
        date: Double? = 0,
        size: Int = 0
    ) -> MessageListItem {
        MessageListItem(
            id: id, accountID: UUID(), folder: "INBOX", uid: 1, subject: subject,
            from: from, recipients: to, date: date.map { Date(timeIntervalSince1970: $0) },
            isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
            hasAttachments: false, sizeBytes: size, spamVerdict: nil
        )
    }

    /// Grundstellung ist Datum absteigend; ohne Datum steht am Ende.
    @Test func standardIsNewestFirst() {
        let items = [item("a", date: 1), item("b", date: nil), item("c", date: 3)]
        #expect(MessageSort.standard.isStandard)
        #expect(MessageSort.standard.sorted(items, showsRecipients: false).map(\.id) == ["c", "a", "b"])
        let ascending = MessageSort(field: .date, ascending: true)
        #expect(!ascending.isStandard)
        #expect(ascending.sorted(items, showsRecipients: false).map(\.id) == ["a", "c", "b"])
    }

    /// Von: nach Name bzw. Adresse, ohne Groß-/Kleinschreibung.
    @Test func personSortsByName() {
        let items = [
            item("1", from: "Zoe <z@example.org>"),
            item("2", from: "anna <x@example.org>"),
            item("3", from: "berta@example.org"),
        ]
        let sort = MessageSort(field: .person, ascending: true)
        #expect(sort.sorted(items, showsRecipients: false).map(\.id) == ["2", "3", "1"])
        let descending = MessageSort(field: .person, ascending: false)
        #expect(descending.sorted(items, showsRecipients: false).map(\.id) == ["1", "3", "2"])
    }

    /// In Gesendet/Entwürfen sortiert „Von“ nach dem ersten Empfänger.
    @Test func personUsesRecipientsInSent() {
        let items = [
            item("1", from: "a@example.org", to: ["Zoe <z@example.org>"]),
            item("2", from: "z@example.org", to: ["Anna <x@example.org>"]),
        ]
        let sort = MessageSort(field: .person, ascending: true)
        #expect(sort.sorted(items, showsRecipients: true).map(\.id) == ["2", "1"])
        #expect(MessageSort.Field.person.title(showsRecipients: true) == "An")
        #expect(MessageSort.Field.person.title(showsRecipients: false) == "Von")
    }

    /// Betreff: Zahlen nach ihrem Wert.
    @Test func subjectComparesNumbersByValue() {
        let items = [item("a", subject: "Rechnung 10"), item("b", subject: "Rechnung 9")]
        let sort = MessageSort(field: .subject, ascending: true)
        #expect(sort.sorted(items, showsRecipients: false).map(\.id) == ["b", "a"])
    }

    /// Größe in beide Richtungen.
    @Test func sizeSorts() {
        let items = [item("a", size: 20), item("b", size: 5), item("c", size: 300)]
        #expect(MessageSort(field: .size, ascending: true).sorted(items, showsRecipients: false).map(\.id) == ["b", "a", "c"])
        #expect(MessageSort(field: .size, ascending: false).sorted(items, showsRecipients: false).map(\.id) == ["c", "a", "b"])
    }

    /// Gleichstand: neueste zuerst, unabhängig von der Richtung.
    @Test func tiesAreNewestFirst() {
        let items = [item("a", subject: "X", date: 1), item("b", subject: "X", date: 5)]
        #expect(MessageSort(field: .subject, ascending: true).sorted(items, showsRecipients: false).map(\.id) == ["b", "a"])
        #expect(MessageSort(field: .subject, ascending: false).sorted(items, showsRecipients: false).map(\.id) == ["b", "a"])
    }
}
