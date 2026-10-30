//
//  SearchIndexBuilder.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 15.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Trägt fehlende Einträge im Suchindex schrittweise nach – nach
//  dem Update auf den Suchindex für den ganzen Cache, sonst für einzelne
//  Mails, deren Eintrag nicht geschrieben werden konnte.
//
//  Gearbeitet wird in kleinen Paketen mit Pausen dazwischen. Jedes Paket
//  läuft seit v0.2.3b abseits des Hauptthreads (`indexBatch`,
//  `@concurrent`) – Aufbereitung der Mailtexte und Schreiben belasten die
//  Oberfläche nicht mehr. Die Pausen bleiben, damit ein gleichzeitiger
//  Abruf die Schreibverbindung nicht lange entbehren muss. Die neuesten
//  Mails kommen zuerst an die Reihe.
//
//  Abgrenzung: Schreiben eines Eintrags im MessageStore.
//
//  Abhängigkeiten: MessageStore, Log.
//

import Foundation
import os

/// Nachtragen des Suchindex im Hintergrund der Oberfläche.
enum SearchIndexBuilder {
    /// Mails je Paket.
    static let batchSize = 50
    /// Pause zwischen zwei Paketen.
    static let pause: Duration = .milliseconds(30)

    /// Läuft gerade ein Nachtragen? Verhindert doppelte Läufe.
    private static var isRunning = false

    /// Trägt alle fehlenden Einträge nach.
    ///
    /// Verarbeitung: Ruft `indexMissingSearchEntries` in Paketen auf, bis
    /// nichts mehr fehlt oder ein Paket scheitert (dann beim nächsten Start
    /// erneut). Läuft bereits ein Nachtragen, kehrt der Aufruf sofort
    /// zurück. Die Anzahl wird protokolliert. Jedes Paket ist ein
    /// Messpunkt für Instruments („Suchindex-Paket“).
    ///
    /// - Parameter store: Ablage, in der Regel `MessageStore.shared`.
    static func run(store: MessageStore) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var total = 0
        while !Task.isCancelled {
            let count = await indexBatch(store: store, limit: batchSize)
            guard count > 0 else { break }
            total += count
            try? await Task.sleep(for: pause)
        }
        if total > 0 {
            Log.store.info("🔎 Suchindex nachgetragen: \(total) Mails")
        }
    }

    /// Trägt ein Paket nach – abseits des Hauptthreads.
    ///
    /// Verarbeitung: Messpunkt für Instruments („Suchindex-Paket“).
    ///
    /// - Parameters:
    ///   - store: Ablage.
    ///   - limit: Höchstzahl der Mails im Paket.
    /// - Returns: Anzahl der nachgetragenen Mails (0 = fertig oder gescheitert).
    @concurrent
    nonisolated private static func indexBatch(store: MessageStore, limit: Int) async -> Int {
        let interval = Log.beginInterval(Log.Interval.searchIndexBatch)
        defer { Log.endInterval(interval) }
        return store.indexMissingSearchEntries(limit: limit)
    }
}
