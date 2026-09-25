//
//  MailwerkApp.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//

import SwiftUI
import SwiftData

@main
struct MailwerkApp: App {

    /// Speicher der Filterlisten. Bevorzugt mit iCloud-Abgleich; ist der
    /// nicht verfügbar (kein iCloud-Konto, Gerät offline eingerichtet),
    /// arbeitet die App lokal weiter, statt den Start zu verweigern.
    private let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                filterLists: SwiftDataFilterListRepository(context: modelContainer.mainContext)
            )
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Container

    private static let cloudContainerID = "iCloud.de.sieber-bw.Mailwerk"

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
                print("🗂️ Filterlisten-Speicher: \(name)")
                return container
            } catch {
                print("⚠️ Filterlisten-Speicher \(name) nicht verfügbar: \(error.localizedDescription)")
            }
        }

        // Alle drei Varianten gescheitert – dann stimmt etwas Grundlegendes nicht.
        fatalError("Kein Speicher für die Filterlisten verfügbar")
    }
}
