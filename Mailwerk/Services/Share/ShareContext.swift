//
//  ShareContext.swift
//  Mailwerk
//
//  Zweck: Abschrift der Daten, die die Teilen-Erweiterung zum Verfassen
//  braucht: Postfächer, Standard-Postfach und Signaturen. Die App schreibt
//  sie in den gemeinsamen Ordner der App Group (ShareContextPublisher),
//  die Erweiterung liest sie nur.
//
//  Warum eine Abschrift: Postfächer liegen im iCloud-Key-Value-Speicher,
//  Signaturen in SwiftData mit CloudKit-Abgleich. Ein zweiter Prozess mit
//  eigenem CloudKit-Abgleich auf denselben Daten wäre fehleranfällig und
//  beim ersten Start langsam. Die Abschrift ist dagegen sofort lesbar und
//  folgt jeder Änderung in der App.
//
//  Passwörter stehen nicht darin; die Erweiterung liest sie über die
//  gemeinsame Schlüsselbundgruppe (KeychainService).
//
//  Abgrenzung: Schreiben bei Änderungen → ShareContextPublisher; Lesen
//  in der Erweiterung → ShareRootView.
//
//  Abhängigkeiten: Foundation, MailAccount, SignatureItem, Log.
//

import Foundation
import os

/// Abschrift von Postfächern, Standard-Postfach und Signaturen für die
/// Teilen-Erweiterung.
struct ShareContext: Codable, Equatable {
    /// Aktuelle Fassung des Dateiformats.
    static let currentVersion = 1

    /// Fassung des Dateiformats; eine neuere Fassung liest die Erweiterung
    /// nicht (siehe `ShareContextFile.read`).
    var version: Int = ShareContext.currentVersion
    /// Eingerichtete Postfächer in ihrer Reihenfolge.
    var accounts: [MailAccount]
    /// Standard-Postfach für neue Mails; `nil` = keins.
    var defaultAccountID: UUID?
    /// Signaturen aller Postfächer, nach Postfach sortiert.
    var signatures: [SignatureItem]

    /// Legt eine Abschrift an.
    ///
    /// Verarbeitung: Die Signaturen werden nach Postfach sortiert, damit
    /// derselbe Stand immer dieselbe Datei ergibt und unveränderte Stände
    /// nicht neu geschrieben werden.
    ///
    /// - Parameters:
    ///   - accounts: Postfächer.
    ///   - defaultAccountID: Standard-Postfach.
    ///   - signatures: Signaturen (beliebige Reihenfolge).
    init(accounts: [MailAccount], defaultAccountID: UUID?, signatures: [SignatureItem]) {
        self.accounts = accounts
        self.defaultAccountID = defaultAccountID
        self.signatures = signatures.sorted { $0.accountID.uuidString < $1.accountID.uuidString }
    }
}

/// Ablage der Abschrift im gemeinsamen Ordner der App Group.
enum ShareContextFile {

    /// Kennung der App Group von App und Teilen-Erweiterung.
    static let appGroupID = "group.de.sieber-bw.Mailwerk"
    /// Dateiname der Abschrift.
    static let fileName = "ShareContext.json"

    /// Ergebnis beim Lesen der Abschrift.
    enum ReadResult: Equatable {
        /// Abschrift gelesen.
        case loaded(ShareContext)
        /// Keine Abschrift vorhanden (App noch nie mit dieser Funktion gestartet).
        case missing
        /// Abschrift nicht lesbar oder von einer neueren App-Fassung.
        case unreadable
    }

    /// Ort der Abschrift; `nil`, wenn die App Group nicht verfügbar ist
    /// (Capability fehlt).
    static var defaultURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Kodiert eine Abschrift.
    ///
    /// Verarbeitung: Sortierte Schlüssel, damit derselbe Stand byte-gleich
    /// kodiert wird (Vergleich vor dem Schreiben).
    ///
    /// - Parameter context: Abschrift.
    /// - Returns: JSON-Daten.
    /// - Throws: Kodierfehler.
    static func encode(_ context: ShareContext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(context)
    }

    /// Schreibt die Abschrift, sofern sie sich geändert hat.
    ///
    /// Verarbeitung: Gleicht die neuen Daten mit der vorhandenen Datei ab
    /// und schreibt nur bei einer Änderung – atomar, damit die Erweiterung
    /// nie eine halbe Datei liest. Auf iOS ist die Datei nach dem ersten
    /// Entsperren lesbar (wie die Passwörter im Schlüsselbund).
    ///
    /// - Parameters:
    ///   - context: Abschrift.
    ///   - url: Zieldatei.
    /// - Returns: `true`, wenn geschrieben wurde; `false` bei unverändertem Stand.
    /// - Throws: Kodier- oder Schreibfehler.
    @discardableResult
    static func write(_ context: ShareContext, to url: URL) throws -> Bool {
        let data = try encode(context)
        if let existing = try? Data(contentsOf: url), existing == data { return false }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        return true
    }

    /// Liest die Abschrift.
    ///
    /// Verarbeitung: Eine fehlende Datei ergibt `.missing`; eine nicht
    /// dekodierbare Datei oder eine neuere Fassung des Formats ergibt
    /// `.unreadable` (die Erweiterung bittet dann, Mailwerk zu öffnen).
    ///
    /// - Parameter url: Datei der Abschrift.
    /// - Returns: Ergebnis des Lesens.
    static func read(from url: URL) -> ReadResult {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        do {
            let context = try JSONDecoder().decode(ShareContext.self, from: data)
            guard context.version <= ShareContext.currentVersion else {
                Log.store.error("⚠️ Abschrift für das Teilen hat neuere Fassung \(context.version, privacy: .public)")
                return .unreadable
            }
            return .loaded(context)
        } catch {
            Log.store.error("⚠️ Abschrift für das Teilen nicht lesbar: \(String(describing: error), privacy: .public)")
            return .unreadable
        }
    }
}
