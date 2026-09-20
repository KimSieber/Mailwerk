//
//  MailAccount.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//


//
//  MailAccount.swift
//  Mailwerk
//

import Foundation

/// Repräsentiert ein konfiguriertes IMAP/SMTP-Postfach.
/// Enthält bewusst KEIN Passwort – das liegt separat im Keychain,
/// referenziert über `id`.
struct MailAccount: Identifiable, Codable, Equatable {
    let id: UUID

    /// Frei wählbarer Anzeigename, z. B. "Kim @ manitu"
    var displayName: String

    /// Für IMAP/SMTP-Login (bei manitu i. d. R. die volle E-Mail-Adresse)
    var username: String

    var imapHost: String
    var imapPort: Int
    var imapUseTLS: Bool

    var smtpHost: String
    var smtpPort: Int
    var smtpUseTLS: Bool

    /// Hex-Farbwert aus AccountColor, z. B. "#378ADD". nil = keine Farbmarkierung.
    var colorHex: String?
    
    init(
        id: UUID = UUID(),
        displayName: String,
        username: String,
        imapHost: String,
        imapPort: Int = 993,
        imapUseTLS: Bool = true,
        smtpHost: String,
        smtpPort: Int = 465,
        smtpUseTLS: Bool = true,
        colorHex: String? = nil       // ← neu
    ) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.imapUseTLS = imapUseTLS
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.smtpUseTLS = smtpUseTLS
        self.colorHex = colorHex      // ← neu
    }
}
