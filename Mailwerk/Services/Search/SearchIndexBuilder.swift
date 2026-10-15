//
//  SearchIndexBuilder.swift
//  Mailwerk
//
//  Zweck: Trägt fehlende Einträge im Suchindex schrittweise nach – nach
//  dem Update auf den Suchindex für den ganzen Cache, sonst für einzelne
//  Mails, deren Eintrag nicht geschrieben werden konnte.
//
//  Gearbeitet wird in kleinen Paketen mit Pausen dazwischen. Die Ablage
//  läuft auf dem Main-Actor; so bleibt die Oberfläche bedienbar, auch
//  wenn beim ersten Start einige tausend Mails nachzutragen sind. Die
//  neuesten Mails kommen zuerst an die Reihe.
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
    /// zurück. Die Anzahl wird protokolliert.
    ///
    /// - Parameter store: Ablage, in der Regel `MessageStore.shared`.
    static func run(store: MessageStore) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var total = 0
        while !Task.isCancelled {
            let count = store.indexMissingSearchEntries(limit: batchSize)
            guard count > 0 else { break }
            total += count
            try? await Task.sleep(for: pause)
        }
        if total > 0 {
            Log.store.info("🔎 Suchindex nachgetragen: \(total) Mails")
        }
    }
}
