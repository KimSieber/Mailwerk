//
//  SyncStateTests.swift
//  MailwerkTests
//
//  Tests für den Stand einer Ansicht und die Einordnung von
//  Verbindungsfehlern.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SyncStateTests {

    private let early = Date(timeIntervalSince1970: 1_000)
    private let late = Date(timeIntervalSince1970: 2_000)

    // MARK: - SyncState

    @Test func noFoldersMeansNever() {
        #expect(SyncState.oldest([]) == .never)
    }

    @Test func singleFolderUsesItsStamp() {
        #expect(SyncState.oldest([late]) == .at(late))
    }

    @Test func singleFolderNeverFetched() {
        #expect(SyncState.oldest([nil]) == .never)
    }

    @Test func severalFoldersUseTheOldestStamp() {
        #expect(SyncState.oldest([late, early, late]) == .at(early))
    }

    @Test func oneFolderNeverFetchedMakesWholeViewNever() {
        #expect(SyncState.oldest([late, nil, early]) == .never)
    }

    // MARK: - Verbindungsfehler

    private struct OtherError: Error {}

    @Test func offlineURLErrorIsConnectionError() {
        #expect(ConnectionErrorClassifier.isConnectionError(URLError(.notConnectedToInternet)))
        #expect(ConnectionErrorClassifier.isConnectionError(URLError(.timedOut)))
    }

    @Test func otherURLErrorIsNotConnectionError() {
        #expect(!ConnectionErrorClassifier.isConnectionError(URLError(.badURL)))
    }

    @Test func posixNetworkErrorIsConnectionError() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENETUNREACH))
        #expect(ConnectionErrorClassifier.isConnectionError(error))
    }

    @Test func otherPosixErrorIsNotConnectionError() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        #expect(!ConnectionErrorClassifier.isConnectionError(error))
    }

    @Test func unrelatedErrorIsNotConnectionError() {
        #expect(!ConnectionErrorClassifier.isConnectionError(OtherError()))
    }
}
