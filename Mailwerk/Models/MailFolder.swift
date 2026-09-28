//
//  MailFolder.swift
//  Mailwerk
//
//  Ein IMAP-Ordner, wie ihn der Server beim LIST meldet – flach, mit
//  vollständigem Pfad. Den Baum für die Anzeige baut `FolderTreeBuilder`.
//
//  Bis v0.1.6 lag der Typ in MailActionService.swift. Er ist ein reiner
//  Werttyp ohne IMAP-Bezug und wird auch von der Ordner- und Spam-Logik
//  außerhalb des Main-Actors genutzt, deshalb eigene Datei und `nonisolated`.
//

import Foundation

nonisolated struct MailFolder: Identifiable, Hashable, Sendable {
    let id: String          // Vollständiger IMAP-Pfad (z. B. "INBOX.Trash")
    let name: String        // Anzeigename (letztes Pfad-Segment)
    let specialUse: SpecialUse?
    /// Trennzeichen der Ordnerhierarchie, wie vom Server gemeldet
    /// (bei manitu "."). Wird gebraucht, um neue Ordner an der
    /// richtigen Stelle vorzuschlagen und den Ordnerbaum aufzubauen.
    let hierarchyDelimiter: String?
    /// `false` bei `\Noselect`: reiner Container ohne eigene Mails.
    /// `var` mit Vorgabewert, damit bestehende Aufrufe unverändert bleiben.
    var isSelectable: Bool = true

    nonisolated enum SpecialUse: String, Sendable {
        case drafts, sent, trash, junk, archive, flagged, all
    }
}

/// Ordnerliste eines Postfachs, wie sie der Server beim Anmelden und
/// beim LIST meldet. Grundlage für den Ordnerbaum der Seitenleiste.
nonisolated struct FolderListing: Sendable {
    /// Alle Ordner des Kontos, INBOX eingeschlossen.
    let folders: [MailFolder]
    /// Präfix des persönlichen Namespace (bei manitu „INBOX.“),
    /// `nil`, wenn der Server keins meldet.
    let namespacePrefix: String?
}
