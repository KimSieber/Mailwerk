//
//  NetworkMonitor.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 29.09.2026
//  Geändert: 10.10.2026
//
//  Zweck: Meldet, ob das Gerät eine Netzverbindung hat. Ohne Netz
//  versucht die App keinen Abruf und zeigt keine Fehlermeldung; kommt das
//  Netz zurück, ruft die Mail-Liste ihre Ansicht selbst ab.
//
//  In Debug-Builds wird jede Pfadänderung mit Status und Schnittstellen
//  protokolliert (Diagnose im Simulator).
//
//  Abgrenzung: Reaktion auf den Netzzustand → InboxView/InboxViewModel.
//
//  Abhängigkeiten: Network (NWPathMonitor), Log.
//

import Foundation
import Network
import Observation
import os

/// Netzzustand des Geräts.
@Observable
final class NetworkMonitor {
    /// Gemeinsame Instanz der App.
    static let shared = NetworkMonitor()

    /// `true`, solange ein Netzpfad besteht. Startet optimistisch mit
    /// `true`; der erste Befund des Systems folgt praktisch sofort.
    private(set) var isOnline = true

    /// Beobachter der Netzpfade.
    @ObservationIgnored private let monitor = NWPathMonitor()
    /// Queue, auf der der Beobachter meldet.
    @ObservationIgnored private let queue = DispatchQueue(label: "de.sieber-bw.Mailwerk.NetworkMonitor")

    /// Startet die Beobachtung der Netzpfade.
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
            let online = Self.isUsable(path)
            #if DEBUG
            let description = Self.describe(path, online: online)
            Log.fetch.debug("\(description, privacy: .public)")
            #endif
            Task { @MainActor [weak self] in
                self?.update(online: online)
            }
        }
        monitor.start(queue: queue)
    }

    /// Echte Internetverbindung nur über WLAN, Mobilfunk oder Kabel.
    ///
    /// `status == .satisfied` allein genügt nicht: Im Flugmodus bleibt bei
    /// gekoppelter Apple Watch eine Bluetooth-Verbindung bestehen, die das
    /// System als Netzpfad (Typ „other") meldet – ins Internet führt sie
    /// nicht. VPNs laufen über WLAN/Mobilfunk und werden über die
    /// darunterliegende Schnittstelle weiter erkannt (auf dem iPhone
    /// bestätigt: `en0`, `pdp_ip0` und `utun`).
    ///
    /// Simulator: Er meldet nur einen Tunnel des Macs (`utun`,
    /// Typ „other"), nie WLAN. Dort gilt deshalb jeder verbundene Pfad als
    /// online – es gibt keine Watch und kein Bluetooth-Netz. Außerdem meldet
    /// der Simulator Netzwechsel zur Laufzeit nicht zuverlässig: Für einen
    /// Offline-Test WLAN am Mac aus und die App neu starten.
    ///
    /// Die Regel gilt für iOS und macOS. Eine künftige watchOS-App braucht
    /// eine eigene Bewertung: Die Watch geht oft legitim über das gekoppelte
    /// iPhone per Bluetooth ins Netz.
    ///
    /// - Parameter path: Gemeldeter Netzpfad.
    /// - Returns: `true` bei nutzbarer Internetverbindung.
    nonisolated private static func isUsable(_ path: NWPath) -> Bool {
        guard path.status == .satisfied else { return false }
        #if targetEnvironment(simulator)
        return true
        #else
        let internetTypes: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet]
        return path.availableInterfaces.contains { internetTypes.contains($0.type) }
        #endif
    }

    #if DEBUG
    /// Diagnosezeile, z. B. „🌐 Netzpfad: satisfied · en0 (wifi) · Ergebnis: online“.
    /// Enthält nur Status und Schnittstellen, keine schützenswerten Daten.
    ///
    /// - Parameters:
    ///   - path: Gemeldeter Netzpfad.
    ///   - online: Ergebnis der Bewertung.
    /// - Returns: Diagnosezeile.
    nonisolated private static func describe(_ path: NWPath, online: Bool) -> String {
        let status: String
        switch path.status {
        case .satisfied:          status = "satisfied"
        case .unsatisfied:        status = "unsatisfied"
        case .requiresConnection: status = "requiresConnection"
        @unknown default:         status = "unbekannt"
        }
        let interfaces = path.availableInterfaces.map { "\($0.name) (\(typeName($0.type)))" }
        let list = interfaces.isEmpty ? "keine Schnittstelle" : interfaces.joined(separator: ", ")
        return "🌐 Netzpfad: \(status) · \(list) · Ergebnis: \(online ? "online" : "offline")"
    }

    /// Lesbarer Name eines Schnittstellentyps.
    ///
    /// - Parameter type: Schnittstellentyp.
    /// - Returns: Name für die Diagnose.
    nonisolated private static func typeName(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi:          return "wifi"
        case .cellular:      return "cellular"
        case .wiredEthernet: return "wiredEthernet"
        case .loopback:      return "loopback"
        case .other:         return "other"
        @unknown default:    return "unbekannt"
        }
    }
    #endif

    /// Übernimmt einen neuen Netzzustand und protokolliert Wechsel.
    ///
    /// - Parameter online: Neuer Zustand.
    private func update(online: Bool) {
        guard isOnline != online else { return }
        isOnline = online
        Log.fetch.info("\(online ? "🌐 Netz verfügbar" : "📴 Kein Netz", privacy: .public)")
    }
}
