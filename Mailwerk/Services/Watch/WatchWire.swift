//
//  WatchWire.swift
//  Mailwerk
//
//  Zweck: Übertragungsform zwischen iPhone und Apple Watch – Kodieren
//  (binäre Property-List), Packen (LZFSE) und Stückeln.
//
//  Stückeln: Eine Nachricht über WatchConnectivity darf nur rund 64 KB
//  groß sein. Jede Lieferung wird deshalb gepackt und in Stücke von
//  höchstens `maxChunkSize` Byte geteilt. Das erste Stück kommt als
//  Antwort bzw. Nachricht, die übrigen holt die Watch einzeln
//  (`WatchRequest.chunk`). Eine Lieferung kann damit beliebig groß sein.
//
//  Reine Logik, deshalb `nonisolated`; vollständig per Unit-Test abgedeckt.
//
//  Abgrenzung: Inhalt der Lieferungen → WatchTransfer; Versand →
//  WatchBridge (iPhone) bzw. WatchConnector (Watch).
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Ein Stück einer gepackten Lieferung.
nonisolated struct WatchChunk: Codable, Equatable, Sendable {
    /// Kennung der Lieferung.
    let token: UUID
    /// Position des Stücks, ab 0.
    let index: Int
    /// Anzahl der Stücke der Lieferung.
    let count: Int
    /// Daten des Stücks.
    let data: Data
}

/// Fehler beim Entpacken.
nonisolated enum WatchWireError: Error, Equatable {
    /// Die Daten ließen sich nicht entpacken.
    case undecodable
}

/// Kodieren, Packen und Stückeln.
nonisolated enum WatchWire {

    /// Größte Datenmenge je Stück. Mit Rand unter der Grenze von
    /// WatchConnectivity (rund 64 KB je Nachricht).
    static let maxChunkSize = 48_000

    /// Kodiert einen Wert als binäre Property-List.
    ///
    /// - Parameter value: Wert.
    /// - Returns: Daten.
    /// - Throws: Fehler des Kodierers.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    /// Liest einen Wert aus einer binären Property-List.
    ///
    /// - Parameters:
    ///   - type: Erwarteter Typ.
    ///   - data: Daten.
    /// - Returns: Wert.
    /// - Throws: Fehler des Dekodierers.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try PropertyListDecoder().decode(type, from: data)
    }

    /// Kodiert und packt eine Lieferung.
    ///
    /// - Parameter payload: Lieferung.
    /// - Returns: Gepackte Daten.
    /// - Throws: Fehler beim Kodieren oder Packen.
    static func pack(_ payload: WatchPayload) throws -> Data {
        let raw = try encode(payload)
        return try (raw as NSData).compressed(using: .lzfse) as Data
    }

    /// Entpackt und liest eine Lieferung.
    ///
    /// - Parameter blob: Gepackte Daten.
    /// - Returns: Lieferung.
    /// - Throws: `WatchWireError.undecodable` oder Fehler des Dekodierers.
    static func unpack(_ blob: Data) throws -> WatchPayload {
        guard let raw = try? (blob as NSData).decompressed(using: .lzfse) as Data else {
            throw WatchWireError.undecodable
        }
        return try decode(WatchPayload.self, from: raw)
    }

    /// Teilt gepackte Daten in Stücke.
    ///
    /// Verarbeitung: Auch leere Daten ergeben ein (leeres) Stück, damit
    /// jede Lieferung mindestens eine Antwort hat.
    ///
    /// - Parameters:
    ///   - blob: Gepackte Daten.
    ///   - token: Kennung der Lieferung.
    ///   - maxSize: Größte Datenmenge je Stück.
    /// - Returns: Stücke in ihrer Reihenfolge.
    static func split(_ blob: Data, token: UUID, maxSize: Int = maxChunkSize) -> [WatchChunk] {
        let size = max(1, maxSize)
        let count = max(1, (blob.count + size - 1) / size)
        return (0..<count).map { index in
            let start = blob.startIndex + index * size
            let end = min(start + size, blob.endIndex)
            return WatchChunk(token: token, index: index, count: count, data: blob.subdata(in: start..<end))
        }
    }
}

/// Setzt die Stücke einer Lieferung wieder zusammen.
nonisolated struct WatchChunkAssembler: Sendable {
    /// Kennung der Lieferung.
    let token: UUID
    /// Anzahl der Stücke.
    let count: Int
    /// Bisher erhaltene Stücke je Position.
    private var parts: [Int: Data] = [:]

    /// Beginnt mit einem ersten erhaltenen Stück.
    ///
    /// - Parameter chunk: Beliebiges Stück der Lieferung.
    init(_ chunk: WatchChunk) {
        token = chunk.token
        count = chunk.count
        add(chunk)
    }

    /// Nimmt ein Stück auf. Stücke anderer Lieferungen und unpassende
    /// Positionen werden übergangen.
    ///
    /// - Parameter chunk: Stück.
    mutating func add(_ chunk: WatchChunk) {
        guard chunk.token == token, chunk.count == count,
              (0..<count).contains(chunk.index) else { return }
        parts[chunk.index] = chunk.data
    }

    /// Positionen, die noch fehlen, aufsteigend.
    var missing: [Int] {
        (0..<count).filter { parts[$0] == nil }
    }

    /// Die vollständigen Daten; `nil`, solange Stücke fehlen.
    var blob: Data? {
        guard missing.isEmpty else { return nil }
        var result = Data()
        for index in 0..<count {
            result.append(parts[index] ?? Data())
        }
        return result
    }
}
