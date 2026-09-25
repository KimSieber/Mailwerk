//
//  AccountStore.swift
//  Mailwerk
//
//  Verwaltet die Postfach-Konfigurationen (iCloud Key-Value-Store) und das
//  Standard-Postfach für neue Mails. Passwörter liegen im Keychain.
//

import Foundation
import Observation

@Observable
final class AccountStore {
    private static let accountsKey = "mailwerk.accounts"
    private static let defaultAccountKey = "mailwerk.defaultAccountID"
    private let store = NSUbiquitousKeyValueStore.default

    private(set) var accounts: [MailAccount] = []

    /// ID des Standard-Postfachs für neue Mails. `nil` = kein Standard definiert.
    private(set) var defaultAccountID: UUID?

    /// Das Standard-Postfach, sofern definiert und noch vorhanden.
    var defaultAccount: MailAccount? {
        guard let defaultAccountID else { return nil }
        return accounts.first { $0.id == defaultAccountID }
    }

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

    // MARK: - Postfächer

    func addAccount(_ account: MailAccount, password: String) throws {
        try KeychainService.savePassword(password, for: account.id)
        accounts.append(account)
        saveAccounts()
    }

    func removeAccount(_ account: MailAccount) throws {
        try KeychainService.deletePassword(for: account.id)
        accounts.removeAll { $0.id == account.id }
        saveAccounts()

        // Gelöschtes Standard-Postfach → Standard zurücksetzen
        if defaultAccountID == account.id {
            setDefaultAccount(nil)
        }
    }

    func updateAccount(_ updated: MailAccount, newPassword: String?) throws {
        guard let index = accounts.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        if let newPassword, !newPassword.isEmpty {
            try KeychainService.savePassword(newPassword, for: updated.id)
        }
        accounts[index] = updated
        saveAccounts()
    }

    func password(for account: MailAccount) throws -> String? {
        try KeychainService.readPassword(for: account.id)
    }

    /// Merkt den gefundenen bzw. angelegten Spam-Ordner beim Postfach.
    /// Unbekannte Kennungen werden übergangen.
    func setSpamFolder(_ folder: String?, for accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }),
              accounts[index].spamFolder != folder else { return }
        accounts[index].spamFolder = folder
        saveAccounts()
    }

    // MARK: - Standard-Postfach

    /// Setzt das Standard-Postfach. `nil` entfernt die Einstellung.
    /// Unbekannte IDs werden ignoriert.
    func setDefaultAccount(_ id: UUID?) {
        if let id, !accounts.contains(where: { $0.id == id }) {
            return
        }
        defaultAccountID = id
        if let id {
            store.set(id.uuidString, forKey: Self.defaultAccountKey)
        } else {
            store.removeObject(forKey: Self.defaultAccountKey)
        }
        store.synchronize()
    }

    // MARK: - Persistenz

    @objc private func externalChange(_ notification: Notification) {
        // Die Notification kommt auf einem Hintergrund-Thread an –
        // Observable-State wird ausschließlich auf dem Main-Thread geändert.
        DispatchQueue.main.async { [weak self] in
            self?.load()
        }
    }

    private func load() {
        if let data = store.data(forKey: Self.accountsKey),
           let decoded = try? JSONDecoder().decode([MailAccount].self, from: data) {
            accounts = decoded
        }

        // Standard-Postfach nur übernehmen, wenn es (schon) existiert.
        // Der gespeicherte Wert bleibt unangetastet: Kommen die Konten per
        // iCloud später an, greift er beim nächsten load() wieder.
        if let raw = store.string(forKey: Self.defaultAccountKey),
           let id = UUID(uuidString: raw),
           accounts.contains(where: { $0.id == id }) {
            defaultAccountID = id
        } else {
            defaultAccountID = nil
        }
    }

    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        store.set(data, forKey: Self.accountsKey)
        store.synchronize()
    }
}
