//
//  FilterEntry.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 24.09.2026
//  Geändert: 24.10.2026
//
//  Zweck: Datenmodell der Black- und Whitelist – Listen- und Eintragsart,
//  Wert-Typ für Oberfläche und Tests, Fehler der Listenpflege und das
//  SwiftData-Speichermodell. Ein Datensatz je Eintrag, damit gleichzeitige
//  Änderungen auf mehreren Geräten sich nicht gegenseitig überschreiben.
//
//  CloudKit-Vorgaben für SwiftData: kein `@Attribute(.unique)`, jede
//  Eigenschaft mit Standardwert. Doppelte Einträge werden deshalb beim
//  Lesen zusammengeführt statt beim Schreiben verhindert.
//
//  Abgrenzung: Lesen und Schreiben → SwiftDataFilterListRepository;
//  Zusammenführen → FilterListRules.
//
//  Abhängigkeiten: Foundation, SwiftData.
//

import Foundation
import SwiftData

/// Auf welcher der beiden Listen ein Eintrag steht.
nonisolated enum FilterList: String, CaseIterable, Sendable {
    /// Whitelist: vertrauenswürdige Absender.
    case white
    /// Blacklist: blockierte Absender.
    case black

    /// Die jeweils andere Liste.
    var other: FilterList { self == .white ? .black : .white }
}

/// Art des Eintrags. Die ganze Adresse ist spezifischer als die Domain.
nonisolated enum FilterEntryKind: String, CaseIterable, Codable, Sendable {
    /// Ganze Adresse.
    case address
    /// Ganze Domain.
    case domain
}

/// Ein Listeneintrag als Wert – für Oberfläche, Tests und Export.
/// Entkoppelt den Rest der App vom Speichermodell.
nonisolated struct FilterEntryItem: Identifiable, Hashable, Sendable {
    /// Kennung des Eintrags.
    let id: UUID
    /// Bereits normalisiert: kleingeschrieben, ohne Anzeigename, ohne `*@`.
    let value: String
    /// Adresse oder Domain.
    let kind: FilterEntryKind
    /// Liste, auf der der Eintrag steht.
    let list: FilterList
    /// Zeitpunkt des Eintrags.
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
    /// Kennung des Eintrags.
    var id: UUID = UUID()
    /// Normalisierter Wert.
    var value: String = ""
    /// Eintragsart als Text (für SwiftData/CloudKit).
    var kindRaw: String = FilterEntryKind.address.rawValue
    /// Liste als Text (für SwiftData/CloudKit).
    var listRaw: String = FilterList.black.rawValue
    /// Zeitpunkt des Eintrags.
    var createdAt: Date = Date()

    /// Legt einen Eintrag an.
    ///
    /// - Parameters:
    ///   - id: Kennung.
    ///   - value: Normalisierter Wert.
    ///   - kind: Adresse oder Domain.
    ///   - list: White- oder Blacklist.
    ///   - createdAt: Zeitpunkt des Eintrags.
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
    /// Liste; unbekannte Werte gelten als Blacklist.
    var list: FilterList { FilterList(rawValue: listRaw) ?? .black }

    /// Eintrag als Wert-Typ.
    var item: FilterEntryItem {
        FilterEntryItem(id: id, value: value, kind: kind, list: list, createdAt: createdAt)
    }
}
