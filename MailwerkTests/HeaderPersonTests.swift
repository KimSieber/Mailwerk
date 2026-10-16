//
//  HeaderPersonTests.swift
//  MailwerkTests
//
//  Zweck: Tests für HeaderPerson – Personen im Mailkopf (Zerlegen,
//  Doppelte, „Antwort an“ nur bei Abweichung, Marke für die Suche).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct HeaderPersonTests {

    /// Name und Adresse werden getrennt; ohne Namen zeigt der Titel die Adresse.
    @Test func parsesNameAndAddress() {
        let named = HeaderPerson(raw: "Kim Sieber <kim@example.org>")
        #expect(named.name == "Kim Sieber")
        #expect(named.address == "kim@example.org")
        #expect(named.title == "Kim Sieber")
        let plain = HeaderPerson(raw: " anna@example.org ")
        #expect(plain.name == nil)
        #expect(plain.title == "anna@example.org")
    }

    /// Leere Einträge und doppelte Adressen entfallen, die Reihenfolge bleibt.
    @Test func listDropsEmptyAndDuplicates() {
        let people = HeaderPerson.list(["Ben <ben@example.org>", "", "anna@example.org", "BEN@example.org"])
        #expect(people.map(\.address) == ["ben@example.org", "anna@example.org"])
    }

    /// „Antwort an“ nur, wenn es vom Absender abweicht (ohne Groß-/Kleinschreibung).
    @Test func replyToOnlyWhenDifferent() {
        let sender = "IONITY <News@ionity.eu>"
        #expect(HeaderPerson.replyTo(["news@ionity.eu"], sender: sender).isEmpty)
        #expect(HeaderPerson.replyTo([], sender: sender).isEmpty)
        #expect(HeaderPerson.replyTo(["no-reply@ionity.eu"], sender: sender).map(\.address) == ["no-reply@ionity.eu"])
    }

    /// Die Marke für die Suche trägt die Adresse in Kleinschreibung.
    @Test func searchPersonUsesLowercasedAddress() {
        let person = HeaderPerson(raw: "Anna <Anna@Example.org>")
        #expect(person.searchPerson == SearchPerson(name: "Anna", address: "anna@example.org"))
    }
}
