//
//  MessageSteppingTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Weiterschalten der geöffneten Mail im
//  Spaltenlayout – Nachbarn in der Liste und die Mail, die nach Löschen
//  oder Verschieben nachrückt (MessageStepping).
//

import Foundation
import Testing
@testable import Mailwerk

struct MessageSteppingTests {

    /// Liste in Anzeigereihenfolge.
    private let ids = ["a", "b", "c"]

    /// Nächste und vorige Mail sind die Zeilen darunter bzw. darüber.
    @Test func neighborsFollowListOrder() {
        #expect(MessageStepping.neighbor(of: "b", in: ids, direction: .next) == "c")
        #expect(MessageStepping.neighbor(of: "b", in: ids, direction: .previous) == "a")
    }

    /// Am Listenrand gibt es in dieser Richtung keinen Nachbarn.
    @Test func noNeighborBeyondEdges() {
        #expect(MessageStepping.neighbor(of: "c", in: ids, direction: .next) == nil)
        #expect(MessageStepping.neighbor(of: "a", in: ids, direction: .previous) == nil)
    }

    /// Ohne geöffnete Mail beginnt das Weiterschalten oben – in beide Richtungen.
    @Test func startsAtFirstWithoutCurrent() {
        #expect(MessageStepping.neighbor(of: nil, in: ids, direction: .next) == "a")
        #expect(MessageStepping.neighbor(of: nil, in: ids, direction: .previous) == "a")
        #expect(MessageStepping.neighbor(of: "fehlt", in: ids, direction: .next) == "a")
    }

    /// Leere Liste: kein Ziel.
    @Test func emptyListHasNoNeighbor() {
        #expect(MessageStepping.neighbor(of: nil, in: [], direction: .next) == nil)
    }

    /// Noch vorhandene Mail bleibt geöffnet.
    @Test func keepsMessageThatRemains() {
        #expect(MessageStepping.replacement(for: "b", oldIDs: ids, newIDs: ["a", "b"]) == "b")
    }

    /// Gelöschte Mail: die darunter rückt nach.
    @Test func followingMessageReplacesRemoved() {
        #expect(MessageStepping.replacement(for: "b", oldIDs: ids, newIDs: ["a", "c"]) == "c")
    }

    /// Letzte Mail gelöscht: die darüber rückt nach.
    @Test func previousMessageReplacesLastRemoved() {
        #expect(MessageStepping.replacement(for: "c", oldIDs: ids, newIDs: ["a", "b"]) == "b")
    }

    /// Mehrere darunter ebenfalls entfernt: die nächste noch vorhandene.
    @Test func skipsOtherRemovedMessages() {
        let old = ["a", "b", "c", "d"]
        #expect(MessageStepping.replacement(for: "b", oldIDs: old, newIDs: ["a", "d"]) == "d")
    }

    /// Liste leer oder nichts geöffnet: keine Mail.
    @Test func noReplacementWhenNothingLeft() {
        #expect(MessageStepping.replacement(for: "b", oldIDs: ids, newIDs: []) == nil)
        #expect(MessageStepping.replacement(for: nil, oldIDs: ids, newIDs: ids) == nil)
    }
}
