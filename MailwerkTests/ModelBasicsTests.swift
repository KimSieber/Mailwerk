//
//  ModelBasicsTests.swift
//  MailwerkTests
//
//  Zweck: Tests für kleine Grundbausteine – Erkennung des Posteingangs,
//  Ordnerschlüssel und Ordnernamen bei flacher Hierarchie.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct ModelBasicsTests {

    /// Der Posteingang wird in jeder Schreibweise erkannt, Unterordner nicht.
    @Test func inboxIsRecognizedCaseInsensitive() {
        #expect(MailFolder.isInbox("INBOX"))
        #expect(MailFolder.isInbox("Inbox"))
        #expect(!MailFolder.isInbox("INBOX.Sent"))
    }

    /// Ein „|“ im Ordnernamen macht zwei Schlüssel nicht gleich.
    @Test func folderKeyIsUnambiguous() {
        let account = UUID()
        let first = FolderKey(accountID: account, folder: "A|B")
        let second = FolderKey(accountID: account, folder: "A")
        #expect(first != second)
        #expect(Set([first, second, first]).count == 2)
    }

    /// Ohne Trennzeichen wird der ganze Pfad als Name verglichen.
    @Test func spamFolderFoundInFlatHierarchy() {
        let folders = [
            MailFolder(id: "Spam", name: "Spam", specialUse: nil, hierarchyDelimiter: nil),
            MailFolder(id: "Archiv.Spam", name: "Archiv.Spam", specialUse: nil, hierarchyDelimiter: nil)
        ]
        let resolution = SpamFolderResolver.resolve(folders: folders, delimiter: nil, configured: nil)
        #expect(resolution == .found("Spam"))
    }
}
