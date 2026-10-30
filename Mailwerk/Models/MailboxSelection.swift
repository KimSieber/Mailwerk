//
//  MailboxSelection.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 28.09.2026
//  Geändert: 16.10.2026
//
//  Zweck: Welche Ansicht die Mail-Liste zeigt – alle Posteingänge, die
//  ungelesenen Mails der Posteingänge, die gekennzeichneten Mails, die
//  Spam-Ordner aller Postfächer oder ein einzelner Ordner. Steuert Titel,
//  Symbol, Abfrage an den Cache und die Markierung in der Seitenleiste.
//
//  Sammelansichten (alle außer einem einzelnen Ordner) umfassen die
//  Postfächer mit eingeschaltetem Abruf; eine neue Mail geht dort vom
//  Standard-Postfach aus.
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
    /// Ungelesene Nachrichten aus den Posteingängen.
    case unread
    /// Nur gekennzeichnete Nachrichten aus den Posteingängen.
    case flagged
    /// Die Spam-Ordner aller Konten.
    case spam
    /// Ein bestimmter Ordner eines Postfachs.
    case folder(accountID: UUID, path: String, displayName: String)

    /// Titel der Liste.
    var title: String {
        switch self {
        case .allInboxes:                    return "Alle Eingänge"
        case .unread:                        return "Ungelesen"
        case .flagged:                       return "Mit Kennzeichnung"
        case .spam:                          return "Spam"
        case .folder(_, _, let displayName): return displayName
        }
    }

    /// SF-Symbol der Ansicht.
    var systemImage: String {
        switch self {
        case .allInboxes: return "tray.2"
        case .unread:     return "envelope.badge"
        case .flagged:    return "flag"
        case .spam:       return "xmark.bin"
        case .folder:     return "folder"
        }
    }

    /// Postfach-ID, falls ein einzelner Ordner gewählt ist.
    var accountID: UUID? {
        if case .folder(let id, _, _) = self { return id }
        return nil
    }
}
