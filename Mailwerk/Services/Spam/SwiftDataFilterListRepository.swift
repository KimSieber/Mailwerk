//
//  SwiftDataFilterListRepository.swift
//  Mailwerk
//
//  Zweck: Listenpflege über SwiftData. Ist der Container mit CloudKit
//  verbunden, gleicht sich der Bestand von selbst über alle Geräte ab;
//  ohne iCloud arbeitet dieselbe Klasse rein lokal weiter.
//
//  Die Regeln stecken in `FilterListRules` und sind mit der
//  In-Memory-Variante identisch – nur das Speichern unterscheidet sich.
//
//  Abgrenzung: Protokoll und Test-Variante → FilterListRepository.
//
//  Abhängigkeiten: Foundation, SwiftData, FilterEntry, FilterListRules.
//

import Foundation
import SwiftData

/// Filterlisten in SwiftData (mit CloudKit-Abgleich).
@MainActor
final class SwiftDataFilterListRepository: FilterListRepository {

    /// SwiftData-Kontext der App.
    private let context: ModelContext

    /// Legt das Repository an.
    ///
    /// - Parameter context: SwiftData-Kontext.
    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Lesen

    /// Alle Einträge, zusammengeführt und sortiert.
    ///
    /// - Returns: Einträge.
    /// - Throws: Fehler beim Lesen.
    func entries() async throws -> [FilterEntryItem] {
        FilterListRules.merged(try storedItems())
    }

    /// Momentaufnahme für den Classifier.
    ///
    /// - Returns: Listen als Mengen.
    /// - Throws: Fehler beim Lesen.
    func lists() async throws -> FilterLists {
        FilterListRules.lists(from: try storedItems())
    }

    // MARK: - Schreiben

    /// Legt einen Eintrag an (siehe Protokoll) und speichert.
    ///
    /// - Parameters:
    ///   - value: Eingabe.
    ///   - kind: Adresse oder Domain.
    ///   - list: Ziel-Liste.
    /// - Returns: Angelegter oder vorhandener Eintrag.
    /// - Throws: `FilterListError`, Speicherfehler.
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

    /// Entfernt einen Eintrag samt seiner zusammengeführten Doppelten.
    ///
    /// - Parameter id: Kennung des Eintrags.
    /// - Throws: Speicherfehler.
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

    /// Alle gespeicherten Datensätze als Wert-Typen, auch Doppelte.
    ///
    /// - Returns: Einträge.
    /// - Throws: Fehler beim Lesen.
    private func storedItems() throws -> [FilterEntryItem] {
        try context.fetch(FetchDescriptor<FilterEntry>()).map(\.item)
    }
}
