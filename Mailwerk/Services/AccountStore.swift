//
//  AccountStore.swift
//  Mailwerk
//

import Foundation
import Observation

@Observable
final class AccountStore {
    private static let key = "mailwerk.accounts"
    private let store = NSUbiquitousKeyValueStore.default

    private(set) var accounts: [MailAccount] = []

    init() {
        load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    func addAccount(_ account: MailAccount, password: String) throws {
        try KeychainService.savePassword(password, for: account.id)
        accounts.append(account)
        save()
    }

    func removeAccount(_ account: MailAccount) throws {
        try KeychainService.deletePassword(for: account.id)
        accounts.removeAll { $0.id == account.id }
        save()
    }

    func updateAccount(_ updated: MailAccount, newPassword: String?) throws {
        guard let index = accounts.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        if let newPassword, !newPassword.isEmpty {
            try KeychainService.savePassword(newPassword, for: updated.id)
        }
        accounts[index] = updated
        save()
    }
    
    func password(for account: MailAccount) throws -> String? {
        try KeychainService.readPassword(for: account.id)
    }

    @objc private func externalChange(_ notification: Notification) {
        load()
    }

    private func load() {
        guard let data = store.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([MailAccount].self, from: data) else {
            return
        }
        accounts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        store.set(data, forKey: Self.key)
        store.synchronize()
    }
}
