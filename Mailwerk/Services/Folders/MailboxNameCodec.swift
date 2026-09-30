//
//  MailboxNameCodec.swift
//  Mailwerk
//
//  Wandelt IMAP-Ordnernamen zwischen der Server-Form „modified UTF-7“
//  (RFC 3501, Abschnitt 5.1.3) und lesbarem Text um:
//  „Rechnungen M&APw-ller“ ⇄ „Rechnungen Müller“.
//
//  SwiftMail reicht Ordnernamen in beiden Richtungen unverändert durch.
//  Intern arbeitet Mailwerk deshalb immer mit der kodierten Server-Form
//  (Pfade, Cache, Befehle); lesbarer Text entsteht nur für die Anzeige,
//  kodiert wird nur beim Anlegen eines Ordners.
//
//  Regeln der Kodierung:
//  - Druckbares ASCII (0x20–0x7E) steht für sich selbst, außer „&“.
//  - „&“ wird als „&-“ geschrieben.
//  - Alles andere wird als UTF-16 (Big Endian) in Base64 mit „,“ statt „/“
//    und ohne Auffüllzeichen geschrieben, eingefasst in „&“ … „-“.
//
//  Reine Logik ohne IMAP-Bezug, deshalb `nonisolated`.
//

import Foundation

nonisolated enum MailboxNameCodec {

    // MARK: - Anzeige

    /// Lesbarer Name für die Anzeige. Ist die Kodierung ungültig, bleibt
    /// der Servername stehen – lieber ein seltsamer Name als ein falscher.
    static func displayName(_ encoded: String) -> String {
        decode(encoded) ?? encoded
    }

    // MARK: - Kodieren

    /// Kodiert einen lesbaren Namen in die Server-Form.
    static func encode(_ name: String) -> String {
        var result = ""
        var pending: [UInt16] = []

        func flush() {
            guard !pending.isEmpty else { return }
            result += "&" + base64(pending) + "-"
            pending.removeAll()
        }

        for scalar in name.unicodeScalars {
            if scalar == "&" {
                flush()
                result += "&-"
            } else if isPrintableASCII(scalar) {
                flush()
                result.unicodeScalars.append(scalar)
            } else {
                pending.append(contentsOf: String(scalar).utf16)
            }
        }
        flush()
        return result
    }

    // MARK: - Dekodieren

    /// Dekodiert die Server-Form. `nil`, wenn der Text keine gültige
    /// Kodierung ist (etwa rohe Nicht-ASCII-Zeichen, unvollständige oder
    /// fehlerhafte Base64-Abschnitte).
    static func decode(_ encoded: String) -> String? {
        var result = ""
        let scalars = Array(encoded.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            guard isPrintableASCII(scalar) else { return nil }

            guard scalar == "&" else {
                result.unicodeScalars.append(scalar)
                index += 1
                continue
            }

            // Ende des Abschnitts suchen.
            guard let end = scalars[(index + 1)...].firstIndex(of: "-") else { return nil }
            let body = String(String.UnicodeScalarView(scalars[(index + 1)..<end]))

            if body.isEmpty {
                result += "&"
            } else {
                guard let text = decodeBase64Section(body) else { return nil }
                result += text
            }
            index = end + 1
        }
        return result
    }

    // MARK: - Intern

    private static let alphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+,".unicodeScalars
    )

    private static func isPrintableASCII(_ scalar: Unicode.Scalar) -> Bool {
        (0x20...0x7E).contains(scalar.value)
    }

    /// UTF-16-Einheiten als Base64 mit „,“ statt „/“ und ohne „=“.
    private static func base64(_ units: [UInt16]) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(units.count * 2)
        for unit in units {
            bytes.append(UInt8(unit >> 8))
            bytes.append(UInt8(unit & 0xFF))
        }

        var output = ""
        var buffer: UInt32 = 0
        var bitCount = 0
        for byte in bytes {
            buffer = (buffer << 8) | UInt32(byte)
            bitCount += 8
            while bitCount >= 6 {
                bitCount -= 6
                output.unicodeScalars.append(alphabet[Int((buffer >> UInt32(bitCount)) & 0x3F)])
            }
        }
        if bitCount > 0 {
            output.unicodeScalars.append(alphabet[Int((buffer << UInt32(6 - bitCount)) & 0x3F)])
        }
        return output
    }

    /// Dekodiert einen Base64-Abschnitt (ohne „&“ und „-“) zu Text.
    private static func decodeBase64Section(_ body: String) -> String? {
        var bytes: [UInt8] = []
        var buffer: UInt32 = 0
        var bitCount = 0

        for scalar in body.unicodeScalars {
            guard let value = alphabet.firstIndex(of: scalar) else { return nil }
            buffer = (buffer << 6) | UInt32(value)
            bitCount += 6
            if bitCount >= 8 {
                bitCount -= 8
                bytes.append(UInt8((buffer >> UInt32(bitCount)) & 0xFF))
            }
        }
        // Übrige Bits sind reine Auffüllung: weniger als ein Byte und null.
        guard bitCount < 6, buffer & ((1 << UInt32(bitCount)) - 1) == 0 else { return nil }
        // UTF-16 braucht ganze Zwei-Byte-Einheiten.
        guard !bytes.isEmpty, bytes.count % 2 == 0 else { return nil }

        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        for pair in stride(from: 0, to: bytes.count, by: 2) {
            units.append(UInt16(bytes[pair]) << 8 | UInt16(bytes[pair + 1]))
        }

        // Nur echte Sonderzeichen dürfen kodiert sein; einzelne
        // Surrogate (kaputtes UTF-16) werden abgelehnt.
        var text = ""
        for decoded in scalars(fromUTF16: units) {
            guard let scalar = decoded, !isPrintableASCII(scalar) else { return nil }
            text.unicodeScalars.append(scalar)
        }
        return text
    }

    /// UTF-16-Einheiten zu Unicode-Scalars; `nil` für ungültige Folgen.
    private static func scalars(fromUTF16 units: [UInt16]) -> [Unicode.Scalar?] {
        var iterator = units.makeIterator()
        var decoder = UTF16()
        var result: [Unicode.Scalar?] = []
        loop: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): result.append(scalar)
            case .emptyInput: break loop
            case .error: result.append(nil)
            }
        }
        return result
    }
}
