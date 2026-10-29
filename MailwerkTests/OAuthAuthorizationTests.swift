//
//  OAuthAuthorizationTests.swift
//  MailwerkTests
//
//  Zweck: Tests für PKCE (OAuthPKCE), den Aufbau der Anmelde-Adresse, die
//  Prüfung der Rückkehr aus dem Anmeldefenster und die Anfragen an den
//  Token-Endpunkt (OAuthAuthorization) sowie die Microsoft-Konfiguration.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Mailwerk

@MainActor
struct OAuthAuthorizationTests {

    /// Testhilfe: feste PKCE-Werte aus RFC 7636, Anhang B.
    private let pkce = OAuthPKCE(
        verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    )

    /// Testhilfe: Parameter einer Adresse als Wörterbuch.
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    /// Testhilfe: Formular-Text einer Anfrage als Wörterbuch (dekodiert).
    private func form(_ request: URLRequest) -> [String: String] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        var result: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            result[parts[0]] = parts.count > 1 ? parts[1].removingPercentEncoding : ""
        }
        return result
    }

    /// Abbild des Prüfwerts entspricht dem Beispiel aus RFC 7636.
    @Test func challengeMatchesRFC7636() {
        #expect(OAuthPKCE.challenge(for: pkce.verifier) == pkce.challenge)
    }

    /// Neuer Prüfwert: 43 Zeichen Base64-URL, ohne Füllzeichen, passendes Abbild.
    @Test func generatedVerifierIsValid() throws {
        let made = try OAuthPKCE.make()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(made.verifier.count == 43)
        #expect(made.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
        #expect(made.challenge == OAuthPKCE.challenge(for: made.verifier))
        #expect(made.method == "S256")
        #expect(try OAuthPKCE.make().verifier != made.verifier)
    }

    /// Base64-URL ersetzt „+“ und „/“ und lässt „=“ weg.
    @Test func base64URLHasNoPadding() {
        #expect(OAuthPKCE.base64URL(Data([0xFB, 0xFF])) == "-_8")
    }

    /// Anmelde-Adresse enthält Code-Verfahren, PKCE, state und Vorschlag.
    @Test func authorizationURLCarriesAllParameters() {
        let url = OAuthAuthorization.authorizationURL(
            provider: .microsoft, pkce: pkce, state: "abc", loginHint: " kim@outlook.com "
        )
        let items = query(url)
        #expect(url.host == "login.microsoftonline.com")
        #expect(url.path == "/consumers/oauth2/v2.0/authorize")
        #expect(items["client_id"] == OAuthProvider.microsoft.clientID)
        #expect(items["response_type"] == "code")
        #expect(items["redirect_uri"] == "msauth.de.sieber-bw.Mailwerk://auth")
        #expect(items["scope"] == "https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access")
        #expect(items["state"] == "abc")
        #expect(items["code_challenge"] == pkce.challenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["login_hint"] == "kim@outlook.com")
        #expect(items["code_verifier"] == nil)
    }

    /// Ohne Vorschlag fehlt `login_hint`.
    @Test func authorizationURLWithoutHint() {
        let url = OAuthAuthorization.authorizationURL(provider: .microsoft, pkce: pkce, state: "s", loginHint: "  ")
        #expect(query(url)["login_hint"] == nil)
    }

    /// Rückkehr mit passendem state liefert den Code.
    @Test func callbackWithMatchingStateYieldsCode() throws {
        let url = URL(string: "msauth.de.sieber-bw.Mailwerk://auth?code=M.C123&state=abc")!
        #expect(try OAuthAuthorization.code(from: url, expectedState: "abc") == "M.C123")
    }

    /// Abweichender state ist ein Fehler, auch mit Code.
    @Test func callbackWithWrongStateThrows() {
        let url = URL(string: "msauth.de.sieber-bw.Mailwerk://auth?code=M.C123&state=fremd")!
        #expect(throws: OAuthError.stateMismatch) {
            try OAuthAuthorization.code(from: url, expectedState: "abc")
        }
    }

    /// Fehler des Anbieters wird mit Code und Text gemeldet.
    @Test func callbackWithProviderErrorThrows() {
        let url = URL(string: "msauth.de.sieber-bw.Mailwerk://auth?error=access_denied&error_description=Abgelehnt&state=abc")!
        #expect(throws: OAuthError.providerError(code: "access_denied", description: "Abgelehnt")) {
            try OAuthAuthorization.code(from: url, expectedState: "abc")
        }
    }

    /// Rückkehr ohne Code ist ein Fehler.
    @Test func callbackWithoutCodeThrows() {
        let url = URL(string: "msauth.de.sieber-bw.Mailwerk://auth?state=abc")!
        #expect(throws: OAuthError.invalidResponse("Kein Anmelde-Code")) {
            try OAuthAuthorization.code(from: url, expectedState: "abc")
        }
    }

    /// Tausch des Codes: POST mit Prüfwert, ohne Client-Geheimnis.
    @Test func codeExchangeRequestCarriesVerifier() {
        let request = OAuthAuthorization.codeExchangeRequest(provider: .microsoft, code: "M.C123", verifier: pkce.verifier)
        let fields = form(request)
        #expect(request.httpMethod == "POST")
        #expect(request.url == OAuthProvider.microsoft.tokenEndpoint)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["code"] == "M.C123")
        #expect(fields["code_verifier"] == pkce.verifier)
        #expect(fields["redirect_uri"] == "msauth.de.sieber-bw.Mailwerk://auth")
        #expect(fields["client_secret"] == nil)
    }

    /// Erneuern: POST mit Refresh-Token und Berechtigungen.
    @Test func refreshRequestCarriesRefreshToken() {
        let request = OAuthAuthorization.refreshRequest(provider: .microsoft, refreshToken: "R+1/2=")
        let fields = form(request)
        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["refresh_token"] == "R+1/2=")
        #expect(fields["scope"] == OAuthProvider.microsoft.scopeString)
    }

    /// Formular-Kodierung lässt nur nicht reservierte Zeichen stehen.
    @Test func formEncodingEscapesReservedCharacters() {
        #expect(OAuthAuthorization.formEncoded([("a", "x y+z/:=&"), ("b", "A-z._~0")])
                == "a=x%20y%2Bz%2F%3A%3D%26&b=A-z._~0")
    }

    /// Microsoft: Server und Weiterleitungsschema wie belegt.
    @Test func microsoftConfiguration() {
        let provider = OAuthProvider.provider(for: .microsoft)
        #expect(provider.imapHost == "outlook.office365.com")
        #expect(provider.imapPort == 993)
        #expect(provider.smtpHost == "smtp-mail.outlook.com")
        #expect(provider.smtpPort == 587)
        #expect(provider.callbackScheme == "msauth.de.sieber-bw.Mailwerk")
    }
}
