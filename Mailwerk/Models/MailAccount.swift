//
//  MailAccount.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//

import Foundation

/// Repräsentiert ein konfiguriertes IMAP/SMTP-Postfach.
/// Enthält bewusst KEIN Passwort – das liegt separat im Keychain,
/// referenziert über `id`.
///
/// Verbindungen sind immer verschlüsselt (siehe MailServerFactory) –
/// daher gibt es keine TLS-Schalter mehr.
struct MailAccount: Identifiable, Codable, Equatable {
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

    var imapHost: String
    var imapPort: Int

    var smtpHost: String
    var smtpPort: Int

    /// Hex-Farbwert aus AccountColor, z. B. "#378ADD". nil = keine Farbmarkierung.
    var colorHex: String?

    /// Vollständiger IMAP-Pfad des Spam-Ordners dieses Postfachs,
    /// z. B. "Junk" oder "INBOX.Spam". nil = noch nicht ermittelt.
    /// Wird beim ersten Filterlauf gefüllt und danach wiederverwendet.
    var spamFolder: String?

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

    /// Leere bzw. nur aus Leerzeichen bestehende Namen werden zu nil.
    static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
