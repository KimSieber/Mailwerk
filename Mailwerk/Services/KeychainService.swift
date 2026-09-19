//
//  KeychainService.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//


//
//  KeychainService.swift
//  Mailwerk
//

import Foundation
import Security

/// Schlanker Wrapper um die Keychain Services API zur sicheren
/// Ablage von Postfach-Passwörtern, referenziert über die Account-UUID.
enum KeychainService {

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
        case dataConversionFailed
    }

    private static let service = "de.sieber-bw.Mailwerk.mailaccount"

    static func savePassword(_ password: String, for accountID: UUID) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let account = accountID.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true
        ]

        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func readPassword(for accountID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        return password
    }

    /// Löscht das Passwort, z. B. beim Entfernen eines Accounts.
    static func deletePassword(for accountID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
