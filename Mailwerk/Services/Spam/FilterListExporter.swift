//
//  FilterListExporter.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 24.09.2026
//  Geändert: 18.10.2026
//
//  Zweck: Gibt eine Liste als Text aus – eine Angabe je Zeile, Domains in
//  der Schreibweise `*firma.de` (Domain samt Subdomains). So verstehen es
//  das manitu-Portal und andere Blacklists, sodass sich eine Liste dort
//  übernehmen lässt.
//
//  Reine Logik, deshalb `nonisolated`.
//
//  Abgrenzung: Teilen der Datei → FilterListView.
//
//  Abhängigkeiten: Foundation, FilterEntryItem, FilterDomain.
//

import Foundation

/// Textausgabe der Filterlisten.
nonisolated enum FilterListExporter {

    /// Eine Zeile je Eintrag, Adressen zuerst, dann Domains – innerhalb
    /// beider Gruppen alphabetisch.
    ///
    /// - Parameter entries: Einträge einer Liste.
    /// - Returns: Text mit einer Angabe je Zeile.
    static func text(for entries: [FilterEntryItem]) -> String {
        entries
            .sorted { lhs, rhs in
                lhs.kind == rhs.kind
                    ? lhs.value < rhs.value
                    : lhs.kind == .address
            }
            .map(line(for:))
            .joined(separator: "\n")
    }

    /// Dateiname für den Export, z. B. "Mailwerk-Blacklist.txt".
    ///
    /// - Parameter list: Liste.
    /// - Returns: Dateiname.
    static func filename(for list: FilterList) -> String {
        list == .white ? "Mailwerk-Whitelist.txt" : "Mailwerk-Blacklist.txt"
    }

    /// Schreibt die Liste als Textdatei ins Temp-Verzeichnis.
    ///
    /// Verarbeitung: Nur mit einer Datei bietet das Teilen-Menü das Versenden
    /// per Mail mit Anhang an – ein reiner Text landet dort nur im
    /// Nachrichtentext. Eine vorhandene Datei wird ersetzt.
    ///
    /// - Parameters:
    ///   - entries: Einträge der Liste.
    ///   - list: Liste (bestimmt den Dateinamen).
    /// - Returns: Adresse der Datei.
    /// - Throws: Fehler beim Anlegen oder Schreiben.
    static func writeTemporaryFile(
        for entries: [FilterEntryItem],
        list: FilterList
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mailwerk-Listen", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(filename(for: list))
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try Data(text(for: entries).utf8).write(to: fileURL)
        return fileURL
    }

    /// Zeile eines Eintrags; Domains als `*domain`.
    ///
    /// - Parameter entry: Eintrag.
    /// - Returns: Zeile.
    private static func line(for entry: FilterEntryItem) -> String {
        FilterDomain.display(entry.value, kind: entry.kind)
    }
}
