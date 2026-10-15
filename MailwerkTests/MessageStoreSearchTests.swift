//
//  MessageStoreSearchTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Suchabfragen des MessageStore – Treffer im
//  Suchbereich (Postfach, Ordner, Kennzeichnung), gewählte Person,
//  Teilzeichenfolgen und die Adressen für die Namensvorschläge.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageStoreSearchTests {

    private static let account = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private static let other = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3302")!

    /// Testhilfe: neue Ablage im Temp-Verzeichnis.
    private func makeStore() -> MessageStore {
        MessageStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("MailwerkTests-\(UUID().uuidString).sqlite").path)
    }

    /// Testhilfe: Nachricht mit Postfach, Ordner, Absender, Cc, Text und Kennzeichen.
    private func message(
        uid: UInt32,
        account: UUID? = nil,
        folder: String = "INBOX",
        from: String = "Anna Muster <anna@example.org>",
        cc: [String] = [],
        text: String = "",
        flagged: Bool = false
    ) -> CachedMessage {
        let account = account ?? Self.account
        var headers = CachedMessageHeaders()
        headers.toList = ["kim@example.org"]
        headers.ccList = cc
        return CachedMessage(
            id: CachedMessage.makeID(accountID: account, folder: folder, uid: uid),
            accountID: account, accountDisplayName: "Test", folder: folder, uid: uid,
            subject: "Betreff \(uid)", from: from, to: "kim@example.org",
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(uid)),
            isUnread: false, isFlagged: flagged, isAnswered: false, isForwarded: false,
            totalSizeBytes: 100, hasAttachments: false, textBody: text, htmlBody: nil,
            fetchedAt: Date(), headers: headers
        )
    }

    /// Testhilfe: Suche mit Eingabe und optionaler Person; liefert die UIDs sortiert.
    private func search(
        _ store: MessageStore,
        _ query: String,
        address: String? = nil,
        scope: SearchScope? = nil
    ) -> [String] {
        let scope = scope ?? SearchScope(accountIDs: [Self.account], folder: "INBOX", flaggedOnly: false)
        guard let expression = SearchText.matchExpression(query: query, address: address) else { return [] }
        return store.searchMessageIDs(in: scope, match: expression).sorted()
    }

    /// Teilzeichenfolge findet Wortteile, nur im Suchbereich.
    @Test func substringMatchesInScopeOnly() {
        let store = makeStore()
        let hit = message(uid: 1, text: "Ihre Stromrechnung")
        store.saveMessage(hit)
        store.saveMessage(message(uid: 2, folder: "Archiv", text: "Gasrechnung"))
        store.saveMessage(message(uid: 3, account: Self.other, text: "Rechnung"))
        #expect(search(store, "rechnung") == [hit.id])
    }

    /// Kennzeichen-Sicht: nur gekennzeichnete Treffer.
    @Test func flaggedScopeFindsFlaggedOnly() {
        let store = makeStore()
        let flagged = message(uid: 1, text: "Termin", flagged: true)
        store.saveMessage(flagged)
        store.saveMessage(message(uid: 2, text: "Termin"))
        let scope = SearchScope(accountIDs: [Self.account], folder: "INBOX", flaggedOnly: true)
        #expect(search(store, "termin", scope: scope) == [flagged.id])
    }

    /// Eine gewählte Person findet Mails von ihr und an sie (Cc), aber keine längere Adresse.
    @Test func personMatchesFromAndCcExactly() {
        let store = makeStore()
        let fromBen = message(uid: 1, from: "Ben <ben@example.org>")
        let ccBen = message(uid: 2, cc: ["ben@example.org"])
        store.saveMessage(fromBen)
        store.saveMessage(ccBen)
        store.saveMessage(message(uid: 3, from: "Ruben <ruben@example.org>"))
        #expect(search(store, "", address: "ben@example.org") == [fromBen.id, ccBen.id].sorted())
    }

    /// Person und Text zusammen müssen beide zutreffen.
    @Test func personAndTextCombine() {
        let store = makeStore()
        let both = message(uid: 1, from: "ben@example.org", text: "Angebot")
        store.saveMessage(both)
        store.saveMessage(message(uid: 2, from: "ben@example.org", text: "Gruß"))
        store.saveMessage(message(uid: 3, text: "Angebot"))
        #expect(search(store, "Angebot", address: "ben@example.org") == [both.id])
    }

    /// Adressen für die Vorschläge: Von, An und Cc ohne Doppelte, nur im Bereich.
    @Test func participantAddressesInScope() {
        let store = makeStore()
        store.saveMessage(message(uid: 1, cc: ["Chef <chef@firma.de>"]))
        store.saveMessage(message(uid: 2))
        store.saveMessage(message(uid: 3, folder: "Archiv", from: "x@archiv.de"))
        let scope = SearchScope(accountIDs: [Self.account], folder: "INBOX", flaggedOnly: false)
        let addresses = Set(store.participantAddresses(in: scope))
        #expect(addresses == ["Anna Muster <anna@example.org>", "kim@example.org", "Chef <chef@firma.de>"])
    }
}
