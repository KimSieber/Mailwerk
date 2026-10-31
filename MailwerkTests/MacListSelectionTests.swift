//
//  MacListSelectionTests.swift
//  MailwerkTests
//
//  Zweck: Tests der Mehrfachauswahl in der Mailliste des Mac
//  (MacListSelection).
//

import Foundation
import Testing
@testable import Mailwerk

struct MacListSelectionTests {

    /// Mails der Liste.
    private let ids = ["a", "b", "c"]

    /// Leere Auswahl schließt die Mailansicht.
    @Test func emptySelectionCloses() {
        #expect(MacListSelection.outcome(for: [], visibleIDs: ids) == .empty)
    }

    /// Eine Mail wird geöffnet.
    @Test func singleMailOpens() {
        #expect(MacListSelection.outcome(for: ["b"], visibleIDs: ids) == .open("b"))
    }

    /// Mehrere Mails ergeben die Mehrfachauswahl.
    @Test func severalMailsAreMultiple() {
        #expect(MacListSelection.outcome(for: ["a", "c"], visibleIDs: ids) == .multiple(["a", "c"]))
    }

    /// Zeilen ohne Mail (Serversuche) zählen nicht mit.
    @Test func foreignRowsAreDropped() {
        #expect(MacListSelection.outcome(for: ["a", "treffer"], visibleIDs: ids) == .open("a"))
    }

    /// Nur Zeilen ohne Mail: nichts ändern.
    @Test func onlyForeignRowsAreIgnored() {
        #expect(MacListSelection.outcome(for: ["treffer"], visibleIDs: ids) == .ignore)
    }

    /// Verschwundene Mails fallen aus der Auswahl.
    @Test func pruneDropsVanishedMails() {
        #expect(MacListSelection.pruned(["a", "b", "x"], visibleIDs: ["b", "c"]) == ["b"])
    }
}
