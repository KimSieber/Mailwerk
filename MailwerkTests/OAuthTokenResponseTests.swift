//
//  OAuthTokenResponseTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Lesen der Antwort des Token-Endpunkts
//  (OAuthTokenResponse) und die Gültigkeit eines Access-Tokens
//  (OAuthTokenSet).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct OAuthTokenResponseTests {

    /// Testhilfe: fester Zeitpunkt.
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// Testhilfe: JSON-Text als Daten.
    private func json(_ text: String) -> Data { Data(text.utf8) }

    /// Erfolg: Tokens und Ablaufzeit aus `expires_in`.
    @Test func parsesSuccessfulResponse() throws {
        let tokens = try OAuthTokenResponse.parse(
            json(#"{"token_type":"Bearer","access_token":"A1","refresh_token":"R1","expires_in":3600}"#),
            statusCode: 200, now: now
        )
        #expect(tokens.accessToken == "A1")
        #expect(tokens.refreshToken == "R1")
        #expect(tokens.expiresAt == now.addingTimeInterval(3600))
    }

    /// Ohne Refresh-Token bleibt es `nil`; `expires_in` darf Text sein.
    @Test func refreshTokenIsOptional() throws {
        let tokens = try OAuthTokenResponse.parse(
            json(#"{"access_token":"A1","expires_in":"1800"}"#), statusCode: 200, now: now
        )
        #expect(tokens.refreshToken == nil)
        #expect(tokens.expiresAt == now.addingTimeInterval(1800))
    }

    /// `invalid_grant` heißt: neu anmelden.
    @Test func invalidGrantMeansSignInRequired() {
        #expect(throws: OAuthError.signInRequired) {
            try OAuthTokenResponse.parse(
                json(#"{"error":"invalid_grant","error_description":"AADSTS70000"}"#),
                statusCode: 400, now: now
            )
        }
    }

    /// Andere Fehler bleiben Fehler des Anbieters.
    @Test func otherErrorsAreProviderErrors() {
        #expect(throws: OAuthError.providerError(code: "invalid_client", description: "falsch")) {
            try OAuthTokenResponse.parse(
                json(#"{"error":"invalid_client","error_description":"falsch"}"#),
                statusCode: 401, now: now
            )
        }
    }

    /// Fehlerstatus ohne lesbaren Inhalt ist eine unerwartete Antwort.
    @Test func errorStatusWithoutJSONIsInvalid() {
        #expect(throws: OAuthError.invalidResponse("HTTP 503")) {
            try OAuthTokenResponse.parse(json("Service Unavailable"), statusCode: 503, now: now)
        }
    }

    /// Fehlendes Access-Token bzw. fehlende Ablaufzeit sind unerwartet.
    @Test func missingFieldsAreInvalid() {
        #expect(throws: OAuthError.invalidResponse("Kein Access-Token")) {
            try OAuthTokenResponse.parse(json(#"{"expires_in":3600}"#), statusCode: 200, now: now)
        }
        #expect(throws: OAuthError.invalidResponse("Keine Ablaufzeit")) {
            try OAuthTokenResponse.parse(json(#"{"access_token":"A1"}"#), statusCode: 200, now: now)
        }
    }

    /// Ein Token gilt nur bis fünf Minuten vor dem Ablauf.
    @Test func tokenIsUsableUntilRenewalMargin() {
        let tokens = OAuthTokenSet(accessToken: "A", refreshToken: nil, expiresAt: now.addingTimeInterval(600))
        #expect(tokens.isUsable(at: now))
        #expect(tokens.isUsable(at: now.addingTimeInterval(299)))
        #expect(!tokens.isUsable(at: now.addingTimeInterval(300)))
    }

    /// Meldung „abgelaufen“ verweist auf Mailwerk.
    @Test func signInRequiredMessage() {
        #expect(OAuthError.signInRequired.errorDescription == "Die Anmeldung ist abgelaufen. Bitte in Mailwerk neu anmelden.")
    }
}
