//
//  OAuthProvider.swift
//  Mailwerk
//
//  Zweck: Anbieter-Konfiguration für die Anmeldung per OAuth 2 – wo das
//  Anmeldefenster liegt, wo Tokens getauscht werden, unter welcher
//  Kennung Mailwerk dort registriert ist, welche Berechtigungen es
//  anfragt und welche Server das Postfach hat.
//
//  Die Anmeldung ist allgemein gebaut: Ein Anbieter ist nur ein Satz
//  Daten. Microsoft (Outlook.com, Hotmail, Live) ist der erste; weitere
//  (etwa Gmail) kommen als weiterer Fall dazu, ohne dass sich Ablauf,
//  Token-Ablage oder Anmeldung am Server ändern.
//
//  Microsoft: Mailwerk ist bei Microsoft Entra als öffentlicher Client
//  registriert (nur persönliche Microsoft-Konten). Die Client-ID ist kein
//  Geheimnis; ein Client-Geheimnis gibt es bewusst nicht – Schutz bietet
//  PKCE (OAuthPKCE). Angemeldet wird über den Endpunkt „consumers“, weil
//  die Registrierung nur persönliche Konten zulässt.
//
//  Abgrenzung: Anfragen bauen und Antworten lesen → OAuthAuthorization,
//  OAuthTokenResponse; Tokens holen und erneuern → OAuthTokenService.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Konfiguration eines Anbieters für die Anmeldung per OAuth 2.
nonisolated struct OAuthProvider: Equatable, Sendable {

    /// Kennung des Anbieters; wird am Postfach gespeichert.
    enum ID: String, Codable, Sendable, CaseIterable {
        /// Microsoft – Outlook.com, Hotmail, Live.
        case microsoft
    }

    /// Kennung des Anbieters.
    let id: ID
    /// Name des Anbieters für die Oberfläche, z. B. „Microsoft“.
    let name: String
    /// Beschreibung der Postfach-Art im Formular, z. B. „Microsoft
    /// (Outlook.com, Hotmail, Live)“.
    let accountKindTitle: String
    /// Adresse des Anmeldefensters (Authorization Endpoint).
    let authorizationEndpoint: URL
    /// Adresse für Tausch und Erneuerung der Tokens (Token Endpoint).
    let tokenEndpoint: URL
    /// Kennung von Mailwerk beim Anbieter (öffentlich, kein Geheimnis).
    let clientID: String
    /// Weiterleitungsadresse nach der Anmeldung; muss beim Anbieter genau
    /// so registriert sein.
    let redirectURI: String
    /// Angefragte Berechtigungen.
    let scopes: [String]
    /// IMAP-Server des Postfachs.
    let imapHost: String
    /// IMAP-Port (TLS ab dem ersten Byte).
    let imapPort: Int
    /// SMTP-Server des Postfachs.
    let smtpHost: String
    /// SMTP-Port (STARTTLS).
    let smtpPort: Int

    /// Schema der Weiterleitungsadresse (ohne „://“); daran erkennt das
    /// Anmeldefenster die Rückkehr zu Mailwerk.
    var callbackScheme: String {
        URL(string: redirectURI)?.scheme ?? ""
    }

    /// Berechtigungen als eine Zeile, durch Leerzeichen getrennt (so
    /// verlangt es OAuth 2).
    var scopeString: String {
        scopes.joined(separator: " ")
    }

    /// Microsoft – persönliche Konten (Outlook.com, Hotmail, Live).
    ///
    /// Berechtigungen: IMAP-Zugriff und SMTP-Versand im Namen des Nutzers,
    /// dazu `offline_access` für ein Refresh-Token (dauerhafte Anmeldung).
    /// Server laut Microsoft: IMAP `outlook.office365.com:993` (SSL/TLS),
    /// SMTP `smtp-mail.outlook.com:587` (STARTTLS).
    static let microsoft = OAuthProvider(
        id: .microsoft,
        name: "Microsoft",
        accountKindTitle: "Microsoft (Outlook.com, Hotmail, Live)",
        authorizationEndpoint: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize")!,
        tokenEndpoint: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!,
        clientID: "9cad2233-5a8c-4b11-845e-c21b19ae2e0a",
        redirectURI: "msauth.de.sieber-bw.Mailwerk://auth",
        scopes: [
            "https://outlook.office.com/IMAP.AccessAsUser.All",
            "https://outlook.office.com/SMTP.Send",
            "offline_access"
        ],
        imapHost: "outlook.office365.com",
        imapPort: 993,
        smtpHost: "smtp-mail.outlook.com",
        smtpPort: 587
    )

    /// Liefert die Konfiguration zu einer Kennung.
    ///
    /// - Parameter id: Kennung des Anbieters.
    /// - Returns: Konfiguration des Anbieters.
    static func provider(for id: ID) -> OAuthProvider {
        switch id {
        case .microsoft: return .microsoft
        }
    }
}
