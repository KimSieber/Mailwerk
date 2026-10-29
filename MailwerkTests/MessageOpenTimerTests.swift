//
//  MessageOpenTimerTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Stoppuhr „Mail sichtbar“ (MessageOpenTimer):
//  passendes Ende, fremdes Ende, Verwerfen bei neuer Mail.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für MessageOpenTimer.
@MainActor
struct MessageOpenTimerTests {

    /// Ende für dieselbe Mail liefert die Dauer und beendet die Messung.
    @Test("Ende für dieselbe Mail liefert eine Dauer")
    func finishesMatchingMessage() {
        let timer = MessageOpenTimer()
        timer.start(messageID: "a")
        #expect(timer.finish(messageID: "a") != nil)
        #expect(!timer.isRunning)
    }

    /// Ende für eine andere Mail wird übergangen.
    @Test("Ende für eine andere Mail wird übergangen")
    func ignoresOtherMessage() {
        let timer = MessageOpenTimer()
        timer.start(messageID: "a")
        #expect(timer.finish(messageID: "b") == nil)
        #expect(timer.isRunning)
    }

    /// Neue Mail verwirft die laufende Messung der vorigen.
    @Test("Neue Mail verwirft die vorige Messung")
    func restartDiscardsPrevious() {
        let timer = MessageOpenTimer()
        timer.start(messageID: "a")
        timer.start(messageID: "b")
        #expect(timer.finish(messageID: "a") == nil)
        #expect(timer.finish(messageID: "b") != nil)
    }

    /// Ohne laufende Messung passiert nichts.
    @Test("Ohne laufende Messung wird nichts gemeldet")
    func finishWithoutStart() {
        #expect(MessageOpenTimer().finish(messageID: "a") == nil)
    }
}
