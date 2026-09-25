//
//  FilterListExporter.swift
//  Mailwerk
//
//  Gibt eine Liste als Text aus – eine Angabe je Zeile, Domains in der
//  Schreibweise `*@firma.de`. Genau dieses Format erwartet das
//  manitu-Portal, sodass sich eine Liste dort übernehmen lässt.
//
//  Reine Logik, deshalb `nonisolated`.
//

import Foundation

nonisolated enum FilterListExporter {

    /// Eine Zeile je Eintrag, Adressen zuerst, dann Domains – innerhalb
    /// beider Gruppen alphabetisch.
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
    static func filename(for list: FilterList) -> String {
        list == .white ? "Mailwerk-Whitelist.txt" : "Mailwerk-Blacklist.txt"
    }

    /// Schreibt die Liste als Textdatei ins Temp-Verzeichnis und liefert die
    /// Adresse. Nur mit einer Datei bietet das Teilen-Menü das Versenden per
    /// Mail mit Anhang an – ein reiner Text landet dort nur im Nachrichtentext.
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

    private static func line(for entry: FilterEntryItem) -> String {
        switch entry.kind {
        case .address: entry.value
        case .domain: "*@\(entry.value)"
        }
    }
}
