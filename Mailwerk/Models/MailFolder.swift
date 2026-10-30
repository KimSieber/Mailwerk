//
//  MailFolder.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 28.09.2026
//  Geändert: 10.10.2026
//
//  Zweck: Ein IMAP-Ordner, wie ihn der Server beim LIST meldet – flach,
//  mit vollständigem Pfad – sowie die Ordnerliste eines Postfachs. Den
//  Baum für die Anzeige baut `FolderTreeBuilder`.
//
//  Hier steht auch der Name des Posteingangs („INBOX“) als einzige
//  Konstante der App samt Vergleich ohne Groß-/Kleinschreibung.
//
//  Reiner Werttyp ohne IMAP-Bezug; wird auch von der Ordner- und
//  Spam-Logik außerhalb des Main-Actors genutzt, deshalb `nonisolated`.
//
//  Abgrenzung: Ordnerbaum → FolderNode/FolderTreeBuilder; Ordnerliste
//  vom Server → MailActionService.
//
//  Abhängigkeiten: keine.
//

import Foundation

/// Ein IMAP-Ordner aus der Ordnerliste des Servers.
nonisolated struct MailFolder: Identifiable, Hashable, Sendable, Codable {
    /// Vollständiger IMAP-Pfad (z. B. „INBOX.Trash“).
    let id: String
    /// Letztes Pfadsegment in Server-Form (modified UTF-7); lesbar über
    /// `MailboxNameCodec.displayName`.
    let name: String
    /// Sonderrolle laut SPECIAL-USE (RFC 6154), sonst `nil`.
    let specialUse: SpecialUse?
    /// Trennzeichen der Ordnerhierarchie, wie vom Server gemeldet (bei
    /// manitu „.“). Wird gebraucht, um neue Ordner an der richtigen Stelle
    /// vorzuschlagen und den Ordnerbaum aufzubauen.
    let hierarchyDelimiter: String?
    /// `false` bei `\Noselect`: reiner Container ohne eigene Mails.
    var isSelectable: Bool = true

    /// Sonderrollen laut SPECIAL-USE.
    nonisolated enum SpecialUse: String, Sendable, Codable {
        case drafts, sent, trash, junk, archive, flagged, all
    }

    /// Name des Posteingangs. IMAP schreibt genau diese Schreibweise vor
    /// (RFC 3501); Server dürfen ihn in beliebiger Schreibweise melden.
    static let inboxPath = "INBOX"

    /// Prüft, ob ein Pfad der Posteingang ist – ohne Groß-/Kleinschreibung,
    /// wie RFC 3501 es für „INBOX“ verlangt.
    ///
    /// - Parameter path: IMAP-Pfad.
    /// - Returns: `true` für den Posteingang.
    static func isInbox(_ path: String) -> Bool {
        path.caseInsensitiveCompare(inboxPath) == .orderedSame
    }
}

/// Ordnerliste eines Postfachs, wie sie der Server beim Anmelden und beim
/// LIST meldet. Grundlage für den Ordnerbaum der Seitenleiste; wird je
/// Postfach im Cache gespeichert, damit die Leiste auch offline ihre
/// Ordner zeigt.
nonisolated struct FolderListing: Sendable, Codable, Equatable {
    /// Alle Ordner des Kontos, INBOX eingeschlossen.
    let folders: [MailFolder]
    /// Präfix des persönlichen Namespace (etwa „INBOX.“; manitu meldet ein
    /// leeres Präfix), `nil`, wenn der Server keins meldet.
    let namespacePrefix: String?
}
