//
//  RawSourceSearch.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.10.2026
//  Geändert: 18.10.2026
//
//  Zweck: Einfache Suche im Blatt „Originalquelle“ – findet alle Stellen
//  eines Begriffs, Worts oder Satzes im Text, ohne Rücksicht auf Groß- und
//  Kleinschreibung, und bestimmt den nächsten Treffer für „Weiter“. Nach
//  dem letzten Treffer geht es wieder beim ersten los.
//
//  Gesucht wird genau die Eingabe, wie sie dasteht (auch Leerzeichen
//  zählen mit), keine Platzhalter und kein Wortanfang. Die Treffer kommen
//  als `NSRange`, weil die Textansicht (UITextView/NSTextView) damit
//  markiert und scrollt.
//
//  Abgrenzung: Eingabefeld, Markierung und Scrollen → RawSourceView.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Suche im Text der Originalquelle.
enum RawSourceSearch {

    /// Alle Fundstellen eines Suchbegriffs, ohne Rücksicht auf Groß- und
    /// Kleinschreibung.
    ///
    /// Verarbeitung: Ein leerer Begriff ergibt keine Treffer. Treffer
    /// überlappen nicht – nach einem Fund geht die Suche hinter ihm weiter.
    ///
    /// - Parameters:
    ///   - query: Suchbegriff, unverändert übernommen.
    ///   - text: Durchsuchter Text.
    /// - Returns: Fundstellen in Textreihenfolge.
    static func matches(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let source = text as NSString
        var result: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let found = source.range(of: query, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            result.append(found)
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: source.length - next)
        }
        return result
    }

    /// Index des nächsten Treffers für „Weiter“.
    ///
    /// - Parameters:
    ///   - current: Bisher gezeigter Treffer; `nil` = noch keiner.
    ///   - count: Anzahl der Treffer.
    /// - Returns: Nächster Index, nach dem letzten wieder `0`; `nil` ohne
    ///   Treffer.
    static func nextIndex(after current: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return 0 }
        return (current + 1) % count
    }
}
