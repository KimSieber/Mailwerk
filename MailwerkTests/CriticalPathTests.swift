//
//  CriticalPathTests.swift
//  MailwerkTests
//
//  Zweck: Tests für kritische Pfade, die das Code-Review v0.3.1 (Regel 16)
//  als ungetestet meldete: IMAP-Flags (FlagState), Anmeldestand und
//  Anmeldung per OAuth 2 (OAuthSignInState), Spam-Einstellungen
//  (SpamSettings), Schlüsselbund (KeychainService), Entwürfe-Ordner
//  (DraftService) und das Zusammenführen der Serversuche (SearchViewModel).
//

import Foundation
import SwiftMail
import Testing
@testable import Mailwerk

/// Tests der bisher ungetesteten kritischen Pfade.
@MainActor
struct CriticalPathTests {

    // MARK: - FlagState

    /// Ohne `\Seen` ungelesen; `$Forwarded` ohne Groß-/Kleinschreibung.
    @Test("IMAP-Flags auswerten")
    func flagState() {
        let none = FlagState([])
        #expect(none.isUnread && !none.isFlagged && !none.isAnswered && !none.isForwarded)
        let all = FlagState([.seen, .flagged, .answered, .custom("$forwarded")])
        #expect(!all.isUnread && all.isFlagged && all.isAnswered && all.isForwarded)
        #expect(!FlagState([.custom("$Junk")]).isForwarded)
    }

    // MARK: - OAuthSignInState

    /// Abgelaufen setzen und zurücknehmen; doppeltes Setzen ändert nichts.
    @Test("Anmeldestand je Postfach")
    func signInRequiredTransitions() {
        let state = OAuthSignInState()
        let id = UUID()
        #expect(!state.isSignInRequired(id))
        state.setSignInRequired(true, for: id)
        state.setSignInRequired(true, for: id)
        #expect(state.signInRequired == [id])
        state.setSignInRequired(false, for: id)
        #expect(!state.isSignInRequired(id))
    }

    /// Ohne Anmeldefenster ist keine Anmeldung möglich.
    @Test("Anmeldung ohne Anmeldefenster")
    func signInUnavailable() async {
        let state = OAuthSignInState()
        #expect(!state.canSignIn)
        await #expect(throws: OAuthError.signInUnavailable) {
            _ = try await state.signIn(provider: .microsoft, loginHint: "name@example.com")
        }
    }

    /// Lehnt der Anbieter ab, kommt sein Fehler an – ohne Token-Abfrage.
    @Test("Anmeldung vom Anbieter abgelehnt")
    func signInRejectedByProvider() async {
        let state = OAuthSignInState()
        state.webSignIn = { _, scheme in
            URL(string: "\(scheme)://auth?error=access_denied")!
        }
        await #expect(throws: OAuthError.providerError(code: "access_denied", description: nil)) {
            _ = try await state.signIn(provider: .microsoft, loginHint: "name@example.com")
        }
    }

    // MARK: - SpamSettings

    /// Fehlender Schalter = Standard; Score-Grenze 0 = nicht gespeichert.
    @Test("Spam-Einstellungen: Standardwerte")
    func spamSettingsFallback() {
        #expect(SpamSettings.enabled(stored: nil) == SpamSettings.defaultEnabled)
        #expect(SpamSettings.enabled(stored: "ja") == SpamSettings.defaultEnabled)
        #expect(SpamSettings.enabled(stored: false) == false)
        #expect(SpamSettings.validScoreLimit(0) == nil)
        #expect(SpamSettings.validScoreLimit(-3) == nil)
        #expect(SpamSettings.validScoreLimit(8.5) == 8.5)
    }

    // MARK: - KeychainService

    /// Speichern, überschreiben, lesen, löschen; Lesen ohne Eintrag ergibt nil.
    @Test("Schlüsselbund: Passwort speichern, lesen, löschen")
    func keychainRoundTrip() throws {
        let id = UUID()
        defer { try? KeychainService.deletePassword(for: id) }
        #expect(try KeychainService.readPassword(for: id) == nil)
        try KeychainService.savePassword("erstes", for: id)
        try KeychainService.savePassword("zweites", for: id)
        #expect(try KeychainService.readPassword(for: id) == "zweites")
        try KeychainService.deletePassword(for: id)
        #expect(try KeychainService.readPassword(for: id) == nil)
        try KeychainService.deletePassword(for: id)
    }

    // MARK: - DraftService

    /// SPECIAL-USE vor Namen; Namen ohne Groß-/Kleinschreibung, letztes Segment.
    @Test("Entwürfe-Ordner finden")
    func draftsFolder() {
        func entry(_ path: String, _ use: MailFolder.SpecialUse? = nil) -> MailboxListing.Entry {
            MailboxListing.Entry(path: path, delimiter: ".", specialUse: use, isSelectable: true)
        }
        #expect(DraftService.draftsFolder(in: [entry("INBOX.Entwürfe"), entry("Vorlagen", .drafts)]) == "Vorlagen")
        #expect(DraftService.draftsFolder(in: [entry("INBOX"), entry("INBOX.DRAFTS")]) == "INBOX.DRAFTS")
        #expect(DraftService.draftsFolder(in: [entry("INBOX"), entry("Archiv")]) == nil)
    }

    // MARK: - SearchViewModel.combine

    /// Treffer gemeinsam nach Datum; hasMore aus einem Ordner; Fehler zählen.
    @Test("Serversuche: Ergebnisse zusammenführen")
    func combineServerResults() {
        func hit(_ uid: UInt32, daysAgo: Double) -> MessageListItem {
            MessageListItem(
                id: "a-INBOX-\(uid)", accountID: UUID(), folder: "INBOX", uid: uid,
                subject: "Betreff", from: "a@example.com", recipients: [],
                date: Date(timeIntervalSinceNow: -daysAgo * 86_400),
                isUnread: false, isFlagged: false, isAnswered: false, isForwarded: false,
                hasAttachments: false, sizeBytes: 0, spamVerdict: nil
            )
        }
        struct Offline: Error {}
        let combined = SearchViewModel.combine([
            .success(MailFetchService.ServerSearchResult(hits: [hit(1, daysAgo: 3)], hasMore: false)),
            .failure(Offline()),
            .success(MailFetchService.ServerSearchResult(hits: [hit(2, daysAgo: 1)], hasMore: true))
        ])
        #expect(combined.hits.map(\.uid) == [2, 1])
        #expect(combined.state == .done(hasMore: true, unreachable: 1))
    }
}
