//
//  MessageDisplayHintsTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die vorberechneten Anzeige-Hinweise
//  (MessageDisplayHints): Berechnung sowie Speichern und Lesen im
//  MessageStore samt Versionsprüfung (Schema-Stufe 9).
//
//  Jeder Speichertest arbeitet auf einer eigenen Datei im Temp-Verzeichnis,
//  damit die Ablage der App unberührt bleibt.
//

import Foundation
import SQLite3
import Testing
@testable import Mailwerk

/// Tests für MessageDisplayHints.
@MainActor
struct MessageDisplayHintsTests {

    // MARK: - Hilfen

    /// Testhilfe: Pfad einer neuen Testdatenbank.
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite")
            .path
    }

    /// Testhilfe: Mail mit Text- und HTML-Teil.
    private func message(uid: UInt32 = 1, text: String? = "Text", html: String? = nil) -> CachedMessage {
        let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
        return CachedMessage(
            id: CachedMessage.makeID(accountID: account, folder: "INBOX", uid: uid),
            accountID: account, accountDisplayName: "Test", folder: "INBOX", uid: uid,
            subject: "Betreff", from: "anna@example.org", to: "kim@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isUnread: true, isFlagged: false, isAnswered: false, isForwarded: false,
            totalSizeBytes: 1_024, hasAttachments: false, textBody: text, htmlBody: html,
            fetchedAt: Date(), headers: CachedMessageHeaders()
        )
    }

    /// Englischer Text, lang genug für die Spracherkennung.
    private static let englishText = """
        Dear customer, thank you very much for your order. Your package has been shipped \
        today and will arrive within the next three business days. Kind regards, your team.
        """

    /// Deutscher Text, lang genug für die Spracherkennung.
    private static let germanText = """
        Liebe Kundin, lieber Kunde, vielen Dank für Ihre Bestellung. Ihr Paket wurde heute \
        verschickt und kommt in den nächsten drei Werktagen bei Ihnen an. Viele Grüße.
        """

    // MARK: - Berechnung

    /// Externe Verweise und eigene Farben werden im HTML erkannt.
    @Test("Externe Inhalte und eigene Farben werden erkannt")
    func detectsRemoteContentAndColors() {
        let html = ##"<body bgcolor="#ffffff"><img src="https://example.com/logo.png"></body>"##
        let hints = MessageDisplayHints.compute(text: nil, html: html)
        #expect(hints.hasRemoteContent)
        #expect(hints.usesOwnColors)
    }

    /// Schlichtes HTML ohne externe Verweise und ohne Farben.
    @Test("Schlichtes HTML: keine externen Inhalte, keine eigenen Farben")
    func plainHTML() {
        let hints = MessageDisplayHints.compute(text: nil, html: "<p>Hallo</p>")
        #expect(!hints.hasRemoteContent)
        #expect(!hints.usesOwnColors)
    }

    /// Fremde Sprache wird als Code gespeichert, Deutsch nicht.
    @Test("Englisch wird erkannt, Deutsch ergibt keine Sprache")
    func detectsForeignLanguageOnly() {
        #expect(MessageDisplayHints.compute(text: Self.englishText, html: nil).languageCode == "en")
        #expect(MessageDisplayHints.compute(text: Self.germanText, html: nil).languageCode == nil)
    }

    // MARK: - Speichern und Lesen

    /// Ohne Hinweise gespeichert → nicht berechnet.
    @Test("Ohne Hinweise gespeicherte Mail liefert keine Hinweise")
    func missingHintsReadAsNil() {
        let store = MessageStore(path: temporaryPath())
        let mail = message()
        store.saveMessage(mail)
        #expect(store.displayHints(messageID: mail.id) == nil)
    }

    /// Beim Speichern mitgegebene Hinweise werden gelesen.
    @Test("Mit der Mail gespeicherte Hinweise werden gelesen")
    func hintsSavedWithMessage() {
        let store = MessageStore(path: temporaryPath())
        let mail = message()
        let hints = MessageDisplayHints(hasRemoteContent: true, usesOwnColors: false, languageCode: "en")
        #expect(store.saveMessageWithAttachments(mail, attachments: [], hints: hints))
        #expect(store.displayHints(messageID: mail.id) == hints)
    }

    /// Nachträglich gespeicherte Hinweise (Rückfall beim Öffnen) werden gelesen.
    @Test("Nachträglich gespeicherte Hinweise werden gelesen")
    func hintsSavedLater() {
        let store = MessageStore(path: temporaryPath())
        let mail = message()
        store.saveMessage(mail)
        let hints = MessageDisplayHints(hasRemoteContent: false, usesOwnColors: true, languageCode: nil)
        store.saveDisplayHints(hints, messageID: mail.id)
        #expect(store.displayHints(messageID: mail.id) == hints)
    }

    /// Hinweise einer älteren Version gelten als nicht berechnet.
    @Test("Veraltete Version gilt als nicht berechnet")
    func outdatedVersionReadsAsNil() {
        let path = temporaryPath()
        let store = MessageStore(path: path)
        let mail = message()
        let hints = MessageDisplayHints(hasRemoteContent: true, usesOwnColors: true, languageCode: "fr")
        store.saveMessageWithAttachments(mail, attachments: [], hints: hints)

        // Version direkt in der Datei zurücksetzen (wie ein Stand vor einer Regeländerung).
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "UPDATE message SET hintsVersion = 0", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        #expect(store.displayHints(messageID: mail.id) == nil)
    }
}
