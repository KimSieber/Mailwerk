//
//  FolderCatalog.swift
//  Mailwerk
//
//  Hält die Ordnerbäume aller Postfächer für die Seitenleiste.
//
//  Geladen wird beim ersten Öffnen der Leiste, alle Postfächer parallel.
//  Jedes Postfach hat seinen eigenen Zustand: Scheitert eines, zeigen die
//  anderen trotzdem ihre Ordner.
//
//  v0.1.8b – offline verfügbar: Ein gespeicherter Baum (`CachedLoader`)
//  erscheint sofort, danach wird einmal je Sitzung vom Server geladen.
//  Scheitert ein Abruf, bleibt ein vorhandener Baum stehen – ohne
//  Fehlermeldung, wie bei der Mail-Liste. „Konnte nicht geladen werden“
//  erscheint nur, wenn es gar keinen Baum gibt.
//
//  Abruf und gespeicherter Baum werden als Closures übergeben. So bleibt
//  der Katalog ohne IMAP- und Datenbankbezug und lässt sich ohne Server
//  testen.
//

import Foundation
import Observation

@Observable
final class FolderCatalog {

    enum State: Equatable {
        case idle
        case loading
        case loaded([FolderNode])
        case failed(String)
    }

    /// Ausdrücklich `@MainActor`: Ohne feste Isolation wird eine gespeicherte
    /// async-Closure unter „Approachable Concurrency“ `nonisolated(nonsending)`.
    /// In dieser Form kamen die Parameter im Test beschädigt beim Lader an
    /// (Compiler-Fehler in Swift 6.2). Der eigentliche Netzwerkverkehr läuft
    /// ohnehin im Actor von SwiftMail, der Main-Actor wartet nur.
    typealias Loader = @MainActor (MailAccount) async throws -> [FolderNode]
    /// Gespeicherter Baum eines Postfachs, `nil`, wenn keiner vorliegt.
    typealias CachedLoader = @MainActor (MailAccount) -> [FolderNode]?

    private(set) var states: [UUID: State] = [:]
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private let cached: CachedLoader
    /// Postfächer mit laufendem Abruf. Getrennt vom Zustand, weil ein
    /// geladenes Postfach beim Neuladen `.loaded` bleibt.
    @ObservationIgnored private var inFlight: Set<UUID> = []
    /// Postfächer, für die in dieser Sitzung schon ein Abruf lief
    /// (erfolgreich oder gescheitert). Ein abgebrochener zählt nicht.
    @ObservationIgnored private var attempted: Set<UUID> = []

    init(loader: @escaping Loader, cached: @escaping CachedLoader = { _ in nil }) {
        self.loader = loader
        self.cached = cached
    }

    func state(for accountID: UUID) -> State {
        states[accountID] ?? .idle
    }

    /// Zeigt gespeicherte Bäume sofort und lädt Postfächer, für die in
    /// dieser Sitzung noch kein Abruf lief. Zustände entfernter Postfächer
    /// werden dabei verworfen.
    func loadIfNeeded(_ accounts: [MailAccount]) async {
        prune(keeping: accounts)
        for account in accounts where state(for: account.id) == .idle {
            if let tree = cached(account) {
                states[account.id] = .loaded(tree)
            }
        }
        await load(accounts.filter { !attempted.contains($0.id) })
    }

    /// Lädt alle Postfächer neu (Pull-to-Refresh). Bereits geladene
    /// Ordner bleiben bis zum Ergebnis sichtbar.
    func reload(_ accounts: [MailAccount]) async {
        prune(keeping: accounts)
        await load(accounts)
    }

    /// Lädt ein einzelnes Postfach erneut, etwa nach einem Fehler.
    func retry(_ account: MailAccount) async {
        await load([account])
    }

    // MARK: - Intern

    private func load(_ accounts: [MailAccount]) async {
        let pending = accounts.filter { !inFlight.contains($0.id) }
        inFlight.formUnion(pending.map(\.id))
        await withTaskGroup(of: Void.self) { group in
            for account in pending {
                group.addTask { @MainActor in
                    await self.loadOne(account)
                }
            }
        }
    }

    private func loadOne(_ account: MailAccount) async {
        defer { inFlight.remove(account.id) }
        let previous = state(for: account.id)
        // Beim Neuladen bleibt der bisherige Baum stehen, statt kurz
        // zu verschwinden; nur ohne Ergebnis wird „lädt“ angezeigt.
        if case .loaded = previous {} else {
            states[account.id] = .loading
        }
        do {
            let tree = try await loader(account)
            attempted.insert(account.id)
            states[account.id] = .loaded(tree)
            print("📁 [\(account.displayName)] \(tree.count) Ordner auf oberster Ebene")
        } catch where error is CancellationError || Task.isCancelled {
            // Abgebrochen, etwa weil die Leiste geschlossen wurde. Das ist
            // kein Fehler des Postfachs: Zustand zurücksetzen, damit beim
            // nächsten Öffnen neu geladen wird.
            attempted.remove(account.id)
            states[account.id] = (previous == .loading) ? .idle : previous
        } catch {
            attempted.insert(account.id)
            print("⚠️ [\(account.displayName)] Ordnerliste fehlgeschlagen: \(error.localizedDescription)")
            // Vorhandenen (auch gespeicherten) Baum stehen lassen.
            if case .loaded = previous { return }
            states[account.id] = .failed(error.localizedDescription)
        }
    }

    private func prune(keeping accounts: [MailAccount]) {
        let ids = Set(accounts.map(\.id))
        for id in states.keys where !ids.contains(id) {
            states.removeValue(forKey: id)
        }
        attempted.formIntersection(ids)
    }
}
