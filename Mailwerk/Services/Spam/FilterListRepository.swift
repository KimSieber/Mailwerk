//
//  FilterListRepository.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 24.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Zugriff auf die Black- und Whitelist. Einzige Stelle, die den
//  Speicherort kennt – heute iCloud (CloudKit), später vielleicht eine
//  eigene API. Enthält das Protokoll und eine Variante im Speicher für
//  Tests und Vorschauen.
//
//  Main-Actor-gebunden, weil SwiftData seinen Kontext an einen Actor
//  bindet. Der Filterlauf holt sich einmal je Durchlauf die Momentaufnahme
//  `lists()` und rechnet damit außerhalb des Main-Actors weiter.
//
//  Abgrenzung: SwiftData-Variante → SwiftDataFilterListRepository;
//  Kopie im Speicher → CachingFilterListRepository; gemeinsame Regeln →
//  FilterListRules.
//
//  Abhängigkeiten: Foundation, FilterEntryItem, FilterLists, FilterListRules.
//

import Foundation

/// Zugriff auf die Filterlisten, unabhängig vom Speicherort.
@MainActor
protocol FilterListRepository: AnyObject {

    /// Alle Einträge, sortiert nach Liste und darin nach Wert.
    ///
    /// - Returns: Zusammengeführte Einträge.
    /// - Throws: Fehler beim Lesen.
    func entries() async throws -> [FilterEntryItem]

    /// Momentaufnahme für den Classifier.
    ///
    /// - Returns: Listen als Mengen.
    /// - Throws: Fehler beim Lesen.
    func lists() async throws -> FilterLists

    /// Legt einen Eintrag an. Der Wert wird normalisiert.
    ///
    /// Verarbeitung: Steht er schon auf derselben Liste, wird der vorhandene
    /// Eintrag geliefert; steht er auf der anderen Liste, wird abgelehnt.
    ///
    /// - Parameters:
    ///   - value: Eingabe.
    ///   - kind: Adresse oder Domain.
    ///   - list: Ziel-Liste.
    /// - Returns: Angelegter oder vorhandener Eintrag.
    /// - Throws: `FilterListError.invalidValue`, `.alreadyOnOtherList`, Speicherfehler.
    @discardableResult
    func add(_ value: String, kind: FilterEntryKind, to list: FilterList) async throws -> FilterEntryItem

    /// Entfernt einen Eintrag. Unbekannte Kennungen werden übergangen.
    ///
    /// - Parameter id: Kennung des Eintrags.
    /// - Throws: Speicherfehler.
    func remove(_ id: UUID) async throws

    /// Momentaufnahme frisch aus dem Speicherort – auch wenn eine Hülle
    /// (CachingFilterListRepository) eine Kopie im Speicher hält. Für
    /// Stellen, an denen Änderungen anderer Geräte ankommen sollen.
    ///
    /// - Returns: Listen als Mengen.
    /// - Throws: Fehler beim Lesen.
    func refreshedLists() async throws -> FilterLists
}

extension FilterListRepository {
    /// Ohne Kopie im Speicher ist jede Momentaufnahme frisch.
    ///
    /// - Returns: Listen als Mengen (`lists()`).
    /// - Throws: Fehler beim Lesen.
    func refreshedLists() async throws -> FilterLists {
        try await lists()
    }
}

/// Implementierung für Tests und Vorschauen. Hält alles im Speicher.
@MainActor
final class InMemoryFilterListRepository: FilterListRepository {

    /// Gespeicherte Einträge, auch Doppelte.
    private var storage: [FilterEntryItem]

    /// Legt die Variante mit Startinhalt an.
    ///
    /// - Parameter entries: Startinhalt.
    init(entries: [FilterEntryItem] = []) {
        self.storage = entries
    }

    /// Alle Einträge, zusammengeführt und sortiert.
    ///
    /// - Returns: Einträge.
    /// - Throws: Nie; `throws` verlangt das Protokoll.
    func entries() async throws -> [FilterEntryItem] {
        FilterListRules.merged(storage)
    }

    /// Momentaufnahme für den Classifier.
    ///
    /// - Returns: Listen als Mengen.
    /// - Throws: Nie; `throws` verlangt das Protokoll.
    func lists() async throws -> FilterLists {
        FilterListRules.lists(from: storage)
    }

    /// Legt einen Eintrag an (siehe Protokoll).
    ///
    /// - Parameters:
    ///   - value: Eingabe.
    ///   - kind: Adresse oder Domain.
    ///   - list: Ziel-Liste.
    /// - Returns: Angelegter oder vorhandener Eintrag.
    /// - Throws: `FilterListError`.
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

    /// Entfernt einen Eintrag samt seiner zusammengeführten Doppelten.
    ///
    /// - Parameter id: Kennung des Eintrags.
    /// - Throws: Nie; `throws` verlangt das Protokoll.
    func remove(_ id: UUID) async throws {
        guard let target = storage.first(where: { $0.id == id }) else { return }
        // Auch die zusammengeführten Doppelten entfernen, sonst taucht der
        // Eintrag nach dem nächsten Abgleich wieder auf.
        storage.removeAll { $0.kind == target.kind && $0.value == target.value }
    }
}
