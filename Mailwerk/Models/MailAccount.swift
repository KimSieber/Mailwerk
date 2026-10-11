//
//  MailAccount.swift
//  Mailwerk
//
//  Zweck: Datenmodell eines eingerichteten IMAP-/SMTP-Postfachs – Bezeichnung,
//  Absendername, Benutzername, Server und Ports, Farbe und gemerkter
//  Spam-Ordner.
//
//  Das Passwort gehört bewusst nicht dazu; es liegt im Schlüsselbund
//  (KeychainService), referenziert über `id`. Verbindungen sind immer
//  verschlüsselt (MailServerFactory), deshalb gibt es keine TLS-Schalter.
//
//  Abgrenzung: Speichern und Abgleich über iCloud → AccountStore.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Repräsentiert ein konfiguriertes IMAP/SMTP-Postfach.
/// Enthält bewusst KEIN Passwort – das liegt separat im Keychain,
/// referenziert über `id`.
///
/// Verbindungen sind immer verschlüsselt (siehe MailServerFactory) –
/// daher gibt es keine TLS-Schalter mehr.
struct MailAccount: Identifiable, Codable, Equatable {
    /// Kennung; verknüpft das Postfach mit Passwort und Cache.
    let id: UUID

    /// Frei wählbare Bezeichnung des Postfachs, z. B. "Kim @ manitu".
    /// Nur zur Anzeige in der App, wird nicht versendet.
    var displayName: String

    /// Name, der beim Versand in der Absenderzeile erscheint,
    /// z. B. "Kim Sieber". nil = nur die Adresse wird gesendet.
    var senderName: String?

    /// Für IMAP/SMTP-Login (bei manitu die volle E-Mail-Adresse).
    /// Dient zugleich als Absenderadresse.
    var username: String

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

    /// Legt ein Postfach an.
    ///
    /// Verarbeitung: Ein leerer Absendername wird zu `nil` (`normalized`).
    ///
    /// - Parameters:
    ///   - id: Kennung (neu, wenn nicht angegeben).
    ///   - displayName: Bezeichnung in der App.
    ///   - senderName: Name in der Absenderzeile.
    ///   - username: Anmeldename, zugleich Absenderadresse.
    ///   - imapHost: IMAP-Server.
    ///   - imapPort: IMAP-Port.
    ///   - smtpHost: SMTP-Server.
    ///   - smtpPort: SMTP-Port.
    ///   - colorHex: Farbe als Hex-Wert.
    ///   - spamFolder: gemerkter Spam-Ordner.
    init(
        id: UUID = UUID(),
        displayName: String,
        senderName: String? = nil,
        username: String,
        imapHost: String,
        imapPort: Int = 993,
        smtpHost: String,
        smtpPort: Int = 465,
        colorHex: String? = nil,
        spamFolder: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.senderName = MailAccount.normalized(senderName)
        self.username = username
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.colorHex = colorHex
        self.spamFolder = spamFolder
    }

    /// Bereinigt einen Namen: Leerraum an den Rändern entfällt, ein leerer
    /// Name wird zu `nil`.
    ///
    /// - Parameter name: Eingegebener Name.
    /// - Returns: Bereinigter Name oder `nil`.
    static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
