//
//  InboxMessage.swift
//  Mailwerk
//
//  Created by Kim Sieber on 18.09.26.
//


//
//  InboxMessage.swift
//  Mailwerk
//

import Foundation
import SwiftMail

/// Ein Nachrichten-Header, angereichert um die Information, aus welchem
/// Postfach er stammt – Grundlage für die Unified-Inbox-Liste.
struct InboxMessage: Identifiable {
    let accountID: UUID
    let accountDisplayName: String
    let info: MessageInfo

    var id: String {
        if let uid = info.uid {
            return "\(accountID.uuidString)-\(uid.value)"
        }
        return "\(accountID.uuidString)-\(info.sequenceNumber.value)"
    }

    var subject: String { info.subject ?? "(kein Betreff)" }
    var from: String { info.from ?? "(unbekannt)" }
    var date: Date? { info.date ?? info.internalDate }

    var isUnread: Bool {
        !info.flags.contains(where: {
            if case .seen = $0 { return true }
            return false
        })
    }
}