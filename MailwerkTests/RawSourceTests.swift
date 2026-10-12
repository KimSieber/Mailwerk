//
//  RawSourceTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Originalquelle – Aufbereitung der Rohdaten
//  (RawMessageFormatter: Kopfzeilen unverändert, Base64-Text dekodiert,
//  Quoted-Printable unverändert, Anlagen und Inline-Bilder ausgelassen,
//  eingebettete Mails aufgelöst, tolerant bei Fehlern) und die Prüfung,
//  ob die Quelle geholt wird (RawMessageService.availability).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct RawSourceTests {

    /// Testhilfe: Rohdaten aus Zeilen mit CRLF.
    private func raw(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\r\n").utf8)
    }

    /// Testhilfe: Mail mit Text (Base64), HTML (Quoted-Printable), PDF und Inline-Bild.
    private var sampleMail: Data {
        raw([
            "Received: from mx.example.org by mail.example.de",
            "\twith ESMTPS; Mon, 12 Oct 2026 10:00:00 +0200",
            "From: Anna <anna@example.org>",
            "Subject: Test",
            "MIME-Version: 1.0",
            #"Content-Type: multipart/mixed; boundary="outer""#,
            "",
            "This is a multi-part message in MIME format.",
            "--outer",
            "Content-Type: multipart/related;",
            " boundary=inner",
            "",
            "--inner",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
            "",
            "SGFsbG8gV2VsdCDDpMO2w7w=",
            "--inner",
            #"Content-Type: text/html; charset="iso-8859-1""#,
            "Content-Transfer-Encoding: quoted-printable",
            "",
            "<p>Gr=FC=DFe</p>",
            "--inner",
            "Content-Type: image/png",
            "Content-ID: <logo@example.org>",
            "Content-Transfer-Encoding: base64",
            "",
            "iVBORw0KGgo=",
            "--inner--",
            "--outer",
            #"Content-Type: application/pdf; name="Rechnung.pdf""#,
            #"Content-Disposition: attachment; filename="Rechnung.pdf""#,
            "Content-Transfer-Encoding: base64",
            "",
            "JVBERi0xLjQKJcfsj6IKNSAwIG9iago8PC9MZW5ndGggNiAwIFI+PgpzdHJlYW0K",
            "--outer--",
            ""
        ])
    }

    /// Kopfzeilen samt Folgezeilen und MIME-Grenzen bleiben unverändert.
    @Test func headersAndBoundariesStayUnchanged() {
        let text = RawMessageFormatter.format(sampleMail)
        #expect(text.hasPrefix("Received: from mx.example.org by mail.example.de\n\twith ESMTPS"))
        #expect(text.contains("Subject: Test\n"))
        #expect(text.contains("This is a multi-part message in MIME format.\n--outer\n"))
        #expect(text.contains("--inner--\n"))
        #expect(text.contains("--outer--"))
        #expect(!text.contains("\r"))
    }

    /// Base64-Text wird dekodiert und gekennzeichnet; Quoted-Printable bleibt.
    @Test func textPartsAreReadable() {
        let text = RawMessageFormatter.format(sampleMail)
        #expect(text.contains("Content-Transfer-Encoding: base64\n\n[Base64 dekodiert]\nHallo Welt äöü"))
        #expect(!text.contains("SGFsbG8gV2VsdCDDpMO2w7w="))
        #expect(text.contains("<p>Gr=FC=DFe</p>"))
    }

    /// Anlage und Inline-Bild werden durch eine Zeile ersetzt, ihre Kopfzeilen bleiben.
    @Test func attachmentsAreOmitted() {
        let text = RawMessageFormatter.format(sampleMail)
        #expect(text.contains(#"Content-Disposition: attachment; filename="Rechnung.pdf""#))
        #expect(text.contains("[Anlage ausgelassen: Rechnung.pdf, "))
        #expect(!text.contains("JVBERi0xLjQK"))
        #expect(text.contains("Content-ID: <logo@example.org>"))
        #expect(text.contains("[Anlage ausgelassen: image/png, "))
        #expect(!text.contains("iVBORw0KGgo="))
    }

    /// Textdatei als Anlage wird ausgelassen; Name nach RFC 2231 dekodiert.
    @Test func textAttachmentIsOmittedWithDecodedName() {
        let text = RawMessageFormatter.format(raw([
            "Content-Type: multipart/mixed; boundary=b",
            "",
            "--b",
            "Content-Type: text/plain",
            "",
            "Hauptteil",
            "--b",
            "Content-Type: text/plain; name*=utf-8''M%C3%A4rz.txt",
            "",
            "Inhalt der Datei",
            "--b--"
        ]))
        #expect(text.contains("Hauptteil"))
        #expect(text.contains("[Anlage ausgelassen: März.txt, "))
        #expect(!text.contains("Inhalt der Datei"))
    }

    /// Eingebettete Mail (z. B. Unzustellbarkeitsbericht) wird nach denselben Regeln aufgelöst.
    @Test func embeddedMessageIsResolved() {
        let text = RawMessageFormatter.format(raw([
            #"Content-Type: multipart/report; report-type=delivery-status; boundary="r""#,
            "",
            "--r",
            "Content-Type: message/delivery-status",
            "",
            "Status: 5.1.1",
            "--r",
            "Content-Type: message/rfc822",
            "",
            "Subject: Original",
            #"Content-Type: multipart/mixed; boundary="x""#,
            "",
            "--x",
            "Content-Type: text/plain",
            "",
            "Originaltext",
            "--x",
            "Content-Type: application/zip",
            "Content-Transfer-Encoding: base64",
            "",
            "UEsDBA==",
            "--x--",
            "--r--"
        ]))
        #expect(text.contains("Status: 5.1.1"))
        #expect(text.contains("Subject: Original"))
        #expect(text.contains("Originaltext"))
        #expect(text.contains("[Anlage ausgelassen: application/zip, "))
        #expect(!text.contains("UEsDBA=="))
    }

    /// Fehlerhafte Mails: fehlende Grenze, abgeschnittener Teil, ungültiges Base64 bleiben stehen.
    @Test func toleratesBrokenMails() {
        let noBoundary = RawMessageFormatter.format(raw([
            "Content-Type: multipart/mixed",
            "",
            "--irgendwas",
            "Text"
        ]))
        #expect(noBoundary.contains("--irgendwas\nText"))

        let truncated = RawMessageFormatter.format(raw([
            "Content-Type: multipart/alternative; boundary=b",
            "",
            "--b",
            "Content-Type: text/plain",
            "",
            "Abgeschnitten"
        ]))
        #expect(truncated.contains("Abgeschnitten"))

        let invalidBase64 = RawMessageFormatter.format(raw([
            "Content-Type: text/plain",
            "Content-Transfer-Encoding: base64",
            "",
            "kein@gültiges#base64"
        ]))
        #expect(invalidBase64.contains("kein@gültiges#base64"))
        #expect(!invalidBase64.contains(RawMessageFormatter.decodedMarker))
    }

    /// Zeilen in ISO-8859-1 (8-Bit-Kopfzeilen alter Mails) werden lesbar.
    @Test func latin1LinesAreReadable() {
        var data = Data("Subject: Gr".utf8)
        data.append(contentsOf: [0xFC, 0xDF, 0x65])   // „üße“ in ISO-8859-1
        data.append(contentsOf: Array("\r\n\r\nText".utf8))
        #expect(RawMessageFormatter.format(data).hasPrefix("Subject: Grüße\n"))
    }

    /// Base64-Text im angegebenen Zeichensatz.
    @Test func decodesCharset() {
        #expect(RawMessageFormatter.decodeText(Data([0x47, 0x72, 0xFC, 0xDF, 0x65]), charset: "iso-8859-1") == "Grüße")
        #expect(RawMessageFormatter.decodeText(Data("Grüße".utf8), charset: "unbekannt") == "Grüße")
    }

    /// Ohne Netz zuerst „offline“; sonst entscheidet die Größe.
    @Test func availabilityFollowsNetworkAndSize() {
        #expect(RawMessageService.availability(sizeBytes: 1_000, isOnline: false, limit: 5_000) == .offline)
        #expect(RawMessageService.availability(sizeBytes: 9_000, isOnline: false, limit: 5_000) == .offline)
        #expect(RawMessageService.availability(sizeBytes: 5_000, isOnline: true, limit: 5_000) == .available)
        #expect(RawMessageService.availability(sizeBytes: 5_001, isOnline: true, limit: 5_000) == .tooLarge)
    }
}
