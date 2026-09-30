//
//  FolderDeletion.swift
//  Mailwerk
//
//  Löscht einen leeren Ordner über einen eigenen, schlanken IMAP-Dialog.
//
//  WARUM EIGENER WEG: SwiftMail 1.12.0 kennt DELETE nur intern. Der Weg ist
//  bewusst auf genau diese eine Aufgabe beschränkt und wird zurückgebaut,
//  sobald SwiftMail `deleteMailbox` öffentlich anbietet (Technical Debt).
//
//  Ablauf in EINER Verbindung – die Prüfung findet unmittelbar vor dem
//  Löschen statt, denn DELETE entfernt enthaltene Mails ohne Rückfrage:
//    1. Begrüßung abwarten („* OK“)
//    2. AUTHENTICATE PLAIN mit Initial Response (SASL-IR, RFC 4959):
//       Zugangsdaten in Base64, keine Probleme mit Sonderzeichen
//    3. LIST "" "<Pfad>"               – Ordner vorhanden? wählbar? Trennzeichen?
//    4. LIST "" "<Pfad><Trenner>%"      – Unterordner?
//    5. STATUS "<Pfad>" (MESSAGES)      – Mails?
//    6. DELETE "<Pfad>"                 – nur, wenn 3–5 ergeben: leer
//    7. LOGOUT
//
//  Diese Datei enthält nur Protokoll-Logik gegen `IMAPLineChannel` und
//  ist ohne Netz testbar. Den verschlüsselten Transport liefert
//  `IMAPLineConnection`. Zugangsdaten werden nie protokolliert.
//

import Foundation

/// Zeilenweiser Kanal zu einem IMAP-Server. Zeilen ohne CRLF.
nonisolated protocol IMAPLineChannel: AnyObject {
    func send(_ line: String) async throws
    func readLine() async throws -> String
}

nonisolated enum FolderDeletion {

    /// Ergebnis, wenn die Verbindung selbst funktioniert hat.
    enum Outcome: Equatable {
        case deleted
        case notFound
        case notSelectable
        case hasSubfolders
        case notEmpty(messages: Int)

        /// Hinweis für den Nutzer, `nil` bei Erfolg.
        var userMessage: String? {
            switch self {
            case .deleted:
                return nil
            case .notFound:
                return "Den Ordner gibt es auf dem Server nicht mehr."
            case .notSelectable:
                return "Dieser Ordner ist nur ein Container und kann hier nicht gelöscht werden."
            case .hasSubfolders:
                return "Der Ordner enthält Unterordner – bitte zuerst diese löschen."
            case .notEmpty(let count):
                let mails = count == 1 ? "1 Mail" : "\(count) Mails"
                return "Der Ordner enthält \(mails) – bitte zuerst verschieben oder löschen."
            }
        }
    }

    enum DeletionError: LocalizedError, Equatable {
        case unexpectedGreeting
        case authenticationFailed
        case unsupportedPath
        case unexpectedResponse(String)
        case serverRefused(String)

        var errorDescription: String? {
            switch self {
            case .unexpectedGreeting:
                return "Der Server hat die Verbindung nicht wie erwartet begrüßt."
            case .authenticationFailed:
                return "Anmeldung am Server fehlgeschlagen."
            case .unsupportedPath:
                return "Dieser Ordnername kann in Mailwerk nicht gelöscht werden – bitte im Webmail löschen."
            case .unexpectedResponse(let detail):
                return "Unerwartete Antwort des Servers: \(detail)"
            case .serverRefused(let detail):
                return "Der Server hat das Löschen abgelehnt: \(detail)"
            }
        }
    }

    // MARK: - Ablauf

    static func run(
        on channel: IMAPLineChannel,
        username: String,
        password: String,
        path: String
    ) async throws -> Outcome {
        guard let quotedPath = quoted(path), !path.contains("*"), !path.contains("%") else {
            throw DeletionError.unsupportedPath
        }

        let greeting = try await channel.readLine()
        guard greeting.hasPrefix("* OK") else { throw DeletionError.unexpectedGreeting }

        var session = Session(channel: channel)

        let auth = try await session.command(
            "AUTHENTICATE PLAIN " + plainCredentials(username: username, password: password),
            abortOnContinuation: true
        )
        guard auth.status == .ok else { throw DeletionError.authenticationFailed }

        do {
            let outcome = try await checkAndDelete(path: path, quotedPath: quotedPath, session: &session)
            _ = try? await session.command("LOGOUT")
            return outcome
        } catch {
            _ = try? await session.command("LOGOUT")
            throw error
        }
    }

    private static func checkAndDelete(
        path: String,
        quotedPath: String,
        session: inout Session
    ) async throws -> Outcome {
        // 3. Den Ordner selbst.
        let own = try await session.command("LIST \"\" \(quotedPath)")
        try own.requireOK()
        guard let entry = own.untagged
            .compactMap(parseListLine)
            .first(where: { $0.name == path })
        else { return .notFound }
        if entry.attributes.contains("\\noselect") || entry.attributes.contains("\\nonexistent") {
            return .notSelectable
        }

        // 4. Unterordner – unabhängig davon, ob der Server CHILDREN meldet.
        if entry.attributes.contains("\\haschildren") { return .hasSubfolders }
        if let delimiter = entry.delimiter, let pattern = quoted(path + delimiter + "%") {
            let children = try await session.command("LIST \"\" \(pattern)")
            try children.requireOK()
            if children.untagged.contains(where: { parseListLine($0) != nil }) {
                return .hasSubfolders
            }
        }

        // 5. Mails.
        let status = try await session.command("STATUS \(quotedPath) (MESSAGES)")
        try status.requireOK()
        guard let count = status.untagged.lazy.compactMap(parseStatusMessages).first else {
            throw DeletionError.unexpectedResponse("STATUS ohne Anzahl")
        }
        if count > 0 { return .notEmpty(messages: count) }

        // 6. Löschen.
        let delete = try await session.command("DELETE \(quotedPath)")
        guard delete.status == .ok else { throw DeletionError.serverRefused(delete.text) }
        return .deleted
    }

    // MARK: - Befehle

    /// Ein Befehl mit fortlaufendem Kennzeichen und seine Antwortzeilen.
    private struct Session {
        let channel: IMAPLineChannel
        var counter = 0

        mutating func command(
            _ command: String,
            abortOnContinuation: Bool = false
        ) async throws -> Response {
            counter += 1
            let tag = "MW\(counter)"
            try await channel.send("\(tag) \(command)")
            var untagged: [String] = []
            while true {
                let line = try await channel.readLine()
                if line.hasPrefix("+") {
                    // Der Server will weitere Daten, die wir nicht senden –
                    // etwa weil er SASL-IR nicht unterstützt. Abbrechen.
                    guard abortOnContinuation else {
                        throw DeletionError.unexpectedResponse("Fortsetzung erwartet")
                    }
                    try await channel.send("*")
                    continue
                }
                if let completion = FolderDeletion.completion(of: line, tag: tag) {
                    return Response(status: completion.status, text: completion.text, untagged: untagged)
                }
                if line.hasPrefix("* BYE") {
                    throw DeletionError.unexpectedResponse("Server hat die Verbindung beendet")
                }
                untagged.append(line)
            }
        }
    }

    struct Response {
        let status: Status
        let text: String
        let untagged: [String]

        func requireOK() throws {
            guard status == .ok else { throw DeletionError.serverRefused(text) }
        }
    }

    enum Status: Equatable { case ok, no, bad }

    // MARK: - Kodierung

    /// IMAP-Zeichenkette in Anführungszeichen. `nil`, wenn der Text Zeichen
    /// enthält, die nur als Literal übertragbar wären (CR, LF, NUL,
    /// Nicht-ASCII) – Ordnerpfade sind nach modified UTF-7 reines ASCII.
    static func quoted(_ text: String) -> String? {
        var result = "\""
        for scalar in text.unicodeScalars {
            guard scalar.isASCII, scalar != "\r", scalar != "\n", scalar != "\0" else { return nil }
            if scalar == "\"" || scalar == "\\" { result += "\\" }
            result.unicodeScalars.append(scalar)
        }
        return result + "\""
    }

    /// SASL PLAIN (RFC 4616): Base64 von „\0Benutzer\0Passwort“.
    static func plainCredentials(username: String, password: String) -> String {
        var bytes: [UInt8] = [0]
        bytes += Array(username.utf8)
        bytes.append(0)
        bytes += Array(password.utf8)
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Antworten auswerten

    /// Abschlusszeile zum Kennzeichen, etwa „MW3 OK List completed“.
    static func completion(of line: String, tag: String) -> (status: Status, text: String)? {
        guard line.hasPrefix(tag + " ") else { return nil }
        let rest = line.dropFirst(tag.count + 1)
        let parts = rest.split(separator: " ", maxSplits: 1)
        guard let word = parts.first else { return nil }
        let text = parts.count > 1 ? String(parts[1]) : ""
        switch word.uppercased() {
        case "OK":  return (.ok, text)
        case "NO":  return (.no, text)
        case "BAD": return (.bad, text)
        default:    return nil
        }
    }

    struct ListEntry: Equatable {
        /// Attribute, kleingeschrieben (z. B. „\haschildren“).
        let attributes: Set<String>
        let delimiter: String?
        /// Ordnername in Server-Form.
        let name: String
    }

    /// Wertet „* LIST (\HasNoChildren) "." Test.Neu“ aus. Namen als Literal
    /// („{12}“) werden nicht unterstützt und ergeben `nil` – im Zweifel
    /// wird dann nicht gelöscht.
    static func parseListLine(_ line: String) -> ListEntry? {
        var scanner = Scanner(line)
        guard scanner.consume("* LIST ") || scanner.consume("* list "),
              scanner.consume("("),
              let attributeText = scanner.upTo(")"),
              scanner.consume(") ")
        else { return nil }

        let delimiter: String?
        if scanner.consume("NIL ") || scanner.consume("nil ") {
            delimiter = nil
        } else {
            guard let value = scanner.quotedString(), scanner.consume(" ") else { return nil }
            delimiter = value
        }

        let name: String
        if scanner.peek == "\"" {
            guard let value = scanner.quotedString(), scanner.isAtEnd else { return nil }
            name = value
        } else {
            let atom = scanner.remainder
            guard !atom.isEmpty, !atom.hasPrefix("{"), !atom.contains(" ") else { return nil }
            name = atom
        }

        let attributes = Set(
            attributeText.split(separator: " ").map { $0.lowercased() }
        )
        return ListEntry(attributes: attributes, delimiter: delimiter, name: name)
    }

    /// Anzahl aus „* STATUS "Test.Neu" (MESSAGES 0)“.
    static func parseStatusMessages(_ line: String) -> Int? {
        guard line.uppercased().hasPrefix("* STATUS "),
              let open = line.lastIndex(of: "("),
              let close = line.lastIndex(of: ")"), open < close
        else { return nil }
        let items = line[line.index(after: open)..<close].split(separator: " ")
        guard let index = items.firstIndex(where: { $0.uppercased() == "MESSAGES" }),
              items.index(after: index) < items.endIndex
        else { return nil }
        return Int(items[items.index(after: index)])
    }

    // MARK: - Kleiner Zeilenleser

    private struct Scanner {
        private let scalars: [Unicode.Scalar]
        private var index = 0

        init(_ text: String) { scalars = Array(text.unicodeScalars) }

        var isAtEnd: Bool { index >= scalars.count }
        var peek: Unicode.Scalar? { isAtEnd ? nil : scalars[index] }
        var remainder: String { String(String.UnicodeScalarView(scalars[index...])) }

        mutating func consume(_ literal: String) -> Bool {
            let expected = Array(literal.unicodeScalars)
            guard index + expected.count <= scalars.count,
                  Array(scalars[index..<(index + expected.count)]) == expected
            else { return false }
            index += expected.count
            return true
        }

        mutating func upTo(_ terminator: Unicode.Scalar) -> String? {
            guard let end = scalars[index...].firstIndex(of: terminator) else { return nil }
            let text = String(String.UnicodeScalarView(scalars[index..<end]))
            index = end
            return text
        }

        /// „"…"“ mit Escapes für \" und \\.
        mutating func quotedString() -> String? {
            guard consume("\"") else { return nil }
            var result = ""
            while let scalar = peek {
                index += 1
                switch scalar {
                case "\"":
                    return result
                case "\\":
                    guard let escaped = peek else { return nil }
                    index += 1
                    result.unicodeScalars.append(escaped)
                default:
                    result.unicodeScalars.append(scalar)
                }
            }
            return nil
        }
    }
}
