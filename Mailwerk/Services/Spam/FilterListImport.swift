//
//  FilterListImport.swift
//  Mailwerk
//
//  Zweck: Bereitet den Import einer Textdatei in eine Filterliste vor –
//  Datei lesen, Einträge erkennen, schon Vorhandenes aussortieren – und
//  fasst das Ergebnis für die Meldung zusammen.
//
//  Format: dasselbe wie beim Export (FilterListExporter) und im
//  manitu-Portal – eine Angabe je Zeile, Domains als `*firma.de`. Erkannt
//  wird mit derselben Zerlegung wie bei „Neuer Eintrag …“
//  (FilterListInput); damit gelten auch dieselben Regeln: Komma,
//  Semikolon und Leerzeichen trennen ebenfalls, `firma.de`, `*firma.de`,
//  `*.firma.de` und `*@firma.de` (ältere Exporte) werden zur Domain.
//
//  Ob ein Eintrag schon auf der anderen Liste steht, prüft erst das
//  Eintragen selbst (FilterListRepository) – genau wie bei der manuellen
//  Anlage.
//
//  Reine Logik, deshalb `nonisolated`.
//
//  Abgrenzung: Dateiauswahl, Rückfrage und Eintragen → FilterListView.
//
//  Abhängigkeiten: Foundation, FilterListInput, FilterEntryItem.
//

import Foundation

/// Vorbereitung und Ergebnis des Imports einer Filterliste.
nonisolated enum FilterListImport {

    /// Was aus einer Datei übernommen würde.
    struct Plan: Equatable {
        /// Neue Einträge in Dateireihenfolge.
        var entries: [FilterListInputEntry] = []
        /// Angaben, die schon auf dieser Liste stehen.
        var alreadyPresent: [String] = []
        /// Abschnitte, aus denen sich nichts Brauchbares lesen ließ.
        var invalid: [String] = []
    }

    /// Liest den Text einer Datei.
    ///
    /// Verarbeitung: Erst UTF-8 (ein vorangestelltes BOM entfällt), sonst
    /// Windows-1252 – so lassen sich auch ältere Exporte anderer Programme
    /// lesen.
    ///
    /// - Parameter data: Inhalt der Datei.
    /// - Returns: Text oder `nil`, wenn er sich nicht lesen lässt.
    static func text(from data: Data) -> String? {
        if var text = String(data: data, encoding: .utf8) {
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            return text
        }
        return String(data: data, encoding: .windowsCP1252)
    }

    /// Ermittelt, was aus einem Text übernommen würde.
    ///
    /// Verarbeitung: Zerlegt den Text wie „Neuer Eintrag …“ und sortiert
    /// Einträge aus, die mit gleicher Art schon auf dieser Liste stehen.
    ///
    /// - Parameters:
    ///   - text: Inhalt der Datei.
    ///   - existing: Einträge der Ziel-Liste.
    /// - Returns: Neue, vorhandene und unbrauchbare Angaben.
    static func plan(text: String, existing: [FilterEntryItem]) -> Plan {
        let parsed = FilterListInput.parse(text)
        let present = Set(existing.map { FilterListInputEntry(value: $0.value, kind: $0.kind) })
        var plan = Plan(invalid: parsed.invalid)
        for entry in parsed.entries {
            if present.contains(entry) {
                plan.alreadyPresent.append(entry.value)
            } else {
                plan.entries.append(entry)
            }
        }
        return plan
    }

    /// Text der Rückfrage vor dem Import.
    ///
    /// - Parameters:
    ///   - plan: Was übernommen würde.
    ///   - fileName: Name der gewählten Datei.
    /// - Returns: z. B. „„liste.txt“: 3 neue Einträge. 1 schon vorhanden. …“
    static func confirmationMessage(for plan: Plan, fileName: String) -> String {
        let count = plan.entries.count
        return "„\(fileName)“: \(count == 1 ? "1 neuer Eintrag" : "\(count) neue Einträge")."
            + (plan.alreadyPresent.isEmpty ? "" : " \(plan.alreadyPresent.count) schon vorhanden.")
            + " Jeder Eintrag wird wie bei „Neuer Eintrag …“ geprüft."
    }

    /// Ergebnis eines Imports.
    struct Outcome: Equatable {
        /// Anzahl übernommener Einträge.
        var added = 0
        /// Anzahl schon vorhandener Einträge.
        var alreadyPresent = 0
        /// Angaben, die schon auf der anderen Liste stehen.
        var conflicts: [String] = []
        /// Nicht verwertbare Angaben.
        var invalid: [String] = []
    }

    /// Fasst das Ergebnis eines Imports zusammen.
    ///
    /// Verarbeitung: Nennt die Anzahl der übernommenen und schon
    /// vorhandenen Einträge; abgelehnte (andere Liste) und unbrauchbare
    /// Angaben werden einzeln benannt, damit klar ist, was noch zu tun ist.
    ///
    /// - Parameters:
    ///   - outcome: Ergebnis des Imports.
    ///   - otherListName: Name der anderen Liste, z. B. „Whitelist“.
    /// - Returns: Text für die Meldung.
    static func summary(_ outcome: Outcome, otherListName: String) -> String {
        let added = outcome.added
        let alreadyPresent = outcome.alreadyPresent
        var parts = [added == 1 ? "1 Eintrag übernommen" : "\(added) Einträge übernommen"]
        if alreadyPresent > 0 {
            parts.append(alreadyPresent == 1 ? "1 Eintrag war schon vorhanden" : "\(alreadyPresent) Einträge waren schon vorhanden")
        }
        if !outcome.conflicts.isEmpty {
            parts.append("Nicht übernommen, weil bereits auf der \(otherListName): \(outcome.conflicts.joined(separator: ", "))")
        }
        if !outcome.invalid.isEmpty {
            parts.append("Nicht verwertbar: \(outcome.invalid.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }
}
