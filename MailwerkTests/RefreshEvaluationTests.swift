//
//  RefreshEvaluationTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Auswertungen, die in v0.3.1b aus Abruf, Spamfilter,
//  Verbindungstest und Watch-Aktionen herausgelöst wurden:
//  AccountRefreshService.evaluate, SpamFilterPlanner.uncheckedUIDs,
//  MailConnectionTester.smtpTestError und WatchBridge.failureHandling.
//

import Foundation
import SwiftMail
import Testing
@testable import Mailwerk

/// Tests für die herausgelösten Auswertungen.
@MainActor
struct RefreshEvaluationTests {

    /// Testhilfe: beliebiger Fehler mit fester Meldung.
    private struct SampleError: LocalizedError {
        var errorDescription: String? { "Testfehler" }
    }

    // MARK: - AccountRefreshService.evaluate

    /// Ohne Abruffehler: vollständig, ein leerer Spam-Ordner zählt als keiner.
    @Test("Abruf ohne Fehler")
    func evaluateCompleted() {
        guard case .completed(let folder) = AccountRefreshService.evaluate(.init(spamFolder: "")) else {
            Issue.record("erwartet: completed"); return
        }
        #expect(folder == nil)
    }

    /// Posteingang fertig, nur der Spam-Ordner scheiterte: Spam-Ordner nachholen.
    @Test("Nur der Spam-Ordner scheiterte")
    func evaluateSpamFolderFailed() {
        let failure = MailFetchService.FolderRefreshError(
            folder: "Spam", completed: [MailFolder.inboxPath], underlying: SampleError()
        )
        guard case .spamFolderFailed(let folder, let underlying) =
                AccountRefreshService.evaluate(.init(spamFolder: "Spam", fetchError: failure)) else {
            Issue.record("erwartet: spamFolderFailed"); return
        }
        #expect(folder == "Spam")
        #expect(underlying is SampleError)
    }

    /// Scheitert schon der Posteingang, ist der Abruf gescheitert.
    @Test("Posteingang gescheitert")
    func evaluateFailed() {
        let failure = MailFetchService.FolderRefreshError(
            folder: MailFolder.inboxPath, completed: [], underlying: SampleError()
        )
        guard case .failed(let underlying) =
                AccountRefreshService.evaluate(.init(spamFolder: "Spam", fetchError: failure)) else {
            Issue.record("erwartet: failed"); return
        }
        #expect(underlying is SampleError)
    }

    // MARK: - SpamFilterPlanner.uncheckedUIDs

    /// Mit Schlüsselwörtern zählen alle Treffer, sonst nur die nicht gecachten.
    @Test("Ungeprüfte Mails mit und ohne Schlüsselwörter")
    func uncheckedUIDs() {
        #expect(SpamFilterPlanner.uncheckedUIDs(found: [1, 2, 3], usesKeywords: true, cached: [2]) == [1, 2, 3])
        #expect(SpamFilterPlanner.uncheckedUIDs(found: [1, 2, 3], usesKeywords: false, cached: [2]) == [1, 3])
    }

    // MARK: - MailConnectionTester.smtpTestError

    /// Scheitert die Verbindung, gilt smtpFailed; bei der Anmeldung je Zugang.
    @Test("Fehler des SMTP-Tests je Schritt und Zugang")
    func smtpTestError() {
        let error = SampleError()
        #expect(MailConnectionTester.smtpTestError(for: error, step: .connect, login: .password("x")) == .smtpFailed("Testfehler"))
        #expect(MailConnectionTester.smtpTestError(for: error, step: .login, login: .password("x")) == .smtpLoginRejected(nil))
        #expect(MailConnectionTester.smtpTestError(for: error, step: .login, login: .accessToken("t")) == .smtpTokenRejected(nil))
    }

    // MARK: - WatchBridge.failureHandling

    /// Verbindungsfehler lassen die Aktion offen, andere Fehler scheitern mit Text.
    @Test("Fehler einer Watch-Aktion")
    func watchFailureHandling() {
        #expect(WatchBridge.failureHandling(for: URLError(.notConnectedToInternet), spamRequest: nil) == .keepOpen)
        #expect(WatchBridge.failureHandling(for: SampleError(), spamRequest: nil) == .fail("Testfehler"))
    }
}
