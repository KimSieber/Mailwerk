//
//  FolderCatalogTests.swift
//  MailwerkTests
//
//  Tests für die Zustände des Ordnerkatalogs – ohne Server, mit
//  einem Test-Lader.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FolderCatalogTests {

    private struct LoadError: LocalizedError {
        var errorDescription: String? { "Anmeldung fehlgeschlagen" }
    }

    /// Zählt die Abrufe je Postfach und liefert je nach Einstellung
    /// einen Baum oder einen Fehler.
    @MainActor
    private final class FakeLoader {
        var calls: [UUID: Int] = [:]
        var failing: Set<UUID> = []
        var cancelling: Set<UUID> = []
        var folderName = "Posteingang"

        func load(_ account: MailAccount) async throws -> [FolderNode] {
            calls[account.id, default: 0] += 1
            if cancelling.contains(account.id) { throw CancellationError() }
            if failing.contains(account.id) { throw LoadError() }
            return [FolderNode(id: "INBOX", name: folderName, role: .inbox, isSelectable: true, children: [])]
        }
    }

    private func account(_ name: String) -> MailAccount {
        MailAccount(displayName: name, username: "\(name)@example.org", imapHost: "imap.example.org", smtpHost: "smtp.example.org")
    }

    private func makeCatalog(_ fake: FakeLoader) -> FolderCatalog {
        FolderCatalog { account in try await fake.load(account) }
    }

    private func names(_ state: FolderCatalog.State) -> [String]? {
        if case .loaded(let tree) = state { return tree.map(\.name) }
        return nil
    }

    // MARK: - Tests

    @Test func unknownAccountIsIdle() {
        let catalog = makeCatalog(FakeLoader())
        #expect(catalog.state(for: UUID()) == .idle)
    }

    @Test func loadIfNeededLoadsAllAccounts() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a"), b = account("b")

        await catalog.loadIfNeeded([a, b])

        #expect(names(catalog.state(for: a.id)) == ["Posteingang"])
        #expect(names(catalog.state(for: b.id)) == ["Posteingang"])
    }

    @Test func loadIfNeededDoesNotLoadTwice() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a")

        await catalog.loadIfNeeded([a])
        await catalog.loadIfNeeded([a])

        #expect(fake.calls[a.id] == 1)
    }

    @Test func failureOfOneAccountDoesNotAffectOthers() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a"), b = account("b")
        fake.failing = [a.id]

        await catalog.loadIfNeeded([a, b])

        #expect(catalog.state(for: a.id) == .failed("Anmeldung fehlgeschlagen"))
        #expect(names(catalog.state(for: b.id)) == ["Posteingang"])
    }

    @Test func failedAccountIsNotReloadedAutomatically() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a")
        fake.failing = [a.id]

        await catalog.loadIfNeeded([a])
        await catalog.loadIfNeeded([a])

        #expect(fake.calls[a.id] == 1)
    }

    @Test func retryLoadsFailedAccount() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a")
        fake.failing = [a.id]
        await catalog.loadIfNeeded([a])

        fake.failing = []
        await catalog.retry(a)

        #expect(names(catalog.state(for: a.id)) == ["Posteingang"])
    }

    @Test func reloadFetchesAgainAndReplacesTree() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a")
        await catalog.loadIfNeeded([a])

        fake.folderName = "Neu"
        await catalog.reload([a])

        #expect(fake.calls[a.id] == 2)
        #expect(names(catalog.state(for: a.id)) == ["Neu"])
    }

    /// v0.1.8b: Ein gescheitertes Neuladen lässt den Baum stehen
    /// (bis v0.1.8a wurde er durch die Fehlermeldung ersetzt).
    @Test func failedReloadKeepsExistingTree() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a")
        await catalog.loadIfNeeded([a])

        fake.failing = [a.id]
        await catalog.reload([a])

        #expect(names(catalog.state(for: a.id)) == ["Posteingang"])
    }

    @Test func cancelledFirstLoadReturnsToIdleAndLoadsAgain() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a")
        fake.cancelling = [a.id]

        await catalog.loadIfNeeded([a])
        #expect(catalog.state(for: a.id) == .idle)

        fake.cancelling = []
        await catalog.loadIfNeeded([a])
        #expect(names(catalog.state(for: a.id)) == ["Posteingang"])
    }

    @Test func cancelledReloadKeepsExistingTree() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a")
        await catalog.loadIfNeeded([a])

        fake.cancelling = [a.id]
        await catalog.reload([a])

        #expect(names(catalog.state(for: a.id)) == ["Posteingang"])
    }

    @Test func removedAccountsAreDropped() async {
        let fake = FakeLoader()
        let catalog = makeCatalog(fake)
        let a = account("a"), b = account("b")
        await catalog.loadIfNeeded([a, b])

        await catalog.loadIfNeeded([b])

        #expect(catalog.state(for: a.id) == .idle)
        #expect(catalog.states.count == 1)
    }

    // MARK: - Gespeicherter Baum (v0.1.8b)

    private func cachedTree(_ name: String) -> [FolderNode] {
        [FolderNode(id: "INBOX", name: name, role: .inbox, isSelectable: true, children: [])]
    }

    @Test func cachedTreeIsShownWhenServerFails() async {
        let fake = FakeLoader()
        let a = account("a")
        fake.failing = [a.id]
        let catalog = FolderCatalog(
            loader: { account in try await fake.load(account) },
            cached: { _ in self.cachedTree("Gespeichert") }
        )

        await catalog.loadIfNeeded([a])

        #expect(names(catalog.state(for: a.id)) == ["Gespeichert"])
        #expect(fake.calls[a.id] == 1)
    }

    @Test func serverTreeReplacesCachedTree() async {
        let fake = FakeLoader()
        let a = account("a")
        let catalog = FolderCatalog(
            loader: { account in try await fake.load(account) },
            cached: { _ in self.cachedTree("Gespeichert") }
        )

        await catalog.loadIfNeeded([a])

        #expect(names(catalog.state(for: a.id)) == ["Posteingang"])
    }

    @Test func cachedTreeIsFetchedOnlyOncePerSession() async {
        let fake = FakeLoader()
        let a = account("a")
        let catalog = FolderCatalog(
            loader: { account in try await fake.load(account) },
            cached: { _ in self.cachedTree("Gespeichert") }
        )

        await catalog.loadIfNeeded([a])
        await catalog.loadIfNeeded([a])

        #expect(fake.calls[a.id] == 1)
    }

    @Test func withoutCacheFailureIsReported() async {
        let fake = FakeLoader()
        let a = account("a")
        fake.failing = [a.id]
        let catalog = FolderCatalog(
            loader: { account in try await fake.load(account) },
            cached: { _ in nil }
        )

        await catalog.loadIfNeeded([a])

        #expect(catalog.state(for: a.id) == .failed("Anmeldung fehlgeschlagen"))
    }
}
