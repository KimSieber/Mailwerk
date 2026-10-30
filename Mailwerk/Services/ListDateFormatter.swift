//
//  ListDateFormatter.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 11.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Datum einer Mail in der Mailliste – heute nur die Uhrzeit
//  („17:06“), sonst Wochentag, volles Datum mit vierstelliger Jahreszahl
//  und Uhrzeit („Mo, 28.09.2026 17:06“). Für die Apple Watch eine Kurzform
//  ohne Jahr und Uhrzeit („Mo, 28.09.“).
//
//  Die Wochentage stehen als feste Kürzel ohne Punkt in einer Liste; die
//  Kürzel der Systemformate („Mo.“) weichen davon ab. Zahlenteil und
//  Uhrzeit kommen aus einem festen Format, unabhängig von den
//  Spracheinstellungen des Geräts.
//
//  „Jetzt“ und Kalender sind Parameter, damit die Tests ohne echte
//  Uhrzeit auskommen.
//
//  Abgrenzung: Anzeige → MessageRow, WatchMailRow.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Datumsformat der Mailliste.
enum ListDateFormatter {

    /// Wochentagskürzel in der Reihenfolge von `Calendar.component(.weekday)`
    /// (1 = Sonntag).
    private static let weekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    /// Formatiert ein Datum für die Mailliste.
    ///
    /// Verarbeitung: Liegt das Datum am selben Kalendertag wie `now`, nur
    /// die Uhrzeit; sonst – auch für Daten in der Zukunft – Wochentag,
    /// Datum und Uhrzeit.
    ///
    /// - Parameters:
    ///   - date: Datum der Mail.
    ///   - now: Bezugszeitpunkt; Standard ist die aktuelle Zeit.
    ///   - calendar: Kalender samt Zeitzone; Standard ist der des Geräts.
    /// - Returns: Anzeigetext.
    static func string(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let time = formatted(date, pattern: "HH:mm", calendar: calendar)
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        let weekday = weekdays[calendar.component(.weekday, from: date) - 1]
        let day = formatted(date, pattern: "dd.MM.yyyy", calendar: calendar)
        return "\(weekday), \(day) \(time)"
    }

    /// Kurzform für schmale Anzeigen (Apple Watch).
    ///
    /// Verarbeitung: Am selben Kalendertag wie `now` nur die Uhrzeit, sonst
    /// Wochentag und Tag.Monat – ohne Jahr und Uhrzeit.
    ///
    /// - Parameters:
    ///   - date: Datum der Mail.
    ///   - now: Bezugszeitpunkt; Standard ist die aktuelle Zeit.
    ///   - calendar: Kalender samt Zeitzone; Standard ist der des Geräts.
    /// - Returns: Anzeigetext, z. B. „14:32“ oder „Mo, 12.10.“.
    static func compactString(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard !calendar.isDate(date, inSameDayAs: now) else {
            return formatted(date, pattern: "HH:mm", calendar: calendar)
        }
        let weekday = weekdays[calendar.component(.weekday, from: date) - 1]
        return "\(weekday), \(formatted(date, pattern: "dd.MM.", calendar: calendar))"
    }

    /// Bereits angelegte Formatierer je Muster und Zeitzone. Das Anlegen
    /// eines `DateFormatter` ist teuer, die Liste formatiert bei jedem
    /// Neuaufbau viele Zeilen.
    private static var formatters: [String: DateFormatter] = [:]

    /// Wendet ein festes Datumsmuster an.
    ///
    /// Verarbeitung: Gregorianische Ziffern über `en_US_POSIX`, damit
    /// Geräteeinstellungen (z. B. 12-Stunden-Anzeige) das Muster nicht
    /// verändern; Zeitzone aus dem übergebenen Kalender. Der Formatierer
    /// wird je Muster und Zeitzone nur einmal angelegt.
    ///
    /// - Parameters:
    ///   - date: Datum.
    ///   - pattern: Muster, z. B. `dd.MM.yyyy`.
    ///   - calendar: Kalender mit Zeitzone.
    /// - Returns: Formatierter Text.
    private static func formatted(_ date: Date, pattern: String, calendar: Calendar) -> String {
        let key = "\(pattern)|\(calendar.timeZone.identifier)"
        if let formatter = formatters[key] {
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        formatters[key] = formatter
        return formatter.string(from: date)
    }
}
