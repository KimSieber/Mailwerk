//
//  SpamHeaderParser.swift
//  Mailwerk
//
//  Liest die Spam-Einstufung des Servers (rspamd bei manitu) aus den
//  Headern `X-Spam` und `X-Spam-Status`. Reine Logik ohne IMAP,
//  vollständig per Unit-Test abgedeckt.
//
//  `nonisolated`, weil der Filterlauf außerhalb des Main-Actors arbeitet.
//

import Foundation

/// Eine Header-Zeile, unabhängig vom Typ der Mail-Bibliothek.
nonisolated struct SpamHeaderLine: Equatable {
    let name: String
    let value: String
}

/// Befund der Server-Header.
nonisolated struct SpamHeaderVerdict: Equatable {
    /// Irgendeine Zeile stuft die Mail als Spam ein.
    let isSpam: Bool
    /// Höchster lesbarer Score aller `X-Spam-Status`-Zeilen, sonst nil.
    let score: Double?

    static let clean = SpamHeaderVerdict(isSpam: false, score: nil)
}

nonisolated enum SpamHeaderParser {

    /// Header, die beim Filterlauf per `BODY.PEEK[HEADER.FIELDS (…)]` geladen werden.
    static let fieldNames = ["X-Spam", "X-Spam-Status"]

    private static let spamHeader = "x-spam"
    private static let statusHeader = "x-spam-status"

    /// Zeichen, die das erste Wort eines Header-Werts abschließen.
    private static let wordBoundaries = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)

    /// `score=<Zahl>`, unabhängig von Groß-/Kleinschreibung.
    private static let scorePattern = try? NSRegularExpression(
        pattern: #"score\s*=\s*(-?\d+(?:\.\d+)?)"#,
        options: [.caseInsensitive]
    )

    /// Wertet ausschließlich `X-Spam` und `X-Spam-Status` aus, nie den Betreff.
    ///
    /// - Spam, wenn irgendeine `X-Spam`-Zeile `Yes` lautet oder irgendeine
    ///   `X-Spam-Status`-Zeile mit `Yes` beginnt.
    /// - Score ist der höchste Wert aller `X-Spam-Status`-Zeilen. Ein Absender
    ///   kann eigene Header mitschicken; ein gefälschter niedriger Score darf
    ///   die Einstufung nicht senken.
    static func parse(_ lines: [SpamHeaderLine]) -> SpamHeaderVerdict {
        var isSpam = false
        var highestScore: Double?

        for line in lines {
            let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == spamHeader || name == statusHeader else { continue }

            if startsWithYes(line.value) { isSpam = true }

            if name == statusHeader, let score = score(in: line.value) {
                highestScore = max(highestScore ?? score, score)
            }
        }

        return SpamHeaderVerdict(isSpam: isSpam, score: highestScore)
    }

    /// Erstes Wort des Werts, verglichen ohne Groß-/Kleinschreibung.
    /// So zählt `Yesterday` nicht als `Yes`.
    private static func startsWithYes(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.components(separatedBy: wordBoundaries).first ?? ""
        return firstWord.lowercased() == "yes"
    }

    private static func score(in value: String) -> Double? {
        guard let scorePattern else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = scorePattern.firstMatch(in: value, range: range),
              let numberRange = Range(match.range(at: 1), in: value) else { return nil }
        return Double(value[numberRange])
    }
}
