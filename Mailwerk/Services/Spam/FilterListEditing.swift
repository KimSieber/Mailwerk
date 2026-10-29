//
//  FilterListEditing.swift
//  Mailwerk
//
//  Zweck: Bearbeiten eines Eintrags der White- oder Blacklist, z. B. eine
//  Adresse mit Subdomain auf die reine Domain kürzen.
//  - `plan` prüft die Eingabe: unverändert, ungültig, mehrere Angaben oder
//    ein neuer Wert (Adresse bzw. Domain, wie beim Anlegen erkannt).
//  - `save` übernimmt den neuen Wert ohne Datenverlust: Erst wird er wie
//    beim Anlegen eingetragen und geprüft (nicht auf der anderen Liste,
//    gültig); nur wenn das gelingt, wird der alte Eintrag entfernt.
//    Scheitert die Prüfung, bleibt der alte Eintrag unverändert.
//
//  Ein unveränderter Eintrag wird nicht gespeichert – sonst würde „neu
//  anlegen, alten entfernen“ den Eintrag ganz löschen, weil beide denselben
//  Wert haben.
//
//  Abgrenzung: Zerlegen der Eingabe → FilterListInput; Speichern und
//  Konfliktprüfung → FilterListRepository; Oberfläche → FilterListView.
//
//  Abhängigkeiten: FilterListInput, FilterListRepository, FilterEntryItem,
//  FilterDomain.
//

import Foundation

/// Bearbeiten eines Listeneintrags.
nonisolated enum FilterListEditing {

    /// Ergebnis der Prüfung einer Eingabe.
    enum Plan: Equatable {
        /// Wert und Art wie bisher – nichts zu tun.
        case unchanged
        /// Keine brauchbare Adresse bzw. Domain.
        case invalid
        /// Mehr als eine Angabe; bearbeitet wird genau ein Eintrag.
        case multiple
        /// Neuer Wert für den Eintrag.
        case replace(FilterListInputEntry)
    }

    /// Text, mit dem das Bearbeiten-Feld vorbelegt wird: die Adresse bzw.
    /// die Domain in der Schreibweise der Liste (`*firma.de`).
    ///
    /// - Parameter item: Bisheriger Eintrag.
    /// - Returns: Vorbelegung.
    static func editText(for item: FilterEntryItem) -> String {
        FilterDomain.display(item.value, kind: item.kind)
    }

    /// Prüft die Eingabe für einen bearbeiteten Eintrag.
    ///
    /// Verarbeitung: Zerlegt die Eingabe wie beim Anlegen (Adresse oder
    /// Domain, auch `*firma.de`). Genau ein brauchbarer Wert wird
    /// übernommen; derselbe Wert wie bisher gilt als unverändert.
    ///
    /// - Parameters:
    ///   - item: Bisheriger Eintrag.
    ///   - input: Eingabe im Bearbeiten-Feld.
    /// - Returns: Was zu tun ist.
    static func plan(editing item: FilterEntryItem, input: String) -> Plan {
        let parsed = FilterListInput.parse(input)
        if parsed.entries.count + parsed.invalid.count > 1 {
            return .multiple
        }
        guard let entry = parsed.entries.first else { return .invalid }
        if entry.value == item.value && entry.kind == item.kind {
            return .unchanged
        }
        return .replace(entry)
    }

    /// Ersetzt einen Eintrag durch einen neuen Wert auf derselben Liste.
    ///
    /// Verarbeitung: Trägt den neuen Wert ein (mit der Prüfung des
    /// Repositorys) und entfernt erst danach den alten. Steht der neue Wert
    /// schon auf derselben Liste, entfällt nur der alte Eintrag.
    ///
    /// - Parameters:
    ///   - entry: Neuer Wert.
    ///   - item: Bisheriger Eintrag.
    ///   - repository: Speicher der Filterlisten.
    /// - Throws: `FilterListError.alreadyOnOtherList` bzw. `.invalidValue`
    ///   (der alte Eintrag bleibt dann erhalten) oder Speicherfehler.
    @MainActor
    static func save(
        _ entry: FilterListInputEntry,
        replacing item: FilterEntryItem,
        in repository: any FilterListRepository
    ) async throws {
        try await repository.add(entry.value, kind: entry.kind, to: item.list)
        try await repository.remove(item.id)
    }
}
