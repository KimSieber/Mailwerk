//
//  CachedMessage.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//

import Foundation

/// Adress- und Threading-Header einer Nachricht.
/// Grundlage für Antworten, Allen antworten und Weiterleiten.
struct CachedMessageHeaders: Equatable {
    /// Empfänger (To) – je Eintrag eine formatierte Adresse, z. B. "Kim Sieber <kim@example.org>"
    var toList: [String] = []
    /// Kopie-Empfänger (Cc)
    var ccList: [String] = []
    /// Abweichende Antwortadresse(n) (Reply-To)
    var replyToList: [String] = []
    /// Message-ID inkl. spitzer Klammern, z. B. "<abc@example.org>"
    var rfcMessageID: String?
    /// Message-ID der Nachricht, auf die diese antwortet
    var rfcInReplyTo: String?
    /// References-Kette, durch Leerzeichen getrennt
    var rfcReferences: String?
}

/// Lokal zwischengespeicherte Nachricht inkl. Body.
/// Anhänge werden separat in CachedAttachment gehalten.
struct CachedMessage: Identifiable {
    let id: String              // "<accountUUID>-<folder>-<uid>"
    let accountID: UUID
    let accountDisplayName: String
    /// IMAP-Ordner, in dem die Nachricht liegt (z. B. "INBOX", "Junk").
    /// UIDs sind nur innerhalb eines Ordners eindeutig, deshalb gehört der
    /// Ordner zur Identität einer gecachten Nachricht.
    let folder: String
    let uid: UInt32
    let subject: String
    let from: String
    let to: String              // Anzeige-String; für Logik headers.toList verwenden
    let date: Date?
    var isUnread: Bool
    var isFlagged: Bool
    var isAnswered: Bool        // IMAP \Answered
    var isForwarded: Bool       // IMAP-Keyword $Forwarded
    let totalSizeBytes: Int     // RFC822.SIZE – entscheidet, ob Anhänge automatisch geladen werden
    let hasAttachments: Bool    // true wenn die Mail mindestens einen Anhang hat
    let textBody: String?
    let htmlBody: String?
    let fetchedAt: Date
    let headers: CachedMessageHeaders

    /// Bildet die Cache-Kennung. Einzige Stelle, an der das Format entsteht –
    /// die Kennung wird nirgends wieder zerlegt, weil Ordnernamen selbst
    /// Bindestriche enthalten dürfen.
    static func makeID(accountID: UUID, folder: String, uid: UInt32) -> String {
        "\(accountID.uuidString)-\(folder)-\(uid)"
    }
}

/// Ein einzelner gecachter Anhang, referenziert über die messageID.
struct CachedAttachment: Identifiable {
    let id: String              // "<messageID>-<partSection>"
    let messageID: String       // Fremdschlüssel auf CachedMessage.id
    let filename: String
    let contentType: String
    let sizeBytes: Int
    let data: Data?             // nil = noch nicht heruntergeladen (Mail > 5 MB)
}
