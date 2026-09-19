//
//  CachedMessage.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//


//
//  CachedMessage.swift
//  Mailwerk
//

import Foundation

/// Lokal zwischengespeicherte Nachricht inkl. Body.
/// Anhänge werden separat in CachedAttachment gehalten.
struct CachedMessage: Identifiable {
    let id: String              // "<accountUUID>-<uid>"
    let accountID: UUID
    let accountDisplayName: String
    let uid: UInt32
    let subject: String
    let from: String
    let to: String
    let date: Date?
    var isUnread: Bool
    let totalSizeBytes: Int     // RFC822.SIZE – entscheidet, ob Anhänge automatisch geladen werden
    let textBody: String?
    let htmlBody: String?
    let fetchedAt: Date
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