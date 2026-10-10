//
//  MailwerkApp.swift
//  Mailwerk
//
//  Zweck: Einstiegspunkt der App. Richtet den Filterlisten-Speicher ein
//  (bevorzugt mit iCloud-Abgleich, sonst lokal, notfalls im Speicher),
//  räumt beim Start temporäre Dateien auf und zeigt einmalig einen
//  Hinweis, falls der lokale Mail-Speicher beim Start neu angelegt
//  werden musste oder nicht verfügbar ist.
//
//  Alle langlebigen Objekte (Postfächer, Einstellungen, ViewModel der
//  Liste, Ordnerkatalog) entstehen hier genau einmal (`AppObjects`). Der
//  `body` der App wird von SwiftUI mehrfach ausgewertet; was dort erzeugt
//  würde, entstünde jedes Mal neu.
//
//  Abgrenzung: Wurzelansicht → ContentView.
//
//  Abhängigkeiten: SwiftUI, SwiftData, AttachmentManager (Aufräumen),
//  MessageStore (Starthinweis), AppObjects, Dialogs, Log.
//

import SwiftUI
import SwiftData
import os

@main
struct MailwerkApp: App {

    /// Speicher der Filterlisten. Bevorzugt mit iCloud-Abgleich; ist der
    /// nicht verfügbar (kein iCloud-Konto, Gerät offline eingerichtet),
    /// arbeitet die App lokal weiter, statt den Start zu verweigern.
    private let modelContainer: ModelContainer

    /// Langlebige Objekte der App, einmal angelegt.
    private let objects: AppObjects

    /// Hinweis des Mail-Speichers vom Start; `nil` = keiner anzuzeigen.
    @State private var storeNotice: AlertItem?

    /// Richtet Speicher und Objekte einmalig beim Start ein.
    ///
    /// Verarbeitung: Erzeugt den Filterlisten-Speicher, darauf aufbauend
    /// alle langlebigen Objekte, und räumt temporäre Anhang-Dateien auf.
    init() {
        let container = Self.makeContainer()
        modelContainer = container
        objects = AppObjects(
            filterLists: SwiftDataFilterListRepository(context: container.mainContext)
        )

        // Temporäre Anhang-Dateien aus der letzten Sitzung entfernen.
        // Das System leert das tmp-Verzeichnis zwar selbst, aber nicht
        // zuverlässig bei jeder Sitzung.
        AttachmentManager.cleanupTempFiles()
    }

    /// Hauptfenster mit der Wurzelansicht und dem einmaligen Starthinweis.
    var body: some Scene {
        WindowGroup {
            ContentView(objects: objects)
            .task {
                // Einmalig abholen; der Speicher liefert ihn nur einmal.
                if let notice = MessageStore.shared.consumeStartupNotice() {
                    storeNotice = AlertItem(title: notice.title, message: notice.message)
                }
            }
            .alertItem($storeNotice)
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Container

    /// CloudKit-Container für den Abgleich der Filterlisten.
    private static let cloudContainerID = "iCloud.de.sieber-bw.Mailwerk"

    /// Erzeugt den Filterlisten-Speicher in absteigender Präferenz.
    ///
    /// Verarbeitung: Versucht zuerst iCloud (CloudKit), dann eine lokale
    /// Datei, zuletzt einen flüchtigen Speicher im RAM. Der erste
    /// erfolgreiche Versuch gewinnt; scheitern alle drei, bricht die App
    /// ab, weil etwas Grundlegendes nicht stimmt.
    ///
    /// - Returns: Funktionierender `ModelContainer`.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([FilterEntry.self])

        let candidates: [(String, ModelConfiguration)] = [
            ("iCloud", ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudContainerID)
            )),
            ("lokal", ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )),
            ("flüchtig", ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            ))
        ]

        for (name, configuration) in candidates {
            do {
                let container = try ModelContainer(for: schema, configurations: configuration)
                Log.spam.info("🗂️ Filterlisten-Speicher: \(name, privacy: .public)")
                return container
            } catch {
                Log.spam.error("⚠️ Filterlisten-Speicher \(name, privacy: .public) nicht verfügbar: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Alle drei Varianten gescheitert – dann stimmt etwas Grundlegendes nicht.
        fatalError("Kein Speicher für die Filterlisten verfügbar")
    }
}
