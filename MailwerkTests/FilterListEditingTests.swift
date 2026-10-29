//
//  FilterListEditingTests.swift
//  MailwerkTests
//
//  Zweck: Tests für FilterListEditing – Prüfung der Eingabe beim
//  Bearbeiten und Ersetzen ohne Datenverlust (gegen das
//  In-Memory-Repository).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FilterListEditingTests {

    /// Testhilfe: Eintrag mit Wert, Art und Liste.
    private func item(_ value: String, _ kind: FilterEntryKind, _ list: FilterList = .black) -> FilterEntryItem {
        FilterEntryItem(id: UUID(), value: value, kind: kind, list: list, createdAt: Date())
    }

    /// Derselbe Wert (auch anders geschrieben) gilt als unverändert.
    @Test func sameValueIsUnchanged() {
        #expect(FilterListEditing.plan(editing: item("news.firma.de", .domain), input: " News.Firma.DE ") == .unchanged)
    }

    /// Leere oder unbrauchbare Eingabe ist ungültig, mehrere Angaben werden abgelehnt.
    @Test func invalidAndMultipleInput() {
        let old = item("firma.de", .domain)
        #expect(FilterListEditing.plan(editing: old, input: "") == .invalid)
        #expect(FilterListEditing.plan(editing: old, input: "kein wert!") == .multiple)
        #expect(FilterListEditing.plan(editing: old, input: "a.de, b.de") == .multiple)
    }

    /// Kürzen auf die Domain – auch von einer Adresse aus.
    @Test func shorteningToDomainIsReplace() {
        #expect(FilterListEditing.plan(editing: item("news.firma.de", .domain), input: "firma.de")
            == .replace(FilterListInputEntry(value: "firma.de", kind: .domain)))
        #expect(FilterListEditing.plan(editing: item("max@firma.de", .address), input: "*@firma.de")
            == .replace(FilterListInputEntry(value: "firma.de", kind: .domain)))
    }

    /// Speichern ersetzt den alten Eintrag durch den neuen.
    @Test func saveReplacesEntry() async throws {
        let repo = InMemoryFilterListRepository()
        let old = try await repo.add("news.firma.de", kind: .domain, to: .black)
        try await FilterListEditing.save(FilterListInputEntry(value: "firma.de", kind: .domain), replacing: old, in: repo)
        #expect(try await repo.entries().map(\.value) == ["firma.de"])
    }

    /// Steht der neue Wert auf der anderen Liste, bleibt der alte Eintrag erhalten.
    @Test func conflictKeepsOldEntry() async throws {
        let repo = InMemoryFilterListRepository()
        let old = try await repo.add("news.firma.de", kind: .domain, to: .black)
        try await repo.add("firma.de", kind: .domain, to: .white)
        await #expect(throws: FilterListError.alreadyOnOtherList(.white)) {
            try await FilterListEditing.save(FilterListInputEntry(value: "firma.de", kind: .domain), replacing: old, in: repo)
        }
        let black = try await repo.entries().filter { $0.list == .black }
        #expect(black.map(\.value) == ["news.firma.de"])
    }

    /// Steht der neue Wert schon auf derselben Liste, bleibt er einmal stehen.
    @Test func existingValueOnSameListMerges() async throws {
        let repo = InMemoryFilterListRepository()
        let old = try await repo.add("news.firma.de", kind: .domain, to: .black)
        try await repo.add("firma.de", kind: .domain, to: .black)
        try await FilterListEditing.save(FilterListInputEntry(value: "firma.de", kind: .domain), replacing: old, in: repo)
        #expect(try await repo.entries().map(\.value) == ["firma.de"])
    }
}
