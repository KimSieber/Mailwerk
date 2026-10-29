//
//  FolderNodeTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die eingerückte Anzeigeliste des Ordnerbaums, die
//  Symbole der Ordnerrollen und die Suche eines Ordners über seinen Pfad.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für FolderNode.
@MainActor
struct FolderNodeTests {

    /// Testhilfe: Knoten mit Unterknoten.
    private func node(_ id: String, _ children: [FolderNode] = []) -> FolderNode {
        FolderNode(id: id, name: id, role: .regular, isSelectable: true, children: children)
    }

    /// Ein leerer Baum ergibt eine leere Liste.
    @Test func emptyTreeGivesEmptyList() {
        #expect([FolderNode]().indented().isEmpty)
    }

    /// Unterordner folgen ihrem Ordner mit tieferer Einrückung.
    @Test func childrenFollowTheirParentWithDeeperIndent() {
        let tree = [
            node("A", [node("A1", [node("A1a")]), node("A2")]),
            node("B")
        ]
        let list = tree.indented()
        #expect(list.map(\.id) == ["A", "A1", "A1a", "A2", "B"])
        #expect(list.map(\.depth) == [0, 1, 2, 1, 0])
    }

    /// Die Starttiefe wird berücksichtigt.
    @Test func startDepthIsRespected() {
        #expect([node("A", [node("A1")])].indented(startingAt: 2).map(\.depth) == [2, 3])
    }

    /// Jede Ordnerrolle hat ein Symbol.
    @Test func everyRoleHasASymbol() {
        let roles: [FolderRole] = [.inbox, .drafts, .sent, .archive, .junk, .trash, .flagged, .all, .regular]
        #expect(roles.allSatisfy { !$0.systemImage.isEmpty })
        #expect(Set(roles.map(\.systemImage)).count == roles.count)
    }

    // MARK: - Suche über den Pfad

    /// Ein Ordner wird auch in tieferen Ebenen über seinen Pfad gefunden.
    @Test func nodeIsFoundByPathAtAnyDepth() {
        let tree = [node("INBOX", [node("INBOX.Sent", [node("INBOX.Sent.2025")])]), node("B")]
        #expect(tree.node(withPath: "INBOX.Sent.2025")?.id == "INBOX.Sent.2025")
        #expect(tree.node(withPath: "B")?.id == "B")
    }

    /// Unbekannte Pfade und andere Schreibweise ergeben keinen Treffer.
    @Test func unknownPathGivesNoNode() {
        let tree = [node("INBOX", [node("INBOX.Sent")])]
        #expect(tree.node(withPath: "INBOX.Archiv") == nil)
        #expect(tree.node(withPath: "inbox.sent") == nil)
    }
}
