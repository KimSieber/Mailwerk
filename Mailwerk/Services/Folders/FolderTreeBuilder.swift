//
//  FolderTreeBuilder.swift
//  Mailwerk
//
//  Baut aus der flachen Ordnerliste eines Postfachs den Ordnerbaum für
//  die Seitenleiste.
//
//  1. Namespace-Präfix entfernen: Legt der Server alle Ordner unter
//     „INBOX.“ ab (manitu), stehen sie in der Anzeige auf derselben Ebene
//     wie der Posteingang. Grundlage ist die NAMESPACE-Auskunft des
//     Servers, nicht der Ordnername – ohne Auskunft bleibt der Pfad, wie er ist.
//  2. Pfade am Trennzeichen zerlegen und verschachteln. Fehlt eine
//     Zwischenebene in der Liste, wird sie als nicht wählbarer Knoten ergänzt.
//  3. Rollen bestimmen: INBOX, dann SPECIAL-USE (RFC 6154), dann
//     gebräuchliche Namen – Letzteres nur auf der obersten Ebene und nur
//     für Rollen, die der Server nicht selbst gemeldet hat. Den Spam-Ordner
//     bestimmt `SpamFolderResolver`, damit Filter und Anzeige übereinstimmen.
//  4. Sortieren: oberste Ebene nach Rolle, sonst alphabetisch.
//
//  Reine Logik, deshalb `nonisolated` und ohne IMAP-Zugriff.
//

import Foundation

nonisolated enum FolderTreeBuilder {

    /// Pfad des Posteingangs laut RFC 3501; Groß-/Kleinschreibung egal.
    static let inboxPath = "INBOX"

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

    /// - Parameters:
    ///   - folders: vollständige Ordnerliste des Kontos, INBOX eingeschlossen.
    ///   - namespacePrefix: Präfix des persönlichen Namespace laut Server
    ///     (bei manitu „INBOX.“), `nil` oder leer, wenn keins gemeldet wurde.
    ///   - configuredSpamFolder: für das Konto gemerkter Spam-Ordner.
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
        let root = Draft(id: "", name: "")
        for folder in folders {
            let segments = displaySegments(of: folder, namespacePrefix: namespacePrefix)
            guard !segments.isEmpty else { continue }
            insert(
                folder,
                segments: segments,
                underInbox: isNestedUnderInbox(folder, segments: segments, namespacePrefix: namespacePrefix),
                into: root,
                role: roles[folder.id] ?? .regular
            )
        }

        let frozen = root.children.values.map { $0.freeze() }
        return resolveNameCollisions(frozen)
            .sorted(by: topLevelOrder)
    }

    // MARK: - Rollen

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

    private static func isInbox(_ path: String) -> Bool {
        path.caseInsensitiveCompare(inboxPath) == .orderedSame
    }

    /// Pfadsegmente für die Anzeige, ohne Namespace-Präfix.
    /// INBOX selbst ist immer ein einzelnes Segment auf oberster Ebene.
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

    private static func lastSegment(of folder: MailFolder, namespacePrefix: String?) -> String {
        displaySegments(of: folder, namespacePrefix: namespacePrefix).last ?? folder.id
    }

    /// Präfixvergleich; der INBOX-Anteil ist laut RFC 3501 nicht
    /// Groß-/Kleinschreibung-relevant, der Rest schon.
    private static func hasPrefix(_ path: String, _ prefix: String) -> Bool {
        if path.hasPrefix(prefix) { return true }
        let inboxLength = inboxPath.count
        guard prefix.count > inboxLength, path.count >= prefix.count,
              isInbox(String(prefix.prefix(inboxLength))),
              isInbox(String(path.prefix(inboxLength)))
        else { return false }
        return path.dropFirst(inboxLength).hasPrefix(prefix.dropFirst(inboxLength))
    }

    /// Vollständiger Pfad einer Zwischenebene, rekonstruiert aus dem Ordner.
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
        let id: String
        var name: String
        var role: FolderRole = .regular
        var isSelectable = false
        var children: [String: Draft] = [:]

        init(id: String, name: String) {
            self.id = id
            self.name = name
        }

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

    private static func insert(
        _ folder: MailFolder,
        segments: [String],
        underInbox: Bool,
        into root: Draft,
        role: FolderRole
    ) {
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
                node = Draft(id: id, name: segment)
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
    private static func resolveNameCollisions(_ nodes: [FolderNode]) -> [FolderNode] {
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
                  node.role.displayName != nil
            else { return node }
            // Servernamen aus der ID zurückholen: letztes Pfadsegment.
            let serverName = node.id.components(separatedBy: ".").last
                ?? node.id.components(separatedBy: "/").last
                ?? node.id
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

    private static func alphabetical(_ lhs: FolderNode, _ rhs: FolderNode) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }

    private static func topLevelOrder(_ lhs: FolderNode, _ rhs: FolderNode) -> Bool {
        lhs.role == rhs.role ? alphabetical(lhs, rhs) : lhs.role < rhs.role
    }
}
