//
//  FolderDeletionTests.swift
//  MailwerkTests
//
//  Tests für den eigenen IMAP-Dialog zum Löschen leerer Ordner.
//  Ein simulierter Server antwortet wie manitu (Dovecot) und zeichnet
//  alle gesendeten Befehle auf.
//

import Foundation
import Testing
@testable import Mailwerk

// MARK: - Simulierter Server

/// Antwortet je Befehlsart mit vorbereiteten Zeilen; „TAG“ wird durch
/// das Kennzeichen des Befehls ersetzt.
nonisolated private final class FakeServer: IMAPLineChannel {
    var greeting = "* OK [CAPABILITY IMAP4rev1 SASL-IR AUTH=PLAIN] Dovecot ready."
    var replies: [String: [String]] = [:]
    private(set) var sent: [String] = []
    private var pending: [String] = []
    private var lastTag = ""

    init() { pending = [greeting] }

    func send(_ line: String) async throws {
        sent.append(line)
        if line == "*" { pending.append("\(lastTag) NO Authentication aborted"); return }
        let parts = line.split(separator: " ", maxSplits: 2)
        let tag = String(parts[0])
        lastTag = tag
        let key = parts.count > 1 ? String(parts[1]) : ""
        let lines = replies[key] ?? ["TAG OK done"]
        pending += lines.map { $0.replacingOccurrences(of: "TAG", with: tag) }
    }

    func readLine() async throws -> String {
        guard !pending.isEmpty else { throw CancellationError() }
        return pending.removeFirst()
    }

    func setGreeting(_ line: String) { greeting = line; pending = [line] }

    /// Befehle ohne Kennzeichen, zur einfachen Prüfung.
    var commands: [String] {
        sent.map { $0.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? $0 }
    }
}

@MainActor
struct FolderDeletionTests {

    private func emptyFolderServer(path: String = "Test.Neu") -> FakeServer {
        let server = FakeServer()
        server.replies["LIST"] = []   // wird je Test gesetzt
        server.replies["STATUS"] = ["* STATUS \"\(path)\" (MESSAGES 0)", "TAG OK Status completed"]
        return server
    }

    private func run(_ server: FakeServer, path: String = "Test.Neu") async throws -> FolderDeletion.Outcome {
        try await FolderDeletion.run(on: server, username: "kim@ordinum.com", password: "geh\"eim\\", path: path)
    }

    /// LIST liefert beim ersten Aufruf den Ordner, beim zweiten die Kinder.
    nonisolated private final class ListingServer: IMAPLineChannel {
        let base: FakeServer
        var ownLines: [String]
        var childLines: [String]
        private var listCalls = 0

        init(base: FakeServer, own: [String], children: [String] = []) {
            self.base = base
            self.ownLines = own
            self.childLines = children
        }

        func send(_ line: String) async throws {
            if line.contains(" LIST ") {
                listCalls += 1
                base.replies["LIST"] = (listCalls == 1 ? ownLines : childLines) + ["TAG OK List completed"]
            }
            try await base.send(line)
        }

        func readLine() async throws -> String { try await base.readLine() }
    }

    // MARK: - Ablauf

    @Test func emptyFolderIsDeleted() async throws {
        let base = emptyFolderServer()
        let server = ListingServer(base: base, own: [#"* LIST (\HasNoChildren \UnMarked) "." Test.Neu"#])
        let outcome = try await FolderDeletion.run(
            on: server, username: "kim@ordinum.com", password: "x", path: "Test.Neu"
        )
        #expect(outcome == .deleted)
        #expect(base.commands == [
            "AUTHENTICATE PLAIN " + FolderDeletion.plainCredentials(username: "kim@ordinum.com", password: "x"),
            #"LIST "" "Test.Neu""#,
            #"LIST "" "Test.Neu.%""#,
            #"STATUS "Test.Neu" (MESSAGES)"#,
            #"DELETE "Test.Neu""#,
            "LOGOUT"
        ])
    }

    @Test func folderWithMessagesIsNotDeleted() async throws {
        let base = emptyFolderServer()
        base.replies["STATUS"] = [#"* STATUS "Test.Neu" (MESSAGES 12)"#, "TAG OK Status completed"]
        let server = ListingServer(base: base, own: [#"* LIST (\HasNoChildren) "." Test.Neu"#])
        let outcome = try await FolderDeletion.run(on: server, username: "u", password: "p", path: "Test.Neu")
        #expect(outcome == .notEmpty(messages: 12))
        #expect(!base.commands.contains { $0.hasPrefix("DELETE") })
        #expect(base.commands.last == "LOGOUT")
    }

    @Test func folderWithChildrenAttributeIsNotDeleted() async throws {
        let base = emptyFolderServer(path: "Test")
        let server = ListingServer(base: base, own: [#"* LIST (\HasChildren \UnMarked) "." Test"#])
        let outcome = try await FolderDeletion.run(on: server, username: "u", password: "p", path: "Test")
        #expect(outcome == .hasSubfolders)
        #expect(!base.commands.contains { $0.hasPrefix("DELETE") || $0.hasPrefix("STATUS") })
    }

    @Test func childrenAreFoundWithoutChildrenAttribute() async throws {
        let base = emptyFolderServer(path: "Test")
        let server = ListingServer(
            base: base,
            own: [#"* LIST () "." Test"#],
            children: [#"* LIST () "." Test.Untertest2"#]
        )
        let outcome = try await FolderDeletion.run(on: server, username: "u", password: "p", path: "Test")
        #expect(outcome == .hasSubfolders)
        #expect(!base.commands.contains { $0.hasPrefix("DELETE") })
    }

    @Test func missingFolderIsReported() async throws {
        let base = emptyFolderServer()
        let server = ListingServer(base: base, own: [])
        let outcome = try await FolderDeletion.run(on: server, username: "u", password: "p", path: "Test.Neu")
        #expect(outcome == .notFound)
        #expect(!base.commands.contains { $0.hasPrefix("DELETE") })
    }

    @Test func noselectFolderIsNotDeleted() async throws {
        let base = emptyFolderServer()
        let server = ListingServer(base: base, own: [#"* LIST (\Noselect \HasNoChildren) "." Test.Neu"#])
        let outcome = try await FolderDeletion.run(on: server, username: "u", password: "p", path: "Test.Neu")
        #expect(outcome == .notSelectable)
    }

    @Test func encodedPathIsSentUnchanged() async throws {
        let path = "INBOX.Kunden &APw-bersee"
        let base = emptyFolderServer(path: path)
        let server = ListingServer(base: base, own: [#"* LIST (\HasNoChildren) "." "INBOX.Kunden &APw-bersee""#])
        let outcome = try await FolderDeletion.run(on: server, username: "u", password: "p", path: path)
        #expect(outcome == .deleted)
        #expect(base.commands.contains(#"DELETE "INBOX.Kunden &APw-bersee""#))
    }

    // MARK: - Fehler

    @Test func failedLoginStopsBeforeAnyFolderCommand() async throws {
        let base = FakeServer()
        base.replies["AUTHENTICATE"] = ["TAG NO [AUTHENTICATIONFAILED] Authentication failed."]
        await #expect(throws: FolderDeletion.DeletionError.authenticationFailed) {
            _ = try await self.run(base)
        }
        #expect(base.commands.count == 1)
    }

    @Test func continuationRequestIsAborted() async throws {
        let base = FakeServer()
        base.replies["AUTHENTICATE"] = ["+ "]
        await #expect(throws: FolderDeletion.DeletionError.authenticationFailed) {
            _ = try await self.run(base)
        }
        #expect(base.sent.last == "*")
    }

    @Test func badGreetingStopsBeforeLogin() async throws {
        let base = FakeServer()
        base.setGreeting("* BYE Too many connections")
        await #expect(throws: FolderDeletion.DeletionError.unexpectedGreeting) {
            _ = try await self.run(base)
        }
        #expect(base.sent.isEmpty)
    }

    @Test func serverRefusalOfDeleteIsReported() async throws {
        let base = emptyFolderServer()
        base.replies["DELETE"] = ["TAG NO Mailbox is in use"]
        let server = ListingServer(base: base, own: [#"* LIST (\HasNoChildren) "." Test.Neu"#])
        await #expect(throws: FolderDeletion.DeletionError.serverRefused("Mailbox is in use")) {
            _ = try await FolderDeletion.run(on: server, username: "u", password: "p", path: "Test.Neu")
        }
    }

    @Test func wildcardPathIsRefusedWithoutConnection() async throws {
        let base = FakeServer()
        await #expect(throws: FolderDeletion.DeletionError.unsupportedPath) {
            _ = try await FolderDeletion.run(on: base, username: "u", password: "p", path: "Alle*")
        }
        #expect(base.sent.isEmpty)
    }

    @Test func outcomesExplainThemselves() {
        #expect(FolderDeletion.Outcome.deleted.userMessage == nil)
        #expect(FolderDeletion.Outcome.notEmpty(messages: 1).userMessage?.contains("1 Mail –") == true)
        #expect(FolderDeletion.Outcome.notEmpty(messages: 12).userMessage?.contains("12 Mails") == true)
        #expect(FolderDeletion.Outcome.hasSubfolders.userMessage != nil)
    }

    // MARK: - Bausteine

    @Test func quotingEscapesAndRejectsLiteralCharacters() {
        #expect(FolderDeletion.quoted(#"a"b\c"#) == #""a\"b\\c""#)
        #expect(FolderDeletion.quoted("Zeile\r\nDELETE INBOX") == nil)
        #expect(FolderDeletion.quoted("Müller") == nil)
    }

    @Test func plainCredentialsFollowRFC4616() {
        // Base64 von "\0tim\0tanstaaftanstaaf" aus RFC 4616.
        #expect(FolderDeletion.plainCredentials(username: "tim", password: "tanstaaftanstaaf")
                == "AHRpbQB0YW5zdGFhZnRhbnN0YWFm")
    }

    @Test func listLinesAreParsed() {
        let atom = FolderDeletion.parseListLine(#"* LIST (\HasNoChildren \UnMarked) "." Test.Untertest2"#)
        #expect(atom?.name == "Test.Untertest2")
        #expect(atom?.delimiter == ".")
        #expect(atom?.attributes.contains("\\hasnochildren") == true)

        let quoted = FolderDeletion.parseListLine(#"* LIST () "." "Deleted Messages""#)
        #expect(quoted?.name == "Deleted Messages")

        let noDelimiter = FolderDeletion.parseListLine(#"* LIST (\Noselect) NIL Flat"#)
        #expect(noDelimiter?.delimiter == nil)

        #expect(FolderDeletion.parseListLine("* LIST () \".\" {12}") == nil)
        #expect(FolderDeletion.parseListLine("* STATUS INBOX (MESSAGES 3)") == nil)
    }

    @Test func statusLinesAreParsed() {
        #expect(FolderDeletion.parseStatusMessages(#"* STATUS "Test.Neu" (MESSAGES 0)"#) == 0)
        #expect(FolderDeletion.parseStatusMessages("* STATUS Test (UIDNEXT 5 MESSAGES 42)") == 42)
        #expect(FolderDeletion.parseStatusMessages("* LIST () \".\" Test") == nil)
    }

    @Test func completionLinesAreRecognized() {
        #expect(FolderDeletion.completion(of: "MW2 OK List completed", tag: "MW2")?.status == .ok)
        #expect(FolderDeletion.completion(of: "MW2 NO nope", tag: "MW2")?.text == "nope")
        #expect(FolderDeletion.completion(of: "MW21 OK x", tag: "MW2") == nil)
        #expect(FolderDeletion.completion(of: "* OK still here", tag: "MW2") == nil)
    }
}
