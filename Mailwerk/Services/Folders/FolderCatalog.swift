//
//  FolderCatalog.swift
//  Mailwerk
//
//  Hält die Ordnerbäume aller Postfächer für die Seitenleiste – nur für
//  die laufende App-Sitzung, ein Cache folgt in einer späteren Version.
//
//  Geladen wird beim ersten Öffnen der Leiste, alle Postfächer parallel.
//  Jedes Postfach hat seinen eigenen Zustand: Scheitert eines, zeigen die
//  anderen trotzdem ihre Ordner.
//
//  Der eigentliche Abruf wird als `Loader` übergeben. So bleibt der
//  Katalog ohne IMAP-Bezug und lässt sich ohne Server testen.
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

    private(set) var states: [UUID: State] = [:]
    @ObservationIgnored private let loader: Loader
    /// Postfächer mit laufendem Abruf. Getrennt vom Zustand, weil ein
    /// geladenes Postfach beim Neuladen `.loaded` bleibt.
    @ObservationIgnored private var inFlight: Set<UUID> = []

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func state(for accountID: UUID) -> State {
        states[accountID] ?? .idle
    }

    /// Lädt nur Postfächer, die noch nie geladen wurden. Zustände
    /// entfernter Postfächer werden dabei verworfen.
    func loadIfNeeded(_ accounts: [MailAccount]) async {
        prune(keeping: accounts)
        await load(accounts.filter { state(for: $0.id) == .idle })
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
            states[account.id] = .loaded(tree)
            print("📁 [\(account.displayName)] \(tree.count) Ordner auf oberster Ebene")
        } catch where error is CancellationError || Task.isCancelled {
            // Abgebrochen, etwa weil die Leiste geschlossen wurde. Das ist
            // kein Fehler des Postfachs: Zustand zurücksetzen, damit beim
            // nächsten Öffnen neu geladen wird.
            states[account.id] = (previous == .loading) ? .idle : previous
        } catch {
            states[account.id] = .failed(error.localizedDescription)
            print("⚠️ [\(account.displayName)] Ordnerliste fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func prune(keeping accounts: [MailAccount]) {
        let ids = Set(accounts.map(\.id))
        for id in states.keys where !ids.contains(id) {
            states.removeValue(forKey: id)
        }
    }
}
