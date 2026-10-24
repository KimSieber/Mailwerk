//
//  AccountFetchStateTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Erreichbarkeit je Postfach – Hinweis in der
//  Titelzeile (offline, alle, eines, mehrere, keines), Hinweise für die
//  Apple Watch, Setzen und Löschen des Zustands sowie die
//  zusammengefassten Hinweise der Kennzeichen am Postfach.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct AccountFetchStateTests {

    private let gmx = (id: UUID(), name: "GMX")
    private let posteo = (id: UUID(), name: "Posteo")
    private let gmail = (id: UUID(), name: "Gmail")

    private var all: [(id: UUID, name: String)] { [gmx, posteo, gmail] }

    // MARK: - Titelzeile

    /// Ohne Netz zählt nichts anderes: „Offline“.
    @Test func offlineWins() {
        let status = AccountFetchState.titleStatus(isOnline: false, accounts: all, unreachable: [gmx.id])
        #expect(status == "Offline")
    }

    /// Alles erreichbar: kein Hinweis.
    @Test func allReachableYieldsNoStatus() {
        #expect(AccountFetchState.titleStatus(isOnline: true, accounts: all, unreachable: []) == nil)
    }

    /// Ein Postfach nicht erreichbar: sein Name.
    @Test func singleUnreachableNamesAccount() {
        let status = AccountFetchState.titleStatus(isOnline: true, accounts: all, unreachable: [gmx.id])
        #expect(status == "GMX nicht erreichbar")
    }

    /// Mehrere, aber nicht alle: die Anzahl.
    @Test func severalUnreachableCountsAccounts() {
        let status = AccountFetchState.titleStatus(isOnline: true, accounts: all, unreachable: [gmx.id, gmail.id])
        #expect(status == "2 Postfächer nicht erreichbar")
    }

    /// Alle Postfächer der Ansicht nicht erreichbar: „Keine Verbindung“.
    @Test func allUnreachableYieldsNoConnection() {
        let status = AccountFetchState.titleStatus(
            isOnline: true, accounts: all, unreachable: [gmx.id, posteo.id, gmail.id]
        )
        #expect(status == "Keine Verbindung")
    }

    /// Ein Ordner gehört zu einem Postfach: Ist es nicht erreichbar, gilt
    /// „Keine Verbindung“.
    @Test func singleAccountViewYieldsNoConnection() {
        let status = AccountFetchState.titleStatus(isOnline: true, accounts: [gmx], unreachable: [gmx.id])
        #expect(status == "Keine Verbindung")
    }

    /// Nicht erreichbare Postfächer außerhalb der Ansicht zählen nicht.
    @Test func accountsOutsideViewAreIgnored() {
        let status = AccountFetchState.titleStatus(isOnline: true, accounts: [posteo], unreachable: [gmx.id])
        #expect(status == nil)
    }

    // MARK: - Watch

    /// Je nicht erreichbarem Postfach eine Zeile, in der Reihenfolge der
    /// Postfächer.
    @Test func watchProblemsPerAccount() {
        let problems = AccountFetchState.watchProblems(accounts: all, unreachable: [gmail.id, gmx.id])
        #expect(problems == [
            "GMX: keine Verbindung zum Mailserver",
            "Gmail: keine Verbindung zum Mailserver",
        ])
    }

    /// Alles erreichbar: keine Zeile.
    @Test func watchProblemsEmptyWhenReachable() {
        #expect(AccountFetchState.watchProblems(accounts: all, unreachable: []).isEmpty)
    }

    // MARK: - Zustand

    /// Setzen und Löschen je Postfach; andere Postfächer bleiben unberührt.
    @Test func setAndClearPerAccount() {
        let state = AccountFetchState()
        state.setUnreachable(true, for: gmx.id, name: gmx.name)
        state.setUnreachable(true, for: posteo.id, name: posteo.name)
        #expect(state.isUnreachable(gmx.id))
        #expect(state.isUnreachable(posteo.id))

        state.setUnreachable(false, for: gmx.id, name: gmx.name)
        #expect(!state.isUnreachable(gmx.id))
        #expect(state.isUnreachable(posteo.id))
        #expect(state.unreachable == [posteo.id])
    }

    // MARK: - Kennzeichen

    /// Zusammengefasste Hinweise in der Reihenfolge der Zeichen.
    @Test func badgeSummary() {
        #expect(AccountStatusBadges.summary(needsSignIn: false, isUnreachable: false, isPaused: false) == nil)
        #expect(AccountStatusBadges.summary(needsSignIn: false, isUnreachable: true, isPaused: false)
                == "Postfach nicht erreichbar")
        #expect(AccountStatusBadges.summary(needsSignIn: true, isUnreachable: true, isPaused: true)
                == "Anmeldung abgelaufen, Postfach nicht erreichbar, Abruf ausgeschaltet")
    }
}
