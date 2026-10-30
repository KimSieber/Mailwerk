//
//  MailAccount.swift
//  Mailwerk
//
//  Zweck: Datenmodell eines eingerichteten IMAP-/SMTP-Postfachs – Bezeichnung,
//  Absendername, Benutzername, E-Mail-Adresse, Server und Ports, Farbe,
//  gemerkter Spam-Ordner und ob eine Kopie in „Gesendet“ abgelegt wird.
//
//  Gesendet-Kopie: Manche Anbieter (z. B. Gmail) legen über SMTP gesendete
//  Mails selbst ab; eine eigene Kopie wäre dort doppelt. Einen Standard,
//  der das meldet, gibt es nicht – deshalb ein Schalter je Postfach
//  (`storesSentCopy`), wie in anderen Mail-Programmen. Ältere gespeicherte
//  Postfächer ohne das Feld legen weiterhin eine Kopie ab.
//
//  Benutzername und E-Mail-Adresse sind getrennt: Der Benutzername dient
//  nur der Anmeldung, die Adresse dem Versand („From“) und dem Erkennen
//  der eigenen Adresse bei „Allen antworten“. In den Formularen ist die
//  Adresse Pflicht und der Benutzername optional – leer heißt „Anmeldung
//  mit der Adresse“ (`loginName`). Gespeichert wird immer der tatsächliche
//  Anmeldename. Ältere Postfächer ohne Adressfeld laufen weiter:
//  `senderAddress` fällt dann auf den Benutzernamen zurück.
//
//  Das Passwort gehört bewusst nicht dazu; es liegt im Schlüsselbund
//  (KeychainService), referenziert über `id`. Verbindungen sind immer
//  verschlüsselt (MailServerFactory), deshalb gibt es keine TLS-Schalter.
//
//  Anmeldeart: Ohne `oauthProvider` meldet sich Mailwerk mit Benutzername
//  und Passwort an (alle älteren Postfächer). Mit `oauthProvider` (z. B.
//  Microsoft) per OAuth 2: Statt des Passworts liegt dann ein
//  Refresh-Token im Schlüsselbund, angemeldet wird mit XOAUTH2. Das Feld
//  ist optional, damit gespeicherte Postfächer ohne es weiter lesbar sind.
//
//  Nebenläufigkeit (v0.2.3b): `nonisolated` – reine Werte bzw. Logik ohne
//  Bezug zur Oberfläche, damit der Abruf sie abseits des Hauptthreads
//  nutzen kann.
//
//  Abgrenzung: Speichern und Abgleich über iCloud → AccountStore.
//
//  Abhängigkeiten: Foundation, OAuthProvider.
//

import Foundation

/// Repräsentiert ein konfiguriertes IMAP/SMTP-Postfach.
/// Enthält bewusst KEIN Passwort – das liegt separat im Keychain,
/// referenziert über `id`.
///
/// Verbindungen sind immer verschlüsselt (siehe MailServerFactory) –
/// daher gibt es keine TLS-Schalter mehr.
nonisolated struct MailAccount: Identifiable, Codable, Equatable, Sendable {
    /// Kennung; verknüpft das Postfach mit Passwort und Cache.
    let id: UUID

    /// Frei wählbare Bezeichnung des Postfachs, z. B. "Kim @ manitu".
    /// Nur zur Anzeige in der App, wird nicht versendet.
    var displayName: String

    /// Name, der beim Versand in der Absenderzeile erscheint,
    /// z. B. "Kim Sieber". nil = nur die Adresse wird gesendet.
    var senderName: String?

    /// Tatsächlicher Anmeldename für IMAP und SMTP (bei manitu die volle
    /// E-Mail-Adresse).
    var username: String

    /// E-Mail-Adresse des Postfachs. Bei neu angelegten oder bearbeiteten
    /// Postfächern immer gesetzt; `nil` nur bei älteren gespeicherten
    /// Postfächern – dann ist der Benutzername die Adresse.
    var emailAddress: String?

    /// IMAP-Server.
    var imapHost: String
    /// IMAP-Port (Standard 993).
    var imapPort: Int

    /// SMTP-Server.
    var smtpHost: String
    /// SMTP-Port (Standard 465).
    var smtpPort: Int

    /// Hex-Farbwert aus AccountColor, z. B. "#378ADD". nil = keine Farbmarkierung.
    var colorHex: String?

    /// Vollständiger IMAP-Pfad des Spam-Ordners dieses Postfachs,
    /// z. B. "Junk" oder "INBOX.Spam". nil = noch nicht ermittelt.
    /// Wird beim ersten Filterlauf gefüllt und danach wiederverwendet.
    var spamFolder: String?

    /// Ob Mailwerk nach dem Versand eine Kopie im Gesendet-Ordner ablegt.
    /// `nil` (ältere gespeicherte Postfächer) gilt als „ja“; Auswertung
    /// über `savesSentCopy`.
    var storesSentCopy: Bool?

    /// Anbieter der Anmeldung per OAuth 2; `nil` = Anmeldung mit Passwort
    /// (auch alle älteren gespeicherten Postfächer).
    var oauthProvider: OAuthProvider.ID?

    /// Legt ein Postfach an.
    ///
    /// Verarbeitung: Ein leerer Absendername wird zu `nil` (`normalized`).
    ///
    /// - Parameters:
    ///   - id: Kennung (neu, wenn nicht angegeben).
    ///   - displayName: Bezeichnung in der App.
    ///   - senderName: Name in der Absenderzeile.
    ///   - username: Anmeldename.
    ///   - emailAddress: Abweichende E-Mail-Adresse; leer wird zu `nil`.
    ///   - imapHost: IMAP-Server.
    ///   - imapPort: IMAP-Port.
    ///   - smtpHost: SMTP-Server.
    ///   - smtpPort: SMTP-Port.
    ///   - colorHex: Farbe als Hex-Wert.
    ///   - spamFolder: gemerkter Spam-Ordner.
    ///   - storesSentCopy: Kopie in „Gesendet“ ablegen.
    ///   - oauthProvider: Anbieter der Anmeldung per OAuth 2; `nil` =
    ///     Passwort.
    init(
        id: UUID = UUID(),
        displayName: String,
        senderName: String? = nil,
        username: String,
        emailAddress: String? = nil,
        imapHost: String,
        imapPort: Int = 993,
        smtpHost: String,
        smtpPort: Int = 465,
        colorHex: String? = nil,
        spamFolder: String? = nil,
        storesSentCopy: Bool = true,
        oauthProvider: OAuthProvider.ID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.senderName = MailAccount.normalized(senderName)
        self.username = username
        self.emailAddress = MailAccount.normalized(emailAddress)
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.colorHex = colorHex
        self.spamFolder = spamFolder
        self.storesSentCopy = storesSentCopy
        self.oauthProvider = oauthProvider
    }

    /// Konfiguration des OAuth-Anbieters; `nil` bei Anmeldung mit Passwort.
    var oauthConfiguration: OAuthProvider? {
        oauthProvider.map { OAuthProvider.provider(for: $0) }
    }

    /// `true`, wenn nach dem Versand eine Kopie in „Gesendet“ abgelegt wird;
    /// ältere Postfächer ohne Angabe gelten als `true`.
    var savesSentCopy: Bool {
        storesSentCopy ?? true
    }

    /// Adresse für Versand und Erkennen der eigenen Adresse: die
    /// E-Mail-Adresse, sonst der Benutzername, ohne Leerraum an den Rändern.
    var senderAddress: String {
        (emailAddress ?? username).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Anmeldename aus den Formularfeldern: der eingetragene Benutzername,
    /// sonst die E-Mail-Adresse.
    ///
    /// - Parameters:
    ///   - username: Eingabe im Feld Benutzername (darf leer sein).
    ///   - emailAddress: Eingabe im Feld E-Mail-Adresse.
    /// - Returns: Anmeldename ohne Leerraum an den Rändern.
    static func loginName(username: String, emailAddress: String) -> String {
        let login = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty
            ? emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            : login
    }

    /// Zulässige TCP-Ports.
    nonisolated static let validPorts = 1...65535

    /// Liest eine Port-Eingabe aus den Formularen.
    ///
    /// Verarbeitung: Leerraum an den Rändern entfällt; nur ganze Zahlen im
    /// Bereich `validPorts` gelten. Werte wie 0 oder 70000 würden sonst
    /// gespeichert und erst beim Verbinden mit einer unklaren Meldung
    /// scheitern.
    ///
    /// - Parameter text: Eingabe im Feld Port.
    /// - Returns: Port oder `nil` bei ungültiger Eingabe.
    nonisolated static func port(from text: String) -> Int? {
        guard let port = Int(text.trimmingCharacters(in: .whitespaces)),
              validPorts.contains(port) else { return nil }
        return port
    }

    /// Bereinigt einen Namen: Leerraum an den Rändern entfällt, ein leerer
    /// Name wird zu `nil`.
    ///
    /// Reine Funktion, deshalb `nonisolated` – auch `MailAddress` nutzt
    /// sie außerhalb des Main-Actors.
    ///
    /// - Parameter name: Eingegebener Name.
    /// - Returns: Bereinigter Name oder `nil`.
    nonisolated static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
