//
//  SpamHeaderParserTests.swift
//  Mailwerk
//
//  Created by Kim Sieber on 23.09.26.
//


//
//  SpamHeaderParserTests.swift
//  MailwerkTests
//
//  Tests für das Auslesen der Server-Spam-Header (X-Spam, X-Spam-Status).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SpamHeaderParserTests {

    private func parse(_ lines: [(String, String)]) -> SpamHeaderVerdict {
        SpamHeaderParser.parse(lines.map { SpamHeaderLine(name: $0.0, value: $0.1) })
    }

    // MARK: - Einstufung

    @Test("Ohne Spam-Header kein Spam")
    func noHeaders() {
        #expect(parse([]) == .clean)
    }

    @Test("X-Spam: Yes ohne Status-Zeile")
    func xSpamYesOnly() {
        let verdict = parse([("X-Spam", "Yes")])
        #expect(verdict.isSpam)
        #expect(verdict.score == nil)
    }

    @Test("X-Spam: No ist kein Spam")
    func xSpamNo() {
        #expect(!parse([("X-Spam", "No")]).isSpam)
    }

    @Test("Groß-/Kleinschreibung von Namen und Werten spielt keine Rolle",
          arguments: [("X-Spam", "yes"), ("x-spam", "YES"), ("X-SPAM-STATUS", "yes, score=7.5"),
                      ("x-spam-status", "Yes, score=7.5")])
    func caseInsensitive(name: String, value: String) {
        #expect(parse([(name, value)]).isSpam)
    }

    @Test("Leerzeichen um den Wert werden ignoriert")
    func surroundingWhitespace() {
        #expect(parse([("X-Spam", "  Yes  ")]).isSpam)
    }

    @Test("Status Yes mit Score")
    func statusYes() {
        let verdict = parse([("X-Spam-Status", "Yes, score=10.00")])
        #expect(verdict.isSpam)
        #expect(verdict.score == 10)
    }

    @Test("Status No mit Score")
    func statusNo() {
        let verdict = parse([("X-Spam-Status", "No, score=2.10")])
        #expect(!verdict.isSpam)
        #expect(verdict.score == 2.1)
    }

    @Test("Ähnliche Wörter zählen nicht als Yes")
    func noPrefixMatch() {
        #expect(!parse([("X-Spam-Status", "Yesterday, score=9")]).isSpam)
    }

    // MARK: - Score

    @Test("Negativer Score")
    func negativeScore() {
        #expect(parse([("X-Spam-Status", "No, score=-1.5")]).score == -1.5)
    }

    @Test("Score-Schlüssel in Großbuchstaben, ohne Nachkommastellen")
    func uppercaseScoreKey() {
        #expect(parse([("X-Spam-Status", "Yes, SCORE=8")]).score == 8)
    }

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

    @Test("Gefalteter Header über mehrere Zeilen")
    func foldedHeader() {
        let verdict = parse([("X-Spam-Status", "Yes,\r\n\tscore=6.20\r\n\trequired=5.00")])
        #expect(verdict.isSpam)
        #expect(verdict.score == 6.2)
    }

    @Test("Spam ohne lesbaren Score", arguments: ["Yes", "Yes, score=abc", "Yes, score="])
    func unreadableScore(value: String) {
        let verdict = parse([("X-Spam-Status", value)])
        #expect(verdict.isSpam)
        #expect(verdict.score == nil)
    }

    // MARK: - Nicht ausgewertete Header

    @Test("Der Betreff wird nie ausgewertet")
    func subjectIgnored() {
        #expect(parse([("Subject", "[SPAM] Sie haben gewonnen")]) == .clean)
    }

    @Test("Andere X-Spam-Header werden ignoriert")
    func otherSpamHeadersIgnored() {
        #expect(parse([("X-Spam-Flag", "YES"), ("X-Spam-Level", "*****"),
                       ("X-Spam-Status-Extra", "Yes, score=99")]) == .clean)
    }
}