//
//  ParallelRefreshPlanner.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 25.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Verteilt den Abruf der Postfächer auf begrenzt parallele
//  Abläufe (Paket v0.2.3e, Prüfbericht P-21). Bisher wurden die Postfächer
//  streng nacheinander abgerufen; die Wartezeit war die Summe aller
//  Postfächer, und ein hängendes Postfach hielt alle folgenden auf.
//
//  Regeln:
//  - Höchstens `maxConcurrent` Postfächer gleichzeitig.
//  - Höchstens `maxPerHost` gleichzeitig je IMAP-Server. Gruppiert wird nach
//    dem Servernamen (ohne Groß-/Kleinschreibung), nicht nach Anbieter –
//    keine anbieterspezifische Sonderlösung. So laufen mehrere Postfächer
//    desselben Servers nicht alle zugleich an, und Anbieter, die dichte
//    Anmeldefolgen bremsen (Gmail, manitu), bekommen keine Anmeldewelle.
//  - Reihenfolge: wie übergeben; ein Postfach, dessen Server gerade voll
//    ist, wird übersprungen, bis dort ein Platz frei wird.
//  - Jedes Postfach höchstens einmal je Runde, auch wenn es während der
//    Runde erneut gemeldet wird.
//
//  Reine Logik ohne Netz und ohne Oberfläche – die Ausführung übernimmt
//  InboxViewModel (`performRefresh`). Getestet in
//  ParallelRefreshPlannerTests.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Verteilung der Postfach-Abrufe einer Runde.
nonisolated struct ParallelRefreshPlanner {

    /// Ein abzurufendes Postfach.
    struct Item: Equatable, Sendable {
        /// Postfach.
        let accountID: UUID
        /// IMAP-Server des Postfachs.
        let host: String
    }

    /// Höchstzahl gleichzeitiger Abrufe insgesamt.
    let maxConcurrent: Int
    /// Höchstzahl gleichzeitiger Abrufe je IMAP-Server.
    let maxPerHost: Int

    /// Noch nicht gestartete Postfächer in Abrufreihenfolge.
    private(set) var pending: [Item] = []
    /// Laufende Abrufe je Server (normalisierter Name).
    private var runningPerHost: [String: Int] = [:]
    /// Alle Postfächer, die in dieser Runde schon eingeplant wurden.
    private var seen: Set<UUID> = []

    /// Legt den Planer an.
    ///
    /// - Parameters:
    ///   - maxConcurrent: Höchstzahl gleichzeitiger Abrufe insgesamt.
    ///   - maxPerHost: Höchstzahl gleichzeitiger Abrufe je Server.
    init(maxConcurrent: Int = 3, maxPerHost: Int = 2) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.maxPerHost = max(1, maxPerHost)
    }

    /// Anzahl laufender Abrufe.
    var runningCount: Int { runningPerHost.values.reduce(0, +) }

    /// Plant Postfächer ein; schon eingeplante werden übergangen.
    ///
    /// - Parameter items: Postfächer in gewünschter Reihenfolge.
    mutating func add(_ items: [Item]) {
        for item in items where !seen.contains(item.accountID) {
            seen.insert(item.accountID)
            pending.append(item)
        }
    }

    /// Nächstes startbares Postfach – und vermerkt es als laufend.
    ///
    /// Verarbeitung: Erstes wartendes Postfach, dessen Server noch Platz
    /// hat, sofern insgesamt noch Platz ist.
    ///
    /// - Returns: Zu startendes Postfach; `nil`, wenn gerade keins starten darf.
    mutating func nextStartable() -> Item? {
        guard runningCount < maxConcurrent,
              let index = pending.firstIndex(where: { runningPerHost[Self.key($0.host), default: 0] < maxPerHost })
        else { return nil }
        let item = pending.remove(at: index)
        runningPerHost[Self.key(item.host), default: 0] += 1
        return item
    }

    /// Alle Postfächer, die jetzt starten dürfen – vermerkt als laufend.
    ///
    /// - Returns: Zu startende Postfächer (leer, wenn keins darf).
    mutating func startableItems() -> [Item] {
        var items: [Item] = []
        while let item = nextStartable() {
            items.append(item)
        }
        return items
    }

    /// Vermerkt einen beendeten Abruf.
    ///
    /// - Parameter item: Beendetes Postfach.
    mutating func finish(_ item: Item) {
        let key = Self.key(item.host)
        guard let count = runningPerHost[key] else { return }
        runningPerHost[key] = count > 1 ? count - 1 : nil
    }

    /// Verwirft alle noch wartenden Postfächer (z. B. bei Netzverlust).
    mutating func dropPending() {
        pending.removeAll()
    }

    /// Normalisierter Servername für die Gruppierung.
    ///
    /// - Parameter host: Servername wie eingerichtet.
    /// - Returns: Kleingeschrieben, ohne Leerraum an den Rändern.
    private static func key(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
