//
//  MailboxSelection.swift
//  Mailwerk
//
//  Zweck: Welche Ansicht die Mail-Liste zeigt – alle Posteingänge, die
//  gekennzeichneten Mails oder ein einzelner Ordner. Steuert Titel,
//  Symbol, Abfrage an den Cache und die Markierung in der Seitenleiste.
//
//  Abgrenzung: Laden der Liste → InboxViewModel; Seitenleiste →
//  FolderSidebarView.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Gewählte Ansicht der Mail-Liste.
enum MailboxSelection: Hashable {
    /// Alle Posteingänge aller Konten.
    case allInboxes
    /// Nur gekennzeichnete Nachrichten aus den Posteingängen.
    case flagged
    /// Ein bestimmter Ordner eines Postfachs.
    case folder(accountID: UUID, path: String, displayName: String)

    /// Titel der Liste.
    var title: String {
        switch self {
        case .allInboxes:                    return "Alle Eingänge"
        case .flagged:                       return "Mit Kennzeichnung"
        case .folder(_, _, let displayName): return displayName
        }
    }

    /// SF-Symbol der Ansicht.
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
