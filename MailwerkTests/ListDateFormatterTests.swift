//
//  ListDateFormatterTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das Datumsformat der Mailliste (ListDateFormatter) –
//  heute nur Uhrzeit, sonst Wochentag, volles Datum und Uhrzeit.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct ListDateFormatterTests {

    /// Testhilfe: Kalender in Berliner Zeit.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Testhilfe: Zeitpunkt in Berliner Zeit.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Bezugszeitpunkt: Montag, 12.10.2026 10:00.
    private var now: Date { date(2026, 10, 12, 10, 0) }

    /// Heute: nur die Uhrzeit.
    @Test func todayShowsTimeOnly() {
        #expect(ListDateFormatter.string(for: date(2026, 10, 12, 7, 5), now: now, calendar: calendar) == "07:05")
    }

    /// Gestern: Wochentag, Datum mit vierstelligem Jahr und Uhrzeit.
    @Test func yesterdayShowsFullDate() {
        #expect(ListDateFormatter.string(for: date(2026, 10, 11, 17, 6), now: now, calendar: calendar) == "So, 11.10.2026 17:06")
    }

    /// Ältere Daten: ebenfalls voll, Wochentag ohne Punkt.
    @Test func olderDateShowsFullDate() {
        #expect(ListDateFormatter.string(for: date(2026, 9, 28, 8, 50), now: now, calendar: calendar) == "Mo, 28.09.2026 08:50")
    }

    /// Daten in der Zukunft (z. B. falsches Datum im Spam) werden voll angezeigt.
    @Test func futureDateShowsFullDate() {
        #expect(ListDateFormatter.string(for: date(2026, 10, 13, 9, 0), now: now, calendar: calendar) == "Di, 13.10.2026 09:00")
    }
}
