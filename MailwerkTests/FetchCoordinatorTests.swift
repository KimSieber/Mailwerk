//
//  FetchCoordinatorTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den FetchCoordinator – Abrufe laufen nacheinander,
//  gleiche Anforderungen werden nicht doppelt ausgeführt, wartende
//  Ordnerabrufe werden von neueren verdrängt. Die Abrufe sind hier
//  Platzhalter, die über eine Schranke angehalten werden; ein Server
//  wird nicht gebraucht.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FetchCoordinatorTests {

    /// Testhilfe: hält eine Operation an, bis `open()` aufgerufen wird.
    final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    /// Testhilfe: Protokoll der Operationen.
    final class Log {
        var entries: [String] = []
    }

    /// Testhilfe: gibt anderen Aufgaben Zeit, bis die Bedingung gilt.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() {
            await Task.yield()
        }
    }

    /// Gleiche Anforderung während des Laufs: wird angeschlossen, nicht wiederholt.
    @Test func sameRequestJoinsRunning() async {
        let coordinator = FetchCoordinator<String>()
        let log = Log()
        let gate = Gate()

        let first = Task {
            await coordinator.run("A") {
                log.entries.append("start A")
                await gate.wait()
                log.entries.append("end A")
            }
        }
        await waitUntil { log.entries.contains("start A") }
        let second = Task {
            await coordinator.run("A") { log.entries.append("start A2") }
        }
        await waitUntil { false }
        gate.open()

        #expect(await first.value == .performed)
        #expect(await second.value == .joined)
        #expect(log.entries == ["start A", "end A"])
    }

    /// Andere Anforderung während des Laufs: startet erst nach dessen Ende.
    @Test func differentRequestsRunSequentially() async {
        let coordinator = FetchCoordinator<String>()
        let log = Log()
        let gate = Gate()

        let first = Task {
            await coordinator.run("A") {
                log.entries.append("start A")
                await gate.wait()
                log.entries.append("end A")
            }
        }
        await waitUntil { log.entries.contains("start A") }
        let second = Task {
            await coordinator.run("B") { log.entries.append("start B") }
        }
        await waitUntil { coordinator.isScheduled("B") }
        #expect(log.entries == ["start A"])
        gate.open()

        #expect(await first.value == .performed)
        #expect(await second.value == .performed)
        #expect(log.entries == ["start A", "end A", "start B"])
    }

    /// Mehrere wartende Ordner: nur der zuletzt gewählte wird abgerufen.
    @Test func newerFolderSupersedesWaitingFolder() async {
        let coordinator = FetchCoordinator<FetchRequest>(supersedes: FetchRequest.supersedes)
        let log = Log()
        let gate = Gate()
        let account = UUID()

        let inbox = Task {
            await coordinator.run(.inboxes) {
                log.entries.append("start inboxes")
                await gate.wait()
                log.entries.append("end inboxes")
            }
        }
        await waitUntil { log.entries.contains("start inboxes") }
        let folder1 = Task {
            await coordinator.run(.folder(accountID: account, path: "Eins")) {
                log.entries.append("Eins")
            }
        }
        await waitUntil { coordinator.isScheduled(.folder(accountID: account, path: "Eins")) }
        let folder2 = Task {
            await coordinator.run(.folder(accountID: account, path: "Zwei")) {
                log.entries.append("Zwei")
            }
        }
        await waitUntil { coordinator.isScheduled(.folder(accountID: account, path: "Zwei")) }
        gate.open()

        #expect(await inbox.value == .performed)
        #expect(await folder1.value == .superseded)
        #expect(await folder2.value == .performed)
        #expect(log.entries == ["start inboxes", "end inboxes", "Zwei"])
    }

    /// Ein laufender Ordnerabruf wird nicht verdrängt.
    @Test func runningFolderIsNotSuperseded() async {
        let coordinator = FetchCoordinator<FetchRequest>(supersedes: FetchRequest.supersedes)
        let log = Log()
        let gate = Gate()
        let account = UUID()

        let folder1 = Task {
            await coordinator.run(.folder(accountID: account, path: "Eins")) {
                log.entries.append("start Eins")
                await gate.wait()
                log.entries.append("end Eins")
            }
        }
        await waitUntil { log.entries.contains("start Eins") }
        let folder2 = Task {
            await coordinator.run(.folder(accountID: account, path: "Zwei")) {
                log.entries.append("Zwei")
            }
        }
        await waitUntil { coordinator.isScheduled(.folder(accountID: account, path: "Zwei")) }
        gate.open()

        #expect(await folder1.value == .performed)
        #expect(await folder2.value == .performed)
        #expect(log.entries == ["start Eins", "end Eins", "Zwei"])
    }

    /// Verdrängter Ordner erneut gewählt: wird neu eingeplant und abgerufen.
    @Test func reselectedSupersededFolderRunsAgain() async {
        let coordinator = FetchCoordinator<FetchRequest>(supersedes: FetchRequest.supersedes)
        let log = Log()
        let gate = Gate()
        let account = UUID()
        let eins = FetchRequest.folder(accountID: account, path: "Eins")
        let zwei = FetchRequest.folder(accountID: account, path: "Zwei")

        let inbox = Task {
            await coordinator.run(.inboxes) {
                await gate.wait()
            }
        }
        await waitUntil { coordinator.isScheduled(.inboxes) }
        let first = Task { await coordinator.run(eins) { log.entries.append("Eins") } }
        await waitUntil { coordinator.isScheduled(eins) }
        let second = Task { await coordinator.run(zwei) { log.entries.append("Zwei") } }
        await waitUntil { coordinator.isScheduled(zwei) }
        let third = Task { await coordinator.run(eins) { log.entries.append("Eins erneut") } }
        await waitUntil { coordinator.isScheduled(eins) }
        gate.open()

        _ = await inbox.value
        #expect(await first.value == .superseded)
        #expect(await second.value == .superseded)
        #expect(await third.value == .performed)
        #expect(log.entries == ["Eins erneut"])
    }

    /// Nach dem Ende kann dieselbe Anforderung erneut ausgeführt werden.
    @Test func sameRequestRunsAgainAfterCompletion() async {
        let coordinator = FetchCoordinator<String>()
        let log = Log()

        #expect(await coordinator.run("A") { log.entries.append("A1") } == .performed)
        #expect(await coordinator.run("A") { log.entries.append("A2") } == .performed)
        #expect(log.entries == ["A1", "A2"])
        #expect(!coordinator.isBusy)
    }

    /// Verdrängungsregel: nur Ordner verdrängen Ordner.
    @Test func supersedeRuleOnlyForFolders() {
        let account = UUID()
        let folder = FetchRequest.folder(accountID: account, path: "X")
        let other = FetchRequest.folder(accountID: account, path: "Y")
        #expect(FetchRequest.supersedes(folder, other))
        #expect(!FetchRequest.supersedes(folder, .inboxes))
        #expect(!FetchRequest.supersedes(.inboxes, folder))
        #expect(!FetchRequest.supersedes(.older(targets: ["a"]), folder))
        #expect(!FetchRequest.supersedes(folder, .older(targets: ["a"])))
    }
}
