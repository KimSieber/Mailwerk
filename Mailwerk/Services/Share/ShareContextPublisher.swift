//
//  ShareContextPublisher.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 15.10.2026
//  Geändert: 15.10.2026
//
//  Zweck: Hält die Abschrift für die Teilen-Erweiterung (ShareContext)
//  aktuell. Beobachtet Postfächer, Standard-Postfach und Signaturen und
//  schreibt die Abschrift bei jeder Änderung neu – auch bei Änderungen,
//  die per iCloud von einem anderen Gerät kommen.
//
//  Läuft nur in der App; die Erweiterung liest die Abschrift nur.
//
//  Abgrenzung: Format und Datei → ShareContext/ShareContextFile.
//
//  Abhängigkeiten: Foundation, Observation, AccountStore, SignatureStore,
//  ShareContext, Log.
//

import Foundation
import Observation
import os

/// Schreibt die Abschrift für die Teilen-Erweiterung bei jeder Änderung.
final class ShareContextPublisher {
    /// Quelle der Postfächer und des Standard-Postfachs.
    private let accountStore: AccountStore
    /// Quelle der Signaturen.
    private let signatures: SignatureStore
    /// Zieldatei; `nil` = App Group nicht verfügbar, dann wird nichts geschrieben.
    private let url: URL?

    /// Legt den Beobachter an und schreibt den aktuellen Stand.
    ///
    /// - Parameters:
    ///   - accountStore: Postfächer und Standard-Postfach.
    ///   - signatures: Signaturen.
    ///   - url: Zieldatei; `nil` = `ShareContextFile.defaultURL`.
    init(accountStore: AccountStore, signatures: SignatureStore, url: URL? = nil) {
        self.accountStore = accountStore
        self.signatures = signatures
        self.url = url ?? ShareContextFile.defaultURL
        if self.url == nil {
            Log.store.error("⚠️ App Group nicht verfügbar – Teilen mit Mailwerk hat keine Postfächer")
        }
        observe()
    }

    /// Liest den aktuellen Stand unter Beobachtung und schreibt ihn.
    ///
    /// Verarbeitung: `withObservationTracking` meldet die nächste Änderung
    /// noch vor dem Setzen des neuen Werts; deshalb wird erst im nächsten
    /// Durchlauf des Main-Actors neu gelesen und dabei wieder beobachtet.
    /// Der Beobachter hält sich dabei selbst fest; das ist gewollt, er lebt
    /// so lange wie die App (AppObjects).
    private func observe() {
        let context = withObservationTracking {
            Self.makeContext(accountStore: accountStore, signatures: signatures)
        } onChange: {
            Task { @MainActor in self.observe() }
        }
        publish(context)
    }

    /// Bildet die Abschrift aus dem aktuellen Stand.
    ///
    /// - Parameters:
    ///   - accountStore: Postfächer und Standard-Postfach.
    ///   - signatures: Signaturen.
    /// - Returns: Abschrift.
    static func makeContext(accountStore: AccountStore, signatures: SignatureStore) -> ShareContext {
        ShareContext(
            accounts: accountStore.accounts,
            defaultAccountID: accountStore.defaultAccountID,
            signatures: Array(signatures.signatures.values)
        )
    }

    /// Schreibt die Abschrift, sofern sie sich geändert hat.
    ///
    /// Verarbeitung: Fehler werden protokolliert; die App arbeitet
    /// unverändert weiter.
    ///
    /// - Parameter context: Abschrift.
    private func publish(_ context: ShareContext) {
        guard let url else { return }
        do {
            if try ShareContextFile.write(context, to: url) {
                Log.store.info("📤 Abschrift für das Teilen geschrieben: \(context.accounts.count) Postfächer, \(context.signatures.count) Signaturen")
            }
        } catch {
            Log.store.error("⚠️ Abschrift für das Teilen nicht geschrieben: \(error.localizedDescription, privacy: .public)")
        }
    }
}
