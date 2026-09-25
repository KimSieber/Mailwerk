//
//  FilterList.swift
//  Mailwerk
//
//  Created by Kim Sieber on 24.09.26.
//


//
//  FilterEntry.swift
//  Mailwerk
//
//  Datenmodell der Black- und Whitelist. Ein Datensatz je Eintrag, damit
//  gleichzeitige Änderungen auf mehreren Geräten sich nicht gegenseitig
//  überschreiben.
//
//  CloudKit-Vorgaben für SwiftData: kein `@Attribute(.unique)`, jede
//  Eigenschaft mit Standardwert. Doppelte Einträge werden deshalb beim
//  Lesen zusammengeführt statt beim Schreiben verhindert.
//

import Foundation
import SwiftData

/// Auf welcher der beiden Listen ein Eintrag steht.
nonisolated enum FilterList: String, CaseIterable, Sendable {
    case white
    case black

    var other: FilterList { self == .white ? .black : .white }
}

/// Art des Eintrags. Die ganze Adresse ist spezifischer als die Domain.
nonisolated enum FilterEntryKind: String, CaseIterable, Sendable {
    case address
    case domain
}

/// Ein Listeneintrag als Wert – für Oberfläche, Tests und Export.
/// Entkoppelt den Rest der App vom Speichermodell.
nonisolated struct FilterEntryItem: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Bereits normalisiert: kleingeschrieben, ohne Anzeigename, ohne `*@`.
    let value: String
    let kind: FilterEntryKind
    let list: FilterList
    let createdAt: Date
}

/// Fehler bei der Listenpflege.
nonisolated enum FilterListError: Error, Equatable {
    /// Die Eingabe ist keine brauchbare Adresse bzw. Domain.
    case invalidValue
    /// Derselbe Eintrag steht schon auf der anderen Liste.
    case alreadyOnOtherList(FilterList)
}

/// Speichermodell. Alle Eigenschaften haben einen Standardwert,
/// sonst verweigert CloudKit die Synchronisierung.
@Model
final class FilterEntry {
    var id: UUID = UUID()
    var value: String = ""
    var kindRaw: String = FilterEntryKind.address.rawValue
    var listRaw: String = FilterList.black.rawValue
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        value: String,
        kind: FilterEntryKind,
        list: FilterList,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.value = value
        self.kindRaw = kind.rawValue
        self.listRaw = list.rawValue
        self.createdAt = createdAt
    }

    /// Unbekannte Werte (etwa aus einer neueren App-Version) gelten als
    /// Adresse bzw. Blacklist – die vorsichtigere Auslegung.
    var kind: FilterEntryKind { FilterEntryKind(rawValue: kindRaw) ?? .address }
    var list: FilterList { FilterList(rawValue: listRaw) ?? .black }

    var item: FilterEntryItem {
        FilterEntryItem(id: id, value: value, kind: kind, list: list, createdAt: createdAt)
    }
}