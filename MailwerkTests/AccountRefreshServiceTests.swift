//
//  AccountRefreshServiceTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Abruf über eine gemeinsame Verbindung
//  (AccountRefreshService, Prüfbericht P-13): Entscheidung nach einem
//  Fehler des Spam-Schritts, zweiter Anmeldeversuch und Auswahl der
//  abzurufenden Ordner.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für AccountRefreshService.
@MainActor
struct AccountRefreshServiceTests {

    /// Testhilfe: Fehler ohne Verbindungsbezug (z. B. abgelehntes MOVE).
    private struct ProtocolFailure: Error {}

    // MARK: - Fehler des Spam-Schritts

    /// Zeitüberschreitung im Netz → neue Verbindung für den Abruf.
    @Test("Zeitüberschreitung im Spam-Schritt führt zu neuer Verbindung")
    func reconnectsAfterTimeout() {
        #expect(AccountRefreshService.failureHandling(forSpamStepError: URLError(.timedOut)) == .reconnect)
    }

    /// Abgerissene Verbindung (POSIX) → neue Verbindung für den Abruf.
    @Test("Abgerissene Verbindung im Spam-Schritt führt zu neuer Verbindung")
    func reconnectsAfterConnectionReset() {
        let reset = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET))
        #expect(AccountRefreshService.failureHandling(forSpamStepError: reset) == .reconnect)
    }

    /// Fehler ohne Verbindungsbezug → Abruf auf derselben Verbindung.
    @Test("Protokollfehler im Spam-Schritt: weiter auf derselben Verbindung")
    func continuesAfterProtocolFailure() {
        #expect(AccountRefreshService.failureHandling(forSpamStepError: ProtocolFailure()) == .continueOnConnection)
    }

    // MARK: - Zweiter Anmeldeversuch

    /// Zeitüberschreitung bei der Anmeldung → zweiter Versuch.
    @Test("Zeitüberschreitung bei der Anmeldung führt zum zweiten Versuch")
    func retriesLoginTimeout() {
        let failure = MailFetchService.FolderRefreshError(folder: nil, completed: [], underlying: URLError(.timedOut))
        #expect(AccountRefreshService.shouldRetryLogin(after: failure, workStarted: false))
    }

    /// Ist auf der Verbindung schon gearbeitet worden, kein zweiter Durchgang.
    @Test("Nach begonnener Arbeit kein zweiter Durchgang")
    func noRetryAfterWorkStarted() {
        let failure = MailFetchService.FolderRefreshError(folder: MailFolder.inboxPath, completed: [], underlying: URLError(.timedOut))
        #expect(!AccountRefreshService.shouldRetryLogin(after: failure, workStarted: true))
    }

    /// Anmeldefehler ohne Verbindungsbezug (z. B. abgelehnt) → kein zweiter Versuch.
    @Test("Abgelehnte Anmeldung führt nicht zum zweiten Versuch")
    func noRetryForRejectedLogin() {
        let failure = MailFetchService.FolderRefreshError(folder: nil, completed: [], underlying: ProtocolFailure())
        #expect(!AccountRefreshService.shouldRetryLogin(after: failure, workStarted: false))
    }

    /// Erfolgreicher Durchgang → kein zweiter.
    @Test("Erfolg führt nicht zum zweiten Versuch")
    func noRetryOnSuccess() {
        #expect(!AccountRefreshService.shouldRetryLogin(after: nil, workStarted: false))
    }

    // MARK: - Abzurufende Ordner

    /// Ohne Spam-Ordner nur der Posteingang.
    @Test("Ohne Spam-Ordner wird nur der Posteingang abgerufen")
    func inboxOnlyWithoutSpamFolder() {
        #expect(AccountRefreshService.folders(spamFolder: nil) == [MailFolder.inboxPath])
        #expect(AccountRefreshService.folders(spamFolder: "") == [MailFolder.inboxPath])
    }

    /// Mit Spam-Ordner: erst Posteingang, dann Spam-Ordner.
    @Test("Mit Spam-Ordner: erst Posteingang, dann Spam-Ordner")
    func inboxThenSpamFolder() {
        #expect(AccountRefreshService.folders(spamFolder: "Spam") == [MailFolder.inboxPath, "Spam"])
    }

    /// Ein auf den Posteingang zeigender Spam-Ordner wird nicht doppelt abgerufen.
    @Test("Posteingang als Spam-Ordner wird nicht doppelt abgerufen")
    func noDuplicateInbox() {
        #expect(AccountRefreshService.folders(spamFolder: MailFolder.inboxPath) == [MailFolder.inboxPath])
    }
}
