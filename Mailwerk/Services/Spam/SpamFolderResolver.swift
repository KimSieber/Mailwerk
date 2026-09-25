//
//  SpamFolderResolver.swift
//  Mailwerk
//
//  Findet den Spam-Ordner eines Postfachs. Jedes Postfach hat seinen
//  eigenen – verschoben wird immer innerhalb desselben Kontos.
//
//  Reihenfolge der Prüfung:
//  1. der für das Konto gemerkte Ordner, sofern es ihn noch gibt
//  2. SPECIAL-USE \Junk (RFC 6154) – die verlässliche Auskunft des Servers
//  3. gebräuchliche Namen, unabhängig von Groß-/Kleinschreibung
//  4. nichts gefunden → Vorschlag zum Anlegen, den der Nutzer bestätigen muss
//
//  Reine Logik, deshalb `nonisolated` und ohne IMAP-Zugriff.
//

import Foundation

nonisolated enum SpamFolderResolver {

    /// Gebräuchliche Namen in absteigender Verlässlichkeit.
    /// Verglichen wird das letzte Pfadsegment, ohne Groß-/Kleinschreibung.
    static let candidateNames = [
        "junk", "spam", "junk e-mail", "junk-e-mail", "junkmail", "bulk mail"
    ]

    /// Name, der beim Anlegen vorgeschlagen wird.
    static let proposedName = "Junk"

    private static let inbox = "INBOX"

    enum Resolution: Equatable {
        /// Ordner vorhanden – vollständiger IMAP-Pfad.
        case found(String)
        /// Kein Spam-Ordner vorhanden. Der Pfad ist ein Vorschlag und darf
        /// erst nach Rückfrage beim Nutzer angelegt werden.
        case missing(proposal: String)
    }

    /// - Parameters:
    ///   - folders: Ordnerliste des Kontos (ohne INBOX).
    ///   - delimiter: Trennzeichen der Ordnerhierarchie, wie vom Server gemeldet.
    ///   - configured: zuvor für dieses Konto gemerkter Ordner.
    static func resolve(
        folders: [MailFolder],
        delimiter: String?,
        configured: String?
    ) -> Resolution {
        if let match = configuredMatch(in: folders, configured: configured) {
            return .found(match.id)
        }
        if let junk = folders.first(where: { $0.specialUse == .junk }) {
            return .found(junk.id)
        }
        if let named = firstNameMatch(in: folders, delimiter: delimiter) {
            return .found(named.id)
        }
        return .missing(proposal: proposal(for: folders, delimiter: delimiter))
    }

    // MARK: - Teilschritte

    /// Der gemerkte Ordner, sofern er noch existiert. Zuerst wird exakt
    /// verglichen; IMAP-Pfade sind bis auf INBOX Groß-/Kleinschreibung-relevant,
    /// ein abweichend geschriebener Merkwert soll aber trotzdem greifen.
    private static func configuredMatch(
        in folders: [MailFolder],
        configured: String?
    ) -> MailFolder? {
        guard let configured, !configured.isEmpty else { return nil }
        return folders.first { $0.id == configured }
            ?? folders.first { $0.id.caseInsensitiveCompare(configured) == .orderedSame }
    }

    /// Erster Treffer in der Reihenfolge der Kandidatennamen. Kommt ein Name
    /// mehrfach vor, gewinnt der Ordner auf der obersten Ebene.
    private static func firstNameMatch(
        in folders: [MailFolder],
        delimiter: String?
    ) -> MailFolder? {
        for candidate in candidateNames {
            let matches = folders.filter {
                lastSegment(of: $0, delimiter: delimiter).lowercased() == candidate
            }
            if let best = matches.min(by: { lhs, rhs in
                let lhsDepth = depth(of: lhs, delimiter: delimiter)
                let rhsDepth = depth(of: rhs, delimiter: delimiter)
                return lhsDepth == rhsDepth ? lhs.id < rhs.id : lhsDepth < rhsDepth
            }) {
                return best
            }
        }
        return nil
    }

    /// Legt der Server seine Ordner unterhalb der INBOX ab, folgt der
    /// Vorschlag dieser Hierarchie – sonst entsteht ein Ordner, der in
    /// anderen Mail-Programmen an ungewohnter Stelle auftaucht.
    private static func proposal(for folders: [MailFolder], delimiter: String?) -> String {
        guard !folders.isEmpty,
              let separator = hierarchySeparator(for: folders, delimiter: delimiter)
        else {
            return proposedName
        }
        let prefix = inbox + separator
        let allNested = folders.allSatisfy {
            $0.id.lowercased().hasPrefix(prefix.lowercased())
        }
        return allNested ? prefix + proposedName : proposedName
    }

    // MARK: - Helfer

    /// Trennzeichen: bevorzugt die Angabe des Servers, sonst die der Ordner.
    private static func hierarchySeparator(
        for folders: [MailFolder],
        delimiter: String?
    ) -> String? {
        if let delimiter, !delimiter.isEmpty { return delimiter }
        return folders.compactMap(\.hierarchyDelimiter).first { !$0.isEmpty }
    }

    /// Zerlegt den Pfad. Das Trennzeichen des Ordners selbst hat Vorrang,
    /// weil es direkt vom Server zu diesem Ordner gemeldet wurde.
    private static func segments(of folder: MailFolder, delimiter: String?) -> [String] {
        let pathSeparator = hierarchySeparator(for: [folder], delimiter: nil)
            ?? hierarchySeparator(for: [], delimiter: delimiter)
            ?? "."
        return folder.id.components(separatedBy: pathSeparator)
    }

    private static func lastSegment(of folder: MailFolder, delimiter: String?) -> String {
        segments(of: folder, delimiter: delimiter).last ?? folder.id
    }

    private static func depth(of folder: MailFolder, delimiter: String?) -> Int {
        segments(of: folder, delimiter: delimiter).count
    }
}
