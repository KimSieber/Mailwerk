//
//  MessageMenuTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das gemeinsame Mail-Menü – Beschriftungen und Symbole
//  (MessageMenuLabels), Rückfragen und Meldungen (MessageActionDialogs)
//  sowie Texte und Umkehrung von „Rückgängig“ (UndoOffer, StateChange).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageMenuTests {

    /// Testhilfe: Ziel einer Aktion.
    private func target(_ id: String) -> MessageActions.Target {
        MessageActions.Target(id: id, accountID: UUID(), folder: "INBOX", uid: 1)
    }

    /// Kennzeichnung: gleicher Text, Symbol und Bezeichnung nach Wirkung.
    @Test func flagEntryFollowsEffect() {
        let set = MessageMenuLabels.flag(isFlagged: false)
        let remove = MessageMenuLabels.flag(isFlagged: true)
        #expect(set.title == "Kennzeichnung")
        #expect(remove.title == "Kennzeichnung")
        #expect(set.systemImage == "flag")
        #expect(remove.systemImage == "flag.slash")
        #expect(remove.accessibility == "Kennzeichnung entfernen")
    }

    /// Gelesen-Eintrag heißt nach dem Zustand, den der Tipp herstellt.
    @Test func readEntryNamesTargetState() {
        #expect(MessageMenuLabels.read(isUnread: true).title == "Gelesen")
        #expect(MessageMenuLabels.read(isUnread: false).title == "Ungelesen")
    }

    /// Spam-Einträge bleiben kurz; der Wert steht nur in der Bezeichnung.
    @Test func spamEntriesAreShort() {
        let block = MessageMenuLabels.spam(SpamMenuRequest(kind: .block, entryKind: .domain, value: "firma.de"))
        let trust = MessageMenuLabels.spam(SpamMenuRequest(kind: .trust, entryKind: .address, value: "a@firma.de"))
        #expect(block.title == "Blockieren")
        #expect(block.accessibility == "firma.de blockieren")
        #expect(trust.title == "Vertrauen")
        #expect(trust.accessibility == "a@firma.de vertrauen")
    }

    /// Rückfrage Löschen: einzeln ohne, mehrfach mit Anzahl; immer rot.
    @Test func deleteConfirmationShowsCount() {
        let single = MessageActionDialogs.deleteConfirmation(count: 1) {}
        let many = MessageActionDialogs.deleteConfirmation(count: 5) {}
        #expect(single.title == "Mail löschen?")
        #expect(many.title == "5 Mails löschen?")
        #expect(many.isDestructive)
    }

    /// Rückfrage Spam: Blockieren rot, Vertrauen nicht.
    @Test func spamConfirmationMarksBlockDestructive() {
        let block = MessageActionDialogs.spamConfirmation(
            SpamMenuRequest(kind: .block, entryKind: .address, value: "a@firma.de")
        ) {}
        let trust = MessageActionDialogs.spamConfirmation(
            SpamMenuRequest(kind: .trust, entryKind: .domain, value: "firma.de")
        ) {}
        #expect(block.title == "a@firma.de blockieren?")
        #expect(block.isDestructive)
        #expect(trust.confirmLabel == "Vertrauen")
        #expect(!trust.isDestructive)
    }

    /// Eintrag auf der anderen Liste: erklärende Meldung statt Fehlertext.
    @Test func spamFailureExplainsOtherList() {
        let request = SpamMenuRequest(kind: .block, entryKind: .address, value: "a@firma.de")
        let alert = MessageActionDialogs.spamFailureAlert(request, FilterListError.alreadyOnOtherList(.white))
        #expect(alert.message == "a@firma.de steht bereits auf der Whitelist. Entferne den Eintrag dort zuerst.")
    }

    /// Rückgängig-Text: einzeln kurz, mehrfach mit Anzahl.
    @Test func undoTextShowsCount() {
        #expect(UndoOffer(change: .flagged(false), targets: [target("1")]).text == "Kennzeichnung entfernt")
        #expect(UndoOffer(change: .read(true), targets: [target("1"), target("2")]).text == "2 Mails als gelesen markiert")
    }

    /// Rückgängig kehrt den gesetzten Wert um.
    @Test func stateChangeReverses() {
        #expect(MessageActions.StateChange.flagged(true).reversed == .flagged(false))
        #expect(MessageActions.StateChange.read(false).reversed == .read(true))
    }

    /// Originalquelle: kurzer Text, ausführliche Bezeichnung.
    @Test func sourceEntry() {
        #expect(MessageMenuLabels.source.title == "Originalquelle")
        #expect(MessageMenuLabels.source.systemImage == "doc.plaintext")
        #expect(MessageMenuLabels.source.accessibility == "Originalquelle der Mail anzeigen")
    }
}
