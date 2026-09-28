//
//  FolderNodeTests.swift
//  MailwerkTests
//
//  Tests für die eingerückte Anzeigeliste des Ordnerbaums.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FolderNodeTests {

    private func node(_ id: String, _ children: [FolderNode] = []) -> FolderNode {
        FolderNode(id: id, name: id, role: .regular, isSelectable: true, children: children)
    }

    @Test func emptyTreeGivesEmptyList() {
        #expect([FolderNode]().indented().isEmpty)
    }

    @Test func childrenFollowTheirParentWithDeeperIndent() {
        let tree = [
            node("A", [node("A1", [node("A1a")]), node("A2")]),
            node("B")
        ]
        let list = tree.indented()
        #expect(list.map(\.id) == ["A", "A1", "A1a", "A2", "B"])
        #expect(list.map(\.depth) == [0, 1, 2, 1, 0])
    }

    @Test func startDepthIsRespected() {
        #expect([node("A", [node("A1")])].indented(startingAt: 2).map(\.depth) == [2, 3])
    }

    @Test func everyRoleHasASymbol() {
        let roles: [FolderRole] = [.inbox, .drafts, .sent, .archive, .junk, .trash, .flagged, .all, .regular]
        #expect(roles.allSatisfy { !$0.systemImage.isEmpty })
        #expect(Set(roles.map(\.systemImage)).count == roles.count)
    }
}
