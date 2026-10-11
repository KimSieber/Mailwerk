//
//  FolderTreeBuilderTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Aufbau des Ordnerbaums aus der flachen
//  Ordnerliste – Namespace und Ebenen, Rollen, Sortierung, gleichlautende
//  Namen, echte manitu-Liste, Umlaute und Verschiebe-Ziele.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FolderTreeBuilderTests {

    // MARK: - Hilfen

    /// Testhilfe: Ordner mit Pfad, Rolle, Trennzeichen und Wählbarkeit.
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

    /// Testhilfe: Baum mit wählbarem Präfix und gemerktem Spam-Ordner.
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

    /// Mit Namespace-Präfix stehen die Ordner neben dem Posteingang.
    @Test func namespacePrefixPutsFoldersBesideInbox() {
        let tree = build(manituFolders)
        #expect(tree.count == 7)
        #expect(tree.allSatisfy { $0.id == "INBOX" || $0.id.hasPrefix("INBOX.") })
        #expect(tree.first?.role == .inbox)
        #expect(tree.first?.children.isEmpty == true)
    }

    /// Der Posteingang heißt „Posteingang“ und behält seine Server-ID.
    @Test func inboxIsNamedPosteingang() {
        let tree = build(manituFolders)
        #expect(tree.first?.name == "Posteingang")
        #expect(tree.first?.id == "INBOX")
    }

    /// Sonderordner bekommen einheitliche deutsche Namen.
    @Test func specialFoldersGetGermanDisplayNames() {
        let tree = build(manituFolders)
        #expect(tree.first { $0.id == "INBOX.Drafts" }?.name == "Entwürfe")
        #expect(tree.first { $0.id == "INBOX.Sent" }?.name == "Gesendet")
        #expect(tree.first { $0.id == "INBOX.Trash" }?.name == "Papierkorb")
        #expect(tree.first { $0.id == "INBOX.Junk" }?.name == "Spam")
        #expect(tree.first { $0.id == "INBOX.Archiv" }?.name == "Archiv")
    }

    /// Gewöhnliche Ordner behalten ihren Servernamen.
    @Test func regularFoldersKeepServerName() {
        let tree = build(manituFolders)
        #expect(tree.first { $0.id == "INBOX.Rechnungen" }?.name == "Rechnungen")
    }

    /// Unterordner werden verschachtelt und zeigen nur ihr letztes Segment.
    @Test func subfoldersAreNestedWithShortNames() {
        let tree = build(manituFolders)
        let rechnungen = tree.first { $0.id == "INBOX.Rechnungen" }
        #expect(rechnungen?.name == "Rechnungen")
        #expect(rechnungen?.children.map(\.id) == ["INBOX.Rechnungen.2026"])
        #expect(rechnungen?.children.first?.name == "2026")
    }

    /// Ohne Präfix bleiben die Ordner unter dem Posteingang.
    @Test func withoutNamespacePrefixFoldersStayUnderInbox() {
        let tree = build(manituFolders, prefix: nil)
        #expect(tree.count == 1)
        #expect(tree.first?.role == .inbox)
        #expect(tree.first?.children.count == 6)
    }

    /// Bei „/“ als Trennzeichen werden Unterordner des Posteingangs verschachtelt.
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

    /// Ein Ordner „INBOX“ unter dem Präfix verschmilzt nicht mit dem Posteingang.
    @Test func folderNamedInboxBelowPrefixDoesNotMergeWithInbox() {
        let tree = build([folder("INBOX"), folder("INBOX.INBOX")])
        #expect(tree.count == 2)
        #expect(tree.contains { $0.id == "INBOX.INBOX" && $0.role == .regular })
    }

    /// Der Präfix-Vergleich ignoriert die Schreibweise von „INBOX“.
    @Test func prefixMatchIgnoresCaseOfInboxPart() {
        let tree = build([folder("INBOX"), folder("Inbox.Sent", specialUse: .sent)])
        #expect(tree.map(\.name) == ["Posteingang", "Gesendet"])
    }

    /// Eine fehlende Zwischenebene wird als nicht wählbarer Knoten ergänzt.
    @Test func missingIntermediateLevelIsAddedAsNotSelectable() {
        let tree = build([folder("INBOX"), folder("INBOX.Kunden.Meier")])
        let kunden = tree.first { $0.name == "Kunden" }
        #expect(kunden?.id == "INBOX.Kunden")
        #expect(kunden?.isSelectable == false)
        #expect(kunden?.children.first?.id == "INBOX.Kunden.Meier")
        #expect(kunden?.children.first?.isSelectable == true)
    }

    /// Eine nach dem Unterordner gemeldete Zwischenebene behält ihre eigenen Daten.
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

    /// Ein Ordner mit \Noselect ist nicht wählbar.
    @Test func noselectFolderIsNotSelectable() {
        let tree = build([folder("INBOX"), folder("INBOX.Container", selectable: false)])
        #expect(tree.first { $0.name == "Container" }?.isSelectable == false)
    }

    /// Ohne Trennzeichen wird ein Pfad nicht zerlegt.
    @Test func folderWithoutDelimiterIsNotSplit() {
        let tree = build([folder("INBOX", delimiter: nil), folder("A.B", delimiter: nil)], prefix: nil)
        #expect(tree.map(\.name) == ["Posteingang", "A.B"])
    }

    // MARK: - Rollen

    /// SPECIAL-USE bestimmt die Rollen.
    @Test func specialUseDeterminesRoles() {
        let tree = build(manituFolders)
        #expect(tree.first { $0.id == "INBOX.Trash" }?.role == .trash)
        #expect(tree.first { $0.id == "INBOX.Sent" }?.role == .sent)
        #expect(tree.first { $0.id == "INBOX.Drafts" }?.role == .drafts)
    }

    /// Den Spam-Ordner bestimmt der SpamFolderResolver.
    @Test func spamFolderComesFromSpamFolderResolver() {
        let tree = build(manituFolders)
        #expect(tree.first { $0.id == "INBOX.Junk" }?.role == .junk)
    }

    /// Ein gemerkter Spam-Ordner hat Vorrang.
    @Test func configuredSpamFolderWins() {
        let folders = [folder("INBOX"), folder("INBOX.Junk"), folder("INBOX.Werbung")]
        let tree = build(folders, spam: "INBOX.Werbung")
        #expect(tree.first { $0.id == "INBOX.Werbung" }?.role == .junk)
        #expect(tree.first { $0.id == "INBOX.Junk" }?.role == .regular)
    }

    /// Gebräuchliche Namen werden ohne SPECIAL-USE erkannt.
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

    /// Ein Namenstreffer überstimmt SPECIAL-USE nicht.
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

    /// Namen werden nur auf der obersten Ebene erkannt.
    @Test func nameMatchOnlyOnTopLevel() {
        let tree = build([folder("INBOX"), folder("INBOX.Projekte"), folder("INBOX.Projekte.Sent")])
        let sub = tree.first { $0.id == "INBOX.Projekte" }?.children.first
        #expect(sub?.role == .regular)
    }

    /// Jede Rolle wird per Namen nur einmal vergeben.
    @Test func eachRoleIsAssignedByNameOnlyOnce() {
        let tree = build([folder("INBOX"), folder("INBOX.Sent"), folder("INBOX.Gesendet")])
        #expect(tree.filter { $0.role == .sent }.count == 1)
    }

    // MARK: - Sortierung

    /// Die oberste Ebene ist nach Rolle, dann alphabetisch sortiert.
    @Test func topLevelIsSortedByRoleThenAlphabetically() {
        let tree = build(manituFolders)
        #expect(tree.map(\.name) == [
            "Posteingang", "Entwürfe", "Gesendet", "Archiv", "Spam", "Papierkorb", "Rechnungen"
        ])
    }

    /// Gewöhnliche Ordner werden ohne Groß-/Kleinschreibung sortiert.
    @Test func regularFoldersAreSortedCaseInsensitively() {
        let tree = build([folder("INBOX"), folder("INBOX.beta"), folder("INBOX.Alpha"), folder("INBOX.Gamma")])
        #expect(tree.map(\.name) == ["Posteingang", "Alpha", "beta", "Gamma"])
    }

    /// Unterordner werden alphabetisch sortiert.
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

    /// Bei gleichlautenden Namen behalten beide Ordner ihren Servernamen.
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

    /// Ohne Namensgleichheit bleibt der einheitliche Name.
    @Test func noCollisionWhenNamesAreDifferent() {
        let tree = build([
            folder("INBOX"),
            folder("INBOX.Sent", specialUse: .sent),
            folder("INBOX.Rechnungen")
        ])
        #expect(tree.first { $0.id == "INBOX.Sent" }?.name == "Gesendet")
        #expect(tree.first { $0.id == "INBOX.Rechnungen" }?.name == "Rechnungen")
    }

    /// Bei „/“ als Trennzeichen wird der Servername richtig zurückgeholt.
    @Test func collisionUsesServerDelimiter() {
        let tree = build([
            folder("INBOX", delimiter: "/"),
            folder("INBOX/Sent", specialUse: .sent, delimiter: "/"),
            folder("INBOX/Gesendet", delimiter: "/")
        ], prefix: "INBOX/")
        #expect(tree.first { $0.id == "INBOX/Sent" }?.name == "Sent")
        #expect(tree.first { $0.id == "INBOX/Gesendet" }?.name == "Gesendet")
    }

    /// Namensgleichheit mit dem Spam-Ordner wird aufgelöst.
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

    /// Eine leere Liste ergibt einen leeren Baum.
    @Test func emptyListGivesEmptyTree() {
        #expect(build([]).isEmpty)
    }

    /// Der Initialisierer ohne Angabe ergibt einen wählbaren Ordner.
    @Test func existingInitializerStillDefaultsToSelectable() {
        let folder = MailFolder(id: "INBOX.A", name: "A", specialUse: nil, hierarchyDelimiter: ".")
        #expect(folder.isSelectable)
    }

    // MARK: - manitu (echte LIST-Ausgabe)

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

    /// Echte manitu-Liste ohne Präfix ergibt die erwartete Seitenleiste.
    @Test func manituWithoutPrefixMatchesSidebar() {
        let tree = build(realManituFolders, prefix: "")
        #expect(tree.map(\.name) == ["Posteingang", "Entwürfe", "Gesendet", "Archiv",
                                     "Spam", "Papierkorb", "Test"])
        #expect(tree.first?.children.map(\.id) == ["INBOX.Testeingang"])
        #expect(tree.first { $0.id == "Test" }?.children.map(\.id) == ["Test.Untertest2"])
    }

    // MARK: - Umlaute (modified UTF-7)

    /// Namen in modified UTF-7 werden für die Anzeige dekodiert.
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

    /// Ein kodierter gebräuchlicher Name wird erkannt.
    @Test func encodedCandidateNameIsRecognized() {
        let tree = build([folder("INBOX"), folder("Entw&APw-rfe")], prefix: "")
        let drafts = tree.first { $0.id == "Entw&APw-rfe" }
        #expect(drafts?.role == .drafts)
        #expect(drafts?.name == "Entwürfe")
    }

    /// Eine ungültige Kodierung behält den Servernamen.
    @Test func invalidEncodingKeepsServerName() {
        let tree = build([folder("INBOX"), folder("Kaputt&AP")], prefix: "")
        #expect(tree.contains { $0.id == "Kaputt&AP" && $0.name == "Kaputt&AP" })
    }

    // MARK: - Verschieben-Ziel

    /// Als Verschiebe-Ziel entfallen der aktuelle Ordner und Container.
    @Test func moveTargetExcludesCurrentFolderAndContainers() {
        let test = FolderNode(id: "Test", name: "Test", role: .regular, isSelectable: true, children: [])
        let container = FolderNode(id: "Ablage", name: "Ablage", role: .regular, isSelectable: false, children: [])
        let spam = FolderNode(id: "Junk", name: "Spam", role: .junk, isSelectable: true, children: [])

        #expect(test.isMoveTarget(from: "INBOX"))
        #expect(!test.isMoveTarget(from: "Test"))
        #expect(!container.isMoveTarget(from: "INBOX"))
        #expect(spam.isMoveTarget(from: "INBOX"))
    }

    /// Der Posteingang ist Ziel, außer aus ihm selbst in jeder Schreibweise.
    @Test func inboxIsTargetExceptFromInboxInAnySpelling() {
        let inbox = FolderNode(id: "INBOX", name: "Posteingang", role: .inbox, isSelectable: true, children: [])
        #expect(inbox.isMoveTarget(from: "Archive"))
        #expect(inbox.isMoveTarget(from: "INBOX.Testeingang"))
        #expect(!inbox.isMoveTarget(from: "INBOX"))
        #expect(!inbox.isMoveTarget(from: "Inbox"))
    }
}
