//
//  CachingFilterListRepositoryTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Kopie der Filterlisten im Speicher
//  (CachingFilterListRepository): einmal lesen, Verwerfen nach eigenen
//  Änderungen, frisches Lesen über `refreshedLists`.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für CachingFilterListRepository.
@MainActor
struct CachingFilterListRepositoryTests {

    /// Testhilfe: zählt, wie oft die Quelle gelesen wird.
    @MainActor
    private final class CountingRepository: FilterListRepository {
        /// Eigentlicher Speicher.
        let inner = InMemoryFilterListRepository()
        /// Anzahl der Aufrufe von `lists()`.
        private(set) var listReads = 0

        func entries() async throws -> [FilterEntryItem] { try await inner.entries() }
        func lists() async throws -> FilterLists {
            listReads += 1
            return try await inner.lists()
        }
        @discardableResult
        func add(_ value: String, kind: FilterEntryKind, to list: FilterList) async throws -> FilterEntryItem {
            try await inner.add(value, kind: kind, to: list)
        }
        func remove(_ id: UUID) async throws { try await inner.remove(id) }
    }

    /// Wiederholtes Lesen liest die Quelle nur einmal.
    @Test("Wiederholtes Lesen liest die Quelle nur einmal")
    func readsSourceOnce() async throws {
        let source = CountingRepository()
        let repo = CachingFilterListRepository(wrapping: source)
        _ = try await repo.lists()
        _ = try await repo.lists()
        _ = try await repo.lists()
        #expect(source.listReads == 1)
    }

    /// Hinzufügen verwirft die Kopie; der neue Eintrag ist sofort wirksam.
    @Test("Hinzufügen verwirft die Kopie")
    func addInvalidates() async throws {
        let source = CountingRepository()
        let repo = CachingFilterListRepository(wrapping: source)
        _ = try await repo.lists()
        try await repo.add("spam@example.org", kind: .address, to: .black)
        let lists = try await repo.lists()
        #expect(source.listReads == 2)
        #expect(lists != .empty)
    }

    /// Entfernen verwirft die Kopie; der Eintrag ist sofort weg.
    @Test("Entfernen verwirft die Kopie")
    func removeInvalidates() async throws {
        let source = CountingRepository()
        let repo = CachingFilterListRepository(wrapping: source)
        let entry = try await repo.add("spam@example.org", kind: .address, to: .black)
        #expect(try await repo.lists() != .empty)
        try await repo.remove(entry.id)
        #expect(try await repo.lists() == .empty)
        #expect(source.listReads == 2)
    }

    /// `refreshedLists` liest immer frisch und erneuert die Kopie.
    @Test("refreshedLists liest frisch und erneuert die Kopie")
    func refreshedListsReadsFresh() async throws {
        let source = CountingRepository()
        let repo = CachingFilterListRepository(wrapping: source)
        _ = try await repo.lists()
        // Änderung an der Quelle vorbei (wie von einem anderen Gerät).
        try await source.inner.add("neu@example.org", kind: .address, to: .white)
        #expect(try await repo.lists() == .empty)          // noch die alte Kopie
        #expect(try await repo.refreshedLists() != .empty) // frisch gelesen
        #expect(try await repo.lists() != .empty)          // Kopie erneuert
        #expect(source.listReads == 2)
    }
}
