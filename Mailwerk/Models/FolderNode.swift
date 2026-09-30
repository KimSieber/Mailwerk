//
//  FolderNode.swift
//  Mailwerk
//
//  Ein Knoten im Ordnerbaum eines Postfachs, aufbereitet für die Anzeige.
//  Entsteht in `FolderTreeBuilder` aus der flachen Ordnerliste des Servers.
//

import Foundation

/// Rolle eines Ordners. Die Reihenfolge der Fälle ist zugleich die
/// Sortierung auf der obersten Ebene des Baums.
nonisolated enum FolderRole: Int, Comparable, Sendable {
    case inbox
    case drafts
    case sent
    case archive
    case junk
    case trash
    case flagged
    case all
    case regular

    static func < (lhs: FolderRole, rhs: FolderRole) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(_ specialUse: MailFolder.SpecialUse) {
        switch specialUse {
        case .drafts:  self = .drafts
        case .sent:    self = .sent
        case .archive: self = .archive
        case .junk:    self = .junk
        case .trash:   self = .trash
        case .flagged: self = .flagged
        case .all:     self = .all
        }
    }
}

nonisolated struct FolderNode: Identifiable, Hashable, Sendable {
    /// Vollständiger IMAP-Pfad. Bei ergänzten Zwischenebenen der Pfad,
    /// den der Ordner hätte – eindeutig innerhalb des Postfachs.
    let id: String
    /// Anzeigename ohne Namespace-Präfix und ohne übergeordnete Ebenen.
    let name: String
    let role: FolderRole
    /// `false` bei `\Noselect` und bei ergänzten Zwischenebenen,
    /// die der Server gar nicht gemeldet hat.
    let isSelectable: Bool
    let children: [FolderNode]

    var hasChildren: Bool { !children.isEmpty }
}

// MARK: - Anzeige

/// Ein Ordner mit seiner Einrückungstiefe – für eine flache Liste, in der
/// Unterordner immer sichtbar und nur durch Einrückung erkennbar sind.
nonisolated struct IndentedFolder: Identifiable, Hashable, Sendable {
    let node: FolderNode
    /// 0 = oberste Ebene des Postfachs.
    let depth: Int

    var id: String { node.id }
}

nonisolated extension FolderNode {
    /// Kann eine Mail aus `currentFolder` hierher verschoben werden?
    /// Nicht in den eigenen Ordner und nicht in reine Container-Ordner
    /// (`\Noselect`), die keine Mails aufnehmen (v0.1.8c).
    func isMoveTarget(from currentFolder: String) -> Bool {
        guard isSelectable else { return false }
        // „INBOX“ ist laut RFC 3501 unabhängig von der Schreibweise.
        let bothInbox = id.caseInsensitiveCompare("INBOX") == .orderedSame
            && currentFolder.caseInsensitiveCompare("INBOX") == .orderedSame
        return id != currentFolder && !bothInbox
    }
}

nonisolated extension Array where Element == FolderNode {
    /// Baum in Anzeigereihenfolge: jeder Ordner, direkt gefolgt von
    /// seinen Unterordnern (Tiefensuche, Reihenfolge des Baums bleibt).
    func indented(startingAt depth: Int = 0) -> [IndentedFolder] {
        flatMap { node in
            [IndentedFolder(node: node, depth: depth)]
                + node.children.indented(startingAt: depth + 1)
        }
    }
}

nonisolated extension FolderRole {
    /// Einheitlicher deutscher Anzeigename. Ordner mit einer erkannten
    /// Rolle tragen diesen Namen statt ihres Servernamens.
    /// `nil` bei `.regular` – dort bleibt der Servername.
    var displayName: String? {
        switch self {
        case .inbox:   return "Posteingang"
        case .drafts:  return "Entwürfe"
        case .sent:    return "Gesendet"
        case .archive: return "Archiv"
        case .junk:    return "Spam"
        case .trash:   return "Papierkorb"
        case .flagged: return "Markiert"
        case .all:     return "Alle Nachrichten"
        case .regular: return nil
        }
    }

    /// SF Symbol der Rolle; dieselben Symbole wie im Verschieben-Dialog.
    var systemImage: String {
        switch self {
        case .inbox:   return "tray"
        case .drafts:  return "doc"
        case .sent:    return "paperplane"
        case .archive: return "archivebox"
        case .junk:    return "xmark.bin"
        case .trash:   return "trash"
        case .flagged: return "flag"
        case .all:     return "tray.full"
        case .regular: return "folder"
        }
    }
}
