//
//  MessageSelectionTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Mehrfachauswahl – Regeln bei gemischter Auswahl,
//  betroffene Mails, Sperre beim Verschieben über Postfächer hinweg,
//  Verschieben per Ziehen auf einen Ordner (MessageSelection) und
//  Gruppierung je Ordner (MessageActions.groups).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageSelectionTests {

    /// Testhilfe: Listeneintrag mit Zustand, Postfach und Ordner.
    private func item(
        _ id: String,
        unread: Bool = false,
        flagged: Bool = false,
        account: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        folder: String = "INBOX"
    ) -> MessageListItem {
        MessageListItem(
            id: id, accountID: account, folder: folder, uid: UInt32(id.count), subject: "Betreff",
            from: "a@example.org", recipients: [], date: nil, isUnread: unread, isFlagged: flagged,
            isAnswered: false, isForwarded: false, hasAttachments: false, sizeBytes: 0,
            spamVerdict: nil
        )
    }

    /// Gemischt gekennzeichnet: Die Aktion kennzeichnet, nur die fehlenden.
    @Test func mixedFlagsFlagTheRest() {
        let items = [item("a", flagged: true), item("b"), item("c")]
        let change = MessageSelection.flagChange(for: items)
        #expect(change == .flagged(true))
        #expect(MessageSelection.targets(for: change, in: items).map(\.id) == ["b", "c"])
    }

    /// Alle gekennzeichnet: Die Aktion entfernt die Kennzeichnung bei allen.
    @Test func allFlaggedRemovesFlags() {
        let items = [item("a", flagged: true), item("b", flagged: true)]
        let change = MessageSelection.flagChange(for: items)
        #expect(change == .flagged(false))
        #expect(MessageSelection.targets(for: change, in: items).count == 2)
    }

    /// Mindestens eine ungelesen: Die Aktion markiert als gelesen, nur die ungelesenen.
    @Test func anyUnreadMarksRead() {
        let items = [item("a", unread: true), item("b")]
        let change = MessageSelection.readChange(for: items)
        #expect(change == .read(true))
        #expect(MessageSelection.targets(for: change, in: items).map(\.id) == ["a"])
    }

    /// Alle gelesen: Die Aktion markiert als ungelesen.
    @Test func allReadMarksUnread() {
        #expect(MessageSelection.readChange(for: [item("a"), item("b")]) == .read(false))
    }

    /// Verschieben nur innerhalb eines Postfachs; leere Auswahl nie.
    @Test func moveNeedsSingleAccount() {
        let other = UUID()
        #expect(MessageSelection.canMove([item("a"), item("b")]))
        #expect(!MessageSelection.canMove([item("a"), item("b", account: other)]))
        #expect(!MessageSelection.canMove([]))
    }

    /// Gemeinsamer Ordner nur, wenn alle Mails im selben Ordner liegen.
    @Test func commonFolderOnlyWhenUnique() {
        #expect(MessageSelection.commonFolder([item("a"), item("b")]) == "INBOX")
        #expect(MessageSelection.commonFolder([item("a"), item("b", folder: "Archiv")]) == nil)
    }

    /// Testhilfe: Ordner als Ziel beim Ziehen.
    private func folder(_ path: String, selectable: Bool = true) -> FolderNode {
        FolderNode(id: path, name: path, role: .regular, isSelectable: selectable, children: [])
    }

    /// Ziehen: nur Kennungen aus der Liste, fremde Texte bewirken nichts.
    @Test func dropIgnoresUnknownIDs() {
        let account = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let items = [item("a"), item("b")]
        let targets = MessageSelection.dropTargets(
            ids: ["b", "https://example.org"], in: items, accountID: account, folder: folder("Archiv")
        )
        #expect(targets.map(\.id) == ["b"])
    }

    /// Ziehen: nicht in ein anderes Postfach, nicht in den eigenen Ordner,
    /// nicht in einen reinen Container.
    @Test func dropRespectsMoveRules() {
        let account = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let items = [item("a"), item("b", account: UUID())]
        #expect(MessageSelection.dropTargets(ids: ["b"], in: items, accountID: account, folder: folder("Archiv")).isEmpty)
        #expect(MessageSelection.dropTargets(ids: ["a"], in: items, accountID: account, folder: folder("INBOX")).isEmpty)
        #expect(MessageSelection.dropTargets(
            ids: ["a"], in: items, accountID: account, folder: folder("Ablage", selectable: false)
        ).isEmpty)
    }

    /// Gruppen je Postfach und Ordner, in der Reihenfolge des ersten Auftretens.
    @Test func groupsByAccountAndFolder() {
        let other = UUID()
        let targets = [item("a"), item("b", account: other), item("c"), item("d", folder: "Archiv")]
            .map { MessageActions.Target($0) }
        let groups = MessageActions.groups(targets)
        #expect(groups.map { $0.map(\.id) } == [["a", "c"], ["b"], ["d"]])
    }
}
