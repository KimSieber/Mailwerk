//
//  MailwerkApp.swift
//  Mailwerk
//
//  Zweck: Einstiegspunkt der App. Richtet den gemeinsamen Speicher für
//  Filterlisten und Signaturen ein (bevorzugt mit iCloud-Abgleich, sonst
//  lokal, notfalls im Speicher),
//  räumt beim Start temporäre Dateien auf und zeigt einmalig einen
//  Hinweis, falls der lokale Mail-Speicher beim Start neu angelegt
//  werden musste oder nicht verfügbar ist.
//
//  Anmeldefenster: Die App stellt dem OAuthSignInState das Anmeldefenster
//  von Apple bereit (`OAuthWebSignInInstaller`, ASWebAuthenticationSession
//  in einer privaten Browser-Sitzung). Das geschieht nur hier, weil diese
//  Datei nicht zu den Teilen-Erweiterungen gehört – dort gibt es kein
//  Anmeldefenster.
//
//  Alle langlebigen Objekte (Postfächer, Einstellungen, ViewModel der
//  Liste, Ordnerkatalog) entstehen hier genau einmal (`AppObjects`). Auf
//  dem iPhone startet hier auch die Anbindung der Apple Watch
//  (`WatchBridge`), damit Anfragen der Watch nach einem Start im
//  Hintergrund ankommen. Der
//  `body` der App wird von SwiftUI mehrfach ausgewertet; was dort erzeugt
//  würde, entstünde jedes Mal neu.
//
//  mailto:-Links: Links, die das System an Mailwerk übergibt (Schema
//  mailto in der Info.plist), nimmt das Fenster per `onOpenURL` an und
//  reicht sie an den ExternalMailtoRouter weiter. Auf dem Mac sorgt
//  `handlesExternalEvents` dafür, dass ein Link im vorhandenen Fenster
//  landet, statt ein weiteres zu öffnen.
//
//  Menübefehle: Auf iPhone/iPad hängt die Szene die Befehle der Mailliste
//  an (InboxCommands – Menüleiste des iPad und Tastaturkürzel).
//
//  Abgrenzung: Wurzelansicht → ContentView.
//
//  Abhängigkeiten: SwiftUI, SwiftData, AttachmentManager (Aufräumen),
//  MessageStore (Starthinweis), AppObjects, FilterEntry, AccountSignature,
//  SignatureStore, Dialogs, OAuthSignInState, OAuthError,
//  ExternalMailtoRouter, WatchBridge (nur iPhone), InboxCommands, Log.
//

import SwiftUI
import SwiftData
import AuthenticationServices
import os

@main
struct MailwerkApp: App {

    /// Speicher der Filterlisten und Signaturen. Bevorzugt mit iCloud-Abgleich; ist der
    /// nicht verfügbar (kein iCloud-Konto, Gerät offline eingerichtet),
    /// arbeitet die App lokal weiter, statt den Start zu verweigern.
    private let modelContainer: ModelContainer

    /// Langlebige Objekte der App, einmal angelegt.
    private let objects: AppObjects

    /// Hinweis des Mail-Speichers vom Start; `nil` = keiner anzuzeigen.
    @State private var storeNotice: AlertItem?

    /// Richtet Speicher und Objekte einmalig beim Start ein.
    ///
    /// Verarbeitung: Erzeugt den gemeinsamen Speicher, darauf aufbauend
    /// alle langlebigen Objekte, startet auf dem iPhone die Anbindung der
    /// Apple Watch und räumt temporäre Anhang-Dateien auf.
    init() {
        let container = Self.makeContainer()
        modelContainer = container
        let objects = AppObjects(
            filterLists: SwiftDataFilterListRepository(context: container.mainContext),
            signatures: SignatureStore(storage: SwiftDataSignatureStorage(context: container.mainContext))
        )
        self.objects = objects

        #if os(iOS) && canImport(WatchConnectivity)
        // Apple Watch: Anfragen kommen auch, wenn die Watch die App im
        // Hintergrund startet – deshalb gleich hier.
        WatchBridge.shared.start(objects: objects)
        #endif

        // Temporäre Anhang-Dateien aus der letzten Sitzung entfernen.
        // Das System leert das tmp-Verzeichnis zwar selbst, aber nicht
        // zuverlässig bei jeder Sitzung.
        // Temp-Dateien abseits des Starts aufräumen (Prüfbericht P-18).
        Task.detached(priority: .utility) {
            AttachmentManager.cleanupTempFiles()
        }
    }

    /// Hauptfenster mit der Wurzelansicht, dem einmaligen Starthinweis und
    /// der Annahme von mailto:-Links.
    var body: some Scene {
        WindowGroup {
            ContentView(objects: objects)
            .modifier(OAuthWebSignInInstaller())
            .onOpenURL { url in
                // Andere Schemata (z. B. die Rückkehr der Anmeldung) laufen
                // nicht hierüber und werden vom Router ohnehin abgelehnt.
                if ExternalMailtoRouter.shared.receive(url) {
                    Log.view.info("✉️ mailto:-Link von außen angenommen")
                }
            }
            // Mac: Links im vorhandenen Fenster annehmen statt ein neues zu öffnen.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .task {
                // Einmalig abholen; der Speicher liefert ihn nur einmal.
                if let notice = MessageStore.shared.consumeStartupNotice() {
                    storeNotice = AlertItem(title: notice.title, message: notice.message)
                }
            }
            .alertItem($storeNotice)
        }
        .modelContainer(modelContainer)
        #if os(iOS)
        // Menüleiste und Tastaturkürzel der Mailliste (iPad, Tastatur).
        .commands { InboxCommands() }
        #endif
    }

    // MARK: - Container

    /// CloudKit-Container für den Abgleich der Filterlisten und Signaturen.
    private static let cloudContainerID = "iCloud.de.sieber-bw.Mailwerk"

    /// Erzeugt den Speicher für Filterlisten und Signaturen in absteigender Präferenz.
    ///
    /// Verarbeitung: Versucht zuerst iCloud (CloudKit), dann eine lokale
    /// Datei, zuletzt einen flüchtigen Speicher im RAM. Der erste
    /// erfolgreiche Versuch gewinnt; scheitern alle drei, bricht die App
    /// ab, weil etwas Grundlegendes nicht stimmt.
    ///
    /// - Returns: Funktionierender `ModelContainer`.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([FilterEntry.self, AccountSignature.self])

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
                Log.spam.info("🗂️ Speicher für Filterlisten und Signaturen: \(name, privacy: .public)")
                return container
            } catch {
                Log.spam.error("⚠️ Speicher für Filterlisten und Signaturen \(name, privacy: .public) nicht verfügbar: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Alle drei Varianten gescheitert – dann stimmt etwas Grundlegendes nicht.
        fatalError("Kein Speicher für Filterlisten und Signaturen verfügbar")
    }
}

// MARK: - Anmeldefenster

/// Stellt dem OAuthSignInState das Anmeldefenster von Apple bereit.
///
/// Die Sitzung kommt aus der Umgebung des Fensters
/// (`webAuthenticationSession`); sie öffnet sich über dem Fenster, auch
/// wenn darin gerade ein Blatt (z. B. „Postfach hinzufügen“) offen ist.
private struct OAuthWebSignInInstaller: ViewModifier {
    /// Anmeldefenster des Systems für dieses Fenster.
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    /// Hinterlegt beim Erscheinen die Funktion zum Öffnen des Anmeldefensters.
    ///
    /// - Parameter content: Wurzelansicht.
    /// - Returns: Unveränderte Ansicht.
    func body(content: Content) -> some View {
        content.onAppear {
            let session = webAuthenticationSession
            OAuthSignInState.shared.webSignIn = { url, callbackScheme in
                try await Self.authenticate(session, url: url, callbackScheme: callbackScheme)
            }
        }
    }

    /// Öffnet das Anmeldefenster und wartet auf die Rückkehr.
    ///
    /// Verarbeitung: Private Browser-Sitzung (`.ephemeral`) – keine Cookies
    /// anderer Anmeldungen, kein Systemdialog „möchte sich anmelden“.
    /// Schließt der Nutzer das Fenster, wird daraus `OAuthError.cancelled`.
    ///
    /// - Parameters:
    ///   - session: Anmeldefenster des Systems.
    ///   - url: Adresse der Anmeldeseite.
    ///   - callbackScheme: Schema der Weiterleitung zurück zu Mailwerk.
    /// - Returns: Adresse, mit der das Anmeldefenster zurückkehrte.
    /// - Throws: `OAuthError.cancelled` oder Fehler des Systems.
    @MainActor
    private static func authenticate(
        _ session: WebAuthenticationSession,
        url: URL,
        callbackScheme: String
    ) async throws -> URL {
        do {
            return try await session.authenticate(
                using: url,
                callbackURLScheme: callbackScheme,
                preferredBrowserSession: .ephemeral
            )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw OAuthError.cancelled
        }
    }
}
