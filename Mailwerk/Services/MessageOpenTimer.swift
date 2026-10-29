//
//  MessageOpenTimer.swift
//  Mailwerk
//
//  Zweck: Misst, wie lange es vom Öffnen einer Mail dauert, bis ihr Inhalt
//  sichtbar ist („Mail sichtbar“, v0.2.3d). Die vorhandenen Messpunkte
//  „Mail aus Cache“ und „Mail öffnen“ decken nur Teilschritte ab; die
//  Web-Ansicht (Laden, Layout) fehlte bisher.
//
//  Ablauf: Der MessageDetailLoader startet die Messung beim Öffnen; die
//  Web-Ansicht (HTML-Mail, nach dem Laden) bzw. die Mailansicht (Textmail,
//  nach der Vorbereitung) beendet sie. Das Ergebnis erscheint in
//  Instruments als Abschnitt „Mail sichtbar“ und in der Konsole als
//  „⏱ Mail sichtbar: … ms“ – auch im Profile-Build.
//
//  Es läuft immer nur eine Messung: Wird eine neue Mail geöffnet, bevor
//  die vorige sichtbar war, wird die alte verworfen. Ein Ende für eine
//  andere Mail (oder ohne laufende Messung, z. B. Suchtreffer vom Server)
//  wird übergangen.
//
//  Abhängigkeiten: Log (Signposts, Konsole).
//

import Foundation
import os

/// Stoppuhr für „Mail öffnen bis Inhalt sichtbar“.
@MainActor
final class MessageOpenTimer {

    /// Gemeinsame Stoppuhr der App.
    static let shared = MessageOpenTimer()

    /// Laufende Messung.
    private struct Running {
        /// Gemessene Mail.
        let messageID: String
        /// Startzeitpunkt.
        let started: ContinuousClock.Instant
        /// Signpost-Abschnitt für Instruments.
        let interval: Log.MeasuredInterval
    }

    /// Laufende Messung; `nil` = keine.
    private var running: Running?

    /// `true`, solange eine Messung läuft.
    var isRunning: Bool { running != nil }

    /// Startet die Messung für eine Mail; eine laufende wird verworfen.
    ///
    /// - Parameter messageID: Cache-ID der geöffneten Mail.
    func start(messageID: String) {
        if let previous = running {
            Log.endInterval(previous.interval)
            Log.view.info("⏱ Messung verworfen (neue Mail geöffnet, bevor die vorige sichtbar war)")
        }
        running = Running(
            messageID: messageID,
            started: ContinuousClock.now,
            interval: Log.beginInterval(Log.Interval.messageVisible)
        )
    }

    /// Beendet die Messung, wenn sie zu dieser Mail gehört, und gibt die
    /// Dauer aus.
    ///
    /// - Parameter messageID: Cache-ID der sichtbar gewordenen Mail.
    /// - Returns: Gemessene Dauer; `nil`, wenn keine passende Messung lief.
    @discardableResult
    func finish(messageID: String) -> Duration? {
        guard let current = running, current.messageID == messageID else { return nil }
        running = nil
        Log.endInterval(current.interval)
        let elapsed = ContinuousClock.now - current.started
        let millis = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        Log.view.info("⏱ Mail sichtbar: \(millis) ms")
        return elapsed
    }
}
