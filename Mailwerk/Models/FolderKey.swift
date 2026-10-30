//
//  FolderKey.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 10.10.2026
//  Geändert: 10.10.2026
//
//  Zweck: Eindeutiger Schlüssel für einen Ordner eines Postfachs –
//  Postfach-ID plus IMAP-Pfad. Ersetzt zusammengesetzte Zeichenketten wie
//  „<UUID>|<Pfad>“, die bei einem „|“ im Ordnernamen mehrdeutig wären.
//
//  Abgrenzung: Cache-IDs einzelner Mails → CachedMessage.makeID.
//
//  Abhängigkeiten: keine.
//

import Foundation

/// Postfach und Ordner als gemeinsamer Schlüssel.
nonisolated struct FolderKey: Hashable, Sendable {
    /// Postfach.
    let accountID: UUID
    /// IMAP-Pfad des Ordners.
    let folder: String
}
