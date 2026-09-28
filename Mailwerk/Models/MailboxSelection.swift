//
//  MailboxSelection.swift
//  Mailwerk
//
//  Welche Ansicht die Mail-Liste zeigt. Steuert den Titel, die Abfrage
//  an den Cache und die Darstellung in der Seitenleiste.
//
//  v0.1.7b: .allInboxes und .flagged.
//  v0.1.7c+: .folder(accountID:path:) für einzelne Ordner.
//

import Foundation

enum MailboxSelection: Hashable {
    /// Alle Posteingänge aller Konten.
    case allInboxes
    /// Nur gekennzeichnete Nachrichten aus den Posteingängen.
    case flagged

    var title: String {
        switch self {
        case .allInboxes: return "Alle Eingänge"
        case .flagged:    return "Mit Kennzeichnung"
        }
    }

    var systemImage: String {
        switch self {
        case .allInboxes: return "tray.2"
        case .flagged:    return "flag"
        }
    }
}
