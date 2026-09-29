//
//  MessageStoreSyncTests.swift
//  MailwerkTests
//
//  Tests für den gespeicherten Stand je Ordner (Tabelle folder_sync).
//  Jeder Test arbeitet auf einer eigenen Datei im Temp-Verzeichnis.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreSyncTests {

    private let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private let other = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3302")!

    private func makeStore() -> MessageStore {
        MessageStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path)
    }

    @Test func neverFetchedFolderHasNoStamp() {
        let store = makeStore()
        #expect(store.lastSync(accountID: account, folder: "INBOX") == nil)
    }

    @Test func recordedSyncIsReturned() {
        let store = makeStore()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordSync(accountID: account, folder: "INBOX", at: date)
        #expect(store.lastSync(accountID: account, folder: "INBOX") == date)
    }

    @Test func laterSyncReplacesEarlier() {
        let store = makeStore()
        store.recordSync(accountID: account, folder: "INBOX", at: Date(timeIntervalSince1970: 1_000))
        store.recordSync(accountID: account, folder: "INBOX", at: Date(timeIntervalSince1970: 2_000))
        #expect(store.lastSync(accountID: account, folder: "INBOX") == Date(timeIntervalSince1970: 2_000))
    }

    @Test func stampsAreSeparatePerFolderAndAccount() {
        let store = makeStore()
        store.recordSync(accountID: account, folder: "INBOX", at: Date(timeIntervalSince1970: 1_000))
        #expect(store.lastSync(accountID: account, folder: "INBOX.Trash") == nil)
        #expect(store.lastSync(accountID: other, folder: "INBOX") == nil)
    }

    @Test func stampSurvivesReopeningTheStore() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        MessageStore(path: path).recordSync(accountID: account, folder: "INBOX", at: date)
        #expect(MessageStore(path: path).lastSync(accountID: account, folder: "INBOX") == date)
    }
}
