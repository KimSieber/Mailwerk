//
//  InboxViewModel.swift
//  Mailwerk
//

import Foundation
import Observation

@Observable
final class InboxViewModel {
    private let accountStore: AccountStore

    var messages: [CachedMessage] = []
    var isLoading = false
    var errorMessage: String?

    init(accountStore: AccountStore) {
        self.accountStore = accountStore
        loadFromCache()
    }

    func loadFromCache() {
        let accountIDs = accountStore.accounts.map(\.id)
        print("📋 loadFromCache: \(accountIDs.count) Konten → \(accountIDs.map(\.uuidString))")
        messages = MessageStore.shared.allMessages(accountIDs: accountIDs)
        print("📋 loadFromCache: \(messages.count) Nachrichten geladen")
    }

    @MainActor
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        print("🔄 Refresh gestartet für \(accountStore.accounts.count) Konten")

        var errors: [String] = []
        for account in accountStore.accounts {
            print("🔄 Starte Abruf: \(account.displayName) (ID: \(account.id.uuidString))")
            do {
                guard let password = try accountStore.password(for: account) else {
                    errors.append("\(account.displayName): kein Passwort gefunden")
                    print("❌ \(account.displayName): kein Passwort im Keychain")
                    continue
                }
                try await MailFetchService.refreshAndCache(
                    account: account, password: password
                )
                print("✅ \(account.displayName): Abruf abgeschlossen")
            } catch {
                errors.append("\(account.displayName): \(error.localizedDescription)")
                print("❌ \(account.displayName): \(error.localizedDescription)")
            }

            // Nach jedem Konto Liste aktualisieren → schrittweiser Aufbau
            loadFromCache()
        }

        loadFromCache()
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
        print("🔄 Refresh fertig. Fehler: \(errors.count), Nachrichten gesamt: \(messages.count)")
    }
}
