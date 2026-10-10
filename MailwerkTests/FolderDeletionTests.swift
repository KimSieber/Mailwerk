//
//  FolderDeletionTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Prüfung vor dem Löschen eines Ordners – nicht
//  vorhanden, Container, Unterordner, Mails, unbekannter Inhalt, leer.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct FolderDeletionTests {

    /// Testhilfe: Ordner mit Trennzeichen ".".
    private func folder(_ path: String, selectable: Bool = true) -> MailFolder {
        MailFolder(
            id: path,
            name: path.components(separatedBy: ".").last ?? path,
            specialUse: nil,
            hierarchyDelimiter: ".",
            isSelectable: selectable
        )
    }

    /// Ordner nicht in der Liste: gibt es nicht mehr.
    @Test func missingFolderIsNotFound() {
        #expect(FolderDeletion.precheck(path: "Alt", folders: [folder("INBOX")]) == .notFound)
    }

    /// Reiner Container: nicht löschbar.
    @Test func containerIsNotSelectable() {
        let folders = [folder("INBOX"), folder("Archiv", selectable: false)]
        #expect(FolderDeletion.precheck(path: "Archiv", folders: folders) == .notSelectable)
    }

    /// Ordner mit Unterordner: nicht löschbar.
    @Test func folderWithChildHasSubfolders() {
        let folders = [folder("Projekte"), folder("Projekte.Mailwerk")]
        #expect(FolderDeletion.precheck(path: "Projekte", folders: folders) == .hasSubfolders)
    }

    /// Gleicher Namensanfang ohne Trennzeichen ist kein Unterordner.
    @Test func similarNameIsNoSubfolder() {
        let folders = [folder("Projekte"), folder("Projekte2")]
        #expect(FolderDeletion.precheck(path: "Projekte", folders: folders) == nil)
    }

    /// Mails im Ordner: nicht löschbar; leer: löschbar; unbekannt: nicht löschbar.
    @Test func messageCountDecides() {
        #expect(FolderDeletion.outcome(messageCount: 3) == .notEmpty(messages: 3))
        #expect(FolderDeletion.outcome(messageCount: 0) == nil)
        #expect(FolderDeletion.outcome(messageCount: nil) == .unknownContent)
    }

    /// Nur „gelöscht“ und „nicht gefunden“ entfernen den Ordner aus dem Cache.
    @Test func removesFolderOnlyWhenGone() {
        #expect(FolderDeletion.Outcome.deleted.removesFolder)
        #expect(FolderDeletion.Outcome.notFound.removesFolder)
        #expect(!FolderDeletion.Outcome.hasSubfolders.removesFolder)
        #expect(!FolderDeletion.Outcome.notEmpty(messages: 1).removesFolder)
    }
}
