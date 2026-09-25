//
//  FilterListRepository.swift
//  Mailwerk
//
//  Zugriff auf die Black- und Whitelist. Einzige Stelle, die den
//  Speicherort kennt – heute iCloud (CloudKit), später vielleicht eine
//  eigene API.
//
//  Main-Actor-gebunden, weil SwiftData seinen Kontext an einen Actor
//  bindet. Der Filterlauf holt sich einmal je Durchlauf die Momentaufnahme
//  `lists()` und rechnet damit außerhalb des Main-Actors weiter.
//

import Foundation

@MainActor
protocol FilterListRepository: AnyObject {

    /// Alle Einträge, sortiert nach Liste und darin nach Wert.
    func entries() async throws -> [FilterEntryItem]

    /// Momentaufnahme für den Classifier.
    func lists() async throws -> FilterLists

    /// Legt einen Eintrag an. Der Wert wird normalisiert.
    /// - Steht er schon auf derselben Liste, wird der vorhandene Eintrag geliefert.
    /// - Steht er auf der anderen Liste, wirft die Methode `alreadyOnOtherList`.
    @discardableResult
    func add(_ value: String, kind: FilterEntryKind, to list: FilterList) async throws -> FilterEntryItem

    /// Entfernt einen Eintrag. Unbekannte Kennungen werden übergangen.
    func remove(_ id: UUID) async throws
}

/// Implementierung für Tests und Vorschauen. Hält alles im Speicher.
@MainActor
final class InMemoryFilterListRepository: FilterListRepository {

    private var storage: [FilterEntryItem]

    init(entries: [FilterEntryItem] = []) {
        self.storage = entries
    }

    func entries() async throws -> [FilterEntryItem] {
        FilterListRules.merged(storage)
    }

    func lists() async throws -> FilterLists {
        FilterListRules.lists(from: storage)
    }

    @discardableResult
    func add(_ value: String, kind: FilterEntryKind, to list: FilterList) async throws -> FilterEntryItem {
        guard let normalized = FilterListRules.normalize(value, kind: kind) else {
            throw FilterListError.invalidValue
        }

        if let existing = FilterListRules.merged(storage)
            .first(where: { $0.kind == kind && $0.value == normalized }) {
            guard existing.list == list else {
                throw FilterListError.alreadyOnOtherList(existing.list)
            }
            return existing
        }

        let item = FilterEntryItem(
            id: UUID(),
            value: normalized,
            kind: kind,
            list: list,
            createdAt: Date()
        )
        storage.append(item)
        return item
    }

    func remove(_ id: UUID) async throws {
        guard let target = storage.first(where: { $0.id == id }) else { return }
        // Auch die zusammengeführten Doppelten entfernen, sonst taucht der
        // Eintrag nach dem nächsten Abgleich wieder auf.
        storage.removeAll { $0.kind == target.kind && $0.value == target.value }
    }
}
