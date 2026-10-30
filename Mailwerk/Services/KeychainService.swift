//
//  KeychainService.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.09.2026
//  Geändert: 17.10.2026
//
//  Zweck: Schlanker Wrapper um die Keychain Services API zur sicheren
//  Ablage der Zugangsdaten eines Postfachs, referenziert über die
//  Account-UUID: das Passwort (Anmeldung mit Passwort) bzw. das
//  Refresh-Token (Anmeldung per OAuth 2). Beide liegen unter eigenem
//  Service-Namen, damit sie sich nie gegenseitig überschreiben.
//
//  Die Einträge werden mit `kSecAttrSynchronizable = true` angelegt und
//  per iCloud-Schlüsselbund auf alle Geräte synchronisiert. Die
//  Schutzklasse `afterFirstUnlock` stellt sicher, dass sie auch bei
//  gesperrtem Gerät für Hintergrundabrufe verfügbar sind. Die Einträge
//  liegen in der gemeinsamen Schlüsselbundgruppe der App, damit auch die
//  Teilen-Erweiterungen sie lesen (und Refresh-Tokens erneuern) können.
//
//  Der Dienst ist bewusst nicht an den Main-Actor gebunden: Der
//  OAuthTokenService liest und schreibt Refresh-Tokens aus seinem eigenen
//  Actor heraus.
//
//  Abgrenzung: Welches Geheimnis zu welchem Postfach gehört, verwaltet
//  der AccountStore; dieser Service kennt nur die UUID und den String.
//
//  Abhängigkeiten: Security.framework.
//

import Foundation
import Security

nonisolated enum KeychainService {

    /// Fehler beim Zugriff auf den Schlüsselbund.
    enum KeychainError: Error {
        /// Unerwarteter Status der Keychain Services API.
        case unexpectedStatus(OSStatus)
        /// Der Wert konnte nicht in UTF-8 kodiert oder dekodiert werden.
        case dataConversionFailed
    }

    /// Art eines gespeicherten Geheimnisses; bestimmt den Service-Namen.
    enum Item: String {
        /// Passwort eines Postfachs (Service-Name seit der ersten Version).
        case password = "de.sieber-bw.Mailwerk.mailaccount"
        /// Refresh-Token eines Postfachs mit Anmeldung per OAuth 2.
        case refreshToken = "de.sieber-bw.Mailwerk.oauth.refreshtoken"
    }

    /// Basis-Query: identifiziert einen Eintrag über Service, Account-UUID
    /// und Synchronisierbarkeit.
    ///
    /// - Parameters:
    ///   - item: Art des Geheimnisses.
    ///   - accountID: UUID des Postfachs.
    /// - Returns: Query-Dictionary mit den vier Schlüsseln.
    private static func baseQuery(_ item: Item, for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.rawValue,
            kSecAttrAccount as String: accountID.uuidString,
            kSecAttrSynchronizable as String: true
        ]
    }

    // MARK: - Passwort

    /// Speichert oder aktualisiert das Passwort eines Postfachs.
    ///
    /// - Parameters:
    ///   - password: Passwort im Klartext.
    ///   - accountID: UUID des Postfachs.
    /// - Throws: siehe `save(_:as:for:)`.
    static func savePassword(_ password: String, for accountID: UUID) throws {
        try save(password, as: .password, for: accountID)
    }

    /// Liest das Passwort eines Postfachs.
    ///
    /// - Parameter accountID: UUID des Postfachs.
    /// - Returns: Passwort oder `nil`, wenn keins gespeichert ist.
    /// - Throws: siehe `read(_:for:)`.
    static func readPassword(for accountID: UUID) throws -> String? {
        try read(.password, for: accountID)
    }

    /// Löscht das Passwort eines Postfachs.
    ///
    /// - Parameter accountID: UUID des Postfachs.
    /// - Throws: siehe `delete(_:for:)`.
    static func deletePassword(for accountID: UUID) throws {
        try delete(.password, for: accountID)
    }

    // MARK: - Refresh-Token

    /// Speichert oder aktualisiert das Refresh-Token eines Postfachs.
    ///
    /// - Parameters:
    ///   - token: Refresh-Token.
    ///   - accountID: UUID des Postfachs.
    /// - Throws: siehe `save(_:as:for:)`.
    static func saveRefreshToken(_ token: String, for accountID: UUID) throws {
        try save(token, as: .refreshToken, for: accountID)
    }

    /// Liest das Refresh-Token eines Postfachs.
    ///
    /// - Parameter accountID: UUID des Postfachs.
    /// - Returns: Refresh-Token oder `nil`, wenn keins gespeichert ist.
    /// - Throws: siehe `read(_:for:)`.
    static func readRefreshToken(for accountID: UUID) throws -> String? {
        try read(.refreshToken, for: accountID)
    }

    /// Löscht das Refresh-Token eines Postfachs.
    ///
    /// - Parameter accountID: UUID des Postfachs.
    /// - Throws: siehe `delete(_:for:)`.
    static func deleteRefreshToken(for accountID: UUID) throws {
        try delete(.refreshToken, for: accountID)
    }

    // MARK: - Speichern

    /// Speichert oder aktualisiert ein Geheimnis im Schlüsselbund.
    ///
    /// Verarbeitung: Versucht zuerst ein Update des bestehenden Eintrags.
    /// Existiert noch keiner (`errSecItemNotFound`), wird ein neuer Eintrag
    /// angelegt. So bleibt der Schlüsselbund frei von verwaisten Einträgen,
    /// die beim alten Vorgehen „Löschen + Neuanlegen" entstehen konnten.
    ///
    /// - Parameters:
    ///   - value: Geheimnis im Klartext.
    ///   - item: Art des Geheimnisses.
    ///   - accountID: UUID des Postfachs.
    /// - Throws: `KeychainError.dataConversionFailed` bei einem
    ///   Kodierungsfehler, `KeychainError.unexpectedStatus` bei einem
    ///   Fehler der Keychain API.
    private static func save(_ value: String, as item: Item, for accountID: UUID) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let query = baseQuery(item, for: accountID)
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

    /// Liest ein Geheimnis aus dem Schlüsselbund.
    ///
    /// - Parameters:
    ///   - item: Art des Geheimnisses.
    ///   - accountID: UUID des Postfachs.
    /// - Returns: Geheimnis im Klartext oder `nil`, wenn keins gespeichert ist.
    /// - Throws: `KeychainError.unexpectedStatus` bei einem Fehler der
    ///   Keychain API, `KeychainError.dataConversionFailed` bei einem
    ///   Dekodierungsfehler.
    private static func read(_ item: Item, for accountID: UUID) throws -> String? {
        var query = baseQuery(item, for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        return value
    }

    // MARK: - Löschen

    /// Löscht ein Geheimnis aus dem Schlüsselbund.
    ///
    /// Verarbeitung: Der Query enthält `kSecAttrSynchronizable = true`,
    /// damit genau der synchronisierte Eintrag gelöscht wird. Ohne dieses
    /// Attribut würde `SecItemDelete` den Eintrag nicht finden, weil
    /// synchronisierbare Einträge eine eigene Suche erfordern. Ein bereits
    /// fehlender Eintrag (`errSecItemNotFound`) wird still akzeptiert.
    ///
    /// - Parameters:
    ///   - item: Art des Geheimnisses.
    ///   - accountID: UUID des Postfachs.
    /// - Throws: `KeychainError.unexpectedStatus` bei einem Fehler der
    ///   Keychain API.
    private static func delete(_ item: Item, for accountID: UUID) throws {
        let query = baseQuery(item, for: accountID)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
