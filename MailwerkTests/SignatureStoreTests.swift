//
//  SignatureStoreTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Signatur-Speicher (SignatureStore) mit der
//  Variante im Speicher und für die Umwandlungen der Pflege-Seite
//  (SignatureEditing).
//

import Foundation
import Testing
@testable import Mailwerk

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Tests für SignatureStore und SignatureEditing.
@MainActor
struct SignatureStoreTests {

    /// Testhilfe: 1×1-Pixel-PNG.
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    /// Testhilfe: Signatur.
    private func item(_ account: UUID, html: String, at seconds: TimeInterval = 0) -> SignatureItem {
        SignatureItem(
            accountID: account, kind: .simple, html: html,
            logoData: nil, logoMimeType: nil,
            modifiedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    /// Testhilfe: Store ohne iCloud-Abo.
    private func store(_ storage: InMemorySignatureStorage? = nil) -> SignatureStore {
        SignatureStore(storage: storage ?? InMemorySignatureStorage(), observesCloud: false)
    }

    /// Speichern, Lesen und Entfernen.
    @Test("Speichern, Lesen und Entfernen einer Signatur")
    func saveAndRemove() throws {
        let account = UUID()
        let storage = InMemorySignatureStorage()
        let signatures = store(storage)

        try signatures.save(item(account, html: "<p>Gruß</p>"))
        #expect(signatures.signature(for: account)?.html == "<p>Gruß</p>")
        #expect(store(storage).signature(for: account) != nil)   // neu gelesen

        try signatures.remove(accountID: account)
        #expect(signatures.signature(for: account) == nil)
        #expect(storage.items.isEmpty)
    }

    /// Eine leere Signatur entfernt die gespeicherte.
    @Test("Leere Signatur entfernt die gespeicherte")
    func emptyRemoves() throws {
        let account = UUID()
        let signatures = store()
        try signatures.save(item(account, html: "<p>Gruß</p>"))
        try signatures.save(item(account, html: "<p><br></p>"))
        #expect(signatures.signature(for: account) == nil)
    }

    /// Doppelte Datensätze aus dem Abgleich: der neueste gilt.
    @Test("Doppelte Datensätze: der neueste gilt")
    func duplicates() {
        let account = UUID()
        let storage = InMemorySignatureStorage(items: [
            item(account, html: "<p>alt</p>", at: 1),
            item(account, html: "<p>neu</p>", at: 2)
        ])
        #expect(store(storage).signature(for: account)?.html == "<p>neu</p>")
    }

    /// Einfache Signatur mit Logo: Editor → HTML → Editor bleibt gleich.
    @Test("Einfache Signatur: Logo-Platzhalter übersteht Hin- und Rückweg")
    func editingRoundTrip() throws {
        let html = "<p>Max Muster</p>\n<p><img src=\"logo\" width=\"150\" height=\"150\" alt=\"\"></p>"
        let text = SignatureEditing.editorText(html: html, logoData: Self.png).text
        #expect(RichTextHTML.images(in: text).count == 1)
        #expect(SignatureEditing.html(from: text) == html)
    }

    /// Fremde Bilder werden gezählt und entfallen im HTML.
    @Test("Fremde Bilder: gezählt, im HTML entfallen")
    func foreignImages() throws {
        let photo = try #require(MailImageAttachment.make(from: Self.png, displayWidth: 50))
        let text = NSMutableAttributedString(string: "Gruß", attributes: RichTextController.defaultAttributes)
        text.append(NSAttributedString(attachment: photo))
        #expect(SignatureEditing.foreignImageCount(in: text) == 1)
        #expect(!SignatureEditing.html(from: text).contains("<img"))
    }

    /// Logo entfernen nimmt es aus dem Text, Ersetzen behält die Breite.
    @Test("Logo ersetzen und entfernen im Editor")
    func replaceLogo() {
        let text = SignatureEditing.editorText(html: "<p>A<img src=\"logo\" width=\"80\"></p>", logoData: Self.png).text
        let replaced = SignatureEditing.replacingLogo(in: text, with: Self.png)
        #expect(SignatureEditing.html(from: replaced).contains("width=\"80\""))
        let removed = SignatureEditing.replacingLogo(in: text, with: nil)
        #expect(removed.string == "A")
    }
}
