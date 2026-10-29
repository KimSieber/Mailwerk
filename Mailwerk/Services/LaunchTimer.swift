//
//  LaunchTimer.swift
//  Mailwerk
//
//  Zweck: Misst die Zeit vom Start der App bis zur ersten angezeigten
//  Mailliste („Start bis Liste“, v0.2.3d, Prüfbericht P-18). Der Wert
//  „Liste aus Cache #1“ allein sagte darüber wenig: Er beginnt erst im
//  ViewModel und enthält das Warten auf den Hauptthread, der beim Start
//  noch mit dem Aufbau der Oberfläche beschäftigt ist.
//
//  Ablauf: `MailwerkApp.init` merkt den Startzeitpunkt (`markStart`); die
//  erste übernommene Liste meldet sich (`reportFirstList`). Ausgabe in
//  der Konsole „⏱ Start bis Liste: … ms“ (auch im Profile-Build), einmal
//  je Start.
//
//  Abhängigkeiten: Log.
//

import Foundation
import os

/// Zeit vom App-Start bis zur ersten Liste.
@MainActor
enum LaunchTimer {

    /// Startzeitpunkt; `nil`, solange nicht gemerkt.
    private static var started: ContinuousClock.Instant?
    /// `true`, sobald die erste Liste gemeldet wurde.
    private static var reported = false

    /// Merkt den Startzeitpunkt (einmal, in `MailwerkApp.init`).
    static func markStart() {
        if started == nil { started = ContinuousClock.now }
    }

    /// Meldet die erste übernommene Liste – nur beim ersten Aufruf.
    static func reportFirstList() {
        guard !reported, let started else { return }
        reported = true
        let elapsed = ContinuousClock.now - started
        let millis = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        Log.view.info("⏱ Start bis Liste: \(millis) ms")
    }
}
