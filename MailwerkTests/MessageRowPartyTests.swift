//
//  MessageRowPartyTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die gezeigte Person einer Listenzeile
//  (MessageRowParty) – Absender bzw. Empfänger, Texte der Namenszeile,
//  Initialen und feste Farbe.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageRowPartyTests {

    /// Testhilfe: Listeneintrag mit Absender und Empfängern.
    private func item(from: String, to recipients: [String] = []) -> MessageListItem {
        MessageListItem(
            id: "x", accountID: UUID(), folder: "INBOX", uid: 1, subject: "Betreff",
            from: from, recipients: recipients, date: nil, isUnread: false, isFlagged: false,
            isAnswered: false, isForwarded: false, hasAttachments: false, sizeBytes: 0,
            spamVerdict: nil
        )
    }

    /// Absender mit Name: Name fett, Adresse als Zusatz.
    @Test func senderWithNameShowsNameAndAddress() {
        let party = MessageRowParty.make(for: item(from: "Anna Muster <anna@example.org>"), showsRecipients: false)
        #expect(party.title == "Anna Muster")
        #expect(party.subtitle == "anna@example.org")
    }

    /// Absender ohne Name: Adresse fett, kein Zusatz.
    @Test func senderWithoutNameShowsAddressOnly() {
        let party = MessageRowParty.make(for: item(from: "service@bezahldienst.example"), showsRecipients: false)
        #expect(party.title == "service@bezahldienst.example")
        #expect(party.subtitle == nil)
    }

    /// Ein Name, der nur die Adresse wiederholt, entfällt.
    @Test func nameRepeatingAddressIsDropped() {
        let party = MessageRowParty.make(for: item(from: "\"info@firma.de\" <info@firma.de>"), showsRecipients: false)
        #expect(party.name == nil)
        #expect(party.title == "info@firma.de")
    }

    /// Nicht auswertbarer Absender bleibt als Text stehen.
    @Test func unparsableSenderStaysAsText() {
        let party = MessageRowParty.make(for: item(from: "Unbekannt"), showsRecipients: false)
        #expect(party.title == "Unbekannt")
        #expect(party.address == nil)
    }

    /// Gesendet/Entwürfe: erster Empfänger mit Anzahl weiterer.
    @Test func recipientsShowFirstWithCount() {
        let message = item(
            from: "Kim <kim@example.org>",
            to: ["Ben Beispiel <ben@example.org>", "c@example.org", "d@example.org"]
        )
        let party = MessageRowParty.make(for: message, showsRecipients: true)
        #expect(party.title == "Ben Beispiel")
        #expect(party.subtitle == "ben@example.org +2")
    }

    /// Gesendet/Entwürfe ohne Empfänger: Ersatztext statt eigener Adresse.
    @Test func noRecipientsShowsUnknown() {
        let party = MessageRowParty.make(for: item(from: "Kim <kim@example.org>"), showsRecipients: true)
        #expect(party.title == MessageRowParty.unknownTitle)
        #expect(party.initials.isEmpty)
    }

    /// Initialen aus erstem und letztem Wort, Sonderzeichen übersprungen.
    @Test func initialsFromFirstAndLastWord() {
        #expect(MessageRowParty(name: "Anna Maria Muster", address: nil, additionalCount: 0).initials == "AM")
        #expect(MessageRowParty(name: "manitu (Support)", address: nil, additionalCount: 0).initials == "MS")
        #expect(MessageRowParty(name: "Parka", address: nil, additionalCount: 0).initials == "P")
    }

    /// Ohne Name: erster Buchstabe der Adresse.
    @Test func initialsFromAddressWithoutName() {
        #expect(MessageRowParty(name: nil, address: "service@bezahldienst.example", additionalCount: 0).initials == "S")
    }

    /// Gleiche Adresse ergibt unabhängig von der Schreibweise dieselbe Farbe im gültigen Bereich.
    @Test func colorIndexIsStableAndInRange() {
        let a = MessageRowParty(name: "A", address: "Info@Firma.de", additionalCount: 0)
        let b = MessageRowParty(name: "B", address: "info@firma.de", additionalCount: 0)
        #expect(a.colorIndex == b.colorIndex)
        #expect(AccountColor.allCases.indices.contains(a.colorIndex))
    }

    /// Mailansicht: dieselbe Person wie in der Liste, aus Absender und Empfängern.
    @Test func makeFromHeaderFieldsMatchesListItem() {
        let from = "Anna Muster <anna@example.org>"
        let recipients = ["Ben Beispiel <ben@example.org>", "c@example.org"]
        let listItem = item(from: from, to: recipients)
        for showsRecipients in [false, true] {
            #expect(
                MessageRowParty.make(from: from, recipients: recipients, showsRecipients: showsRecipients)
                    == MessageRowParty.make(for: listItem, showsRecipients: showsRecipients)
            )
        }
        #expect(MessageRowParty.make(from: from, recipients: recipients, showsRecipients: true).title == "Ben Beispiel")
    }
}
