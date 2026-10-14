//
//  ShareContextTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Abschrift der Teilen-Erweiterung (ShareContext,
//  ShareContextFile), den nur lesenden AccountStore daraus und die
//  Vorbelegung des Verfassen-Fensters mit geteilten Inhalten.
//

import Foundation
import Testing
@testable import Mailwerk

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Tests für Abschrift, nur lesenden Store und Vorbelegung.
@MainActor
struct ShareContextTests {

    /// Testhilfe: Postfach.
    private func account(_ name: String) -> MailAccount {
        MailAccount(displayName: name, username: "\(name)@example.org", imapHost: "imap.example.org", smtpHost: "smtp.example.org")
    }

    /// Testhilfe: Signatur.
    private func signature(_ accountID: UUID) -> SignatureItem {
        SignatureItem(
            accountID: accountID, kind: .simple, html: "<p>Gruß</p>",
            logoData: Data([1, 2, 3]), logoMimeType: "image/png",
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )
    }

    /// Testhilfe: Datei in einem eigenen temporären Ordner.
    private func temporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(ShareContextFile.fileName)
    }

    /// Schreiben und Lesen ergibt denselben Stand.
    @Test("Abschrift: schreiben und lesen ergibt denselben Stand")
    func roundTrip() throws {
        let url = try temporaryFile()
        let first = account("a"), second = account("b")
        let context = ShareContext(
            accounts: [first, second], defaultAccountID: second.id,
            signatures: [signature(second.id), signature(first.id)]
        )
        #expect(try ShareContextFile.write(context, to: url))
        #expect(ShareContextFile.read(from: url) == .loaded(context))
    }

    /// Unveränderter Stand wird nicht neu geschrieben – auch bei anderer Reihenfolge der Signaturen.
    @Test("Abschrift: unveränderter Stand wird nicht neu geschrieben")
    func skipsUnchanged() throws {
        let url = try temporaryFile()
        let first = account("a"), second = account("b")
        let signatures = [signature(first.id), signature(second.id)]
        let context = ShareContext(accounts: [first, second], defaultAccountID: nil, signatures: signatures)
        #expect(try ShareContextFile.write(context, to: url))
        let reordered = ShareContext(accounts: [first, second], defaultAccountID: nil, signatures: signatures.reversed())
        #expect(try ShareContextFile.write(reordered, to: url) == false)
    }

    /// Fehlende Datei, kaputte Datei und neuere Fassung werden unterschieden.
    @Test("Abschrift: fehlend, unlesbar, neuere Fassung")
    func readFailures() throws {
        let url = try temporaryFile()
        #expect(ShareContextFile.read(from: url) == .missing)

        try Data("kein JSON".utf8).write(to: url)
        #expect(ShareContextFile.read(from: url) == .unreadable)

        var newer = ShareContext(accounts: [account("a")], defaultAccountID: nil, signatures: [])
        newer.version = ShareContext.currentVersion + 1
        try ShareContextFile.encode(newer).write(to: url)
        #expect(ShareContextFile.read(from: url) == .unreadable)
    }

    /// Der nur lesende Store übernimmt Postfächer und ein gültiges Standard-Postfach.
    @Test("Nur lesender Store: Postfächer und Standard-Postfach aus der Abschrift")
    func readOnlyStore() {
        let first = account("a"), second = account("b")
        let store = AccountStore(shareContext: ShareContext(accounts: [first, second], defaultAccountID: second.id, signatures: []))
        #expect(store.accounts == [first, second])
        #expect(store.defaultAccount == second)

        let stale = AccountStore(shareContext: ShareContext(accounts: [first], defaultAccountID: UUID(), signatures: []))
        #expect(stale.defaultAccountID == nil)
    }

    /// Geteilte Inhalte: Standard-Postfach, Betreff, Anhänge, Text mit Link; Vorbelegung zählt nicht als Eingabe.
    @Test("Vorbelegung: Absender, Betreff, Anhänge und Link aus geteilten Inhalten")
    func composePrefill() throws {
        let first = account("a"), second = account("b")
        let store = AccountStore(shareContext: ShareContext(accounts: [first, second], defaultAccountID: second.id, signatures: []))
        let link = try #require(URL(string: "https://www.example.org/"))
        let shared = SharedContent(
            attachments: [SharedAttachment(filename: "Foto.jpeg", mimeType: "image/jpeg", data: Data([9]))],
            texts: ["Schau mal"],
            links: [link],
            title: "Beispielseite"
        )
        let model = ComposeViewModel(accountStore: store, kind: .new, shared: shared)

        #expect(model.accountID == second.id)
        #expect(model.subject == "Beispielseite")
        #expect(model.attachments == [OutgoingAttachment(filename: "Foto.jpeg", mimeType: "image/jpeg", data: Data([9]))])
        #expect(model.body.string == "Schau mal\n\nhttps://www.example.org/")
        let linkRange = (model.body.string as NSString).range(of: "https://")
        #expect(model.body.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL == link)
        #expect(!model.hasContent)
    }
}
