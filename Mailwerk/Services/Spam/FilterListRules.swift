//
//  FilterListRules.swift
//  Mailwerk
//
//  Created by Kim Sieber on 24.09.26.
//


//
//  FilterListRules.swift
//  Mailwerk
//
//  Gemeinsame Regeln beider Repository-Varianten: Normalisieren der
//  Eingabe, Zusammenführen doppelter Datensätze aus der Synchronisierung
//  und Aufbereiten der Momentaufnahme für den Classifier.
//
//  Reine Logik, deshalb `nonisolated`.
//

import Foundation

nonisolated enum FilterListRules {

    /// Normalisiert eine Eingabe passend zur Art des Eintrags.
    /// Liefert nil, wenn die Eingabe unbrauchbar ist.
    static func normalize(_ raw: String, kind: FilterEntryKind) -> String? {
        switch kind {
        case .address: FilterAddress(normalizing: raw)?.address
        case .domain: FilterAddress.normalizedDomain(raw)
        }
    }

    /// Führt Datensätze zusammen, die denselben Eintrag beschreiben, und
    /// sortiert das Ergebnis nach Liste (Whitelist zuerst) und Wert.
    ///
    /// Doppelte entstehen, wenn zwei Geräte denselben Eintrag anlegen,
    /// bevor sie sich abgeglichen haben – CloudKit kennt in SwiftData keine
    /// eindeutigen Attribute. Es gewinnt:
    /// 1. die Whitelist, falls derselbe Eintrag auf beiden Listen steht
    ///    (behalten ist die weniger folgenschwere Entscheidung),
    /// 2. darin der älteste Datensatz, bei gleichem Zeitpunkt die kleinere
    ///    Kennung – so wählt jedes Gerät denselben Gewinner.
    static func merged(_ items: [FilterEntryItem]) -> [FilterEntryItem] {
        let grouped = Dictionary(grouping: items) { Key(kind: $0.kind, value: $0.value) }

        let winners = grouped.values.compactMap { candidates -> FilterEntryItem? in
            let onWhitelist = candidates.filter { $0.list == .white }
            let relevant = onWhitelist.isEmpty ? candidates : onWhitelist
            return relevant.min { lhs, rhs in
                lhs.createdAt == rhs.createdAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.createdAt < rhs.createdAt
            }
        }

        return winners.sorted { lhs, rhs in
            lhs.list == rhs.list ? lhs.value < rhs.value : lhs.list == .white
        }
    }

    /// Baut die Momentaufnahme für den Classifier auf.
    static func lists(from items: [FilterEntryItem]) -> FilterLists {
        var lists = FilterLists.empty
        for item in merged(items) {
            switch (item.list, item.kind) {
            case (.white, .address): lists.whiteAddresses.insert(item.value)
            case (.white, .domain): lists.whiteDomains.insert(item.value)
            case (.black, .address): lists.blackAddresses.insert(item.value)
            case (.black, .domain): lists.blackDomains.insert(item.value)
            }
        }
        return lists
    }

    private struct Key: Hashable {
        let kind: FilterEntryKind
        let value: String
    }
}