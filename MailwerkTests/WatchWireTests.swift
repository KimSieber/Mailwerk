//
//  WatchWireTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Übertragungsform zwischen iPhone und Apple Watch
//  (WatchWire, WatchChunkAssembler) – Packen und Entpacken, Stückeln und
//  Zusammensetzen, Anfragen.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct WatchWireTests {

    /// Testhilfe: kleine Lieferung mit Inhalt.
    private var content: WatchContent {
        WatchContent(
            bodies: [WatchBody(id: "a", html: "<p>Hallo</p>", text: "Hallo", cc: ["x@example.com"],
                               attachments: [WatchAttachment(name: "Plan.pdf", sizeBytes: 1234)])],
            images: [WatchImage(key: WatchAvatarKey.logo("example.com"), data: Data([1, 2, 3])),
                     WatchImage(key: WatchAvatarKey.contact("a@example.com"), data: nil)]
        )
    }

    /// Packen und Entpacken ergeben dieselbe Lieferung.
    @Test func packRoundTrip() throws {
        let blob = try WatchWire.pack(.content(content))
        guard case .content(let decoded) = try WatchWire.unpack(blob) else {
            Issue.record("Falsche Art der Lieferung")
            return
        }
        #expect(decoded == content)
    }

    /// Unlesbare Daten werden abgelehnt.
    @Test func unpackRejectsGarbage() {
        #expect(throws: (any Error).self) { try WatchWire.unpack(Data([0, 1, 2, 3])) }
    }

    /// Stückeln und Zusammensetzen – auch in anderer Reihenfolge.
    @Test func splitAndAssembleOutOfOrder() {
        let blob = Data((0..<1000).map { UInt8($0 % 251) })
        let chunks = WatchWire.split(blob, token: UUID(), maxSize: 300)
        #expect(chunks.count == 4)
        #expect(chunks.allSatisfy { $0.data.count <= 300 })
        var assembler = WatchChunkAssembler(chunks[2])
        #expect(assembler.missing == [0, 1, 3])
        assembler.add(chunks[0])
        assembler.add(chunks[3])
        #expect(assembler.blob == nil)
        assembler.add(chunks[1])
        #expect(assembler.blob == blob)
    }

    /// Stücke einer anderen Lieferung werden übergangen.
    @Test func assemblerIgnoresForeignChunks() {
        let own = WatchWire.split(Data([1, 2, 3, 4]), token: UUID(), maxSize: 2)
        let foreign = WatchWire.split(Data([9, 9, 9, 9]), token: UUID(), maxSize: 2)
        var assembler = WatchChunkAssembler(own[0])
        assembler.add(foreign[1])
        #expect(assembler.missing == [1])
    }

    /// Leere Daten ergeben ein leeres Stück.
    @Test func emptyBlobGivesOneChunk() {
        let chunks = WatchWire.split(Data(), token: UUID())
        #expect(chunks.count == 1)
        #expect(WatchChunkAssembler(chunks[0]).blob == Data())
    }

    /// Eine Anfrage mit Aktionen übersteht Kodieren und Lesen.
    @Test func requestRoundTrip() throws {
        let action = WatchAction(
            .spam(kind: .block, entryKind: .domain, value: "example.com"),
            on: WatchMailboxTests.mail("a")
        )
        let data = try WatchWire.encode(WatchRequest.sync(actions: [action], refresh: true))
        guard case .sync(let actions, let refresh) = try WatchWire.decode(WatchRequest.self, from: data) else {
            Issue.record("Falsche Art der Anfrage")
            return
        }
        #expect(actions == [action])
        #expect(refresh)
    }

    /// Ein volles Stück bleibt unter der Grenze von WatchConnectivity.
    @Test func encodedChunkStaysBelowMessageLimit() throws {
        let blob = Data(repeating: 7, count: WatchWire.maxChunkSize * 2)
        let chunk = WatchWire.split(blob, token: UUID())[0]
        #expect(try WatchWire.encode(chunk).count < 65_000)
    }
}
