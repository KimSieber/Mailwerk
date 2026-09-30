//
//  MailboxNameCodecTests.swift
//  MailwerkTests
//
//  Tests für die Umwandlung von Ordnernamen (modified UTF-7, RFC 3501 5.1.3).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MailboxNameCodecTests {

    // MARK: - Kodieren

    @Test func plainASCIIStaysUnchanged() {
        #expect(MailboxNameCodec.encode("Rechnungen 2026") == "Rechnungen 2026")
    }

    @Test func umlautsAreEncoded() {
        #expect(MailboxNameCodec.encode("Entwürfe") == "Entw&APw-rfe")
        #expect(MailboxNameCodec.encode("Rechnungen Müller") == "Rechnungen M&APw-ller")
        #expect(MailboxNameCodec.encode("Geschäft") == "Gesch&AOQ-ft")
    }

    @Test func consecutiveSpecialCharactersShareOneSection() {
        #expect(MailboxNameCodec.encode("äöü") == "&AOQA9gD8-")
        #expect(MailboxNameCodec.encode("Größe") == "Gr&APYA3w-e")
    }

    @Test func ampersandIsEscaped() {
        #expect(MailboxNameCodec.encode("Haus & Hof") == "Haus &- Hof")
    }

    /// Beispiel aus RFC 3501, Abschnitt 5.1.3.
    @Test func rfcExampleWithCJK() {
        #expect(MailboxNameCodec.encode("~peter/mail/台北/日本語")
                == "~peter/mail/&U,BTFw-/&ZeVnLIqe-")
    }

    @Test func emojiUsesSurrogatePair() {
        #expect(MailboxNameCodec.encode("Urlaub 🌴") == "Urlaub &2DzfNA-")
    }

    // MARK: - Dekodieren

    @Test func decodesUmlauts() {
        #expect(MailboxNameCodec.decode("Entw&APw-rfe") == "Entwürfe")
        #expect(MailboxNameCodec.decode("Gr&APYA3w-e") == "Größe")
        #expect(MailboxNameCodec.decode("Haus &- Hof") == "Haus & Hof")
        #expect(MailboxNameCodec.decode("~peter/mail/&U,BTFw-/&ZeVnLIqe-") == "~peter/mail/台北/日本語")
    }

    @Test func roundTrip() {
        let names = ["Posteingang", "Entwürfe", "Haus & Hof", "Größe & Maß",
                     "Urlaub 🌴 2026", "Ärger", "ß", "&", "a&b", "Ünter.Ördner"]
        for name in names {
            #expect(MailboxNameCodec.decode(MailboxNameCodec.encode(name)) == name)
        }
    }

    @Test func invalidInputIsRejected() {
        #expect(MailboxNameCodec.decode("Entw&APw") == nil)      // kein Abschluss „-“
        #expect(MailboxNameCodec.decode("Entw&A!w-rfe") == nil)  // Zeichen außerhalb Base64
        #expect(MailboxNameCodec.decode("A&AGE-") == nil)        // kodiertes ASCII „a“
        #expect(MailboxNameCodec.decode("&2Dw-") == nil)         // einzelnes Surrogat
        #expect(MailboxNameCodec.decode("&AP-") == nil)          // halbe UTF-16-Einheit
        #expect(MailboxNameCodec.decode("Entwürfe") == nil)      // rohes Nicht-ASCII
    }

    @Test func displayNameFallsBackToServerName() {
        #expect(MailboxNameCodec.displayName("Entw&APw-rfe") == "Entwürfe")
        #expect(MailboxNameCodec.displayName("Kaputt&AP") == "Kaputt&AP")
    }
}
