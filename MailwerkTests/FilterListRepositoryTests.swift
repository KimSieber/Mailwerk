//
//  FilterListRepositoryTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Listenpflege gegen die In-Memory-Implementierung.
//  Die CloudKit-Variante nutzt dieselben Regeln (FilterListRules).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für die In-Memory-Listenpflege.
@MainActor
struct FilterListRepositoryTests {

    /// Testhilfe: leeres Repository.
    private func repository() -> InMemoryFilterListRepository {
        InMemoryFilterListRepository()
    }

    // MARK: - Leerer Zustand

    /// Ein leeres Repository liefert keine Einträge.
    @Test("Ein leeres Repository liefert keine Einträge")
    func startsEmpty() async throws {
        let repo = repository()
        #expect(try await repo.entries().isEmpty)
        #expect(try await repo.lists() == .empty)
    }

    // MARK: - Anlegen und Normalisieren

    /// Eine Adresse wird normalisiert gespeichert.
    @Test("Eine Adresse wird normalisiert gespeichert")
    func addsNormalizedAddress() async throws {
        let repo = repository()
        let entry = try await repo.add("  Anna@Firma.DE ", kind: .address, to: .white)

        #expect(entry.value == "anna@firma.de")
        #expect(entry.kind == .address)
        #expect(entry.list == .white)

        let lists = try await repo.lists()
        #expect(lists.whiteAddresses == ["anna@firma.de"])
        #expect(lists.whiteDomains.isEmpty)
        #expect(lists.blackAddresses.isEmpty)
    }

    /// Eine Domain wird normalisiert gespeichert, auch in der Portal-Schreibweise.
    @Test("Eine Domain wird normalisiert gespeichert, auch in der Portal-Schreibweise")
    func addsNormalizedDomain() async throws {
        let repo = repository()
        let entry = try await repo.add("*@Firma.DE", kind: .domain, to: .black)

        #expect(entry.value == "firma.de")
        #expect(entry.kind == .domain)

        let lists = try await repo.lists()
        #expect(lists.blackDomains == ["firma.de"])
        #expect(lists.blackAddresses.isEmpty)
    }

    /// Unbrauchbare Eingaben werden abgelehnt.
    @Test("Unbrauchbare Eingaben werden abgelehnt",
          arguments: [("firma.de", FilterEntryKind.address), ("anna@firma.de", .domain),
                      ("", .address), ("  ", .domain), ("anna@firma", .address)])
    func rejectsInvalidValue(value: String, kind: FilterEntryKind) async throws {
        let repo = repository()
        await #expect(throws: FilterListError.invalidValue) {
            try await repo.add(value, kind: kind, to: .black)
        }
        #expect(try await repo.entries().isEmpty)
    }

    // MARK: - Doppelte Einträge

    /// Derselbe Eintrag auf derselben Liste bleibt ein Eintrag.
    @Test("Derselbe Eintrag auf derselben Liste bleibt ein Eintrag")
    func duplicateOnSameList() async throws {
        let repo = repository()
        let first = try await repo.add("anna@firma.de", kind: .address, to: .black)
        let second = try await repo.add("ANNA@firma.de", kind: .address, to: .black)

        #expect(first.id == second.id)
        #expect(try await repo.entries().count == 1)
    }

    /// Derselbe Eintrag auf der anderen Liste wird abgelehnt.
    @Test("Derselbe Eintrag auf der anderen Liste wird abgelehnt")
    func duplicateOnOtherList() async throws {
        let repo = repository()
        try await repo.add("anna@firma.de", kind: .address, to: .white)

        await #expect(throws: FilterListError.alreadyOnOtherList(.white)) {
            try await repo.add("anna@firma.de", kind: .address, to: .black)
        }

        let entries = try await repo.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.list == .white)
    }

    /// Adresse und Domain sind verschiedene Einträge und dürfen sich widersprechen.
    @Test("Adresse und Domain sind verschiedene Einträge und dürfen sich widersprechen")
    func addressAndDomainCoexist() async throws {
        let repo = repository()
        try await repo.add("rechnung@firma.de", kind: .address, to: .white)
        try await repo.add("firma.de", kind: .domain, to: .black)

        let lists = try await repo.lists()
        #expect(lists.whiteAddresses == ["rechnung@firma.de"])
        #expect(lists.blackDomains == ["firma.de"])
    }

    // MARK: - Entfernen

    /// Ein Eintrag lässt sich entfernen.
    @Test("Ein Eintrag lässt sich entfernen")
    func removesEntry() async throws {
        let repo = repository()
        let entry = try await repo.add("anna@firma.de", kind: .address, to: .black)
        try await repo.add("firma.de", kind: .domain, to: .black)

        try await repo.remove(entry.id)

        let entries = try await repo.entries()
        #expect(entries.map(\.value) == ["firma.de"])
        #expect(try await repo.lists().blackAddresses.isEmpty)
    }

    /// Eine unbekannte Kennung wird übergangen.
    @Test("Eine unbekannte Kennung wird übergangen")
    func removesUnknownID() async throws {
        let repo = repository()
        try await repo.add("anna@firma.de", kind: .address, to: .black)
        try await repo.remove(UUID())
        #expect(try await repo.entries().count == 1)
    }

    /// Nach dem Entfernen ist derselbe Eintrag wieder anlegbar.
    @Test("Nach dem Entfernen ist derselbe Eintrag wieder anlegbar")
    func reAddAfterRemove() async throws {
        let repo = repository()
        let entry = try await repo.add("anna@firma.de", kind: .address, to: .white)
        try await repo.remove(entry.id)
        let again = try await repo.add("anna@firma.de", kind: .address, to: .black)

        #expect(again.list == .black)
        #expect(try await repo.entries().count == 1)
    }

    // MARK: - Reihenfolge und Zusammenführung

    /// Einträge kommen nach Liste und Wert sortiert zurück.
    @Test("Einträge kommen nach Liste und Wert sortiert zurück")
    func sortedEntries() async throws {
        let repo = repository()
        try await repo.add("zulu.de", kind: .domain, to: .black)
        try await repo.add("alpha@firma.de", kind: .address, to: .black)
        try await repo.add("omega.de", kind: .domain, to: .white)
        try await repo.add("beta@firma.de", kind: .address, to: .white)

        let entries = try await repo.entries()
        #expect(entries.map(\.list) == [.white, .white, .black, .black])
        #expect(entries.map(\.value) == ["beta@firma.de", "omega.de", "alpha@firma.de", "zulu.de"])
    }

    /// Doppelte Datensätze aus der Synchronisierung werden beim Lesen zusammengeführt.
    @Test("Doppelte Datensätze aus der Synchronisierung werden beim Lesen zusammengeführt")
    func mergesDuplicatesFromSync() async throws {
        let value = "anna@firma.de"
        let older = FilterEntryItem(id: UUID(), value: value, kind: .address, list: .black,
                                    createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = FilterEntryItem(id: UUID(), value: value, kind: .address, list: .black,
                                    createdAt: Date(timeIntervalSince1970: 2_000))
        let repo = InMemoryFilterListRepository(entries: [newer, older])

        let entries = try await repo.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.id == older.id, "Der älteste Datensatz gewinnt, damit alle Geräte dieselbe Kennung wählen")
        #expect(try await repo.lists().blackAddresses == [value])
    }
}
