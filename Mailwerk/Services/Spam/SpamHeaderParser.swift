//
//  SpamHeaderParser.swift
//  Mailwerk
//
//  Zweck: Liest die Spam-Einstufung des Servers aus den Headern `X-Spam`,
//  `X-Spam-Flag` (z. B. GMX, web.de) und `X-Spam-Status` (z. B. rspamd bei
//  manitu, mit Score). Groß-/Kleinschreibung und Leerzeichen um den Wert
//  spielen keine Rolle. Reine Logik ohne IMAP, vollständig per Unit-Test
//  abgedeckt.
//
//  Genutzt an zwei Stellen: im Spamfilter-Lauf (Entscheidung behalten
//  oder nach Spam) und beim Abruf, der die Einstufung je Mail im Cache
//  speichert (Grundlage für das sofortige Laden externer Inhalte bei
//  Whitelist-Absendern).
//
//  `nonisolated`, weil der Filterlauf außerhalb des Main-Actors arbeitet.
//
//  Nebenläufigkeit: `nonisolated` und `Sendable` – reine Werte bzw. reine
//  Logik ohne Bezug zur Oberfläche. So kann die Ablage (MessageStore) sie
//  auch außerhalb des Hauptthreads nutzen (v0.2.3b).
//
//  Abgrenzung: Entscheidung aus Einstufung und Listen → SpamClassifier;
//  Abruf der Header → SpamFilterService, MailFetchService.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Eine Header-Zeile, unabhängig vom Typ der Mail-Bibliothek.
nonisolated struct SpamHeaderLine: Equatable {
    /// Name der Kopfzeile, z. B. "X-Spam-Status".
    let name: String
    /// Wert der Kopfzeile.
    let value: String
}

/// Befund der Server-Header.
nonisolated struct SpamHeaderVerdict: Equatable, Sendable {
    /// Irgendeine Zeile stuft die Mail als Spam ein.
    let isSpam: Bool
    /// Höchster lesbarer Score aller `X-Spam-Status`-Zeilen, sonst nil.
    let score: Double?
}

/// Auswertung der Spam-Kopfzeilen des Servers.
nonisolated enum SpamHeaderParser {

    /// Header, die beim Filterlauf und beim Abruf per
    /// `BODY.PEEK[HEADER.FIELDS (…)]` geladen werden.
    static let fieldNames = ["X-Spam", "X-Spam-Flag", "X-Spam-Status"]

    /// Kopfzeilen, die nur „Yes“/„No“ tragen, in Kleinschreibung.
    private static let flagHeaders: Set<String> = ["x-spam", "x-spam-flag"]
    /// Name der Kopfzeile `X-Spam-Status` in Kleinschreibung.
    private static let statusHeader = "x-spam-status"

    /// Zeichen, die das erste Wort eines Header-Werts abschließen.
    private static let wordBoundaries = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)

    /// `score=<Zahl>`, unabhängig von Groß-/Kleinschreibung.
    private static let scorePattern = try? NSRegularExpression(
        pattern: #"score\s*=\s*(-?\d+(?:\.\d+)?)"#,
        options: [.caseInsensitive]
    )

    /// Wertet ausschließlich `X-Spam`, `X-Spam-Flag` und `X-Spam-Status`
    /// aus, nie den Betreff.
    ///
    /// Verarbeitung:
    /// - Spam, wenn irgendeine dieser Zeilen mit `Yes` beginnt (ohne
    ///   Groß-/Kleinschreibung, Leerzeichen davor zählen nicht).
    /// - Score ist der höchste Wert aller `X-Spam-Status`-Zeilen. Ein Absender
    ///   kann eigene Header mitschicken; ein gefälschter niedriger Score darf
    ///   die Einstufung nicht senken.
    /// - Andere Kopfzeilen (z. B. References) werden übergangen.
    ///
    /// - Parameter lines: Kopfzeilen in der Reihenfolge des Servers.
    /// - Returns: Einstufung; ohne Spam-Kopfzeilen `clean`.
    static func parse(_ lines: [SpamHeaderLine]) -> SpamHeaderVerdict {
        var isSpam = false
        var highestScore: Double?

        for line in lines {
            let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard flagHeaders.contains(name) || name == statusHeader else { continue }

            if startsWithYes(line.value) { isSpam = true }

            if name == statusHeader, let score = score(in: line.value) {
                highestScore = max(highestScore ?? score, score)
            }
        }

        return SpamHeaderVerdict(isSpam: isSpam, score: highestScore)
    }

    /// Erstes Wort des Werts, verglichen ohne Groß-/Kleinschreibung.
    /// So zählt `Yesterday` nicht als `Yes`.
    ///
    /// - Parameter value: Wert einer Kopfzeile.
    /// - Returns: `true`, wenn das erste Wort „yes“ ist.
    private static func startsWithYes(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.components(separatedBy: wordBoundaries).first ?? ""
        return firstWord.lowercased() == "yes"
    }

    /// Liest `score=<Zahl>` aus einem `X-Spam-Status`-Wert.
    ///
    /// - Parameter value: Wert der Kopfzeile.
    /// - Returns: Score oder `nil`, wenn keiner lesbar ist.
    private static func score(in value: String) -> Double? {
        guard let scorePattern else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = scorePattern.firstMatch(in: value, range: range),
              let numberRange = Range(match.range(at: 1), in: value) else { return nil }
        return Double(value[numberRange])
    }
}
