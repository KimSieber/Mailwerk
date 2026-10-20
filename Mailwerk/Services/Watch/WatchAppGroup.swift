//
//  WatchAppGroup.swift
//  Mailwerk
//
//  Zweck: Gemeinsamer Speicherort der Watch-App und ihrer Komplikation
//  (App Group) sowie die kleine Datei mit der Zahl der ungelesenen Mails,
//  die die Komplikation liest.
//
//  App Group: Die Kennung wird aus der Bundle-ID abgeleitet, damit Watch-App
//  und Komplikation ohne eigene Info.plist-Einträge dieselbe finden –
//  `de.sieber-bw.Mailwerk.watchkitapp` und deren Erweiterungen ergeben
//  `group.de.sieber-bw.Mailwerk`, die Dev-Variante mit `.dev` entsprechend
//  `group.de.sieber-bw.Mailwerk.dev`. Das ist dieselbe Gruppe wie auf dem
//  iPhone; die Geräte teilen dadurch aber nichts – jede Uhr und jedes
//  iPhone hat ihren eigenen Speicher.
//
//  Abgrenzung: Mails und Inhalte → WatchStore; Anzeige → MailwerkUnreadWidget.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Speicherort der Watch-App und ihrer Komplikation.
nonisolated enum WatchAppGroup {

    /// Teil der Bundle-ID, ab dem Watch-App und Komplikation beginnen.
    static let watchMarker = ".watchkitapp"

    /// Kennung der App Group zu einer Bundle-ID.
    ///
    /// Verarbeitung: Alles vor `.watchkitapp` ist die Bundle-ID der
    /// iPhone-App; davor kommt `group.`.
    ///
    /// - Parameter bundleID: Bundle-ID der Watch-App oder der Komplikation.
    /// - Returns: Kennung oder `nil`, wenn die Bundle-ID nicht passt.
    static func identifier(forBundleID bundleID: String) -> String? {
        guard let range = bundleID.range(of: watchMarker) else { return nil }
        let base = bundleID[..<range.lowerBound]
        guard !base.isEmpty else { return nil }
        return "group." + base
    }

    /// Ordner im gemeinsamen Speicher; ohne App Group der eigene
    /// Programmordner (dann sieht die Komplikation nichts).
    ///
    /// - Returns: Ordner `Mailwerk` im gemeinsamen Speicher.
    static func directory() -> URL {
        let fileManager = FileManager.default
        let base: URL
        if let id = identifier(forBundleID: Bundle.main.bundleIdentifier ?? ""),
           let shared = fileManager.containerURL(forSecurityApplicationGroupIdentifier: id) {
            base = shared
        } else {
            base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
        let directory = base.appendingPathComponent("Mailwerk", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// Zahl der ungelesenen Mails für die Komplikation.
nonisolated struct WatchBadge: Codable, Equatable, Sendable {
    /// Ungelesene Mails in den Posteingängen.
    let unread: Int
    /// Stand der Daten (letzte Lieferung des iPhones); `nil` = noch keine.
    let updatedAt: Date?

    /// Kein Stand.
    static let empty = WatchBadge(unread: 0, updatedAt: nil)

    /// Dateiname im gemeinsamen Speicher.
    static let fileName = "badge.plist"

    /// Liest die Zahl aus dem gemeinsamen Speicher.
    ///
    /// - Parameter directory: Ordner (Standard: App Group).
    /// - Returns: Gespeicherter Stand, sonst `empty`.
    static func load(from directory: URL = WatchAppGroup.directory()) -> WatchBadge {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let badge = try? PropertyListDecoder().decode(WatchBadge.self, from: data) else {
            return .empty
        }
        return badge
    }

    /// Schreibt die Zahl in den gemeinsamen Speicher.
    ///
    /// - Parameter directory: Ordner (Standard: App Group).
    /// - Returns: `true`, wenn sich der gespeicherte Wert geändert hat.
    @discardableResult
    func save(to directory: URL = WatchAppGroup.directory()) -> Bool {
        guard Self.load(from: directory) != self,
              let data = try? PropertyListEncoder().encode(self) else { return false }
        let url = directory.appendingPathComponent(Self.fileName)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
