//
//  FolderNode.swift
//  Mailwerk
//
//  Zweck: Ein Knoten im Ordnerbaum eines Postfachs, aufbereitet für die
//  Anzeige, samt Rolle (Posteingang, Gesendet, …), deutschem Anzeigenamen
//  und Symbol. Dazu die eingerückte Darstellung für die Ordnerleiste.
//
//  Dazu die Suche eines Ordners über seinen Pfad (z. B. für die Rolle der
//  gerade gezeigten Ansicht).
//
//  Abgrenzung: Aufbau aus der flachen Ordnerliste → FolderTreeBuilder;
//  Darstellung → FolderSidebarView, FolderMoveSheet.
//
//  Abhängigkeiten: MailFolder.
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

    /// Sortierung nach der Reihenfolge der Fälle.
    ///
    /// - Parameters:
    ///   - lhs: Linke Rolle.
    ///   - rhs: Rechte Rolle.
    /// - Returns: `true`, wenn `lhs` vor `rhs` steht.
    static func < (lhs: FolderRole, rhs: FolderRole) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Rolle zu einer SPECIAL-USE-Angabe des Servers.
    ///
    /// - Parameter specialUse: Sonderrolle laut Server.
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

/// Ein Ordner im Ordnerbaum.
nonisolated struct FolderNode: Identifiable, Hashable, Sendable {
    /// Vollständiger IMAP-Pfad. Bei ergänzten Zwischenebenen der Pfad,
    /// den der Ordner hätte – eindeutig innerhalb des Postfachs.
    let id: String
    /// Anzeigename ohne Namespace-Präfix und ohne übergeordnete Ebenen.
    let name: String
    /// Rolle des Ordners (Sortierung, Name, Symbol).
    let role: FolderRole
    /// `false` bei `\Noselect` und bei ergänzten Zwischenebenen,
    /// die der Server gar nicht gemeldet hat.
    let isSelectable: Bool
    /// Unterordner in Anzeigereihenfolge.
    let children: [FolderNode]

    /// `true`, wenn der Ordner Unterordner hat.
    var hasChildren: Bool { !children.isEmpty }
}

// MARK: - Anzeige

/// Ein Ordner mit seiner Einrückungstiefe – für eine flache Liste, in der
/// Unterordner immer sichtbar und nur durch Einrückung erkennbar sind.
nonisolated struct IndentedFolder: Identifiable, Hashable, Sendable {
    /// Ordner.
    let node: FolderNode
    /// 0 = oberste Ebene des Postfachs.
    let depth: Int

    /// Kennung für SwiftUI (Pfad des Ordners).
    var id: String { node.id }
}

nonisolated extension FolderNode {
    /// Prüft, ob eine Mail aus `currentFolder` hierher verschoben werden kann.
    ///
    /// Verarbeitung: Nicht in den eigenen Ordner und nicht in reine
    /// Container-Ordner (`\Noselect`), die keine Mails aufnehmen. „INBOX“
    /// ist laut RFC 3501 unabhängig von der Schreibweise.
    ///
    /// - Parameter currentFolder: Bisheriger Ordner der Mail.
    /// - Returns: `true`, wenn der Ordner ein gültiges Ziel ist.
    func isMoveTarget(from currentFolder: String) -> Bool {
        guard isSelectable else { return false }
        let bothInbox = MailFolder.isInbox(id) && MailFolder.isInbox(currentFolder)
        return id != currentFolder && !bothInbox
    }
}

nonisolated extension Array where Element == FolderNode {
    /// Baum in Anzeigereihenfolge: jeder Ordner, direkt gefolgt von
    /// seinen Unterordnern (Tiefensuche, Reihenfolge des Baums bleibt).
    ///
    /// - Parameter depth: Tiefe der obersten Ebene.
    /// - Returns: Flache Liste mit Einrückungstiefe.
    func indented(startingAt depth: Int = 0) -> [IndentedFolder] {
        flatMap { node in
            [IndentedFolder(node: node, depth: depth)]
                + node.children.indented(startingAt: depth + 1)
        }
    }

    /// Sucht einen Ordner samt Unterordnern über seinen IMAP-Pfad.
    ///
    /// Verarbeitung: Tiefensuche; der Pfad muss exakt übereinstimmen, weil
    /// Ordnerpfade auf dem Server die Schreibweise unterscheiden.
    ///
    /// - Parameter path: Vollständiger IMAP-Pfad (`FolderNode.id`).
    /// - Returns: Gefundener Ordner oder `nil`.
    func node(withPath path: String) -> FolderNode? {
        for node in self {
            if node.id == path { return node }
            if let found = node.children.node(withPath: path) { return found }
        }
        return nil
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
