//
//  KeychainService.swift
//  Mailwerk
//
//  Zweck: Schlanker Wrapper um die Keychain Services API zur sicheren
//  Ablage von Postfach-Passwörtern, referenziert über die Account-UUID.
//
//  Die Einträge werden mit `kSecAttrSynchronizable = true` angelegt und
//  per iCloud-Schlüsselbund auf alle Geräte synchronisiert. Die
//  Schutzklasse `afterFirstUnlock` stellt sicher, dass Passwörter auch
//  bei gesperrtem Gerät für Hintergrundabrufe verfügbar sind.
//
//  Abgrenzung: Welches Passwort zu welchem Postfach gehört, verwaltet
//  der AccountStore; dieser Service kennt nur die UUID und den String.
//
//  Abhängigkeiten: Security.framework.
//

import Foundation
import Security

enum KeychainService {

    /// Fehler beim Zugriff auf den Schlüsselbund.
    enum KeychainError: Error {
        /// Unerwarteter Status der Keychain Services API.
        case unexpectedStatus(OSStatus)
        /// Das Passwort konnte nicht in UTF-8 kodiert oder dekodiert werden.
        case dataConversionFailed
    }

    /// Service-Attribut, das alle Mailwerk-Passwörter gruppiert.
    private static let service = "de.sieber-bw.Mailwerk.mailaccount"

    /// Basis-Query: identifiziert einen Eintrag über Service, Account-UUID
    /// und Synchronisierbarkeit.
    ///
    /// - Parameter accountID: UUID des Postfachs.
    /// - Returns: Query-Dictionary mit den drei Schlüsseln.
    private static func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecAttrSynchronizable as String: true
        ]
    }

    // MARK: - Speichern

    /// Speichert oder aktualisiert ein Passwort im Schlüsselbund.
    ///
    /// Verarbeitung: Versucht zuerst ein Update des bestehenden Eintrags.
    /// Existiert noch keiner (`errSecItemNotFound`), wird ein neuer Eintrag
    /// angelegt. So bleibt der Schlüsselbund frei von verwaisten Einträgen,
    /// die beim alten Vorgehen „Löschen + Neuanlegen" entstehen konnten.
    ///
    /// - Parameters:
    ///   - password: Passwort im Klartext.
    ///   - accountID: UUID des Postfachs.
    /// - Throws: `KeychainError.dataConversionFailed` bei einem
    ///   Kodierungsfehler, `KeychainError.unexpectedStatus` bei einem
    ///   Fehler der Keychain API.
    static func savePassword(_ password: String, for accountID: UUID) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let query = baseQuery(for: accountID)
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            // Noch kein Eintrag → neu anlegen
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Lesen

    /// Liest das Passwort eines Postfachs aus dem Schlüsselbund.
    ///
    /// - Parameter accountID: UUID des Postfachs.
    /// - Returns: Passwort im Klartext oder `nil`, wenn keins gespeichert ist.
    /// - Throws: `KeychainError.unexpectedStatus` bei einem Fehler der
    ///   Keychain API, `KeychainError.dataConversionFailed` bei einem
    ///   Dekodierungsfehler.
    static func readPassword(for accountID: UUID) throws -> String? {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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

    // MARK: - Löschen

    /// Löscht das Passwort eines Postfachs aus dem Schlüsselbund.
    ///
    /// Verarbeitung: Der Query enthält `kSecAttrSynchronizable = true`,
    /// damit genau der synchronisierte Eintrag gelöscht wird. Ohne dieses
    /// Attribut würde `SecItemDelete` den Eintrag nicht finden, weil
    /// synchronisierbare Einträge eine eigene Suche erfordern. Ein bereits
    /// fehlender Eintrag (`errSecItemNotFound`) wird still akzeptiert.
    ///
    /// - Parameter accountID: UUID des Postfachs.
    /// - Throws: `KeychainError.unexpectedStatus` bei einem Fehler der
    ///   Keychain API.
    static func deletePassword(for accountID: UUID) throws {
        let query = baseQuery(for: accountID)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
