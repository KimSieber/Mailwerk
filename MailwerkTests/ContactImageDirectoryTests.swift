//
//  ContactImageDirectoryTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Zuordnung Adresse → Kontaktbild
//  (ContactImageDirectory) – Schreibweise der Adressen, Kontakte ohne
//  Bild, mehrfach vorkommende Adressen.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct ContactImageDirectoryTests {

    /// Testhilfe: Bilddaten mit wählbarem Inhalt.
    private func data(_ byte: UInt8) -> Data { Data([byte, byte, byte]) }

    /// Adressen werden ohne Leerraum und kleingeschrieben verglichen.
    @Test func addressesAreNormalized() {
        #expect(ContactImageDirectory.normalized("  Anna@Example.ORG ") == "anna@example.org")
        let map = ContactImageDirectory.thumbnailMap(from: [(addresses: ["Anna@Example.org"], thumbnail: data(1))])
        #expect(map["anna@example.org"] == data(1))
    }

    /// Kontakte ohne Bild oder mit leeren Bilddaten entfallen.
    @Test func contactsWithoutImageAreSkipped() {
        let map = ContactImageDirectory.thumbnailMap(from: [
            (addresses: ["a@example.org"], thumbnail: nil),
            (addresses: ["b@example.org"], thumbnail: Data())
        ])
        #expect(map.isEmpty)
    }

    /// Alle Adressen eines Kontakts zeigen auf sein Bild; bei Mehrfachvorkommen gewinnt der erste Kontakt.
    @Test func allAddressesMapAndFirstContactWins() {
        let map = ContactImageDirectory.thumbnailMap(from: [
            (addresses: ["a@example.org", "a@privat.de"], thumbnail: data(1)),
            (addresses: ["A@example.org"], thumbnail: data(2))
        ])
        #expect(map["a@example.org"] == data(1))
        #expect(map["a@privat.de"] == data(1))
        #expect(map.count == 2)
    }
}
