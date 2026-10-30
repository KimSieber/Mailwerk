//
//  MailSession.swift
//  Mailwerk
//
//  Zweck: Zugangsdaten und Anmeldung an einer Stelle. Jede Server-Aktion
//  (Abruf, Kennzeichnen, Verschieben, Ordner, Spamfilter, Anhang
//  nachladen, Gesendet-Kopie, Versand) braucht dasselbe:
//  1. Postfach und Zugang bestimmen – mit einheitlichen Fehlern, wenn das
//     Postfach fehlt oder kein Passwort gespeichert ist;
//  2. verbinden, anmelden, die Aktion ausführen, abmelden – und bei einem
//     Fehler die Verbindung trennen.
//
//  Anmeldeart: Postfächer mit Passwort melden sich wie bisher mit
//  Benutzername und Passwort an. Postfächer mit Anmeldung per OAuth 2
//  (`MailAccount.oauthProvider`) holen ihr Access-Token beim
//  OAuthTokenService und melden sich mit XOAUTH2 an – an IMAP wie an SMTP.
//  Für IMAP bekommt SwiftMail zusätzlich eine Token-Quelle: Baut es eine
//  abgerissene Verbindung still neu auf, meldet es sich so mit einem
//  frischen Token an statt mit dem alten. Lehnt der Server ein Token ab,
//  wird es im Speicher verworfen, damit der nächste Versuch erneuert.
//
//  Die Verschlüsselung erzwingt weiterhin `MailServerFactory`.
//
//  Nebenläufigkeit (v0.2.3b): `nonisolated`. `withIMAP` läuft im Kontext
//  des Aufrufers – aus dem Abruf (`@concurrent`) also abseits des
//  Hauptthreads. Die Erweiterung von `AccountStore` am Ende bleibt am
//  Main-Actor wie `AccountStore` selbst.
//
//  Abgrenzung: Was auf der Verbindung geschieht, bestimmen die Dienste
//  (MailFetchService, MailActionService, SpamFilterService,
//  MailSendService, AttachmentManager). SMTP baut seine Verbindung im
//  MailSendService selbst auf, meldet sich aber über `authenticate`
//  hier an. Verbindungstest beim Einrichten → MailConnectionTester.
//
//  Abhängigkeiten: SwiftMail (IMAP, SMTP), MailServerFactory, AccountStore,
//  OAuthTokenService, OAuthProvider.
//

import Foundation
import SwiftMail
import os

/// Zugang eines Postfachs: Passwort oder Anmeldung per OAuth 2.
nonisolated enum MailSecret: Equatable, Sendable {
    /// Passwort aus dem Schlüsselbund.
    case password(String)
    /// Anmeldung per OAuth 2 beim Anbieter; das Access-Token liefert der
    /// OAuthTokenService erst beim Anmelden.
    case oauth(OAuthProvider)
}

/// Postfach und Zugang für eine Verbindung.
nonisolated struct MailCredentials: Sendable {
    /// Postfach (Server, Port, Benutzername).
    let account: MailAccount
    /// Passwort bzw. Anbieter der Anmeldung per OAuth 2.
    let secret: MailSecret
}

/// Fehler beim Bestimmen der Zugangsdaten.
nonisolated enum MailCredentialError: LocalizedError, Equatable {
    /// Das Postfach ist (nicht mehr) eingerichtet.
    case accountNotFound
    /// Für das Postfach ist kein Passwort gespeichert.
    case noPassword

    /// Liefert die deutsche Meldung für den Nutzer.
    ///
    /// - Returns: Meldungstext; Aufrufer stellen meist den Postfachnamen voran.
    var errorDescription: String? {
        switch self {
        case .accountNotFound: return "Postfach nicht gefunden"
        case .noPassword: return "Kein Passwort gespeichert"
        }
    }
}

/// Zugangsdaten bestimmen, anmelden und IMAP-Verbindungen führen.
nonisolated enum MailSession {

    /// Bestimmt die Zugangsdaten zu einer Postfach-ID.
    ///
    /// Verarbeitung: Sucht das Postfach in der Liste und bestimmt seinen
    /// Zugang (`resolve(account:password:)`).
    ///
    /// - Parameters:
    ///   - accountID: ID des Postfachs.
    ///   - accounts: Eingerichtete Postfächer.
    ///   - password: Liest das Passwort eines Postfachs (`nil` = keines).
    /// - Returns: Postfach und Zugang.
    /// - Throws: `MailCredentialError` oder den Lesefehler des Schlüsselbunds.
    static func resolve(
        accountID: UUID,
        in accounts: [MailAccount],
        password: (MailAccount) throws -> String?
    ) throws -> MailCredentials {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            throw MailCredentialError.accountNotFound
        }
        return try resolve(account: account, password: password)
    }

    /// Bestimmt die Zugangsdaten zu einem bekannten Postfach.
    ///
    /// Verarbeitung: Ein Postfach mit Anmeldung per OAuth 2 braucht kein
    /// Passwort – sein Token holt erst die Anmeldung. Sonst wird das
    /// Passwort gelesen; ein Lesefehler des Schlüsselbunds wird unverändert
    /// weitergegeben, damit seine Ursache sichtbar bleibt.
    ///
    /// - Parameters:
    ///   - account: Postfach.
    ///   - password: Liest das Passwort eines Postfachs (`nil` = keines).
    /// - Returns: Postfach und Zugang.
    /// - Throws: `MailCredentialError.noPassword` oder den Lesefehler des
    ///   Schlüsselbunds.
    static func resolve(
        account: MailAccount,
        password: (MailAccount) throws -> String?
    ) throws -> MailCredentials {
        if let provider = account.oauthConfiguration {
            return MailCredentials(account: account, secret: .oauth(provider))
        }
        guard let value = try password(account) else {
            throw MailCredentialError.noPassword
        }
        return MailCredentials(account: account, secret: .password(value))
    }

    /// Führt eine Aktion über eine eigene, verschlüsselte IMAP-Verbindung aus.
    ///
    /// Verarbeitung: Verbindet, meldet an, führt `body` aus und meldet ab.
    /// Bei einem Fehler – auch beim Abmelden – wird die Verbindung getrennt
    /// und der Fehler unverändert weitergegeben. Ein Ergebnis gilt also nur,
    /// wenn auch das Abmelden geklappt hat; Aufrufer, die danach einen Stand
    /// speichern, tun das erst nach der Rückkehr.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Zugang.
    ///   - body: Aktion auf der angemeldeten Verbindung.
    /// - Returns: Ergebnis von `body`.
    /// - Throws: Verbindungs-, Anmelde- oder IMAP-Fehler sowie Fehler aus `body`.
    static func withIMAP<T>(
        _ credentials: MailCredentials,
        _ body: (SwiftMail.IMAPServer) async throws -> T
    ) async throws -> T {
        let server = MailServerFactory.imapServer(for: credentials.account)
        do {
            try await server.connect()
            try await authenticate(server, as: credentials)
            let result = try await body(server)
            try await server.logout()
            return result
        } catch {
            await disconnectQuietly(Log.fetch, host: credentials.account.imapHost) {
                try await server.disconnect()
            }
            throw error
        }
    }

    /// Trennt eine Verbindung, deren Ergebnis schon feststeht.
    ///
    /// Verarbeitung: Gerufen nach einem Fehler (der eigentliche Fehler ist
    /// bekannt und wird vom Aufrufer weitergegeben) oder nach erledigtem
    /// Versand. Ein Fehler beim Trennen – etwa weil die Verbindung längst
    /// abgerissen ist – ändert am Ergebnis nichts. Er wird deshalb nur
    /// protokolliert (`.debug`) und nicht geworfen.
    ///
    /// - Parameters:
    ///   - log: Logger des Bereichs (z. B. `Log.fetch`, `Log.send`).
    ///   - host: Server, für die Zuordnung im Protokoll.
    ///   - disconnect: Trennt die Verbindung (IMAP oder SMTP).
    static func disconnectQuietly(
        _ log: Logger,
        host: String,
        _ disconnect: () async throws -> Void
    ) async {
        do {
            try await disconnect()
        } catch {
            log.debug("Trennen von \(host, privacy: .public) gescheitert: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Anmelden

    /// Meldet eine verbundene IMAP-Verbindung an.
    ///
    /// Verarbeitung: Mit Passwort per LOGIN. Per OAuth 2 mit XOAUTH2 und
    /// einem Token vom OAuthTokenService; danach bekommt SwiftMail die
    /// Token-Quelle für das stille Neuverbinden. Lehnt der Server das Token
    /// ab, wird es im Speicher verworfen.
    ///
    /// - Parameters:
    ///   - server: Verbundener IMAP-Server.
    ///   - credentials: Postfach und Zugang.
    /// - Throws: Anmelde- oder Verbindungsfehler, `OAuthError`.
    static func authenticate(_ server: SwiftMail.IMAPServer, as credentials: MailCredentials) async throws {
        let username = credentials.account.username
        switch credentials.secret {
        case .password(let password):
            try await server.login(username: username, password: password)
        case .oauth(let provider):
            let accountID = credentials.account.id
            let tokenSource = accessTokenSource(accountID: accountID, provider: provider)
            let token = try await tokenSource()
            do {
                try await server.authenticateXOAUTH2(email: username, accessToken: token)
            } catch {
                await OAuthTokenService.shared.invalidate(accountID)
                throw error
            }
            await server.setXOAUTH2AccessTokenProvider(email: username, accessTokenProvider: tokenSource)
        }
    }

    /// Meldet eine verbundene SMTP-Verbindung an.
    ///
    /// Verarbeitung: Mit Passwort über das beste Verfahren des Servers
    /// (PLAIN, LOGIN). Per OAuth 2 mit XOAUTH2; lehnt der Server das Token
    /// ab, wird es im Speicher verworfen.
    ///
    /// - Parameters:
    ///   - server: Verbundener SMTP-Server.
    ///   - credentials: Postfach und Zugang.
    /// - Throws: Anmelde- oder Verbindungsfehler, `OAuthError`.
    static func authenticate(_ server: SwiftMail.SMTPServer, as credentials: MailCredentials) async throws {
        let username = credentials.account.username
        switch credentials.secret {
        case .password(let password):
            try await server.login(username: username, password: password)
        case .oauth(let provider):
            let accountID = credentials.account.id
            let token = try await accessTokenSource(accountID: accountID, provider: provider)()
            do {
                try await server.authenticateXOAUTH2(email: username, accessToken: token)
            } catch {
                await OAuthTokenService.shared.invalidate(accountID)
                throw error
            }
        }
    }

    /// Quelle für Access-Tokens eines Postfachs.
    ///
    /// Verarbeitung: Fragt bei jedem Aufruf den OAuthTokenService – der
    /// liefert das Token aus dem Speicher oder erneuert es.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - provider: Anbieter.
    /// - Returns: Funktion, die ein gültiges Access-Token liefert.
    private static func accessTokenSource(
        accountID: UUID,
        provider: OAuthProvider
    ) -> @Sendable () async throws -> String {
        {
            try await OAuthTokenService.shared.accessToken(accountID: accountID, provider: provider)
        }
    }
}

extension AccountStore {
    /// Zugangsdaten zu einer Postfach-ID.
    ///
    /// - Parameter accountID: ID des Postfachs.
    /// - Returns: Postfach und Zugang.
    /// - Throws: `MailCredentialError` oder einen Lesefehler des Schlüsselbunds.
    func credentials(for accountID: UUID) throws -> MailCredentials {
        try MailSession.resolve(accountID: accountID, in: accounts) { try password(for: $0) }
    }

    /// Zugangsdaten zu einem bekannten Postfach.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Postfach und Zugang.
    /// - Throws: `MailCredentialError.noPassword` oder einen Lesefehler des
    ///   Schlüsselbunds.
    func credentials(for account: MailAccount) throws -> MailCredentials {
        try MailSession.resolve(account: account) { try password(for: $0) }
    }
}
