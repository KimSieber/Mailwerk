//
//  SearchPersonTests.swift
//  MailwerkTests
//
//  Zweck: Tests für SearchPerson (Namensvorschläge) und SearchScope
//  (Suchbereich je Ansicht).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SearchPersonTests {

    /// Gleiche Adressen werden zusammengefasst, der bekannte Name bleibt; alphabetisch.
    @Test func collectMergesAndSorts() {
        let people = SearchPerson.collect(from: [
            "zoe@example.org",
            "Anna Muster <ANNA@example.org>",
            "anna@example.org",
            "Bernd <bernd@example.org>",
            "kein Adressformat",
        ])
        #expect(people.map(\.address) == ["anna@example.org", "bernd@example.org", "zoe@example.org"])
        #expect(people.first?.name == "Anna Muster")
        #expect(people.last?.title == "zoe@example.org")
    }

    /// Vorschläge treffen Name oder Adresse, ohne Groß-/Kleinschreibung und Akzente, ab dem ersten Zeichen.
    @Test func suggestionsMatchNameOrAddress() {
        let people = SearchPerson.collect(from: [
            "Jörg Meier <j.meier@firma.de>",
            "Anna Muster <anna@example.org>",
        ])
        #expect(SearchPerson.suggestions(from: people, matching: "jorg").map(\.address) == ["j.meier@firma.de"])
        #expect(SearchPerson.suggestions(from: people, matching: "FIRMA").count == 1)
        #expect(SearchPerson.suggestions(from: people, matching: "a").count == 2)
        #expect(SearchPerson.suggestions(from: people, matching: "  ").isEmpty)
    }

    /// Die Zahl der Vorschläge ist begrenzt.
    @Test func suggestionsAreLimited() {
        let raw = (1...30).map { "person\($0)@example.org" }
        let people = SearchPerson.collect(from: raw)
        #expect(SearchPerson.suggestions(from: people, matching: "person").count == SearchPerson.suggestionLimit)
    }

    /// Suchbereich je Ansicht; Serversuche nicht in der Kennzeichen-Sicht.
    @Test func scopeFollowsSelection() {
        let a = UUID()
        let b = UUID()
        let all = SearchScope.make(for: .allInboxes, fetchingAccountIDs: [a, b])
        #expect(all == SearchScope(accountIDs: [a, b], folder: "INBOX", flaggedOnly: false))
        #expect(all.allowsServerSearch)
        let flagged = SearchScope.make(for: .flagged, fetchingAccountIDs: [a])
        #expect(flagged.flaggedOnly && !flagged.allowsServerSearch)
        let folder = SearchScope.make(for: .folder(accountID: b, path: "Archiv", displayName: "Archiv"), fetchingAccountIDs: [a])
        #expect(folder == SearchScope(accountIDs: [b], folder: "Archiv", flaggedOnly: false))
    }
}
