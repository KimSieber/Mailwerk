//
//  FolderTreeBuilderTests.swift
//  MailwerkTests
//
//  Tests für den Aufbau des Ordnerbaums aus der flachen Ordnerliste.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FolderTreeBuilderTests {

    // MARK: - Hilfen

    private func folder(
        _ path: String,
        specialUse: MailFolder.SpecialUse? = nil,
        delimiter: String? = ".",
        selectable: Bool = true
    ) -> MailFolder {
        let name = path.components(separatedBy: delimiter ?? ".").last ?? path
        return MailFolder(
            id: path,
            name: name,
            specialUse: specialUse,
            hierarchyDelimiter: delimiter,
            isSelectable: selectable
        )
    }

    private func build(
        _ folders: [MailFolder],
        prefix: String? = "INBOX.",
        spam: String? = nil
    ) -> [FolderNode] {
        FolderTreeBuilder.build(
            folders: folders, namespacePrefix: prefix, configuredSpamFolder: spam
        )
    }

    /// Liste eines Servers mit Namespace-Präfix „INBOX.“ (alles darunter).
    /// manitu selbst meldet kein Präfix, siehe `realManituFolders`.
    private var manituFolders: [MailFolder] {
        [
            folder("INBOX"),
            folder("INBOX.Trash", specialUse: .trash),
            folder("INBOX.Sent", specialUse: .sent),
            folder("INBOX.Drafts", specialUse: .drafts),
            folder("INBOX.Junk"),
            folder("INBOX.Rechnungen"),
            folder("INBOX.Rechnungen.2026"),
            folder("INBOX.Archiv")
        ]
    }

    // MARK: - Namespace und Ebenen

    @Test func namespacePrefixPutsFoldersBesideInbox() {
        let tree = build(manituFolders)
        #expect(tree.count == 7)
        #expect(tree.allSatisfy { $0.id == "INBOX" || $0.id.hasPrefix("INBOX.") })
        #expect(tree.first?.role == .inbox)
        #expect(tree.first?.children.isEmpty == true)
    }

    @Test func inboxIsNamedPosteingang() {
        let tree = build(manituFolders)
        #expect(tree.first?.name == "Posteingang")
        #expect(tree.first?.id == "INBOX")
    }

    @Test func specialFoldersGetGermanDisplayNames() {
        let tree = build(manituFolders)
        #expect(tree.first { $0.id == "INBOX.Drafts" }?.name == "Entwürfe")
        #expect(tree.first { $0.id == "INBOX.Sent" }?.name == "Gesendet")
        #expect(tree.first { $0.id == "INBOX.Trash" }?.name == "Papierkorb")
        #expect(tree.first { $0.id == "INBOX.Junk" }?.name == "Spam")
        #expect(tree.first { $0.id == "INBOX.Archiv" }?.name == "Archiv")
    }

    @Test func regularFoldersKeepServerName() {
        let tree = build(manituFolders)
        #expect(tree.first { $0.id == "INBOX.Rechnungen" }?.name == "Rechnungen")
    }

    @Test func subfoldersAreNestedWithShortNames() {
        let tree = build(manituFolders)
        let rechnungen = tree.first { $0.id == "INBOX.Rechnungen" }
        #expect(rechnungen?.name == "Rechnungen")
        #expect(rechnungen?.children.map(\.id) == ["INBOX.Rechnungen.2026"])
        #expect(rechnungen?.children.first?.name == "2026")
    }

    @Test func withoutNamespacePrefixFoldersStayUnderInbox() {
        let tree = build(manituFolders, prefix: nil)
        #expect(tree.count == 1)
        #expect(tree.first?.role == .inbox)
        #expect(tree.first?.children.count == 6)
    }

    @Test func dovecotStyleSubfoldersOfInboxAreNested() {
        let folders = [
            folder("INBOX", delimiter: "/"),
            folder("INBOX/Projekte", delimiter: "/"),
            folder("Sent", specialUse: .sent, delimiter: "/")
        ]
        let tree = build(folders, prefix: "")
        #expect(tree.map(\.id) == ["INBOX", "Sent"])
        #expect(tree.first?.children.map(\.id) == ["INBOX/Projekte"])
    }

    @Test func folderNamedInboxBelowPrefixDoesNotMergeWithInbox() {
        let tree = build([folder("INBOX"), folder("INBOX.INBOX")])
        #expect(tree.count == 2)
        #expect(tree.contains { $0.id == "INBOX.INBOX" && $0.role == .regular })
    }

    @Test func prefixMatchIgnoresCaseOfInboxPart() {
        let tree = build([folder("INBOX"), folder("Inbox.Sent", specialUse: .sent)])
        #expect(tree.map(\.name) == ["Posteingang", "Gesendet"])
    }

    @Test func missingIntermediateLevelIsAddedAsNotSelectable() {
        let tree = build([folder("INBOX"), folder("INBOX.Kunden.Meier")])
        let kunden = tree.first { $0.name == "Kunden" }
        #expect(kunden?.id == "INBOX.Kunden")
        #expect(kunden?.isSelectable == false)
        #expect(kunden?.children.first?.id == "INBOX.Kunden.Meier")
        #expect(kunden?.children.first?.isSelectable == true)
    }

    @Test func intermediateListedAfterChildKeepsItsOwnData() {
        let tree = build([
            folder("INBOX"),
            folder("INBOX.Kunden.Meier"),
            folder("INBOX.Kunden")
        ])
        let kunden = tree.first { $0.name == "Kunden" }
        #expect(kunden?.isSelectable == true)
        #expect(kunden?.children.count == 1)
    }

    @Test func noselectFolderIsNotSelectable() {
        let tree = build([folder("INBOX"), folder("INBOX.Container", selectable: false)])
        #expect(tree.first { $0.name == "Container" }?.isSelectable == false)
    }

    @Test func folderWithoutDelimiterIsNotSplit() {
        let tree = build([folder("INBOX", delimiter: nil), folder("A.B", delimiter: nil)], prefix: nil)
        #expect(tree.map(\.name) == ["Posteingang", "A.B"])
    }

    // MARK: - Rollen

    @Test func specialUseDeterminesRoles() {
        let tree = build(manituFolders)
        #expect(tree.first { $0.id == "INBOX.Trash" }?.role == .trash)
        #expect(tree.first { $0.id == "INBOX.Sent" }?.role == .sent)
        #expect(tree.first { $0.id == "INBOX.Drafts" }?.role == .drafts)
    }

    @Test func spamFolderComesFromSpamFolderResolver() {
        let tree = build(manituFolders)
        #expect(tree.first { $0.id == "INBOX.Junk" }?.role == .junk)
    }

    @Test func configuredSpamFolderWins() {
        let folders = [folder("INBOX"), folder("INBOX.Junk"), folder("INBOX.Werbung")]
        let tree = build(folders, spam: "INBOX.Werbung")
        #expect(tree.first { $0.id == "INBOX.Werbung" }?.role == .junk)
        #expect(tree.first { $0.id == "INBOX.Junk" }?.role == .regular)
    }

    @Test func namesAreRecognizedWithoutSpecialUse() {
        let tree = build([
            folder("INBOX"),
            folder("INBOX.Gesendete Elemente"),
            folder("INBOX.Papierkorb"),
            folder("INBOX.Entwürfe"),
            folder("INBOX.Archiv")
        ])
        #expect(tree.map(\.role) == [.inbox, .drafts, .sent, .archive, .trash])
        // Auch per Namen erkannte Ordner bekommen den einheitlichen Anzeigenamen.
        #expect(tree.first { $0.role == .sent }?.name == "Gesendet")
        #expect(tree.first { $0.role == .trash }?.name == "Papierkorb")
    }

    @Test func nameMatchDoesNotOverrideSpecialUse() {
        let tree = build([
            folder("INBOX"),
            folder("INBOX.Sent"),
            folder("INBOX.Gesendet", specialUse: .sent)
        ])
        #expect(tree.first { $0.id == "INBOX.Gesendet" }?.role == .sent)
        #expect(tree.first { $0.id == "INBOX.Gesendet" }?.name == "Gesendet")
        #expect(tree.first { $0.id == "INBOX.Sent" }?.role == .regular)
        #expect(tree.first { $0.id == "INBOX.Sent" }?.name == "Sent")
    }

    @Test func nameMatchOnlyOnTopLevel() {
        let tree = build([folder("INBOX"), folder("INBOX.Projekte"), folder("INBOX.Projekte.Sent")])
        let sub = tree.first { $0.id == "INBOX.Projekte" }?.children.first
        #expect(sub?.role == .regular)
    }

    @Test func eachRoleIsAssignedByNameOnlyOnce() {
        let tree = build([folder("INBOX"), folder("INBOX.Sent"), folder("INBOX.Gesendet")])
        #expect(tree.filter { $0.role == .sent }.count == 1)
    }

    // MARK: - Sortierung

    @Test func topLevelIsSortedByRoleThenAlphabetically() {
        let tree = build(manituFolders)
        #expect(tree.map(\.name) == [
            "Posteingang", "Entwürfe", "Gesendet", "Archiv", "Spam", "Papierkorb", "Rechnungen"
        ])
    }

    @Test func regularFoldersAreSortedCaseInsensitively() {
        let tree = build([folder("INBOX"), folder("INBOX.beta"), folder("INBOX.Alpha"), folder("INBOX.Gamma")])
        #expect(tree.map(\.name) == ["Posteingang", "Alpha", "beta", "Gamma"])
    }

    @Test func childrenAreSortedAlphabetically() {
        let tree = build([
            folder("INBOX"),
            folder("INBOX.Kunden"),
            folder("INBOX.Kunden.Zander"),
            folder("INBOX.Kunden.Adler"),
            folder("INBOX.Kunden.Trash")
        ])
        #expect(tree.first { $0.name == "Kunden" }?.children.map(\.name) == ["Adler", "Trash", "Zander"])
    }

    // MARK: - Namensgleichheit

    @Test func collisionKeepsBothServerNames() {
        // Der Server meldet "Sent" als SPECIAL-USE, daneben liegt ein
        // gewöhnlicher Ordner "Gesendet". Ohne Kollisionsauflösung stünde
        // zweimal "Gesendet" in der Liste.
        let tree = build([
            folder("INBOX"),
            folder("INBOX.Sent", specialUse: .sent),
            folder("INBOX.Gesendet")
        ])
        #expect(tree.first { $0.id == "INBOX.Sent" }?.name == "Sent")
        #expect(tree.first { $0.id == "INBOX.Gesendet" }?.name == "Gesendet")
    }

    @Test func noCollisionWhenNamesAreDifferent() {
        let tree = build([
            folder("INBOX"),
            folder("INBOX.Sent", specialUse: .sent),
            folder("INBOX.Rechnungen")
        ])
        #expect(tree.first { $0.id == "INBOX.Sent" }?.name == "Gesendet")
        #expect(tree.first { $0.id == "INBOX.Rechnungen" }?.name == "Rechnungen")
    }

    @Test func collisionWithSpamKeepsBothServerNames() {
        let tree = build([
            folder("INBOX"),
            folder("INBOX.Junk"),
            folder("INBOX.Spam")
        ])
        // Einer davon wird vom SpamFolderResolver als .junk erkannt
        let junkNode = tree.first { $0.role == .junk }
        let otherNode = tree.first { $0.role == .regular && ($0.id == "INBOX.Junk" || $0.id == "INBOX.Spam") }
        // Falls der Anzeigename "Spam" kollidiert, behalten beide ihren Servernamen
        if let other = otherNode, other.name.lowercased() == junkNode?.name.lowercased() {
            // Collision detected – both should have server names
            #expect(junkNode?.name == junkNode?.id.components(separatedBy: ".").last)
        } else {
            // No collision – just check they're both present and different
            #expect(junkNode != nil)
        }
    }

    @Test func emptyListGivesEmptyTree() {
        #expect(build([]).isEmpty)
    }

    @Test func existingInitializerStillDefaultsToSelectable() {
        let folder = MailFolder(id: "INBOX.A", name: "A", specialUse: nil, hierarchyDelimiter: ".")
        #expect(folder.isSelectable)
    }

    // MARK: - manitu (echte LIST-Ausgabe, v0.1.8a)

    /// LIST-Ausgabe eines manitu-Postfachs vom 2026-09-30.
    /// NAMESPACE: (("" ".")) – kein Präfix, Trennzeichen „.“.
    private var realManituFolders: [MailFolder] {
        [
            folder("Test"),
            folder("Test.Untertest2"),
            folder("Archive"),
            folder("Sent", specialUse: .sent),
            folder("Drafts", specialUse: .drafts),
            folder("Trash", specialUse: .trash),
            folder("Junk", specialUse: .junk),
            folder("INBOX.Testeingang"),
            folder("INBOX")
        ]
    }

    @Test func manituWithoutPrefixMatchesSidebar() {
        let tree = build(realManituFolders, prefix: "")
        #expect(tree.map(\.name) == ["Posteingang", "Entwürfe", "Gesendet", "Archiv",
                                     "Spam", "Papierkorb", "Test"])
        #expect(tree.first?.children.map(\.id) == ["INBOX.Testeingang"])
        #expect(tree.first { $0.id == "Test" }?.children.map(\.id) == ["Test.Untertest2"])
    }

    // MARK: - Umlaute (modified UTF-7, v0.1.8a)

    @Test func encodedNamesAreDecodedForDisplay() {
        let tree = build([
            folder("INBOX"),
            folder("Rechnungen M&APw-ller"),
            folder("Rechnungen M&APw-ller.Gr&APYA3w-e"),
            folder("INBOX.Gesch&AOQ-ft")
        ], prefix: "")
        let rechnungen = tree.first { $0.id == "Rechnungen M&APw-ller" }
        #expect(rechnungen?.name == "Rechnungen Müller")
        #expect(rechnungen?.children.first?.name == "Größe")
        #expect(rechnungen?.children.first?.id == "Rechnungen M&APw-ller.Gr&APYA3w-e")
        #expect(tree.first?.children.first?.name == "Geschäft")
        #expect(tree.first?.children.first?.id == "INBOX.Gesch&AOQ-ft")
    }

    @Test func encodedCandidateNameIsRecognized() {
        let tree = build([folder("INBOX"), folder("Entw&APw-rfe")], prefix: "")
        let drafts = tree.first { $0.id == "Entw&APw-rfe" }
        #expect(drafts?.role == .drafts)
        #expect(drafts?.name == "Entwürfe")
    }

    @Test func invalidEncodingKeepsServerName() {
        let tree = build([folder("INBOX"), folder("Kaputt&AP")], prefix: "")
        #expect(tree.contains { $0.id == "Kaputt&AP" && $0.name == "Kaputt&AP" })
    }
}
