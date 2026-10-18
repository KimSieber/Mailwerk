//
//  WatchMailboxTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Zustand der Mails auf der Apple Watch (WatchMailbox)
//  – Lieferungen ersetzen den Stand, offene Aktionen wirken sofort und
//  bleiben bis zur Bestätigung, Spam-Aktionen samt Listen und Ablehnung,
//  Sichten und Zahl der ungelesenen Mails.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct WatchMailboxTests {

    /// Testhilfe: Mail mit Absender `name@example.com`.
    static func mail(
        _ id: String,
        box: WatchBox = .inbox,
        unread: Bool = false,
        flagged: Bool = false,
        minutesAgo: Double = 0,
        sender: String = "anna@news.example.com"
    ) -> WatchMail {
        WatchMail(
            id: id, accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            folder: box == .inbox ? "INBOX" : "Junk", uid: 1, box: box,
            subject: "Betreff \(id)", senderTitle: "Anna", senderAddress: sender, filterAddress: sender,
            initials: "A", colorIndex: 0, accountColorHex: nil, from: "Anna <\(sender)>", to: [],
            date: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60),
            isUnread: unread, isFlagged: flagged, verdict: WatchVerdict(.clean),
            hasAttachments: false, avatarKey: nil
        )
    }

    /// Testhilfe: Lieferung.
    static func snapshot(
        _ mails: [WatchMail],
        at seconds: Double = 100,
        unreadTotal: Int? = nil,
        lists: FilterLists? = .empty,
        outcomes: [WatchActionOutcome] = []
    ) -> WatchSnapshot {
        WatchSnapshot(
            createdAt: Date(timeIntervalSince1970: seconds), isFresh: true, lastServerSync: nil,
            hasAccounts: true, mails: mails,
            unreadInboxTotal: unreadTotal ?? mails.filter { $0.box == .inbox && $0.isUnread }.count,
            lists: lists.map(WatchFilterLists.init), scoreLimit: 15, outcomes: outcomes, problems: []
        )
    }

    /// Eine Lieferung ersetzt den Stand; eine ältere wird übergangen.
    @Test func newerSnapshotReplacesOlderIsIgnored() {
        var box = WatchMailbox()
        box.receive(Self.snapshot([Self.mail("a")], at: 100))
        box.receive(Self.snapshot([Self.mail("b")], at: 200))
        box.receive(Self.snapshot([Self.mail("c")], at: 150))
        #expect(box.effectiveMails().map(\.id) == ["b"])
    }

    /// Aktionen wirken sofort und bleiben über neue Lieferungen bestehen.
    @Test func pendingActionSurvivesSnapshot() throws {
        var box = WatchMailbox()
        box.receive(Self.snapshot([Self.mail("a", unread: true)], at: 100))
        try box.perform(.read(true), on: Self.mail("a", unread: true))
        #expect(box.effectiveMails().first?.isUnread == false)
        box.receive(Self.snapshot([Self.mail("a", unread: true)], at: 200))
        #expect(box.effectiveMails().first?.isUnread == false)
        #expect(box.pending.count == 1)
    }

    /// Gemeldete Ergebnisse erledigen Aktionen; Gescheiterte kommen zurück.
    @Test func outcomesResolvePendingActions() throws {
        var box = WatchMailbox()
        let mail = Self.mail("a")
        box.receive(Self.snapshot([mail], at: 100))
        let done = try box.perform(.flagged(true), on: mail)
        let failed = try box.perform(.read(false), on: mail)
        let failures = box.receive(Self.snapshot([mail], at: 200, outcomes: [
            WatchActionOutcome(actionID: done.id, result: .done),
            WatchActionOutcome(actionID: failed.id, result: .failed("Server sagt nein"))
        ]))
        #expect(box.pending.isEmpty)
        #expect(failures.map { $0.reason } == ["Server sagt nein"])
        // Der Server ist führend: ohne offene Aktion gilt sein Stand.
        #expect(box.effectiveMails().first?.isFlagged == false)
    }

    /// Eine neuere Aktion derselben Art ersetzt die ältere.
    @Test func newerActionOfSameKindReplacesOlder() throws {
        var box = WatchMailbox()
        let mail = Self.mail("a", unread: true)
        box.receive(Self.snapshot([mail]))
        try box.perform(.read(true), on: mail)
        try box.perform(.flagged(true), on: mail)
        try box.perform(.read(false), on: mail)
        #expect(box.pending.map(\.change) == [.flagged(true), .read(false)])
    }

    /// Blockieren: Mail nach „Spam“, Wert in die Blacklist der Watch.
    @Test func blockMovesToSpamAndListsValue() throws {
        var box = WatchMailbox()
        let mail = Self.mail("a")
        box.receive(Self.snapshot([mail]))
        try box.perform(.spam(kind: .block, entryKind: .domain, value: "example.com"), on: mail)
        #expect(WatchMailbox.mails(in: .spam, from: box.effectiveMails()).map(\.id) == ["a"])
        #expect(WatchMailbox.mails(in: .allInboxes, from: box.effectiveMails()).isEmpty)
        #expect(box.effectiveLists()?.blackDomains == ["example.com"])
    }

    /// Vertrauen holt eine Mail aus „Spam“ zurück.
    @Test func trustMovesBackToInbox() throws {
        var box = WatchMailbox()
        let mail = Self.mail("a", box: .spam)
        box.receive(Self.snapshot([mail]))
        try box.perform(.spam(kind: .trust, entryKind: .address, value: "anna@news.example.com"), on: mail)
        #expect(box.effectiveMails().first?.box == .inbox)
        #expect(box.effectiveLists()?.whiteAddresses == ["anna@news.example.com"])
    }

    /// Steht der Wert auf der anderen Liste, wird abgelehnt – wie auf dem iPhone.
    @Test func spamActionRejectedWhenOnOtherList() {
        var box = WatchMailbox()
        var lists = FilterLists.empty
        lists.whiteDomains = ["example.com"]
        let mail = Self.mail("a")
        box.receive(Self.snapshot([mail], lists: lists))
        #expect(throws: FilterListError.alreadyOnOtherList(.white)) {
            try box.perform(.spam(kind: .block, entryKind: .domain, value: "example.com"), on: mail)
        }
        #expect(box.pending.isEmpty)
    }

    /// Sichten: Ungelesen behält gezeigte Mails, Kennzeichnung nur Eingänge.
    @Test func viewsFilterMails() {
        let mails = [
            Self.mail("a", unread: true),
            Self.mail("b", flagged: true, minutesAgo: 1),
            Self.mail("c", box: .spam, unread: true, flagged: true, minutesAgo: 2)
        ]
        #expect(WatchMailbox.mails(in: .allInboxes, from: mails).map(\.id) == ["a", "b"])
        #expect(WatchMailbox.mails(in: .unread, from: mails).map(\.id) == ["a"])
        #expect(WatchMailbox.mails(in: .unread, from: mails, keeping: ["b"]).map(\.id) == ["a", "b"])
        #expect(WatchMailbox.mails(in: .flagged, from: mails).map(\.id) == ["b"])
        #expect(WatchMailbox.mails(in: .spam, from: mails).map(\.id) == ["c"])
    }

    /// Ungelesen zählt auch Mails außerhalb der Auswahl und folgt Aktionen.
    @Test func unreadCountIncludesMailsOutsideSelection() throws {
        var box = WatchMailbox()
        let mail = Self.mail("a", unread: true)
        box.receive(Self.snapshot([mail, Self.mail("s", box: .spam, unread: true)], unreadTotal: 120))
        #expect(box.unreadCount() == 120)
        try box.perform(.read(true), on: mail)
        #expect(box.unreadCount() == 119)
    }

    /// Ohne Lieferung: nichts.
    @Test func emptyMailboxHasNothing() {
        let box = WatchMailbox()
        #expect(!box.hasSnapshot)
        #expect(box.effectiveMails().isEmpty)
        #expect(box.effectiveLists() == nil)
        #expect(box.unreadCount() == 0)
    }
}
