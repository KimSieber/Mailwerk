//
//  MailSession.swift
//  Mailwerk
//
//  Zweck: Zugangsdaten und IMAP-Verbindung an einer Stelle. Jede
//  Server-Aktion (Abruf, Kennzeichnen, Verschieben, Ordner, Spamfilter,
//  Anhang nachladen, Gesendet-Kopie) braucht dasselbe:
//  1. Postfach und Passwort bestimmen – mit einheitlichen Fehlern, wenn
//     das Postfach fehlt oder kein Passwort gespeichert ist;
//  2. verbinden, anmelden, die Aktion ausführen, abmelden – und bei einem
//     Fehler die Verbindung trennen.
//  Vorher stand das an neun Stellen mit fünf eigenen Fehlerarten.
//
//  Die Verschlüsselung erzwingt weiterhin `MailServerFactory`.
//
//  Abgrenzung: Was auf der Verbindung geschieht, bestimmen die Dienste
//  (MailFetchService, MailActionService, SpamFilterService,
//  MailSendService, AttachmentManager). SMTP und der eigene IMAP-Weg zum
//  Löschen von Ordnern bauen ihre Verbindung weiterhin selbst auf, nutzen
//  aber dieselben Zugangsdaten.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailServerFactory, AccountStore.
//

import Foundation
import SwiftMail

/// Postfach und Passwort für eine Verbindung.
struct MailCredentials {
    /// Postfach (Server, Port, Benutzername).
    let account: MailAccount
    /// Passwort aus dem Schlüsselbund.
    let password: String
}

/// Fehler beim Bestimmen der Zugangsdaten.
enum MailCredentialError: LocalizedError, Equatable {
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

/// Zugangsdaten bestimmen und IMAP-Verbindungen führen.
enum MailSession {

    /// Bestimmt die Zugangsdaten zu einer Postfach-ID.
    ///
    /// Verarbeitung: Sucht das Postfach in der Liste und liest sein
    /// Passwort. Ein Lesefehler des Schlüsselbunds wird unverändert
    /// weitergegeben, damit seine Ursache sichtbar bleibt.
    ///
    /// - Parameters:
    ///   - accountID: ID des Postfachs.
    ///   - accounts: Eingerichtete Postfächer.
    ///   - password: Liest das Passwort eines Postfachs (`nil` = keines).
    /// - Returns: Postfach und Passwort.
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
    /// - Parameters:
    ///   - account: Postfach.
    ///   - password: Liest das Passwort eines Postfachs (`nil` = keines).
    /// - Returns: Postfach und Passwort.
    /// - Throws: `MailCredentialError.noPassword` oder den Lesefehler des
    ///   Schlüsselbunds.
    static func resolve(
        account: MailAccount,
        password: (MailAccount) throws -> String?
    ) throws -> MailCredentials {
        guard let value = try password(account) else {
            throw MailCredentialError.noPassword
        }
        return MailCredentials(account: account, password: value)
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
    ///   - credentials: Postfach und Passwort.
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
            try await server.login(
                username: credentials.account.username, password: credentials.password
            )
            let result = try await body(server)
            try await server.logout()
            return result
        } catch {
            try? await server.disconnect()
            throw error
        }
    }
}

extension AccountStore {
    /// Zugangsdaten zu einer Postfach-ID.
    ///
    /// - Parameter accountID: ID des Postfachs.
    /// - Returns: Postfach und Passwort.
    /// - Throws: `MailCredentialError` oder einen Lesefehler des Schlüsselbunds.
    func credentials(for accountID: UUID) throws -> MailCredentials {
        try MailSession.resolve(accountID: accountID, in: accounts) { try password(for: $0) }
    }

    /// Zugangsdaten zu einem bekannten Postfach.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Postfach und Passwort.
    /// - Throws: `MailCredentialError.noPassword` oder einen Lesefehler des
    ///   Schlüsselbunds.
    func credentials(for account: MailAccount) throws -> MailCredentials {
        try MailSession.resolve(account: account) { try password(for: $0) }
    }
}
