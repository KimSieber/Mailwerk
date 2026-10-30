//
//  SpamHeaderParserTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Auslesen der Server-Spam-Header (X-Spam,
//  X-Spam-Status).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für SpamHeaderParser.
@MainActor
struct SpamHeaderParserTests {

    /// Testhilfe: Auswertung von Name-Wert-Paaren.
    private func parse(_ lines: [(String, String)]) -> SpamHeaderVerdict {
        SpamHeaderParser.parse(lines.map { SpamHeaderLine(name: $0.0, value: $0.1) })
    }

    // MARK: - Einstufung

    /// Ohne Spam-Header kein Spam.
    @Test("Ohne Spam-Header kein Spam")
    func noHeaders() {
        #expect(parse([]) == .clean)
    }

    /// X-Spam: Yes ohne Status-Zeile.
    @Test("X-Spam: Yes ohne Status-Zeile")
    func xSpamYesOnly() {
        let verdict = parse([("X-Spam", "Yes")])
        #expect(verdict.isSpam)
        #expect(verdict.score == nil)
    }

    /// X-Spam: No ist kein Spam.
    @Test("X-Spam: No ist kein Spam")
    func xSpamNo() {
        #expect(!parse([("X-Spam", "No")]).isSpam)
    }

    /// Groß-/Kleinschreibung von Namen und Werten spielt keine Rolle.
    @Test("Groß-/Kleinschreibung von Namen und Werten spielt keine Rolle",
          arguments: [("X-Spam", "yes"), ("x-spam", "YES"), ("X-SPAM-STATUS", "yes, score=7.5"),
                      ("x-spam-status", "Yes, score=7.5")])
    func caseInsensitive(name: String, value: String) {
        #expect(parse([(name, value)]).isSpam)
    }

    /// Leerzeichen um den Wert werden ignoriert.
    @Test("Leerzeichen um den Wert werden ignoriert")
    func surroundingWhitespace() {
        #expect(parse([("X-Spam", "  Yes  ")]).isSpam)
    }

    /// Status Yes mit Score.
    @Test("Status Yes mit Score")
    func statusYes() {
        let verdict = parse([("X-Spam-Status", "Yes, score=10.00")])
        #expect(verdict.isSpam)
        #expect(verdict.score == 10)
    }

    /// Status No mit Score.
    @Test("Status No mit Score")
    func statusNo() {
        let verdict = parse([("X-Spam-Status", "No, score=2.10")])
        #expect(!verdict.isSpam)
        #expect(verdict.score == 2.1)
    }

    /// Ähnliche Wörter zählen nicht als Yes.
    @Test("Ähnliche Wörter zählen nicht als Yes")
    func noPrefixMatch() {
        #expect(!parse([("X-Spam-Status", "Yesterday, score=9")]).isSpam)
    }

    // MARK: - Score

    /// Negativer Score.
    @Test("Negativer Score")
    func negativeScore() {
        #expect(parse([("X-Spam-Status", "No, score=-1.5")]).score == -1.5)
    }

    /// Score-Schlüssel in Großbuchstaben, ohne Nachkommastellen.
    @Test("Score-Schlüssel in Großbuchstaben, ohne Nachkommastellen")
    func uppercaseScoreKey() {
        #expect(parse([("X-Spam-Status", "Yes, SCORE=8")]).score == 8)
    }

    /// Mehrere Status-Zeilen: der höchste Score gewinnt, egal in welcher Reihenfolge.
    @Test("Mehrere Status-Zeilen: der höchste Score gewinnt, egal in welcher Reihenfolge",
          arguments: [
            [("X-Spam-Status", "Yes, score=12.5"), ("X-Spam-Status", "Yes, score=0.1")],
            [("X-Spam-Status", "Yes, score=0.1"), ("X-Spam-Status", "Yes, score=12.5")]
          ])
    func highestScoreWins(lines: [(String, String)]) {
        let verdict = parse(lines)
        #expect(verdict.isSpam)
        #expect(verdict.score == 12.5)
    }

    /// Eine gefälschte No-Zeile hebt die Spam-Einstufung nicht auf.
    @Test("Eine gefälschte No-Zeile hebt die Spam-Einstufung nicht auf")
    func forgedNoLine() {
        let verdict = parse([
            ("X-Spam-Status", "No, score=-100"),
            ("X-Spam", "Yes"),
            ("X-Spam-Status", "Yes, score=5.34")
        ])
        #expect(verdict.isSpam)
        #expect(verdict.score == 5.34)
    }

    /// Gefalteter Header über mehrere Zeilen.
    @Test("Gefalteter Header über mehrere Zeilen")
    func foldedHeader() {
        let verdict = parse([("X-Spam-Status", "Yes,\r\n\tscore=6.20\r\n\trequired=5.00")])
        #expect(verdict.isSpam)
        #expect(verdict.score == 6.2)
    }

    /// Spam ohne lesbaren Score.
    @Test("Spam ohne lesbaren Score", arguments: ["Yes", "Yes, score=abc", "Yes, score="])
    func unreadableScore(value: String) {
        let verdict = parse([("X-Spam-Status", value)])
        #expect(verdict.isSpam)
        #expect(verdict.score == nil)
    }

    // MARK: - Nicht ausgewertete Header

    /// Der Betreff wird nie ausgewertet.
    @Test("Der Betreff wird nie ausgewertet")
    func subjectIgnored() {
        #expect(parse([("Subject", "[SPAM] Sie haben gewonnen")]) == .clean)
    }

    /// Andere X-Spam-Header werden ignoriert.
    @Test("Andere X-Spam-Header werden ignoriert")
    func otherSpamHeadersIgnored() {
        #expect(parse([("X-Spam-Level", "*****"),
                       ("X-Spam-Status-Extra", "Yes, score=99")]) == .clean)
    }

    // MARK: - X-Spam-Flag

    /// X-Spam-Flag zählt wie X-Spam, in jeder Schreibweise und mit Leerzeichen.
    @Test("X-Spam-Flag: YES ist Spam", arguments: ["YES", "Yes", "yes", " YES", "  yes  "])
    func spamFlagYes(value: String) {
        let verdict = parse([("X-Spam-Flag", value)])
        #expect(verdict.isSpam)
        #expect(verdict.score == nil)
    }

    /// X-Spam-Flag: NO ist kein Spam.
    @Test("X-Spam-Flag: NO ist kein Spam", arguments: ["NO", "No", "no", "  NO "])
    func spamFlagNo(value: String) {
        #expect(!parse([("X-Spam-Flag", value)]).isSpam)
    }

    /// Der Name X-Spam-Flag wird ohne Groß-/Kleinschreibung erkannt.
    @Test("Der Name X-Spam-Flag wird ohne Groß-/Kleinschreibung erkannt")
    func spamFlagNameCaseInsensitive() {
        #expect(parse([("x-spam-flag", "YES")]).isSpam)
        #expect(parse([("X-SPAM-FLAG", "yes")]).isSpam)
    }

    /// Leerzeichen um score= werden ignoriert.
    @Test("Leerzeichen um score= werden ignoriert")
    func scoreWithSpaces() {
        #expect(parse([("X-Spam-Status", "Yes,  score = 7.25")]).score == 7.25)
    }

    /// X-Spam-Flag wird beim Abruf mitgeladen.
    @Test("X-Spam-Flag wird beim Abruf mitgeladen")
    func fieldNamesContainSpamFlag() {
        #expect(SpamHeaderParser.fieldNames.contains("X-Spam-Flag"))
    }
}

/// Testhilfe: Befund ohne jede Spam-Kopfzeile (in mehreren Testdateien genutzt).
extension SpamHeaderVerdict {
    nonisolated static let clean = SpamHeaderVerdict(isSpam: false, score: nil)
}
