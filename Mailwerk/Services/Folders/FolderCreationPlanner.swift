//
//  FolderCreationPlanner.swift
//  Mailwerk
//
//  Prüft den Namen eines neuen Ordners und bestimmt seinen Server-Pfad.
//  Grundlage ist eine frische Ordnerliste des Servers (`FolderListing`),
//  abgerufen in derselben Verbindung wie das anschließende CREATE.
//
//  Pfadregel:
//  - oberste Ebene:  Namespace-Präfix + Name   (manitu: „Name“)
//  - Unterordner:    Elternpfad + Trennzeichen + Name
//                    (manitu: „INBOX.Name“, „Test.Name“)
//  Der Name wird in modified UTF-7 kodiert (`MailboxNameCodec`).
//
//  Meldet ein Server ein Namespace-Präfix wie „INBOX.“, sind Unterordner
//  des Posteingangs nicht von Ordnern auf oberster Ebene zu unterscheiden.
//  Dort werden sie abgelehnt.
//
//  Reine Logik ohne IMAP-Zugriff, deshalb `nonisolated`.
//

import Foundation

nonisolated enum FolderCreationPlanner {

    enum PlanError: LocalizedError, Equatable {
        case emptyName
        case containsDelimiter(String)
        case invalidCharacters
        case reservedName
        case alreadyExists(String)
        case subfoldersNotSupported

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Bitte einen Namen eingeben."
            case .containsDelimiter(let delimiter):
                return "Der Name darf kein „\(delimiter)“ enthalten – das Zeichen trennt auf diesem Server die Ordnerebenen."
            case .invalidCharacters:
                return "Der Name darf weder „*“ noch „%“ noch Steuerzeichen enthalten."
            case .reservedName:
                return "„INBOX“ ist dem Posteingang vorbehalten."
            case .alreadyExists(let name):
                return "Auf dieser Ebene gibt es bereits einen Ordner „\(name)“."
            case .subfoldersNotSupported:
                return "Dieser Server erlaubt an dieser Stelle keine Unterordner."
            }
        }
    }

    /// Bestimmt den Server-Pfad des neuen Ordners.
    /// - Parameters:
    ///   - name: vom Nutzer eingegebener Name (lesbar, nicht kodiert).
    ///   - parentPath: Server-Pfad des übergeordneten Ordners,
    ///     `nil` für die oberste Ebene.
    ///   - listing: aktuelle Ordnerliste inklusive INBOX.
    /// - Returns: Pfad in Server-Form (kodiert), bereit für CREATE.
    static func plan(
        name rawName: String,
        parentPath: String?,
        listing: FolderListing
    ) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PlanError.emptyName }

        let delimiter = serverDelimiter(in: listing)
        if let delimiter, name.contains(delimiter) {
            throw PlanError.containsDelimiter(delimiter)
        }
        guard !name.unicodeScalars.contains(where: isForbidden) else {
            throw PlanError.invalidCharacters
        }

        let base: String
        if let parentPath {
            guard let delimiter else { throw PlanError.subfoldersNotSupported }
            if isInbox(parentPath), let prefix = listing.namespacePrefix, !prefix.isEmpty {
                throw PlanError.subfoldersNotSupported
            }
            base = parentPath + delimiter
        } else {
            base = listing.namespacePrefix ?? ""
            if isInbox(name) { throw PlanError.reservedName }
        }

        // Geschwister auf derselben Ebene: Pfad beginnt mit `base` und hat
        // danach kein weiteres Trennzeichen. INBOX zählt auf oberster Ebene mit.
        let siblingNames = listing.folders.compactMap { folder -> String? in
            if parentPath == nil, isInbox(folder.id) { return folder.id }
            guard folder.id.count > base.count, folder.id.hasPrefix(base) else { return nil }
            let rest = String(folder.id.dropFirst(base.count))
            if let delimiter, rest.contains(delimiter) { return nil }
            return MailboxNameCodec.displayName(rest)
        }
        if let existing = siblingNames.first(where: {
            $0.caseInsensitiveCompare(name) == .orderedSame
        }) {
            throw PlanError.alreadyExists(existing)
        }

        return base + MailboxNameCodec.encode(name)
    }

    // MARK: - Intern

    /// Trennzeichen des Servers; alle Ordner eines Kontos nutzen dasselbe.
    private static func serverDelimiter(in listing: FolderListing) -> String? {
        listing.folders
            .compactMap(\.hierarchyDelimiter)
            .first { !$0.isEmpty }
    }

    private static func isInbox(_ path: String) -> Bool {
        path.caseInsensitiveCompare(FolderTreeBuilder.inboxPath) == .orderedSame
    }

    /// Platzhalter von LIST und Steuerzeichen sind im Namen nicht erlaubt.
    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "*" || scalar == "%"
            || scalar.properties.generalCategory == .control
    }
}
