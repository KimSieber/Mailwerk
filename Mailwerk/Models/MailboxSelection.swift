//
//  MailboxSelection.swift
//  Mailwerk
//
//  Welche Ansicht die Mail-Liste zeigt. Steuert den Titel, die Abfrage
//  an den Cache und die Darstellung in der Seitenleiste.
//

import Foundation

enum MailboxSelection: Hashable {
    /// Alle Posteingänge aller Konten.
    case allInboxes
    /// Nur gekennzeichnete Nachrichten aus den Posteingängen.
    case flagged
    /// Ein bestimmter Ordner eines Postfachs.
    case folder(accountID: UUID, path: String, displayName: String)

    var title: String {
        switch self {
        case .allInboxes:                    return "Alle Eingänge"
        case .flagged:                       return "Mit Kennzeichnung"
        case .folder(_, _, let displayName): return displayName
        }
    }

    var systemImage: String {
        switch self {
        case .allInboxes: return "tray.2"
        case .flagged:    return "flag"
        case .folder:     return "folder"
        }
    }

    /// Postfach-ID, falls ein einzelner Ordner gewählt ist.
    var accountID: UUID? {
        if case .folder(let id, _, _) = self { return id }
        return nil
    }
}
