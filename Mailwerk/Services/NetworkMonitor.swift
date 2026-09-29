//
//  NetworkMonitor.swift
//  Mailwerk
//
//  Meldet, ob das Gerät eine Netzverbindung hat. Ohne Netz versucht die
//  App keinen Abruf und zeigt keine Fehlermeldung; kommt das Netz zurück,
//  ruft die Mail-Liste ihre Ansicht selbst ab.
//

import Foundation
import Network
import Observation

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// `true`, solange ein Netzpfad besteht. Startet optimistisch mit
    /// `true`; der erste Befund des Systems folgt praktisch sofort.
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "de.sieber-bw.Mailwerk.NetworkMonitor")

    private init() {
        // Ausdrücklich @Sendable: Der Handler läuft auf `queue`, nicht auf
        // dem Main-Actor. Ohne die Angabe würde er unter der Standard-
        // Isolation dem Main-Actor zugerechnet – ein Aufruf aus der
        // Hintergrund-Queue bräche dann zur Laufzeit ab.
        //
        // `[weak self]` steht zusätzlich am Task: So erhält der Task eine
        // eigene, unveränderliche Kopie der schwachen Referenz, statt auf
        // die (veränderliche) Variable des äußeren Handlers zuzugreifen.
        // Das vermeidet die Warnung „Reference to captured var 'self' in
        // concurrently-executing code".
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.update(online: online)
            }
        }
        monitor.start(queue: queue)
    }

    private func update(online: Bool) {
        guard isOnline != online else { return }
        isOnline = online
        print(online ? "🌐 Netz verfügbar" : "📴 Kein Netz")
    }
}
