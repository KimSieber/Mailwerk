//
//  SyncStateTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Stand einer Ansicht (SyncState) und die Einordnung
//  von Verbindungsfehlern (ConnectionErrorClassifier).
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für SyncState und ConnectionErrorClassifier.
@MainActor
struct SyncStateTests {

    private let early = Date(timeIntervalSince1970: 1_000)
    private let late = Date(timeIntervalSince1970: 2_000)

    // MARK: - SyncState

    /// Ohne Ordner gilt die Ansicht als nie abgerufen.
    @Test func noFoldersMeansNever() {
        #expect(SyncState.oldest([]) == .never)
    }

    /// Ein Ordner liefert seinen Zeitpunkt.
    @Test func singleFolderUsesItsStamp() {
        #expect(SyncState.oldest([late]) == .at(late))
    }

    /// Ein nie abgerufener Ordner ergibt „nie“.
    @Test func singleFolderNeverFetched() {
        #expect(SyncState.oldest([nil]) == .never)
    }

    /// Mehrere Ordner ergeben den ältesten Zeitpunkt.
    @Test func severalFoldersUseTheOldestStamp() {
        #expect(SyncState.oldest([late, early, late]) == .at(early))
    }

    /// Ein nie abgerufener Ordner macht die ganze Ansicht „nie“.
    @Test func oneFolderNeverFetchedMakesWholeViewNever() {
        #expect(SyncState.oldest([late, nil, early]) == .never)
    }

    // MARK: - Verbindungsfehler

    /// Testhilfe: Fehler ohne Bezug zu Verbindungen.
    private struct OtherError: Error {}

    /// „Keine Internetverbindung“ ist ein Verbindungsfehler.
    @Test func offlineURLErrorIsConnectionError() {
        #expect(ConnectionErrorClassifier.isConnectionError(URLError(.notConnectedToInternet)))
        #expect(ConnectionErrorClassifier.isConnectionError(URLError(.timedOut)))
    }

    /// Andere URL-Fehler sind keine Verbindungsfehler.
    @Test func otherURLErrorIsNotConnectionError() {
        #expect(!ConnectionErrorClassifier.isConnectionError(URLError(.badURL)))
    }

    /// POSIX-Netzfehler sind Verbindungsfehler.
    @Test func posixNetworkErrorIsConnectionError() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENETUNREACH))
        #expect(ConnectionErrorClassifier.isConnectionError(error))
    }

    /// Andere POSIX-Fehler sind keine Verbindungsfehler.
    @Test func otherPosixErrorIsNotConnectionError() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        #expect(!ConnectionErrorClassifier.isConnectionError(error))
    }

    /// Fremde Fehler sind keine Verbindungsfehler.
    @Test func unrelatedErrorIsNotConnectionError() {
        #expect(!ConnectionErrorClassifier.isConnectionError(OtherError()))
    }
}
