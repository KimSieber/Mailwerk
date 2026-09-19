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
        messages = MessageStore.shared.allMessages(
            accountIDs: accountStore.accounts.map(\.id)
        )
    }

    @MainActor
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        var errors: [String] = []
        for account in accountStore.accounts {
            do {
                guard let password = try accountStore.password(for: account) else {
                    errors.append("\(account.displayName): kein Passwort gefunden")
                    continue
                }
                try await MailFetchService.refreshAndCache(
                    account: account, password: password
                )
            } catch {
                errors.append("\(account.displayName): \(error.localizedDescription)")
            }
        }

        loadFromCache()
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
}
