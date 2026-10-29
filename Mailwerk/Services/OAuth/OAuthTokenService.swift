//
//  OAuthTokenService.swift
//  Mailwerk
//
//  Zweck: Liefert für Postfächer mit Anmeldung per OAuth 2 ein gültiges
//  Access-Token – aus dem Speicher, sonst erneuert mit dem Refresh-Token
//  aus dem Schlüsselbund. Tauscht außerdem nach dem Anmeldefenster den
//  Anmelde-Code gegen Tokens.
//
//  Regeln:
//  - Access-Tokens liegen nur im Speicher (`cache`), nie im Schlüsselbund
//    oder im Protokoll.
//  - Je Postfach läuft höchstens eine Erneuerung zur Zeit; wer währenddessen
//    ein Token braucht, wartet auf dieselbe (`pending`). So entstehen keine
//    doppelten Anfragen, wenn Abruf, Spamfilter und Versand gleichzeitig
//    anmelden.
//  - Schickt der Anbieter ein neues Refresh-Token, ersetzt es sofort das
//    alte im Schlüsselbund.
//  - Lehnt der Anbieter das Refresh-Token ab (`invalid_grant`) oder ist
//    keins gespeichert, gilt die Anmeldung als abgelaufen: Mailwerk merkt
//    sich das abgelehnte Token (`rejected`) und meldet „neu anmelden“.
//    Solange im Schlüsselbund dasselbe Token liegt, wird nicht erneut
//    beim Anbieter angefragt. Liegt dort ein anderes (etwa weil ein
//    anderes Gerät sich neu angemeldet hat und der iCloud-Schlüsselbund es
//    gebracht hat), wird es versucht.
//  - Ein fehlendes Netz ist kein Ablauf: Verbindungsfehler (URLError)
//    gehen unverändert an den Aufrufer.
//
//  Das Speichern des Refresh-Tokens nach einer Anmeldung übernimmt der
//  AccountStore (zusammen mit dem Postfach); danach übernimmt `adopt` die
//  frischen Tokens.
//
//  Teilen-Erweiterung: Sie nutzt denselben Dienst und darf erneuern; den
//  gemeinsamen Schlüsselbund teilt sie mit der App.
//
//  Abgrenzung: Anfragen bauen → OAuthAuthorization; Antworten lesen →
//  OAuthTokenResponse; Anmeldefenster und Anzeige „abgelaufen“ →
//  OAuthSignInState (dort auch `shared`).
//
//  Abhängigkeiten: Foundation, OAuthProvider, OAuthAuthorization,
//  OAuthTokenResponse, OAuthError, KeychainService (über
//  RefreshTokenStorage), Log.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import os

/// Zugriff auf die gespeicherten Refresh-Tokens (Schlüsselbund; in Tests
/// im Speicher).
nonisolated struct RefreshTokenStorage: Sendable {
    /// Liest das Refresh-Token eines Postfachs; `nil` = keins gespeichert.
    var read: @Sendable (UUID) throws -> String?
    /// Speichert das Refresh-Token eines Postfachs.
    var save: @Sendable (String, UUID) throws -> Void

    /// Ablage im Schlüsselbund (iCloud, mit den Erweiterungen geteilt).
    static let keychain = RefreshTokenStorage(
        read: { try KeychainService.readRefreshToken(for: $0) },
        save: { try KeychainService.saveRefreshToken($0, for: $1) }
    )
}

/// Sendet eine Anfrage und liefert Inhalt und Antwort.
typealias OAuthTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Meldet, ob ein Postfach neu angemeldet werden muss (`true`) oder wieder
/// angemeldet ist (`false`).
typealias OAuthSignInReport = @Sendable (UUID, Bool) async -> Void

/// Access-Tokens holen, erneuern und zwischenspeichern.
actor OAuthTokenService {
    /// Ablage der Refresh-Tokens.
    private let storage: RefreshTokenStorage
    /// Versand der Anfragen an den Token-Endpunkt.
    private let transport: OAuthTransport
    /// Aktueller Zeitpunkt (in Tests fest).
    private let now: @Sendable () -> Date
    /// Meldet Änderungen „neu anmelden“ an die Oberfläche.
    private let report: OAuthSignInReport

    /// Gültige Tokens je Postfach (nur im Speicher).
    private var cache: [UUID: OAuthTokenSet] = [:]
    /// Laufende Erneuerungen je Postfach.
    private var pending: [UUID: Task<OAuthTokenSet, Error>] = [:]
    /// Vom Anbieter abgelehnte Refresh-Tokens je Postfach; leer = es war
    /// keins gespeichert.
    private var rejected: [UUID: String] = [:]

    /// Legt den Dienst an.
    ///
    /// - Parameters:
    ///   - storage: Ablage der Refresh-Tokens.
    ///   - transport: Versand der Anfragen.
    ///   - now: Aktueller Zeitpunkt.
    ///   - report: Meldet „neu anmelden“ bzw. „wieder angemeldet“.
    init(
        storage: RefreshTokenStorage,
        transport: @escaping OAuthTransport,
        now: @escaping @Sendable () -> Date,
        report: @escaping OAuthSignInReport
    ) {
        self.storage = storage
        self.transport = transport
        self.now = now
        self.report = report
    }

    // MARK: - Access-Token

    /// Liefert ein gültiges Access-Token.
    ///
    /// Verarbeitung: Ein Token im Speicher wird genommen, solange es noch
    /// mehr als den Vorlauf gilt. Sonst wird erneuert – läuft für das
    /// Postfach schon eine Erneuerung, wird auf sie gewartet.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - provider: Anbieter des Postfachs.
    /// - Returns: Access-Token.
    /// - Throws: `OAuthError.signInRequired`, Fehler des Anbieters,
    ///   Verbindungsfehler oder Fehler des Schlüsselbunds.
    func accessToken(accountID: UUID, provider: OAuthProvider) async throws -> String {
        if let tokens = cache[accountID], tokens.isUsable(at: now()) {
            return tokens.accessToken
        }
        if let running = pending[accountID] {
            return try await running.value.accessToken
        }
        let task = Task { try await self.renew(accountID: accountID, provider: provider) }
        pending[accountID] = task
        defer { pending[accountID] = nil }
        return try await task.value.accessToken
    }

    /// Erneuert die Tokens eines Postfachs mit dem Refresh-Token.
    ///
    /// Verarbeitung: Ohne gespeichertes Refresh-Token oder mit einem schon
    /// abgelehnten wird ohne Anfrage „neu anmelden“ gemeldet. Sonst wird
    /// angefragt; ein neues Refresh-Token ersetzt das alte im Schlüsselbund
    /// (scheitert das Speichern, bleibt das alte gültig und es wird nur
    /// protokolliert). Nach einer Ablehnung (`invalid_grant`) wird das
    /// Token gemerkt und „neu anmelden“ gemeldet.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - provider: Anbieter.
    /// - Returns: Neue Tokens.
    /// - Throws: wie `accessToken(accountID:provider:)`.
    private func renew(accountID: UUID, provider: OAuthProvider) async throws -> OAuthTokenSet {
        let stored = try storage.read(accountID) ?? ""
        guard !stored.isEmpty else {
            await markSignInRequired(accountID, rejectedToken: "")
            throw OAuthError.signInRequired
        }
        if rejected[accountID] == stored {
            throw OAuthError.signInRequired
        }

        let request = OAuthAuthorization.refreshRequest(provider: provider, refreshToken: stored)
        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        let tokens: OAuthTokenSet
        do {
            tokens = try OAuthTokenResponse.parse(data, statusCode: status, now: now())
        } catch OAuthError.signInRequired {
            Log.auth.error("🔑 Anmeldung abgelehnt (invalid_grant) – neu anmelden nötig")
            await markSignInRequired(accountID, rejectedToken: stored)
            throw OAuthError.signInRequired
        }

        if let newRefreshToken = tokens.refreshToken, newRefreshToken != stored {
            do {
                try storage.save(newRefreshToken, accountID)
            } catch {
                Log.auth.error("⚠️ Neues Refresh-Token nicht gespeichert: \(error.localizedDescription, privacy: .public)")
            }
        }
        cache[accountID] = tokens
        await clearSignInRequired(accountID)
        let minutes = Int(tokens.expiresAt.timeIntervalSince(now()) / 60)
        Log.auth.info("🔑 Access-Token erneuert, gültig \(minutes, privacy: .public) min")
        return tokens
    }

    // MARK: - Anmeldung

    /// Tauscht den Anmelde-Code gegen Tokens.
    ///
    /// Verarbeitung: Eine dauerhafte Anmeldung braucht ein Refresh-Token;
    /// fehlt es, ist die Anmeldung unbrauchbar. Ein ungültiger Code
    /// (`invalid_grant`) ist hier kein Ablauf, sondern ein Fehler des
    /// Anmeldevorgangs.
    ///
    /// - Parameters:
    ///   - code: Anmelde-Code aus der Rückkehr des Anmeldefensters.
    ///   - authorization: Laufende Anmeldung (Anbieter, PKCE).
    /// - Returns: Tokens mit Refresh-Token.
    /// - Throws: `OAuthError` oder Verbindungsfehler.
    func exchange(code: String, authorization: OAuthAuthorization) async throws -> OAuthTokenSet {
        let request = OAuthAuthorization.codeExchangeRequest(
            provider: authorization.provider, code: code, verifier: authorization.pkce.verifier
        )
        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let tokens: OAuthTokenSet
        do {
            tokens = try OAuthTokenResponse.parse(data, statusCode: status, now: now())
        } catch OAuthError.signInRequired {
            throw OAuthError.providerError(code: "invalid_grant", description: "Der Anmelde-Code ist ungültig oder abgelaufen.")
        }
        guard tokens.refreshToken != nil else { throw OAuthError.missingRefreshToken }
        return tokens
    }

    /// Übernimmt die Tokens einer frischen Anmeldung.
    ///
    /// Verarbeitung: Das Refresh-Token hat der Aufrufer schon gespeichert;
    /// hier wird das Access-Token zwischengespeichert und „neu anmelden“
    /// zurückgenommen.
    ///
    /// - Parameters:
    ///   - tokens: Tokens der Anmeldung.
    ///   - accountID: Postfach.
    func adopt(_ tokens: OAuthTokenSet, for accountID: UUID) async {
        cache[accountID] = tokens
        await clearSignInRequired(accountID)
    }

    /// Verwirft das Access-Token im Speicher, etwa weil der Server es
    /// abgelehnt hat; die nächste Anmeldung erneuert es.
    ///
    /// - Parameter accountID: Postfach.
    func invalidate(_ accountID: UUID) {
        cache[accountID] = nil
    }

    /// Vergisst alles zu einem entfernten Postfach.
    ///
    /// - Parameter accountID: Postfach.
    func forget(_ accountID: UUID) {
        cache[accountID] = nil
        rejected[accountID] = nil
        pending[accountID]?.cancel()
        pending[accountID] = nil
    }

    // MARK: - Zustand „neu anmelden“

    /// Merkt ein abgelehntes Refresh-Token und meldet „neu anmelden“.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - rejectedToken: Abgelehntes Token; leer = keins gespeichert.
    private func markSignInRequired(_ accountID: UUID, rejectedToken: String) async {
        cache[accountID] = nil
        rejected[accountID] = rejectedToken
        await report(accountID, true)
    }

    /// Nimmt „neu anmelden“ zurück, falls es gesetzt war.
    ///
    /// - Parameter accountID: Postfach.
    private func clearSignInRequired(_ accountID: UUID) async {
        guard rejected.removeValue(forKey: accountID) != nil else { return }
        await report(accountID, false)
    }
}
