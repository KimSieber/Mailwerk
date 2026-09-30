//
//  IMAPLineConnection.swift
//  Mailwerk
//
//  Verschlüsselter, zeilenweiser Transport für `FolderDeletion` – der
//  einzige IMAP-Weg außerhalb von SwiftMail (Rückbau siehe dort).
//
//  Sicherheitsregeln wie in `MailServerFactory`:
//  - nur TLS ab dem ersten Byte (Port 993); STARTTLS wird bewusst nicht
//    unterstützt, der Aufrufer lehnt andere Ports vorher ab
//  - Mindestversion TLS 1.2
//  - Zertifikatsprüfung durch das System (Vertrauenskette und Hostname),
//    nichts wird abgeschaltet
//  - kein Protokollieren von Zeilen: Die Anmeldezeile enthält Zugangsdaten
//
//  Ohne Netz (Zustand `.waiting`) scheitert der Aufbau sofort, statt zu
//  warten. `close()` bricht auch laufende Lesevorgänge ab.
//

import Foundation
import Network

nonisolated final class IMAPLineConnection: IMAPLineChannel, @unchecked Sendable {

    enum ConnectionError: LocalizedError {
        case invalidPort
        case closed
        case lineTooLong

        var errorDescription: String? {
            switch self {
            case .invalidPort: return "Ungültiger Port."
            case .closed:      return "Die Verbindung zum Server wurde getrennt."
            case .lineTooLong: return "Der Server hat eine unerwartet lange Antwort gesendet."
            }
        }
    }

    /// Schutz vor unbegrenztem Speicherbedarf durch eine endlose Zeile.
    private static let maxLineLength = 64 * 1024

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "de.sieber-bw.Mailwerk.IMAPLineConnection")

    /// Nur auf `queue` gelesen und geschrieben.
    private var openContinuation: CheckedContinuation<Void, Error>?

    /// Empfangene, noch nicht gelesene Bytes. Nur aus `readLine()` heraus
    /// benutzt; der Aufrufer liest streng nacheinander.
    private var buffer = Data()

    init(host: String, port: Int) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port > 0 else {
            throw ConnectionError.invalidPort
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: NWParameters(tls: tls, tcp: tcp)
        )
    }

    deinit {
        connection.cancel()
    }

    // MARK: - Aufbau und Abbau

    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Beide Closures fangen `self` ausdrücklich schwach: Der Handler
            // bleibt an der Verbindung gespeichert, die `self` gehört – ein
            // starker Fang ergäbe einen Referenzzyklus.
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ConnectionError.closed)
                    return
                }
                self.openContinuation = continuation
                self.connection.stateUpdateHandler = { [weak self] state in
                    self?.handle(state)
                }
                self.connection.start(queue: self.queue)
            }
        }
    }

    /// Läuft auf `queue`.
    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            finishOpen(with: nil)
        case .failed(let error), .waiting(let error):
            finishOpen(with: error)
            connection.cancel()
        case .cancelled:
            finishOpen(with: ConnectionError.closed)
        default:
            break
        }
    }

    /// Läuft auf `queue`; setzt die Fortsetzung genau einmal fort.
    private func finishOpen(with error: Error?) {
        guard let continuation = openContinuation else { return }
        openContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    func close() {
        connection.cancel()
    }

    // MARK: - IMAPLineChannel

    func send(_ line: String) async throws {
        let data = Data((line + "\r\n").utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func readLine() async throws -> String {
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                var lineData = buffer[buffer.startIndex..<newline]
                if lineData.last == UInt8(ascii: "\r") { lineData = lineData.dropLast() }
                buffer.removeSubrange(buffer.startIndex...newline)
                return String(decoding: lineData, as: UTF8.self)
            }
            guard buffer.count <= Self.maxLineLength else { throw ConnectionError.lineTooLong }
            buffer.append(try await receiveChunk())
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ConnectionError.closed)
                }
            }
        }
    }
}
