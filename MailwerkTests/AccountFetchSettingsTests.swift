//
//  AccountFetchSettingsTests.swift
//  MailwerkTests
//
//  Zweck: Test für den Schalter „Abruf“ je Postfach im AccountStore
//  (lokal gespeichert, nicht über iCloud).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für den Abruf-Schalter im AccountStore.
@MainActor
struct AccountFetchSettingsTests {

    /// Ausschalten wirkt sofort, bleibt nach Neustart erhalten und lässt sich zurücknehmen.
    @Test("Abruf-Schalter: lokal gespeichert, nach Neustart erhalten")
    func persistsLocally() throws {
        let suite = "mailwerk.tests.fetch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountID = UUID()

        let store = AccountStore(localDefaults: defaults)
        #expect(store.isFetchEnabled(accountID))

        store.setFetchEnabled(false, for: accountID)
        #expect(!store.isFetchEnabled(accountID))
        #expect(!AccountStore(localDefaults: defaults).isFetchEnabled(accountID))

        store.setFetchEnabled(true, for: accountID)
        #expect(AccountStore(localDefaults: defaults).isFetchEnabled(accountID))
    }
}
