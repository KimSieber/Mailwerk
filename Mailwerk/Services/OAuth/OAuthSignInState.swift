//
//  OAuthSignInState.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 17.10.2026
//  Geändert: 17.10.2026
//
//  Zweck: Anmeldung per OAuth 2 aus Sicht der Oberfläche –
//  1. welche Postfächer neu angemeldet werden müssen (`signInRequired`,
//     Grundlage für Warnzeichen und Hinweisleiste),
//  2. das Anmeldefenster öffnen und den Anmelde-Code gegen Tokens tauschen
//     (`signIn`),
//  3. ein bestehendes Postfach neu anmelden (`renewSignIn`).
//
//  Anmeldefenster: Apple `ASWebAuthenticationSession` in einer privaten
//  Browser-Sitzung (keine fremden Cookies, kein Dialog „möchte sich
//  anmelden“). Die Funktion dafür (`webSignIn`) setzt die App beim Start
//  (MailwerkApp); in den Teilen-Erweiterungen bleibt sie leer – dort gibt
//  es kein Anmeldefenster, nur den Hinweis „Bitte in Mailwerk neu
//  anmelden“.
//
//  „Neu anmelden“ gilt nur, solange die App läuft; den Zustand stellt
//  der OAuthTokenService fest (abgelehntes Refresh-Token) und meldet ihn
//  hierher. Nach einem Neustart zeigt ihn der erste Abruf wieder.
//
//  Hier entsteht auch der gemeinsame OAuthTokenService (`shared`), weil
//  er seine Meldungen an diesen Zustand richtet.
//
//  Abgrenzung: Tokens holen, erneuern, zwischenspeichern →
//  OAuthTokenService; Anfragen und Prüfung der Rückkehr →
//  OAuthAuthorization; Anzeige → SignInRequiredBadge, SignInRequiredBar.
//
//  Abhängigkeiten: Foundation, Observation, OAuthProvider,
//  OAuthAuthorization, OAuthTokenService, OAuthError, MailAccount,
//  AccountStore, MailConnectionTester, Log.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation
import os

/// Öffnet das Anmeldefenster mit einer Adresse und liefert die Adresse,
/// mit der es zu Mailwerk zurückkehrt (Schema der Weiterleitung als
/// zweiter Wert). Wirft `OAuthError.cancelled`, wenn der Nutzer schließt.
typealias OAuthWebSignIn = @MainActor (URL, String) async throws -> URL

/// Zustand der Anmeldung per OAuth 2 für die Oberfläche.
@Observable
final class OAuthSignInState {
    /// Gemeinsamer Zustand der App bzw. Erweiterung.
    static let shared = OAuthSignInState()

    /// Postfächer, deren Anmeldung abgelaufen ist.
    private(set) var signInRequired: Set<UUID> = []

    /// Öffnet das Anmeldefenster; `nil` = nicht verfügbar (Erweiterung).
    @ObservationIgnored var webSignIn: OAuthWebSignIn?

    /// `true`, wenn hier ein Anmeldefenster geöffnet werden kann.
    var canSignIn: Bool { webSignIn != nil }

    /// Prüft, ob ein Postfach neu angemeldet werden muss.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: `true`, wenn die Anmeldung abgelaufen ist.
    func isSignInRequired(_ accountID: UUID) -> Bool {
        signInRequired.contains(accountID)
    }

    /// Setzt oder löscht „neu anmelden“ für ein Postfach.
    ///
    /// Verarbeitung: Geschrieben wird nur bei einer Änderung, damit die
    /// Oberfläche nicht ohne Grund neu zeichnet.
    ///
    /// - Parameters:
    ///   - required: `true` = Anmeldung abgelaufen.
    ///   - accountID: Postfach.
    func setSignInRequired(_ required: Bool, for accountID: UUID) {
        guard signInRequired.contains(accountID) != required else { return }
        if required {
            signInRequired.insert(accountID)
        } else {
            signInRequired.remove(accountID)
        }
    }

    // MARK: - Anmelden

    /// Meldet beim Anbieter an und liefert die Tokens.
    ///
    /// Verarbeitung: Bereitet PKCE und `state` vor, öffnet das
    /// Anmeldefenster mit der E-Mail-Adresse als Vorschlag, prüft die
    /// Rückkehr und tauscht den Anmelde-Code gegen Tokens. Gespeichert wird
    /// hier nichts.
    ///
    /// - Parameters:
    ///   - provider: Anbieter.
    ///   - loginHint: E-Mail-Adresse als Vorschlag im Anmeldefenster.
    /// - Returns: Tokens mit Refresh-Token.
    /// - Throws: `OAuthError` (u. a. `.cancelled`, `.signInUnavailable`)
    ///   oder Verbindungsfehler.
    func signIn(provider: OAuthProvider, loginHint: String) async throws -> OAuthTokenSet {
        guard let webSignIn else { throw OAuthError.signInUnavailable }
        let authorization = try OAuthAuthorization.start(provider: provider, loginHint: loginHint)
        let callback = try await webSignIn(authorization.url, provider.callbackScheme)
        let code = try OAuthAuthorization.code(from: callback, expectedState: authorization.state)
        let tokens = try await OAuthTokenService.shared.exchange(code: code, authorization: authorization)
        Log.auth.info("🔑 Anmeldung bei \(provider.name, privacy: .public) erfolgreich")
        return tokens
    }

    /// Meldet ein bestehendes Postfach neu an.
    ///
    /// Verarbeitung: Öffnet das Anmeldefenster mit dem Anmeldenamen des
    /// Postfachs als Vorschlag und prüft mit dem neuen
    /// Token die IMAP-Anmeldung – so wird keine Anmeldung eines anderen
    /// Kontos gespeichert. Erst dann ersetzt das neue Refresh-Token das
    /// alte, der Dienst übernimmt die Tokens und „neu anmelden“ entfällt.
    ///
    /// - Parameters:
    ///   - account: Postfach mit Anmeldung per OAuth 2.
    ///   - accountStore: Ablage des Refresh-Tokens.
    /// - Throws: `OAuthError`, `MailConnectionTester.TestError`, Fehler des
    ///   Schlüsselbunds oder Verbindungsfehler.
    func renewSignIn(for account: MailAccount, accountStore: AccountStore) async throws {
        guard let provider = account.oauthConfiguration else { return }
        let tokens = try await signIn(provider: provider, loginHint: account.username)
        try await MailConnectionTester.testIMAP(
            host: account.imapHost, port: account.imapPort,
            username: account.username, login: .accessToken(tokens.accessToken)
        )
        guard let refreshToken = tokens.refreshToken else { throw OAuthError.missingRefreshToken }
        try accountStore.updateRefreshToken(refreshToken, for: account.id)
        await OAuthTokenService.shared.adopt(tokens, for: account.id)
        setSignInRequired(false, for: account.id)
        Log.auth.info("🔑 [\(account.displayName, privacy: .private)] neu angemeldet")
    }
}

extension OAuthTokenService {
    /// Gemeinsamer Dienst: Refresh-Tokens im Schlüsselbund, Anfragen über
    /// `URLSession`, Meldungen „neu anmelden“ an `OAuthSignInState.shared`.
    nonisolated static let shared = OAuthTokenService(
        storage: .keychain,
        transport: { request in try await URLSession.shared.data(for: request) },
        now: { Date() },
        report: { accountID, required in
            await MainActor.run {
                OAuthSignInState.shared.setSignInRequired(required, for: accountID)
            }
        }
    )
}
