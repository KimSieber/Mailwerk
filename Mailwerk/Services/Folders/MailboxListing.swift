//
//  MailboxListing.swift
//  Mailwerk
//
//  Zweck: Bereitet die Ordnerliste des Servers (LIST) zu `MailFolder`s auf –
//  Anzeigename, Sonderordner, Auswahl und Reihenfolge.
//
//  Regeln:
//  - Anzeigename ist das letzte Pfadsegment. Meldet der Server kein
//    Trennzeichen, ist die Hierarchie flach und der ganze Pfad der Name –
//    ein Trennzeichen wird nicht geraten.
//  - Sonderordner (SPECIAL-USE) in fester Rangfolge: Entwürfe, Gesendet,
//    Papierkorb, Spam, Archiv, Markiert. „Alle Nachrichten“ wird nicht
//    übernommen.
//  - Sonderordner stehen zuerst, danach alphabetisch (ohne Groß-/
//    Kleinschreibung).
//  - Der Posteingang entfällt, wenn er nicht ausdrücklich gewünscht ist
//    (Verschiebeziele, Papierkorb-Suche).
//
//  Reine Logik ohne IMAP (Code-Review v0.3.1, Regel 4); die Abfrage selbst
//  stellt der MailActionService.
//
//  Abhängigkeiten: MailFolder.
//

import Foundation

/// Aufbereitung der Ordnerliste des Servers.
nonisolated enum MailboxListing {

    /// Ein Ordner, wie ihn der Server meldet – ohne Bibliothekstypen.
    struct Entry: Equatable {
        /// Vollständiger Server-Pfad.
        let path: String
        /// Trennzeichen der Hierarchie; `nil` oder leer = flach.
        let delimiter: String?
        /// Sonderordner laut SPECIAL-USE; `nil` = gewöhnlicher Ordner.
        let specialUse: MailFolder.SpecialUse?
        /// `false` bei `\Noselect`.
        let isSelectable: Bool
    }

    /// Sonderordner in der Rangfolge, in der sie geprüft werden.
    static let specialUseOrder: [MailFolder.SpecialUse] = [.drafts, .sent, .trash, .junk, .archive, .flagged]

    /// Bestimmt den Sonderordner aus den Attributen eines Ordners.
    ///
    /// - Parameter matching: Liefert `true`, wenn der Ordner das Attribut
    ///   des Sonderordners trägt.
    /// - Returns: Erster passender Sonderordner in `specialUseOrder`.
    static func specialUse(matching: (MailFolder.SpecialUse) -> Bool) -> MailFolder.SpecialUse? {
        specialUseOrder.first(where: matching)
    }

    /// Anzeigename eines Ordners.
    ///
    /// - Parameters:
    ///   - path: Server-Pfad.
    ///   - delimiter: Trennzeichen der Hierarchie.
    /// - Returns: Letztes Pfadsegment, ohne Trennzeichen der ganze Pfad.
    static func displayName(path: String, delimiter: String?) -> String {
        guard let delimiter, !delimiter.isEmpty else { return path }
        return path.components(separatedBy: delimiter).last ?? path
    }

    /// Baut die Ordner des Postfachs aus der Liste des Servers.
    ///
    /// - Parameters:
    ///   - entries: Ordner laut Server.
    ///   - includeInbox: `true` = Posteingang mitliefern.
    /// - Returns: Sonderordner zuerst, danach alphabetisch.
    static func folders(from entries: [Entry], includeInbox: Bool) -> [MailFolder] {
        entries
            .filter { includeInbox || !MailFolder.isInbox($0.path) }
            .map { entry in
                MailFolder(
                    id: entry.path,
                    name: displayName(path: entry.path, delimiter: entry.delimiter),
                    specialUse: entry.specialUse,
                    hierarchyDelimiter: entry.delimiter,
                    isSelectable: entry.isSelectable
                )
            }
            .sorted { lhs, rhs in
                let lhsRank = lhs.specialUse != nil ? 0 : 1
                let rhsRank = rhs.specialUse != nil ? 0 : 1
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
