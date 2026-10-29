//
//  SignatureStore.swift
//  Mailwerk
//
//  Zweck: Zentrale Stelle für die Signaturen aller Postfächer. Hält den
//  aktuellen Stand für die Oberfläche bereit, speichert und entfernt
//  Signaturen und liest neu, sobald der iCloud-Abgleich Änderungen von
//  einem anderen Gerät übernommen hat.
//
//  Der Speicherort ist austauschbar (`SignatureStorage`): SwiftData mit
//  CloudKit in der App, eine Variante im Speicher für Tests und Vorschauen.
//  Die App legt den Store einmal an und reicht ihn über die Umgebung
//  (`.environment`) an die Ansichten weiter.
//
//  Abgrenzung: Speichermodell → AccountSignature; Regeln → SignatureRules;
//  Pflege-Seite → SignatureEditorView.
//
//  Abhängigkeiten: Foundation, Observation, Combine, SwiftData,
//  AccountSignature, SignatureRules, FilterListCloudEvents (meldet
//  übernommene iCloud-Änderungen des gemeinsamen Speichers), Log.
//

import Combine
import Foundation
import Observation
import SwiftData
import os

// MARK: - Speicherort

/// Lesen und Schreiben der Signaturen, unabhängig vom Speicherort.
@MainActor
protocol SignatureStorage: AnyObject {
    /// Alle gespeicherten Datensätze, auch doppelte.
    ///
    /// - Returns: Signaturen als Werte.
    /// - Throws: Fehler beim Lesen.
    func all() throws -> [SignatureItem]

    /// Speichert die Signatur eines Postfachs und entfernt Doppelte.
    ///
    /// - Parameter item: Signatur.
    /// - Throws: Fehler beim Speichern.
    func save(_ item: SignatureItem) throws

    /// Entfernt alle Datensätze eines Postfachs.
    ///
    /// - Parameter accountID: Kennung des Postfachs.
    /// - Throws: Fehler beim Speichern.
    func remove(accountID: UUID) throws
}

/// Signaturen in SwiftData (mit CloudKit-Abgleich).
@MainActor
final class SwiftDataSignatureStorage: SignatureStorage {
    /// SwiftData-Kontext der App.
    private let context: ModelContext

    /// Legt den Speicher an.
    ///
    /// - Parameter context: SwiftData-Kontext.
    init(context: ModelContext) {
        self.context = context
    }

    /// Alle Datensätze als Werte.
    ///
    /// - Returns: Signaturen.
    /// - Throws: Fehler beim Lesen.
    func all() throws -> [SignatureItem] {
        try context.fetch(FetchDescriptor<AccountSignature>()).map(\.item)
    }

    /// Speichert: aktualisiert den neuesten Datensatz des Postfachs, legt
    /// sonst einen an; weitere Datensätze desselben Postfachs werden
    /// gelöscht.
    ///
    /// - Parameter item: Signatur.
    /// - Throws: Fehler beim Speichern.
    func save(_ item: SignatureItem) throws {
        let existing = try records(for: item.accountID).sorted { $0.modifiedAt > $1.modifiedAt }
        if let first = existing.first {
            first.apply(item)
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
        } else {
            context.insert(AccountSignature(item))
        }
        try context.save()
    }

    /// Entfernt alle Datensätze eines Postfachs.
    ///
    /// - Parameter accountID: Kennung des Postfachs.
    /// - Throws: Fehler beim Speichern.
    func remove(accountID: UUID) throws {
        let existing = try records(for: accountID)
        guard !existing.isEmpty else { return }
        for record in existing { context.delete(record) }
        try context.save()
    }

    /// Datensätze eines Postfachs.
    ///
    /// - Parameter accountID: Kennung des Postfachs.
    /// - Returns: Datensätze (meist einer).
    /// - Throws: Fehler beim Lesen.
    private func records(for accountID: UUID) throws -> [AccountSignature] {
        try context.fetch(FetchDescriptor<AccountSignature>()).filter { $0.accountID == accountID }
    }
}

/// Signaturen im Speicher – für Tests und Vorschauen.
@MainActor
final class InMemorySignatureStorage: SignatureStorage {
    /// Gespeicherte Datensätze, auch doppelte.
    var items: [SignatureItem]

    /// Legt den Speicher mit Startinhalt an.
    ///
    /// - Parameter items: Startinhalt.
    init(items: [SignatureItem] = []) {
        self.items = items
    }

    /// Alle Datensätze.
    ///
    /// - Returns: Signaturen.
    func all() throws -> [SignatureItem] { items }

    /// Ersetzt alle Datensätze des Postfachs durch die Signatur.
    ///
    /// - Parameter item: Signatur.
    func save(_ item: SignatureItem) throws {
        items.removeAll { $0.accountID == item.accountID }
        items.append(item)
    }

    /// Entfernt alle Datensätze des Postfachs.
    ///
    /// - Parameter accountID: Kennung des Postfachs.
    func remove(accountID: UUID) throws {
        items.removeAll { $0.accountID == accountID }
    }
}

// MARK: - Store

/// Signaturen aller Postfächer für die Oberfläche.
@MainActor
@Observable
final class SignatureStore {
    /// Speicherort.
    private let storage: SignatureStorage
    /// Abo auf übernommene iCloud-Änderungen.
    @ObservationIgnored private var cloudSubscription: AnyCancellable?

    /// Aktueller Stand je Postfach (neuester Datensatz).
    private(set) var signatures: [UUID: SignatureItem] = [:]

    /// Legt den Store an und liest den Bestand.
    ///
    /// Verarbeitung: Übernimmt der iCloud-Abgleich Änderungen von einem
    /// anderen Gerät, wird neu gelesen; offene Ansichten folgen über
    /// Observation.
    ///
    /// - Parameters:
    ///   - storage: Speicherort.
    ///   - observesCloud: `false` in Tests – dann kein Abo auf iCloud-Meldungen.
    init(storage: SignatureStorage, observesCloud: Bool = true) {
        self.storage = storage
        reload()
        if observesCloud {
            cloudSubscription = FilterListCloudEvents.remoteChangesImported
                .sink { [weak self] _ in
                    // Die Meldung kommt laut FilterListCloudEvents auf dem Main-Thread.
                    MainActor.assumeIsolated { self?.reload() }
                }
        }
    }

    /// Signatur eines Postfachs.
    ///
    /// - Parameter accountID: Kennung des Postfachs.
    /// - Returns: Signatur oder `nil`, wenn keine angelegt ist.
    func signature(for accountID: UUID) -> SignatureItem? {
        signatures[accountID]
    }

    /// Liest den Bestand neu.
    ///
    /// Verarbeitung: Ein Lesefehler wird protokolliert; der bisherige Stand
    /// bleibt dann erhalten.
    func reload() {
        do {
            signatures = SignatureRules.byAccount(try storage.all())
        } catch {
            Log.store.error("⚠️ Signaturen nicht lesbar: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Speichert eine Signatur; eine leere Signatur (kein Text, kein Logo)
    /// wird stattdessen entfernt.
    ///
    /// - Parameter item: Signatur.
    /// - Throws: Fehler beim Speichern.
    func save(_ item: SignatureItem) throws {
        if item.isEmpty {
            try remove(accountID: item.accountID)
            return
        }
        try storage.save(item)
        signatures[item.accountID] = item
    }

    /// Entfernt die Signatur eines Postfachs.
    ///
    /// - Parameter accountID: Kennung des Postfachs.
    /// - Throws: Fehler beim Speichern.
    func remove(accountID: UUID) throws {
        try storage.remove(accountID: accountID)
        signatures[accountID] = nil
    }
}
