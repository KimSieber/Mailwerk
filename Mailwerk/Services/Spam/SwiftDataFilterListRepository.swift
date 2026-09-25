//
//  SwiftDataFilterListRepository.swift
//  Mailwerk
//
//  Created by Kim Sieber on 24.09.26.
//


//
//  SwiftDataFilterListRepository.swift
//  Mailwerk
//
//  Listenpflege über SwiftData. Ist der Container mit CloudKit verbunden,
//  gleicht sich der Bestand von selbst über alle Geräte ab; ohne iCloud
//  arbeitet dieselbe Klasse rein lokal weiter.
//
//  Die Regeln stecken in `FilterListRules` und sind mit der
//  In-Memory-Variante identisch – nur das Speichern unterscheidet sich.
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataFilterListRepository: FilterListRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Lesen

    func entries() async throws -> [FilterEntryItem] {
        FilterListRules.merged(try storedItems())
    }

    func lists() async throws -> FilterLists {
        FilterListRules.lists(from: try storedItems())
    }

    // MARK: - Schreiben

    @discardableResult
    func add(_ value: String, kind: FilterEntryKind, to list: FilterList) async throws -> FilterEntryItem {
        guard let normalized = FilterListRules.normalize(value, kind: kind) else {
            throw FilterListError.invalidValue
        }

        if let existing = FilterListRules.merged(try storedItems())
            .first(where: { $0.kind == kind && $0.value == normalized }) {
            guard existing.list == list else {
                throw FilterListError.alreadyOnOtherList(existing.list)
            }
            return existing
        }

        let entry = FilterEntry(value: normalized, kind: kind, list: list)
        context.insert(entry)
        try context.save()
        return entry.item
    }

    func remove(_ id: UUID) async throws {
        let stored = try context.fetch(FetchDescriptor<FilterEntry>())
        guard let target = stored.first(where: { $0.id == id }) else { return }

        // Auch die zusammengeführten Doppelten entfernen, sonst taucht der
        // Eintrag nach dem nächsten Abgleich wieder auf.
        for entry in stored where entry.kind == target.kind && entry.value == target.value {
            context.delete(entry)
        }
        try context.save()
    }

    // MARK: - Intern

    private func storedItems() throws -> [FilterEntryItem] {
        try context.fetch(FetchDescriptor<FilterEntry>()).map(\.item)
    }
}