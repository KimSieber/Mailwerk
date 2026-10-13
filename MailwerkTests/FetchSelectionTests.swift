//
//  FetchSelectionTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Regeln des Abrufs je Postfach (FetchSelection).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für FetchSelection.
struct FetchSelectionTests {

    /// Ausgeschaltete Postfächer fallen weg, die Reihenfolge bleibt.
    @Test("Aktive Postfächer: Reihenfolge bleibt, ausgeschaltete fallen weg")
    func activeIDs() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(FetchSelection.activeIDs([a, b, c], paused: [b]) == [a, c])
        #expect(FetchSelection.activeIDs([a, b], paused: []) == [a, b])
        #expect(FetchSelection.activeIDs([a], paused: [a]).isEmpty)
    }

    /// Voller Abruf nur beim Posteingang eines ausgeschalteten Postfachs.
    @Test("Ordner öffnen: voller Abruf nur beim Posteingang eines ausgeschalteten Postfachs")
    func folderRefresh() {
        #expect(FetchSelection.folderRefresh(isInbox: true, isPaused: true) == .fullAccount)
        #expect(FetchSelection.folderRefresh(isInbox: true, isPaused: false) == .folderOnly)
        #expect(FetchSelection.folderRefresh(isInbox: false, isPaused: true) == .folderOnly)
    }

    /// Speicherform: sortiert, Ungültiges wird beim Lesen übergangen.
    @Test("Speicherform: Hin- und Rückweg, Ungültiges übergangen")
    func storage() {
        let a = UUID(), b = UUID()
        let stored = FetchSelection.storedValue([a, b])
        #expect(stored == stored.sorted())
        #expect(FetchSelection.pausedIDs(from: stored) == [a, b])
        #expect(FetchSelection.pausedIDs(from: ["kein-uuid", a.uuidString]) == [a])
        #expect(FetchSelection.pausedIDs(from: nil).isEmpty)
    }
}
