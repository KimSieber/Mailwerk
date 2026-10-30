//
//  FolderTreeBuilder.swift
//  Mailwerk
//
//  Zweck: Baut aus der flachen Ordnerliste eines Postfachs den Ordnerbaum
//  für die Seitenleiste.
//
//  1. Namespace-Präfix entfernen: Legt ein Server alle Ordner unter
//     „INBOX.“ ab, stehen sie in der Anzeige auf derselben Ebene wie der
//     Posteingang. Grundlage ist die NAMESPACE-Auskunft des Servers, nicht
//     der Ordnername – ohne Auskunft bleibt der Pfad, wie er ist.
//     manitu meldet kein Präfix (`(("" "."))`): Ordner liegen auf oberster
//     Ebene („Test“), Unterordner des Posteingangs heißen „INBOX.Name“.
//  2. Pfade am Trennzeichen zerlegen und verschachteln. Fehlt eine
//     Zwischenebene in der Liste, wird sie als nicht wählbarer Knoten ergänzt.
//  3. Rollen bestimmen: INBOX, dann SPECIAL-USE (RFC 6154), dann
//     gebräuchliche Namen – Letzteres nur auf der obersten Ebene und nur
//     für Rollen, die der Server nicht selbst gemeldet hat. Den Spam-Ordner
//     bestimmt `SpamFolderResolver`, damit Filter und Anzeige übereinstimmen.
//  4. Sortieren: oberste Ebene nach Rolle, sonst alphabetisch.
//
//  Namen werden für die Anzeige aus modified UTF-7 dekodiert
//  (`MailboxNameCodec`). Pfade (`FolderNode.id`) bleiben in Server-Form.
//
//  Reine Logik, deshalb `nonisolated` und ohne IMAP-Zugriff.
//
//  Abgrenzung: Ordnerliste vom Server → MailActionService; Anzeige →
//  FolderSidebarView; Spam-Ordner → SpamFolderResolver.
//
//  Abhängigkeiten: MailFolder, FolderListing, FolderNode, FolderRole,
//  MailboxNameCodec, SpamFolderResolver.
//

import Foundation

/// Ordnerbaum aus der flachen Ordnerliste.
nonisolated enum FolderTreeBuilder {

    /// Gebräuchliche Namen je Rolle (kleingeschrieben, letztes Segment).
    /// Spam fehlt bewusst: den bestimmt `SpamFolderResolver`.
    static let candidateNames: [(FolderRole, [String])] = [
        (.drafts,  ["drafts", "draft", "entwürfe"]),
        (.sent,    ["sent", "sent items", "sent messages", "sent mail",
                    "gesendet", "gesendete elemente", "gesendete objekte"]),
        (.archive, ["archive", "archiv"]),
        (.trash,   ["trash", "deleted items", "deleted messages",
                    "papierkorb", "gelöschte elemente", "gelöschte objekte"])
    ]

    /// Baut den Ordnerbaum.
    ///
    /// Verarbeitung: Rollen bestimmen, jeden Ordner entlang seiner
    /// Pfadsegmente einhängen, einfrieren, gleichlautende Namen auflösen
    /// (mit den Servernamen aus derselben Zerlegung) und die oberste Ebene
    /// nach Rolle sortieren.
    ///
    /// - Parameters:
    ///   - folders: vollständige Ordnerliste des Kontos, INBOX eingeschlossen.
    ///   - namespacePrefix: Präfix des persönlichen Namespace laut Server
    ///     (etwa „INBOX.“), `nil` oder leer, wenn keins gemeldet wurde –
    ///     bei manitu leer.
    ///   - configuredSpamFolder: für das Konto gemerkter Spam-Ordner.
    /// - Returns: Knoten der obersten Ebene.
    static func build(
        folders: [MailFolder],
        namespacePrefix: String?,
        configuredSpamFolder: String?
    ) -> [FolderNode] {
        let roles = assignRoles(
            folders: folders,
            namespacePrefix: namespacePrefix,
            configuredSpamFolder: configuredSpamFolder
        )

        // Wurzel des Baums als veränderliche Hilfsstruktur aufbauen.
        // Nebenbei den Servernamen (letztes Segment, dekodiert) je Ordner
        // merken – für die Auflösung gleichlautender Namen.
        let root = Draft(id: "", name: "")
        var serverNames: [String: String] = [:]
        for folder in folders {
            let segments = displaySegments(of: folder, namespacePrefix: namespacePrefix)
            guard let last = segments.last else { continue }
            serverNames[folder.id] = MailboxNameCodec.displayName(last)
            let placement = Placement(
                segments: segments,
                underInbox: isNestedUnderInbox(folder, segments: segments, namespacePrefix: namespacePrefix),
                role: roles[folder.id] ?? .regular
            )
            insert(folder, at: placement, into: root)
        }

        let frozen = root.children.values.map { $0.freeze() }
        return resolveNameCollisions(frozen, serverNames: serverNames)
            .sorted(by: topLevelOrder)
    }

    /// Baum aus einer gespeicherten oder frisch geladenen Ordnerliste.
    ///
    /// - Parameters:
    ///   - listing: Ordnerliste mit Namespace-Präfix.
    ///   - configuredSpamFolder: für das Konto gemerkter Spam-Ordner.
    /// - Returns: Knoten der obersten Ebene.
    static func build(listing: FolderListing, configuredSpamFolder: String?) -> [FolderNode] {
        build(
            folders: listing.folders,
            namespacePrefix: listing.namespacePrefix,
            configuredSpamFolder: configuredSpamFolder
        )
    }

    // MARK: - Rollen

    /// Ordnet jedem Ordner seine Rolle zu.
    ///
    /// Verarbeitung: Posteingang, dann SPECIAL-USE, dann Spam-Ordner wie im
    /// Filter, zuletzt gebräuchliche Namen auf der obersten Ebene für noch
    /// freie Rollen (bei mehreren Treffern der alphabetisch erste Pfad).
    ///
    /// - Parameters:
    ///   - folders: vollständige Ordnerliste.
    ///   - namespacePrefix: Präfix des persönlichen Namespace.
    ///   - configuredSpamFolder: gemerkter Spam-Ordner.
    /// - Returns: Rolle je Ordnerpfad; fehlende Einträge sind gewöhnliche Ordner.
    private static func assignRoles(
        folders: [MailFolder],
        namespacePrefix: String?,
        configuredSpamFolder: String?
    ) -> [String: FolderRole] {
        var roles: [String: FolderRole] = [:]

        for folder in folders {
            if isInbox(folder.id) {
                roles[folder.id] = .inbox
            } else if let specialUse = folder.specialUse {
                roles[folder.id] = FolderRole(specialUse)
            }
        }

        // Spam-Ordner wie der Filter bestimmen. Der Resolver erwartet die
        // Liste ohne INBOX; nur ein gefundener Ordner zählt, kein Vorschlag.
        let withoutInbox = folders.filter { !isInbox($0.id) }
        if case .found(let path) = SpamFolderResolver.resolve(
            folders: withoutInbox,
            delimiter: withoutInbox.compactMap(\.hierarchyDelimiter).first,
            configured: configuredSpamFolder
        ), roles[path] == nil {
            roles[path] = .junk
        }

        // Namensabgleich nur für Rollen, die noch niemand hat, und nur
        // auf der obersten Ebene: „Projekte.Sent“ ist kein Gesendet-Ordner.
        let taken = Set(roles.values)
        let topLevel = folders.filter {
            roles[$0.id] == nil
                && displaySegments(of: $0, namespacePrefix: namespacePrefix).count == 1
        }
        for (role, names) in candidateNames where !taken.contains(role) {
            for name in names {
                let matches = topLevel.filter {
                    roles[$0.id] == nil && lastSegment(of: $0, namespacePrefix: namespacePrefix).lowercased() == name
                }
                if let match = matches.min(by: { $0.id < $1.id }) {
                    roles[match.id] = role
                    break
                }
            }
        }
        return roles
    }

    // MARK: - Pfade

    /// Prüft, ob ein Pfad der Posteingang ist.
    ///
    /// - Parameter path: IMAP-Pfad.
    /// - Returns: `true` für den Posteingang.
    private static func isInbox(_ path: String) -> Bool {
        MailFolder.isInbox(path)
    }

    /// Pfadsegmente ohne Namespace-Präfix, noch in Server-Form (kodiert) –
    /// so passen sie zur Pfad-Rekonstruktion in `ancestorPath`.
    /// INBOX selbst ist immer ein einzelnes Segment auf oberster Ebene.
    ///
    /// - Parameters:
    ///   - folder: Ordner.
    ///   - namespacePrefix: Präfix des persönlichen Namespace.
    /// - Returns: Segmente; leer, wenn nach dem Präfix nichts übrig bleibt.
    private static func displaySegments(
        of folder: MailFolder,
        namespacePrefix: String?
    ) -> [String] {
        if isInbox(folder.id) { return [folder.id] }

        var path = folder.id
        if let prefix = namespacePrefix, !prefix.isEmpty, hasPrefix(path, prefix) {
            path = String(path.dropFirst(prefix.count))
        }
        guard let delimiter = folder.hierarchyDelimiter, !delimiter.isEmpty else {
            return path.isEmpty ? [] : [path]
        }
        return path.components(separatedBy: delimiter).filter { !$0.isEmpty }
    }

    /// Letztes Segment, dekodiert – für den Abgleich mit gebräuchlichen
    /// Namen wie „entwürfe“, die der Server kodiert meldet.
    ///
    /// - Parameters:
    ///   - folder: Ordner.
    ///   - namespacePrefix: Präfix des persönlichen Namespace.
    /// - Returns: Lesbarer Name des letzten Segments.
    private static func lastSegment(of folder: MailFolder, namespacePrefix: String?) -> String {
        MailboxNameCodec.displayName(
            displaySegments(of: folder, namespacePrefix: namespacePrefix).last ?? folder.id
        )
    }

    /// Präfixvergleich; der INBOX-Anteil ist laut RFC 3501 nicht
    /// Groß-/Kleinschreibung-relevant, der Rest schon.
    ///
    /// - Parameters:
    ///   - path: IMAP-Pfad.
    ///   - prefix: Namespace-Präfix.
    /// - Returns: `true`, wenn `path` mit `prefix` beginnt.
    private static func hasPrefix(_ path: String, _ prefix: String) -> Bool {
        if path.hasPrefix(prefix) { return true }
        let inboxLength = MailFolder.inboxPath.count
        guard prefix.count > inboxLength, path.count >= prefix.count,
              isInbox(String(prefix.prefix(inboxLength))),
              isInbox(String(path.prefix(inboxLength)))
        else { return false }
        return path.dropFirst(inboxLength).hasPrefix(prefix.dropFirst(inboxLength))
    }

    /// Vollständiger Pfad einer Zwischenebene, rekonstruiert aus dem Ordner.
    ///
    /// - Parameters:
    ///   - folder: Ordner, dessen Vorfahr gesucht ist.
    ///   - segments: Segmente des Ordners ohne Namespace-Präfix.
    ///   - depth: Tiefe des Vorfahren (1 = oberste Ebene).
    /// - Returns: Server-Pfad des Vorfahren.
    private static func ancestorPath(
        of folder: MailFolder,
        segments: [String],
        depth: Int
    ) -> String {
        let delimiter = folder.hierarchyDelimiter ?? ""
        let fullDepthPath = segments.joined(separator: delimiter)
        let prefix = String(folder.id.dropLast(fullDepthPath.count))
        return prefix + segments.prefix(depth).joined(separator: delimiter)
    }

    // MARK: - Aufbau

    /// Veränderliche Hilfsstruktur für den Aufbau; wird am Ende zu
    /// unveränderlichen `FolderNode`s eingefroren.
    private final class Draft {
        /// Server-Pfad.
        let id: String
        /// Anzeigename.
        var name: String
        /// Rolle des Ordners.
        var role: FolderRole = .regular
        /// `false` für ergänzte Zwischenebenen und `\Noselect`-Container.
        var isSelectable = false
        /// Unterordner, nach Segment (bzw. `inboxKey`).
        var children: [String: Draft] = [:]

        /// Legt einen Knoten an.
        ///
        /// - Parameters:
        ///   - id: Server-Pfad.
        ///   - name: Anzeigename.
        init(id: String, name: String) {
            self.id = id
            self.name = name
        }

        /// Friert den Knoten samt Unterordnern ein.
        ///
        /// - Returns: Unveränderlicher Knoten, Unterordner alphabetisch.
        func freeze() -> FolderNode {
            FolderNode(
                id: id,
                name: name,
                role: role,
                isSelectable: isSelectable,
                children: children.values.map { $0.freeze() }.sorted(by: alphabetical)
            )
        }
    }

    /// Schlüssel des Posteingangs unter den Kindern der Wurzel. Bewusst
    /// kein möglicher Ordnername, damit ein Ordner „INBOX“ unterhalb des
    /// Namespace-Präfixes (Pfad „INBOX.INBOX“) nicht mit ihm verschmilzt.
    private static let inboxKey = "\u{0}INBOX"

    /// Ordner, die ohne Namespace-Präfix unter INBOX liegen (etwa bei
    /// Dovecot „INBOX/Projekte“), sind echte Unterordner des Posteingangs.
    ///
    /// - Parameters:
    ///   - folder: Ordner.
    ///   - segments: Segmente des Ordners ohne Namespace-Präfix.
    ///   - namespacePrefix: Präfix des persönlichen Namespace.
    /// - Returns: `true` für den Posteingang und seine Unterordner.
    private static func isNestedUnderInbox(
        _ folder: MailFolder,
        segments: [String],
        namespacePrefix: String?
    ) -> Bool {
        if isInbox(folder.id) { return true }
        guard let first = segments.first, isInbox(first) else { return false }
        if let prefix = namespacePrefix, !prefix.isEmpty, hasPrefix(folder.id, prefix) {
            return false
        }
        return true
    }

    /// Wo und als was ein Ordner in den Baum kommt.
    private struct Placement {
        /// Segmente ohne Namespace-Präfix.
        let segments: [String]
        /// `true` = erste Ebene ist der Posteingang.
        let underInbox: Bool
        /// Rolle des Ordners.
        let role: FolderRole
    }

    /// Hängt einen Ordner entlang seiner Segmente in den Baum ein.
    ///
    /// Verarbeitung: Fehlende Zwischenebenen entstehen als nicht wählbare
    /// Knoten; der letzte Knoten erhält Rolle, Wählbarkeit und ggf. den
    /// vereinheitlichten Rollennamen.
    ///
    /// - Parameters:
    ///   - folder: Ordner.
    ///   - placement: Segmente, Lage unter dem Posteingang und Rolle.
    ///   - root: Wurzel des Baums.
    private static func insert(_ folder: MailFolder, at placement: Placement, into root: Draft) {
        let segments = placement.segments
        let underInbox = placement.underInbox
        let role = placement.role
        var current = root
        for depth in 1...segments.count {
            let segment = segments[depth - 1]
            let isLast = depth == segments.count
            let key = (depth == 1 && underInbox) ? inboxKey : segment
            let id = isLast ? folder.id : ancestorPath(of: folder, segments: segments, depth: depth)

            let node: Draft
            if let existing = current.children[key] {
                node = existing
            } else {
                node = Draft(id: id, name: MailboxNameCodec.displayName(segment))
                current.children[key] = node
            }
            if isLast {
                node.role = role
                node.isSelectable = folder.isSelectable
                if let displayName = role.displayName {
                    node.name = displayName
                }
            }
            current = node
        }
    }

    // MARK: - Namensgleichheit

    /// Wenn ein vereinheitlichter Rollenname auf derselben Ebene einem
    /// gewöhnlichen Ordner gleicht, behalten beide ihren Servernamen.
    /// Das vermeidet zwei identische Einträge in der Liste.
    ///
    /// Verarbeitung: Der Servername stammt aus derselben Zerlegung wie der
    /// Baum (Trennzeichen des Servers, Namespace-Präfix entfernt). Er wird
    /// nicht aus dem Pfad geraten – bei Servern mit „/“ als Trennzeichen
    /// wäre „.“ falsch.
    ///
    /// - Parameters:
    ///   - nodes: Knoten einer Ebene.
    ///   - serverNames: Servername (dekodiert) je Ordnerpfad.
    /// - Returns: Knoten mit eindeutigen Namen.
    private static func resolveNameCollisions(
        _ nodes: [FolderNode],
        serverNames: [String: String]
    ) -> [FolderNode] {
        // Alle Anzeigenamen auf dieser Ebene zählen.
        var counts: [String: Int] = [:]
        for node in nodes {
            counts[node.name.lowercased(), default: 0] += 1
        }
        // Nur bei echten Kollisionen handeln.
        let collisions = Set(counts.filter { $0.value > 1 }.map(\.key))
        guard !collisions.isEmpty else { return nodes }

        return nodes.map { node in
            guard collisions.contains(node.name.lowercased()),
                  node.role != .regular,
                  node.role.displayName != nil,
                  let serverName = serverNames[node.id]
            else { return node }
            return FolderNode(
                id: node.id,
                name: serverName,
                role: node.role,
                isSelectable: node.isSelectable,
                children: node.children
            )
        }
    }

    // MARK: - Sortierung

    /// Alphabetisch nach Anzeigename, bei Gleichheit nach Pfad.
    ///
    /// - Parameters:
    ///   - lhs: Erster Knoten.
    ///   - rhs: Zweiter Knoten.
    /// - Returns: `true`, wenn `lhs` vor `rhs` steht.
    private static func alphabetical(_ lhs: FolderNode, _ rhs: FolderNode) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }

    /// Oberste Ebene: nach Rolle, innerhalb einer Rolle alphabetisch.
    ///
    /// - Parameters:
    ///   - lhs: Erster Knoten.
    ///   - rhs: Zweiter Knoten.
    /// - Returns: `true`, wenn `lhs` vor `rhs` steht.
    private static func topLevelOrder(_ lhs: FolderNode, _ rhs: FolderNode) -> Bool {
        lhs.role == rhs.role ? alphabetical(lhs, rhs) : lhs.role < rhs.role
    }
}
