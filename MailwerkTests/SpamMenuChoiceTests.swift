//
//  SpamMenuChoiceTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Texte der Spam-Aktionen (SpamMenuTexts), die App und
//  Apple Watch gemeinsam verwenden – Rückfrage, Bestätigung, Hinweis bei
//  der anderen Liste, Symbole.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SpamMenuChoiceTests {

    /// Rückfrage zum Blockieren einer Domain.
    @Test func blockDomainConfirmation() {
        let request = SpamMenuRequest(kind: .block, entryKind: .domain, value: "firma.de")
        #expect(SpamMenuTexts.confirmationTitle(request) == "*firma.de blockieren?")
        #expect(SpamMenuTexts.confirmationMessage(request)
                == "Alle künftigen Mails dieser Domain und ihrer Subdomains wandern in den Spam-Ordner. Diese Mail wird mitverschoben.")
        #expect(SpamMenuTexts.confirmLabel(request) == "Blockieren")
        #expect(request.list == .black)
    }

    /// Rückfrage zum Vertrauen einer Adresse.
    @Test func trustAddressConfirmation() {
        let request = SpamMenuRequest(kind: .trust, entryKind: .address, value: "a@firma.de")
        #expect(SpamMenuTexts.confirmationTitle(request) == "a@firma.de vertrauen?")
        #expect(SpamMenuTexts.confirmationMessage(request)
                == "Alle künftigen Mails dieses Absenders bleiben im Posteingang. Liegt diese Mail im Spam-Ordner, wird sie zurückgeholt.")
        #expect(SpamMenuTexts.confirmLabel(request) == "Vertrauen")
        #expect(request.list == .white)
    }

    /// Bestätigung und Hinweis bei der anderen Liste.
    @Test func resultAndOtherListMessages() {
        let request = SpamMenuRequest(kind: .block, entryKind: .address, value: "a@firma.de")
        #expect(SpamMenuTexts.resultMessage(request) == "a@firma.de steht jetzt auf der Blacklist.")
        #expect(SpamMenuTexts.otherListMessage(request, list: .white)
                == "a@firma.de steht bereits auf der Whitelist. Entferne den Eintrag dort zuerst.")
    }

    /// Ein Abschnitt liefert die Aktionen für seinen Wert.
    @Test func sectionBuildsRequests() {
        let section = SpamMenuSection(entryKind: .domain, value: "firma.de")
        #expect(section.request(.trust) == SpamMenuRequest(kind: .trust, entryKind: .domain, value: "firma.de"))
    }

    /// Symbole je Aktion und Art.
    @Test func systemImages() {
        #expect(SpamMenuTexts.systemImage(SpamMenuRequest(kind: .block, entryKind: .address, value: "a@b.de")) == "person.crop.circle.badge.xmark")
        #expect(SpamMenuTexts.systemImage(SpamMenuRequest(kind: .trust, entryKind: .domain, value: "b.de")) == "globe")
    }
}
