//
//  CachingFilterListRepository.swift
//  Mailwerk
//
//  Zweck: Hält die Momentaufnahme der Filterlisten (`lists()`) im
//  Speicher, damit das Öffnen einer Mail nicht jedes Mal SwiftData liest
//  (v0.2.3d). Bisher kostete jede geöffnete Mail drei Lesevorgänge auf
//  dem Hauptthread: externe Inhalte, Spam-Angabe, Absenderbild.
//
//  Gültigkeit:
//  - Eigene Änderungen (`add`, `remove` – Blockieren, Vertrauen,
//    Listenpflege) verwerfen den Speicher sofort.
//  - Änderungen von anderen Geräten (CloudKit) kommen über
//    `refreshedLists()` an: Das Laden der Mailliste und der Filterlauf
//    lesen immer frisch und erneuern dabei den Speicher.
//  - Ein Lesevorgang, den eine Änderung überholt hat, wird nicht
//    gespeichert (Generationszähler).
//
//  Aufbau: Hülle um ein beliebiges FilterListRepository (Decorator); die
//  App legt sie einmal um die SwiftData-Variante (MailwerkApp). Alle
//  Nutzer teilen sich dieselbe Instanz. `entries()` (Listenpflege) geht
//  immer an die Quelle.
//
//  Abhängigkeiten: FilterListRepository, FilterLists, FilterEntryItem.
//

import Foundation

/// Filterlisten mit Momentaufnahme im Speicher.
@MainActor
final class CachingFilterListRepository: FilterListRepository {

    /// Eigentliche Quelle (SwiftData bzw. im Test die Variante im Speicher).
    private let base: any FilterListRepository
    /// Gespeicherte Momentaufnahme; `nil` = beim nächsten Lesen neu holen.
    private var cached: FilterLists?
    /// Zählt Änderungen; ein Lesevorgang wird nur gespeichert, wenn sich
    /// der Zähler währenddessen nicht verändert hat.
    private var generation = 0

    /// Legt die Hülle an.
    ///
    /// - Parameter base: Eigentliche Quelle der Filterlisten.
    init(wrapping base: any FilterListRepository) {
        self.base = base
    }

    // MARK: - Lesen

    /// Alle Einträge – immer aus der Quelle (Listenpflege).
    ///
    /// - Returns: Einträge.
    /// - Throws: Fehler beim Lesen.
    func entries() async throws -> [FilterEntryItem] {
        try await base.entries()
    }

    /// Momentaufnahme – aus dem Speicher, sonst aus der Quelle.
    ///
    /// Verarbeitung: Fehlt die Momentaufnahme, wird sie gelesen und
    /// gespeichert – außer eine Änderung kam währenddessen dazwischen.
    ///
    /// - Returns: Listen als Mengen.
    /// - Throws: Fehler beim Lesen der Quelle.
    func lists() async throws -> FilterLists {
        if let cached { return cached }
        let started = generation
        let fresh = try await base.lists()
        if started == generation { cached = fresh }
        return fresh
    }

    /// Momentaufnahme frisch aus der Quelle; erneuert den Speicher.
    ///
    /// Verarbeitung: Für Stellen, an denen Änderungen anderer Geräte
    /// (CloudKit) ankommen sollen – Laden der Mailliste, Filterlauf.
    ///
    /// - Returns: Listen als Mengen.
    /// - Throws: Fehler beim Lesen der Quelle.
    func refreshedLists() async throws -> FilterLists {
        invalidate()
        return try await lists()
    }

    // MARK: - Schreiben

    /// Legt einen Eintrag an und verwirft den Speicher – auch bei Fehler,
    /// damit kein unsicherer Stand stehen bleibt.
    ///
    /// - Parameters:
    ///   - value: Eingabe.
    ///   - kind: Adresse oder Domain.
    ///   - list: Ziel-Liste.
    /// - Returns: Angelegter oder vorhandener Eintrag.
    /// - Throws: Fehler der Quelle.
    @discardableResult
    func add(_ value: String, kind: FilterEntryKind, to list: FilterList) async throws -> FilterEntryItem {
        defer { invalidate() }
        return try await base.add(value, kind: kind, to: list)
    }

    /// Entfernt einen Eintrag und verwirft den Speicher.
    ///
    /// - Parameter id: Kennung des Eintrags.
    /// - Throws: Fehler der Quelle.
    func remove(_ id: UUID) async throws {
        defer { invalidate() }
        try await base.remove(id)
    }

    // MARK: - Intern

    /// Verwirft die Momentaufnahme und überholt laufende Lesevorgänge.
    private func invalidate() {
        generation += 1
        cached = nil
    }
}
