//
//  SpamFolderResolver.swift
//  Mailwerk
//
//  Zweck: Findet den Spam-Ordner eines Postfachs. Jedes Postfach hat seinen
//  eigenen – verschoben wird immer innerhalb desselben Kontos.
//
//  Reihenfolge der Prüfung:
//  1. der für das Konto gemerkte Ordner, sofern es ihn noch gibt
//  2. SPECIAL-USE \Junk (RFC 6154) – die verlässliche Auskunft des Servers
//  3. gebräuchliche Namen, unabhängig von Groß-/Kleinschreibung
//  4. nichts gefunden → Vorschlag zum Anlegen, den der Nutzer bestätigen muss
//
//  Abkürzung ohne Server: `knownFolder(in:configured:)` prüft nur, ob der
//  gemerkte Ordner in einer (z. B. gecachten) Ordnerliste steht – dann
//  braucht der Spamfilter keine frische Ordnerliste vom Server.
//
//  Reine Logik, deshalb `nonisolated` und ohne IMAP-Zugriff.
//
//  Abgrenzung: Ordnerliste vom Server und Anlegen → MailActionService;
//  Nutzung im Filter → SpamFilterService, in der Seitenleiste →
//  FolderTreeBuilder.
//
//  Abhängigkeiten: MailFolder.
//

import Foundation

/// Bestimmung des Spam-Ordners eines Postfachs.
nonisolated enum SpamFolderResolver {

    /// Gebräuchliche Namen in absteigender Verlässlichkeit.
    /// Verglichen wird das letzte Pfadsegment, ohne Groß-/Kleinschreibung.
    static let candidateNames = [
        "junk", "spam", "junk e-mail", "junk-e-mail", "junkmail", "bulk mail"
    ]

    /// Name, der beim Anlegen vorgeschlagen wird.
    static let proposedName = "Junk"

    /// Ergebnis der Suche nach dem Spam-Ordner.
    enum Resolution: Equatable {
        /// Ordner vorhanden – vollständiger IMAP-Pfad.
        case found(String)
        /// Kein Spam-Ordner vorhanden. Der Pfad ist ein Vorschlag und darf
        /// erst nach Rückfrage beim Nutzer angelegt werden.
        case missing(proposal: String)
    }

    /// Bestimmt den Spam-Ordner.
    ///
    /// Verarbeitung: Gemerkter Ordner, dann SPECIAL-USE `\Junk`, dann
    /// gebräuchliche Namen; sonst ein Vorschlag zum Anlegen.
    ///
    /// - Parameters:
    ///   - folders: Ordnerliste des Kontos (ohne INBOX).
    ///   - delimiter: Trennzeichen der Ordnerhierarchie, wie vom Server gemeldet.
    ///   - configured: zuvor für dieses Konto gemerkter Ordner.
    /// - Returns: Gefundener Ordner oder Vorschlag.
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
    ///
    /// - Parameters:
    ///   - folders: Ordnerliste.
    ///   - configured: gemerkter Pfad.
    /// - Returns: Passender Ordner oder `nil`.
    /// Der gemerkte Ordner, sofern er in der übergebenen Ordnerliste steht.
    ///
    /// Verarbeitung: Wie Schritt 1 von `resolve`, aber ohne die übrigen
    /// Schritte – findet sich der gemerkte Ordner nicht, ist das Ergebnis
    /// `nil` und der Aufrufer fragt die Ordnerliste beim Server ab.
    ///
    /// - Parameters:
    ///   - folders: Ordnerliste (z. B. aus dem Cache).
    ///   - configured: gemerkter Pfad.
    /// - Returns: IMAP-Pfad des Ordners oder `nil`.
    static func knownFolder(in folders: [MailFolder], configured: String?) -> String? {
        configuredMatch(in: folders, configured: configured)?.id
    }

    /// Sucht den gemerkten Spam-Ordner in der Ordnerliste.
    ///
    /// - Parameters:
    ///   - folders: Ordnerliste.
    ///   - configured: gemerkter Pfad; leer oder `nil` ergibt keinen Treffer.
    /// - Returns: Passender Ordner oder `nil`.
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
    ///
    /// - Parameters:
    ///   - folders: Ordnerliste.
    ///   - delimiter: Trennzeichen laut Server.
    /// - Returns: Passender Ordner oder `nil`.
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
    ///
    /// - Parameters:
    ///   - folders: Ordnerliste.
    ///   - delimiter: Trennzeichen laut Server.
    /// - Returns: Vorgeschlagener Pfad.
    private static func proposal(for folders: [MailFolder], delimiter: String?) -> String {
        guard !folders.isEmpty,
              let separator = hierarchySeparator(for: folders, delimiter: delimiter)
        else {
            return proposedName
        }
        let prefix = MailFolder.inboxPath + separator
        let allNested = folders.allSatisfy {
            $0.id.lowercased().hasPrefix(prefix.lowercased())
        }
        return allNested ? prefix + proposedName : proposedName
    }

    // MARK: - Helfer

    /// Trennzeichen: bevorzugt die Angabe des Servers, sonst die der Ordner.
    ///
    /// - Parameters:
    ///   - folders: Ordner, deren Trennzeichen als Ersatz dienen.
    ///   - delimiter: Trennzeichen laut Server.
    /// - Returns: Trennzeichen oder `nil` bei flacher Hierarchie.
    private static func hierarchySeparator(
        for folders: [MailFolder],
        delimiter: String?
    ) -> String? {
        if let delimiter, !delimiter.isEmpty { return delimiter }
        return folders.compactMap(\.hierarchyDelimiter).first { !$0.isEmpty }
    }

    /// Zerlegt den Pfad. Das Trennzeichen des Ordners selbst hat Vorrang,
    /// weil es direkt vom Server zu diesem Ordner gemeldet wurde. Ohne
    /// Trennzeichen ist die Hierarchie flach; der Pfad ist dann ein
    /// einziges Segment – ein Trennzeichen wird nicht geraten.
    ///
    /// - Parameters:
    ///   - folder: Ordner.
    ///   - delimiter: Trennzeichen laut Server.
    /// - Returns: Pfadsegmente.
    private static func segments(of folder: MailFolder, delimiter: String?) -> [String] {
        guard let pathSeparator = hierarchySeparator(for: [folder], delimiter: nil)
            ?? hierarchySeparator(for: [], delimiter: delimiter)
        else { return [folder.id] }
        return folder.id.components(separatedBy: pathSeparator)
    }

    /// Letztes Pfadsegment.
    ///
    /// - Parameters:
    ///   - folder: Ordner.
    ///   - delimiter: Trennzeichen laut Server.
    /// - Returns: Letztes Segment.
    private static func lastSegment(of folder: MailFolder, delimiter: String?) -> String {
        segments(of: folder, delimiter: delimiter).last ?? folder.id
    }

    /// Tiefe in der Hierarchie (1 = oberste Ebene).
    ///
    /// - Parameters:
    ///   - folder: Ordner.
    ///   - delimiter: Trennzeichen laut Server.
    /// - Returns: Anzahl der Segmente.
    private static func depth(of folder: MailFolder, delimiter: String?) -> Int {
        segments(of: folder, delimiter: delimiter).count
    }
}
