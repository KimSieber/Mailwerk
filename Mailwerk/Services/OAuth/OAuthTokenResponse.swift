//
//  OAuthTokenResponse.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 17.10.2026
//  Geändert: 17.10.2026
//
//  Zweck: Antwort des Token-Endpunkts lesen – Tokens samt Ablaufzeit bei
//  Erfolg, sonst den Fehler des Anbieters richtig einordnen.
//
//  Tokens:
//  - Access-Token: gilt rund eine Stunde und meldet Mailwerk am IMAP- und
//    SMTP-Server an (XOAUTH2). Es liegt nur im Speicher.
//  - Refresh-Token: holt neue Access-Tokens ohne Anmeldefenster. Es liegt
//    im Schlüsselbund. Microsoft schickt bei jeder Erneuerung ein neues
//    mit; das neue ersetzt das alte.
//
//  Fehler: `invalid_grant` heißt, das Refresh-Token gilt nicht mehr
//  (Passwort geändert, Zustimmung widerrufen, lange nicht benutzt) → neu
//  anmelden (`OAuthError.signInRequired`). Alle anderen Fehler bleiben
//  Fehler des Anbieters.
//
//  Abgrenzung: Anfragen bauen → OAuthAuthorization; senden, speichern und
//  erneuern → OAuthTokenService.
//
//  Abhängigkeiten: Foundation, OAuthError.
//

import Foundation

/// Tokens einer Anmeldung.
nonisolated struct OAuthTokenSet: Equatable, Sendable {
    /// Token für die Anmeldung am Server.
    let accessToken: String
    /// Token zum Erneuern; `nil`, wenn der Anbieter keins mitgeschickt hat
    /// (bei einer Erneuerung bleibt dann das bisherige gültig).
    let refreshToken: String?
    /// Zeitpunkt, an dem das Access-Token abläuft.
    let expiresAt: Date

    /// Vorlauf vor dem Ablauf: So lange vorher gilt ein Access-Token schon
    /// als verbraucht – damit es nicht mitten in einer Sitzung abläuft.
    static let renewalMargin: TimeInterval = 5 * 60

    /// Prüft, ob das Access-Token noch verwendet werden darf.
    ///
    /// - Parameter now: Aktueller Zeitpunkt.
    /// - Returns: `true`, wenn bis zum Ablauf mehr als `renewalMargin` bleibt.
    func isUsable(at now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) > Self.renewalMargin
    }
}

/// Auswertung der Antwort des Token-Endpunkts.
nonisolated enum OAuthTokenResponse {

    /// Liest eine Antwort des Token-Endpunkts.
    ///
    /// Verarbeitung: Ein JSON-Feld `error` gilt als Fehler, unabhängig vom
    /// HTTP-Status; `invalid_grant` wird zu `signInRequired`. Bei Erfolg
    /// sind `access_token` und `expires_in` Pflicht; die Ablaufzeit ergibt
    /// sich aus `now` plus `expires_in` Sekunden.
    ///
    /// - Parameters:
    ///   - data: Inhalt der Antwort.
    ///   - statusCode: HTTP-Status.
    ///   - now: Zeitpunkt des Empfangs.
    /// - Returns: Tokens samt Ablaufzeit.
    /// - Throws: `OAuthError.signInRequired`, `.providerError` oder
    ///   `.invalidResponse`.
    static func parse(_ data: Data, statusCode: Int, now: Date) throws -> OAuthTokenSet {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let error = object?["error"] as? String {
            if error == "invalid_grant" {
                throw OAuthError.signInRequired
            }
            throw OAuthError.providerError(
                code: error, description: object?["error_description"] as? String
            )
        }
        guard (200..<300).contains(statusCode) else {
            throw OAuthError.invalidResponse("HTTP \(statusCode)")
        }
        guard let object else {
            throw OAuthError.invalidResponse("Antwort ist kein JSON")
        }
        guard let accessToken = object["access_token"] as? String, !accessToken.isEmpty else {
            throw OAuthError.invalidResponse("Kein Access-Token")
        }
        guard let lifetime = seconds(object["expires_in"]) else {
            throw OAuthError.invalidResponse("Keine Ablaufzeit")
        }
        let refreshToken = (object["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return OAuthTokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(lifetime)
        )
    }

    /// Liest eine Sekundenzahl, die als Zahl oder als Text kommen kann.
    ///
    /// - Parameter value: Wert aus dem JSON.
    /// - Returns: Sekunden oder `nil`, wenn der Wert fehlt oder unlesbar ist.
    private static func seconds(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return TimeInterval(text) }
        return nil
    }
}
