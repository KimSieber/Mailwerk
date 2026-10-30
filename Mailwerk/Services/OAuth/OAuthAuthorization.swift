//
//  OAuthAuthorization.swift
//  Mailwerk
//
//  Zweck: Anfragen der Anmeldung per OAuth 2 („Authorization Code“ mit
//  PKCE) aufbauen und die Rückkehr aus dem Anmeldefenster prüfen.
//
//  Ablauf einer Anmeldung:
//  1. `start` erzeugt PKCE und `state` und baut die Adresse des
//     Anmeldefensters (mit der E-Mail-Adresse als Vorschlag).
//  2. Das Anmeldefenster (Apple, ASWebAuthenticationSession) kehrt über
//     die Weiterleitungsadresse zurück; `code(from:expectedState:)` prüft
//     `state` und liest den Anmelde-Code – oder den Fehler des Anbieters.
//  3. `codeExchangeRequest` tauscht den Code samt Prüfwert gegen Tokens;
//     `refreshRequest` erneuert sie später mit dem Refresh-Token.
//
//  Alle Anfragen sind reine Daten (URL, URLRequest) – senden und
//  auswerten übernimmt der OAuthTokenService, die Antwort liest
//  OAuthTokenResponse.
//
//  Abhängigkeiten: Foundation, OAuthProvider, OAuthPKCE, OAuthError.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Eine laufende Anmeldung: Adresse des Anmeldefensters samt der Werte,
/// die bis zur Rückkehr in der App bleiben.
nonisolated struct OAuthAuthorization: Equatable, Sendable {
    /// Anbieter.
    let provider: OAuthProvider
    /// Prüfwert und Abbild (PKCE).
    let pkce: OAuthPKCE
    /// Zufallswert, der unverändert zurückkommen muss.
    let state: String
    /// Adresse des Anmeldefensters.
    let url: URL

    /// Bereitet eine Anmeldung vor.
    ///
    /// - Parameters:
    ///   - provider: Anbieter.
    ///   - loginHint: E-Mail-Adresse als Vorschlag im Anmeldefenster;
    ///     leer = keiner.
    /// - Returns: Anmeldung mit Adresse, PKCE und `state`.
    /// - Throws: `OAuthError.randomUnavailable`.
    static func start(provider: OAuthProvider, loginHint: String?) throws -> OAuthAuthorization {
        let pkce = try OAuthPKCE.make()
        let state = try OAuthPKCE.randomString(byteCount: 16)
        let url = authorizationURL(provider: provider, pkce: pkce, state: state, loginHint: loginHint)
        return OAuthAuthorization(provider: provider, pkce: pkce, state: state, url: url)
    }

    /// Baut die Adresse des Anmeldefensters.
    ///
    /// Verarbeitung: Verlangt einen Anmelde-Code (`response_type=code`)
    /// mit PKCE (S256). Die E-Mail-Adresse geht als `login_hint` mit,
    /// damit der Nutzer sie nicht erneut tippen muss.
    ///
    /// - Parameters:
    ///   - provider: Anbieter.
    ///   - pkce: Prüfwert und Abbild.
    ///   - state: Zufallswert.
    ///   - loginHint: E-Mail-Adresse als Vorschlag; leer = keiner.
    /// - Returns: Adresse mit allen Parametern.
    static func authorizationURL(
        provider: OAuthProvider,
        pkce: OAuthPKCE,
        state: String,
        loginHint: String?
    ) -> URL {
        var components = URLComponents(url: provider.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: provider.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: provider.redirectURI),
            URLQueryItem(name: "scope", value: provider.scopeString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method)
        ]
        let hint = loginHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hint.isEmpty {
            items.append(URLQueryItem(name: "login_hint", value: hint))
        }
        components.queryItems = items
        return components.url!
    }

    /// Liest den Anmelde-Code aus der Rückkehr des Anmeldefensters.
    ///
    /// Verarbeitung: Zuerst zählt ein Fehler des Anbieters (`error`),
    /// dann muss `state` genau dem gesendeten Wert entsprechen, zuletzt
    /// muss ein Code da sein. Ein abweichendes `state` gilt immer als
    /// Fehler – auch wenn ein Code mitkommt.
    ///
    /// - Parameters:
    ///   - callback: Adresse, mit der das Anmeldefenster zurückkehrte.
    ///   - expectedState: Gesendeter Zufallswert.
    /// - Returns: Anmelde-Code.
    /// - Throws: `OAuthError.providerError`, `.stateMismatch` oder
    ///   `.invalidResponse`.
    static func code(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        /// Wert eines Abfrage-Parameters der Rückkehr-Adresse.
        ///
        /// - Parameter name: Name des Parameters.
        /// - Returns: Wert oder `nil`, wenn er fehlt.
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        if let error = value("error") {
            throw OAuthError.providerError(code: error, description: value("error_description"))
        }
        guard value("state") == expectedState else {
            throw OAuthError.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw OAuthError.invalidResponse("Kein Anmelde-Code")
        }
        return code
    }

    /// Anfrage, die den Anmelde-Code gegen Tokens tauscht.
    ///
    /// - Parameters:
    ///   - provider: Anbieter.
    ///   - code: Anmelde-Code aus der Rückkehr.
    ///   - verifier: Prüfwert der PKCE dieser Anmeldung.
    /// - Returns: POST-Anfrage an den Token-Endpunkt.
    static func codeExchangeRequest(provider: OAuthProvider, code: String, verifier: String) -> URLRequest {
        tokenRequest(provider: provider, parameters: [
            ("client_id", provider.clientID),
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", provider.redirectURI),
            ("code_verifier", verifier),
            ("scope", provider.scopeString)
        ])
    }

    /// Anfrage, die mit dem Refresh-Token neue Tokens holt.
    ///
    /// - Parameters:
    ///   - provider: Anbieter.
    ///   - refreshToken: Gespeichertes Refresh-Token.
    /// - Returns: POST-Anfrage an den Token-Endpunkt.
    static func refreshRequest(provider: OAuthProvider, refreshToken: String) -> URLRequest {
        tokenRequest(provider: provider, parameters: [
            ("client_id", provider.clientID),
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("scope", provider.scopeString)
        ])
    }

    /// Baut eine POST-Anfrage an den Token-Endpunkt.
    ///
    /// Verarbeitung: Parameter als `application/x-www-form-urlencoded`; ein
    /// Client-Geheimnis gibt es nicht (öffentlicher Client).
    ///
    /// - Parameters:
    ///   - provider: Anbieter.
    ///   - parameters: Name-Wert-Paare in fester Reihenfolge.
    /// - Returns: POST-Anfrage.
    private static func tokenRequest(provider: OAuthProvider, parameters: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: provider.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = Data(formEncoded(parameters).utf8)
        return request
    }

    /// Kodiert Parameter als Formular-Text.
    ///
    /// Verarbeitung: Nur die nicht reservierten Zeichen (RFC 3986:
    /// Buchstaben, Ziffern, „-._~“) bleiben stehen; alles andere wird
    /// prozentkodiert – auch „+“, „/“, „:“ und Leerzeichen.
    ///
    /// - Parameter parameters: Name-Wert-Paare.
    /// - Returns: Text der Form `a=1&b=2`.
    static func formEncoded(_ parameters: [(String, String)]) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return parameters.map { name, value in
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedName)=\(encodedValue)"
        }
        .joined(separator: "&")
    }
}
