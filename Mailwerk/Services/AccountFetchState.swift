//
//  AccountFetchState.swift
//  Mailwerk
//
//  Zweck: Merkt sich, welche Postfächer beim letzten Abruf den Server
//  nicht erreicht haben (Verbindungsfehler, z. B. Zeitüberschreitung),
//  und bildet daraus den Hinweis in der Titelzeile der Liste.
//
//  Grundlage für das gelbe Warnzeichen am Postfach (FetchFailedBadge), den
//  Hinweis in der Titelzeile und die Hinweise auf der Apple Watch. Jedes
//  Postfach steht für sich: Scheitert eines, gelten die übrigen weiter als
//  erreichbar – früher färbte ein einzelner Fehler die ganze Ansicht als
//  „Keine Verbindung“.
//
//  Gesetzt wird der Zustand, wenn der Abruf des Posteingangs bzw. eines
//  Ordners an der Verbindung scheitert; gelöscht beim nächsten
//  erfolgreichen Abruf des Postfachs. Er gilt nur für die laufende
//  Sitzung (wie OAuthSignInState).
//
//  Abgrenzung: Setzen und Löschen beim Abruf → InboxViewModel; Anzeige →
//  FetchFailedBadge, AccountStatusBadges, InboxView, WatchBridge; kein
//  Netz am Gerät („Offline“) → NetworkMonitor.
//
//  Abhängigkeiten: Foundation, Observation, Log.
//

import Foundation
import Observation
import os

/// Postfächer, deren letzter Abruf den Server nicht erreicht hat.
@Observable
final class AccountFetchState {
    /// Gemeinsamer Zustand der App.
    static let shared = AccountFetchState()

    /// Postfächer, deren letzter Abruf an der Verbindung scheiterte.
    private(set) var unreachable: Set<UUID> = []

    /// Prüft, ob ein Postfach beim letzten Abruf nicht erreichbar war.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: `true`, wenn der letzte Abruf an der Verbindung scheiterte.
    func isUnreachable(_ accountID: UUID) -> Bool {
        unreachable.contains(accountID)
    }

    /// Setzt oder löscht „nicht erreichbar“ für ein Postfach.
    ///
    /// Verarbeitung: Geschrieben wird nur bei einer Änderung, damit die
    /// Oberfläche nicht ohne Grund neu zeichnet; jeder Wechsel wird
    /// protokolliert (Name privat).
    ///
    /// - Parameters:
    ///   - isUnreachable: `true` = letzter Abruf scheiterte an der Verbindung.
    ///   - accountID: Postfach.
    ///   - name: Anzeigename für das Protokoll.
    func setUnreachable(_ isUnreachable: Bool, for accountID: UUID, name: String) {
        guard unreachable.contains(accountID) != isUnreachable else { return }
        if isUnreachable {
            unreachable.insert(accountID)
            Log.fetch.info("📴 \(name, privacy: .private): nicht erreichbar")
        } else {
            unreachable.remove(accountID)
            Log.fetch.info("🌐 \(name, privacy: .private): wieder erreichbar")
        }
    }

    // MARK: - Titelzeile

    /// Hinweis für die Titelzeile der Liste.
    ///
    /// Verarbeitung: Ohne Netz „Offline“. Sonst zählen nur die Postfächer
    /// der Ansicht: alle nicht erreichbar → „Keine Verbindung“, eines →
    /// „<Name> nicht erreichbar“, mehrere → „<Anzahl> Postfächer nicht
    /// erreichbar“, keines → kein Hinweis.
    ///
    /// - Parameters:
    ///   - isOnline: Netz am Gerät verfügbar.
    ///   - accounts: Postfächer der Ansicht (ID und Anzeigename).
    ///   - unreachable: Nicht erreichbare Postfächer.
    /// - Returns: Hinweistext oder `nil`.
    static func titleStatus(
        isOnline: Bool,
        accounts: [(id: UUID, name: String)],
        unreachable: Set<UUID>
    ) -> String? {
        guard isOnline else { return "Offline" }
        let failed = accounts.filter { unreachable.contains($0.id) }
        guard !failed.isEmpty else { return nil }
        if failed.count == accounts.count { return "Keine Verbindung" }
        if failed.count == 1 { return "\(failed[0].name) nicht erreichbar" }
        return "\(failed.count) Postfächer nicht erreichbar"
    }

    /// Hinweise für die Apple Watch: eine Zeile je nicht erreichbarem
    /// Postfach, in der Reihenfolge der Postfächer.
    ///
    /// - Parameters:
    ///   - accounts: Postfächer mit Abruf (ID und Anzeigename).
    ///   - unreachable: Nicht erreichbare Postfächer.
    /// - Returns: z. B. „GMX: keine Verbindung zum Mailserver“; leer, wenn
    ///   alle erreichbar sind.
    static func watchProblems(
        accounts: [(id: UUID, name: String)],
        unreachable: Set<UUID>
    ) -> [String] {
        accounts
            .filter { unreachable.contains($0.id) }
            .map { "\($0.name): keine Verbindung zum Mailserver" }
    }
}
