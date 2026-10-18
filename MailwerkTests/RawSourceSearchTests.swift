//
//  RawSourceSearchTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Suche in der Originalquelle (RawSourceSearch) –
//  Fundstellen ohne Rücksicht auf Groß- und Kleinschreibung, Sätze mit
//  Leerzeichen, keine Überlappung und „Weiter“ mit Neubeginn am Anfang.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct RawSourceSearchTests {

    /// Groß- und Kleinschreibung spielt keine Rolle.
    @Test func matchesIgnoreCase() {
        let text = "Received: from mx\nreceived again\nRECEIVED"
        let found = RawSourceSearch.matches(of: "received", in: text)
        #expect(found.count == 3)
        #expect(found.first == NSRange(location: 0, length: 8))
    }

    /// Ein Satz mit Leerzeichen wird als Ganzes gesucht.
    @Test func matchesWholePhrase() {
        let text = "Subject: Hallo Welt\nHallo  Welt"
        let found = RawSourceSearch.matches(of: "hallo welt", in: text)
        #expect(found == [NSRange(location: 9, length: 10)])
    }

    /// Treffer überlappen nicht.
    @Test func matchesDoNotOverlap() {
        #expect(RawSourceSearch.matches(of: "aa", in: "aaaa").count == 2)
    }

    /// Leerer Begriff und fehlender Text ergeben keine Treffer.
    @Test func emptyQueryOrNoHitGivesNothing() {
        #expect(RawSourceSearch.matches(of: "", in: "Text").isEmpty)
        #expect(RawSourceSearch.matches(of: "xyz", in: "Text").isEmpty)
    }

    /// Fundstellen stimmen auch hinter Umlauten und Emoji (UTF-16-Bereiche).
    @Test func rangesFitNSString() {
        let text = "Grüße 👋 an Müller"
        let found = RawSourceSearch.matches(of: "müller", in: text)
        #expect(found.count == 1)
        #expect((text as NSString).substring(with: found[0]) == "Müller")
    }

    /// „Weiter“: erster Treffer, dann der nächste, nach dem letzten wieder vorne.
    @Test func nextIndexWrapsAround() {
        #expect(RawSourceSearch.nextIndex(after: nil, count: 3) == 0)
        #expect(RawSourceSearch.nextIndex(after: 0, count: 3) == 1)
        #expect(RawSourceSearch.nextIndex(after: 2, count: 3) == 0)
        #expect(RawSourceSearch.nextIndex(after: nil, count: 0) == nil)
    }
}
