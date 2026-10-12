//
//  RawMessageFormatter.swift
//  Mailwerk
//
//  Zweck: Bereitet die Rohdaten einer Mail (so, wie sie übertragen wurde)
//  als lesbaren Text für die Ansicht „Originalquelle“ auf. Gedacht für die
//  Prüfung von Fehlern und die Analyse von Kopfzeilen und Aufbau.
//
//  Regeln:
//  - Kopfzeilen der Mail und aller Teile bleiben unverändert, ebenso die
//    MIME-Grenzen, Präambel und Epilog.
//  - Text- und HTML-Teile bleiben vollständig. Sind sie Base64-kodiert,
//    werden sie im angegebenen Zeichensatz dekodiert; die Zeile
//    `[Base64 dekodiert]` kennzeichnet das. Quoted-Printable bleibt wie
//    übertragen, weil es lesbar ist und für Analysen oft genau das
//    Interessante enthält.
//  - Anlagen und eingebettete Bilder werden ausgelassen: An Stelle ihres
//    Inhalts steht eine Zeile `[Anlage ausgelassen: Name, Größe]`. Als
//    Anlage gilt ein Teil mit Disposition „attachment“ oder Dateinamen
//    sowie jeder Teil, der kein Text ist.
//  - Eingebettete Mails (`message/rfc822`, z. B. weitergeleitet oder in
//    Unzustellbarkeitsberichten) werden nach denselben Regeln aufgelöst.
//    Zustellberichte (`message/delivery-status` u. Ä.) gelten als Text.
//
//  Die Verarbeitung ist tolerant: Fehlt eine Grenze, ist eine Mail
//  abgeschnitten oder lässt sich Base64 nicht dekodieren, bleibt der
//  betroffene Inhalt wie übertragen stehen. Zeilen werden als UTF-8
//  gelesen, sonst als ISO-8859-1 (alte Mails mit 8-Bit-Kopfzeilen).
//  Zeilenenden erscheinen einheitlich als Zeilenumbruch.
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Abruf vom Server → RawMessageService; Anzeige →
//  RawSourceView.
//
//  Abhängigkeiten: Foundation, SwiftMail (`decodeMIMEHeader` für
//  Dateinamen).
//

import Foundation
import SwiftMail

/// Aufbereitung der Rohdaten einer Mail als lesbarer Text.
nonisolated enum RawMessageFormatter {

    /// Kennzeile vor einem dekodierten Base64-Inhalt.
    static let decodedMarker = "[Base64 dekodiert]"

    /// Höchste Verschachtelungstiefe; tiefer liegende Teile bleiben wie
    /// übertragen (Schutz vor unsinnig verschachtelten Mails).
    static let maxDepth = 20

    /// Bereitet die Rohdaten einer Mail auf.
    ///
    /// Verarbeitung: Zerlegt die Daten in Zeilen und gibt die Mail als
    /// Ganzes nach den Regeln im Dateikopf aus.
    ///
    /// - Parameter data: Rohdaten der Mail (RFC 822).
    /// - Returns: Lesbarer Text, Zeilen durch „\n“ getrennt.
    static func format(_ data: Data) -> String {
        var output: [String] = []
        render(entity: lines(of: data)[...], depth: 0, into: &output)
        return output.joined(separator: "\n")
    }

    /// Zeile für eine ausgelassene Anlage.
    ///
    /// - Parameters:
    ///   - name: Dateiname oder – ohne Namen – der MIME-Typ.
    ///   - byteCount: Größe des Inhalts in Bytes.
    /// - Returns: z. B. „[Anlage ausgelassen: Rechnung.pdf, 1,2 MB]“.
    static func omittedLine(name: String, byteCount: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        return "[Anlage ausgelassen: \(name), \(size)]"
    }

    // MARK: - Zeilen

    /// Zerlegt Rohdaten in Zeilen.
    ///
    /// Verarbeitung: Trennt an LF, entfernt ein CR am Zeilenende; jede
    /// Zeile wird als UTF-8 gelesen, sonst als ISO-8859-1. So verdirbt
    /// eine einzelne fehlerhafte Zeile nicht die ganze Mail.
    ///
    /// - Parameter data: Rohdaten.
    /// - Returns: Zeilen ohne Zeilenende.
    static func lines(of data: Data) -> [String] {
        data.split(separator: 0x0A, omittingEmptySubsequences: false).map { line in
            let bytes = Data(line.last == 0x0D ? line.dropLast() : line)
            return String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .isoLatin1)
                ?? ""
        }
    }

    // MARK: - Teile

    /// Was mit dem Inhalt eines Teils geschieht.
    private enum BodyKind {
        /// Mehrteilig mit Grenze: Teile einzeln behandeln.
        case multipart(boundary: String)
        /// Eingebettete Mail: als Ganzes erneut behandeln.
        case message
        /// Text: anzeigen, Base64 dekodieren.
        case text
        /// Unverändert ausgeben (z. B. mehrteilig ohne Grenze).
        case verbatim
        /// Anlage: durch eine Zeile ersetzen.
        case omitted
    }

    /// Zustellberichte und Kopfzeilen-Teile, die als Text angezeigt werden.
    private static let textualMessageTypes: Set<String> = [
        "message/delivery-status",
        "message/global-delivery-status",
        "message/disposition-notification",
        "message/global-disposition-notification",
        "message/feedback-report",
        "message/global-headers"
    ]

    /// Gibt einen Teil (Kopfzeilen und Inhalt) aus.
    ///
    /// Verarbeitung: Kopfzeilen bis zur ersten Leerzeile unverändert; der
    /// Inhalt danach je nach Art des Teils.
    ///
    /// - Parameters:
    ///   - entity: Zeilen des Teils.
    ///   - depth: Verschachtelungstiefe.
    ///   - output: Ziel der Ausgabe.
    private static func render(entity: ArraySlice<String>, depth: Int, into output: inout [String]) {
        guard let separator = entity.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            // Nur Kopfzeilen, kein Inhalt.
            output.append(contentsOf: entity)
            return
        }
        let headerLines = entity[entity.startIndex..<separator]
        let body = entity[(separator + 1)...]
        output.append(contentsOf: headerLines)
        output.append(entity[separator])

        let header = PartHeader(lines: headerLines)
        switch kind(of: header) {
        case .multipart(let boundary):
            renderMultipart(body, boundary: boundary, depth: depth, into: &output)
        case .message:
            renderEmbeddedMessage(body, header: header, depth: depth, into: &output)
        case .text:
            renderText(body, header: header, into: &output)
        case .verbatim:
            output.append(contentsOf: body)
        case .omitted:
            output.append(omittedLine(for: body, header: header))
        }
    }

    /// Ordnet einen Teil ein.
    ///
    /// - Parameter header: Kopfzeilen des Teils.
    /// - Returns: Art der Behandlung.
    private static func kind(of header: PartHeader) -> BodyKind {
        let type = header.mimeType
        if type.hasPrefix("multipart/") {
            guard let boundary = header.parameter("boundary", of: "content-type"), !boundary.isEmpty else {
                return .verbatim
            }
            return .multipart(boundary: boundary)
        }
        if type == "message/rfc822" || type == "message/global" {
            return .message
        }
        let isTextual = type.hasPrefix("text/") || textualMessageTypes.contains(type)
        return isTextual && !header.isAttachment ? .text : .omitted
    }

    /// Gibt einen mehrteiligen Inhalt aus.
    ///
    /// Verarbeitung: Präambel, Grenzen und Epilog unverändert; jeder Teil
    /// zwischen zwei Grenzen wird für sich behandelt. Fehlt die
    /// Schlussgrenze (abgeschnittene Mail), wird der letzte Teil trotzdem
    /// ausgegeben.
    ///
    /// - Parameters:
    ///   - body: Zeilen des Inhalts.
    ///   - boundary: Grenze aus dem Content-Type.
    ///   - depth: Verschachtelungstiefe.
    ///   - output: Ziel der Ausgabe.
    private static func renderMultipart(
        _ body: ArraySlice<String>,
        boundary: String,
        depth: Int,
        into output: inout [String]
    ) {
        let open = "--" + boundary
        let close = open + "--"
        var part: [String]?   // nil = noch in der Präambel
        var isClosed = false

        func flush() {
            guard let lines = part else { return }
            if depth < maxDepth {
                render(entity: lines[...], depth: depth + 1, into: &output)
            } else {
                output.append(contentsOf: lines)
            }
            part = nil
        }

        for line in body {
            if isClosed {
                output.append(line)   // Epilog
                continue
            }
            let trimmed = trimmingTrailingWhitespace(line)
            if trimmed == close {
                flush()
                output.append(line)
                isClosed = true
            } else if trimmed == open {
                flush()
                output.append(line)
                part = []
            } else if part != nil {
                part?.append(line)
            } else {
                output.append(line)   // Präambel
            }
        }
        if !isClosed { flush() }
    }

    /// Gibt eine eingebettete Mail aus.
    ///
    /// Verarbeitung: Ist sie Base64-kodiert, wird sie zuerst dekodiert und
    /// gekennzeichnet; danach gelten für sie dieselben Regeln wie für die
    /// Mail selbst.
    ///
    /// - Parameters:
    ///   - body: Zeilen des Inhalts.
    ///   - header: Kopfzeilen des Teils.
    ///   - depth: Verschachtelungstiefe.
    ///   - output: Ziel der Ausgabe.
    private static func renderEmbeddedMessage(
        _ body: ArraySlice<String>,
        header: PartHeader,
        depth: Int,
        into output: inout [String]
    ) {
        var lines = Array(body)
        if header.isBase64, let data = base64Data(body) {
            output.append(decodedMarker)
            lines = Self.lines(of: data)
        }
        if depth < maxDepth {
            render(entity: lines[...], depth: depth + 1, into: &output)
        } else {
            output.append(contentsOf: lines)
        }
    }

    /// Gibt einen Textteil aus; Base64 wird im Zeichensatz des Teils
    /// dekodiert und gekennzeichnet.
    ///
    /// - Parameters:
    ///   - body: Zeilen des Inhalts.
    ///   - header: Kopfzeilen des Teils.
    ///   - output: Ziel der Ausgabe.
    private static func renderText(_ body: ArraySlice<String>, header: PartHeader, into output: inout [String]) {
        guard header.isBase64, let data = base64Data(body) else {
            output.append(contentsOf: body)
            return
        }
        let text = decodeText(data, charset: header.parameter("charset", of: "content-type"))
        output.append(decodedMarker)
        output.append(contentsOf: text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n"))
    }

    /// Zeile für eine ausgelassene Anlage aus ihren Kopfzeilen und ihrem
    /// Inhalt.
    ///
    /// - Parameters:
    ///   - body: Zeilen des Inhalts.
    ///   - header: Kopfzeilen des Teils.
    /// - Returns: Ersatzzeile mit Name (bzw. MIME-Typ) und Größe.
    private static func omittedLine(for body: ArraySlice<String>, header: PartHeader) -> String {
        let byteCount: Int
        if header.isBase64, let data = base64Data(body) {
            byteCount = data.count
        } else {
            byteCount = body.reduce(0) { $0 + $1.utf8.count + 1 }
        }
        return omittedLine(name: header.filename ?? header.mimeType, byteCount: byteCount)
    }

    // MARK: - Dekodierung

    /// Dekodiert Base64-Zeilen.
    ///
    /// - Parameter body: Zeilen des Inhalts.
    /// - Returns: Daten; `nil`, wenn der Inhalt kein gültiges Base64 ist.
    private static func base64Data(_ body: ArraySlice<String>) -> Data? {
        Data(base64Encoded: body.joined(), options: .ignoreUnknownCharacters)
    }

    /// Wandelt Daten im angegebenen Zeichensatz in Text.
    ///
    /// Verarbeitung: Unbekannter oder fehlender Zeichensatz → UTF-8; passt
    /// auch das nicht, ISO-8859-1 (liefert immer ein Ergebnis).
    ///
    /// - Parameters:
    ///   - data: Dekodierte Daten.
    ///   - charset: Zeichensatz aus dem Content-Type, z. B. „utf-8“.
    /// - Returns: Text.
    static func decodeText(_ data: Data, charset: String?) -> String {
        if let charset, let encoding = encoding(forCharset: charset),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    /// Bestimmt die Zeichenkodierung zu einem IANA-Namen.
    ///
    /// - Parameter charset: z. B. „iso-8859-15“.
    /// - Returns: Kodierung; `nil`, wenn unbekannt.
    private static func encoding(forCharset charset: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    /// Entfernt Leerraum am Zeilenende (Grenzen dürfen ihn haben).
    ///
    /// - Parameter line: Zeile.
    /// - Returns: Zeile ohne Leerraum am Ende.
    private static func trimmingTrailingWhitespace(_ line: String) -> String {
        var result = Substring(line)
        while let last = result.last, last == " " || last == "\t" {
            result = result.dropLast()
        }
        return String(result)
    }
}

// MARK: - Kopfzeilen eines Teils

/// Ausgewertete Kopfzeilen eines Teils (nur für die Einordnung; ausgegeben
/// werden immer die Originalzeilen).
nonisolated private struct PartHeader {
    /// Felder in Reihenfolge: Name klein geschrieben, Wert entfaltet.
    private let fields: [(name: String, value: String)]

    /// Wertet Kopfzeilen aus.
    ///
    /// Verarbeitung: Folgezeilen (beginnend mit Leerzeichen oder Tab)
    /// werden an das vorige Feld angehängt; Zeilen ohne Doppelpunkt
    /// werden übergangen.
    ///
    /// - Parameter lines: Kopfzeilen des Teils.
    init(lines: ArraySlice<String>) {
        var fields: [(name: String, value: String)] = []
        for line in lines {
            if let first = line.first, first == " " || first == "\t", !fields.isEmpty {
                fields[fields.count - 1].value += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                fields.append((name, value))
            }
        }
        self.fields = fields
    }

    /// Wert des ersten Felds mit diesem Namen.
    ///
    /// - Parameter name: Feldname, klein geschrieben.
    /// - Returns: Wert; `nil`, wenn das Feld fehlt.
    func value(_ name: String) -> String? {
        fields.first { $0.name == name }?.value
    }

    /// MIME-Typ klein geschrieben; ohne Content-Type „text/plain“.
    var mimeType: String {
        let type = value("content-type")?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""
        return type.isEmpty ? "text/plain" : type
    }

    /// `true`, wenn der Inhalt Base64-kodiert ist.
    var isBase64: Bool {
        value("content-transfer-encoding")?.trimmingCharacters(in: .whitespaces).lowercased() == "base64"
    }

    /// `true` bei Disposition „attachment“ oder vorhandenem Dateinamen.
    var isAttachment: Bool {
        let disposition = value("content-disposition")?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return disposition == "attachment" || filename != nil
    }

    /// Dateiname aus Content-Disposition („filename“) oder Content-Type
    /// („name“), MIME-kodierte Namen dekodiert.
    var filename: String? {
        let raw = parameter("filename", of: "content-disposition")
            ?? parameter("name", of: "content-type")
        guard let raw, !raw.isEmpty else { return nil }
        return raw.decodeMIMEHeader()
    }

    /// Parameter eines Felds, z. B. `boundary` aus dem Content-Type.
    ///
    /// Verarbeitung: Erkennt `name=wert`, `name="wert"` und die Form nach
    /// RFC 2231 `name*=zeichensatz''prozent%20kodiert`. Groß- und
    /// Kleinschreibung des Parameternamens spielen keine Rolle.
    ///
    /// - Parameters:
    ///   - name: Parametername, z. B. „charset“.
    ///   - field: Feldname, klein geschrieben.
    /// - Returns: Wert ohne Anführungszeichen; `nil`, wenn er fehlt.
    func parameter(_ name: String, of field: String) -> String? {
        guard let value = value(field) else { return nil }
        let pattern = #"(?:^|;)\s*"# + NSRegularExpression.escapedPattern(for: name)
            + #"(\*)?\s*=\s*("(?:[^"\\]|\\.)*"|[^;]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let valueRange = Range(match.range(at: 2), in: value) else {
            return nil
        }
        var result = value[valueRange].trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("\""), result.hasSuffix("\""), result.count >= 2 {
            result = String(result.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        }
        let isExtended = match.range(at: 1).location != NSNotFound
        if isExtended, let marker = result.range(of: "''") {
            let encoded = String(result[marker.upperBound...])
            result = encoded.removingPercentEncoding ?? encoded
        }
        return result
    }
}
