//
//  SpamMark.swift
//  Mailwerk
//
//  Zweck: Kurzer Text zur Spam-Einschätzung einer Mail, in zwei
//  Darstellungen:
//
//  Mailliste (`.list`) – nur die Warnung, ohne Score:
//  - `[SPAM]`             – Gesamtergebnis Spam
//  - nichts               – sonst
//
//  Mailansicht (`.detail`) – mit Erklärung:
//  - `[SPAM score=7.2]`   – Spam, Score geliefert
//  - `[SPAM]`             – Spam, kein Score
//  - `[NoSpam score=2.1]` – kein Spam, Score geliefert
//  - `[NoSpam]`           – kein Spam, ohne Score, aber bewusst durch die
//                           Whitelist behalten
//  - nichts               – kein Spam, kein Score, kein Whitelist-Treffer
//
//  „NoSpam“ in gemischter Schreibweise wirkt bewusst nicht wie eine
//  Warnung. Gesamtergebnis heißt: dieselbe Regel wie beim Spamfilter
//  (SpamClassifier.classify) aus den aktuellen Listen und dem beim Abruf
//  gespeicherten Befund des Servers. Die Anzeige folgt damit späteren
//  Listenänderungen; verschoben wird dadurch nichts.
//
//  Score mit einer Nachkommastelle und Punkt, wie in der Kopfzeile.
//
//  Reine Logik, deshalb `nonisolated`; vollständig per Unit-Test abgedeckt.
//
//  Abgrenzung: Entscheidung → SpamClassifier; Auslesen der Kopfzeilen →
//  SpamHeaderParser; Darstellung → MessageRow, MessageDetailHeader.
//
//  Abhängigkeiten: Foundation, SpamClassifier, SpamHeaderVerdict,
//  FilterAddress, FilterLists.
//

import Foundation

/// Text zur Spam-Einschätzung einer Mail.
nonisolated enum SpamMark {

    /// Darstellung des Texts.
    enum Style: Equatable, Sendable {
        /// Mailliste: nur `[SPAM]`.
        case list
        /// Mailansicht: mit Score und `[NoSpam]`.
        case detail
    }

    /// Text aus Gesamtergebnis, Score und Whitelist-Entscheidung.
    ///
    /// - Parameters:
    ///   - isSpam: Gesamtergebnis ist Spam.
    ///   - score: Score des Servers; `nil` = keiner geliefert.
    ///   - keptByWhitelist: Die Whitelist hat die Mail bewusst behalten.
    ///   - style: Mailliste oder Mailansicht.
    /// - Returns: Anzeigetext oder `nil`, wenn nichts anzuzeigen ist.
    static func text(isSpam: Bool, score: Double?, keptByWhitelist: Bool, style: Style) -> String? {
        if style == .list {
            return isSpam ? "[SPAM]" : nil
        }
        let scoreText = score.map { "score=\(String(format: "%.1f", $0))" }
        switch (isSpam, scoreText) {
        case (true, let scoreText?): return "[SPAM \(scoreText)]"
        case (true, nil): return "[SPAM]"
        case (false, let scoreText?): return "[NoSpam \(scoreText)]"
        case (false, nil): return keptByWhitelist ? "[NoSpam]" : nil
        }
    }

    /// Text für eine Mail aus Absender, gespeichertem Befund und Listen.
    ///
    /// Verarbeitung: Gesamtergebnis wie beim Spamfilter; Spam ist jede
    /// Entscheidung außer „behalten“. Ohne gespeicherten Befund (z. B.
    /// Treffer der Serversuche) zählt allein die Whitelist: In der
    /// Mailansicht erscheint dann `[NoSpam]`, sonst nichts.
    ///
    /// - Parameters:
    ///   - sender: Absender; `nil`, wenn er sich nicht auswerten lässt.
    ///   - verdict: Gespeicherter Befund des Servers; `nil` = unbekannt.
    ///   - rules: Black- und Whitelist samt Score-Obergrenze.
    ///   - style: Mailliste oder Mailansicht.
    /// - Returns: Anzeigetext oder `nil`.
    static func text(
        sender: FilterAddress?,
        verdict: SpamHeaderVerdict?,
        rules: SpamRules,
        style: Style
    ) -> String? {
        let whitelisted = sender.map { SpamClassifier.isWhitelisted($0, in: rules.lists) } ?? false
        guard let verdict else {
            return text(isSpam: false, score: nil, keptByWhitelist: whitelisted, style: style)
        }
        let decision = SpamClassifier.classify(
            sender: sender, verdict: verdict, lists: rules.lists, scoreLimit: rules.scoreLimit
        )
        let isSpam = decision != .keep
        return text(isSpam: isSpam, score: verdict.score, keptByWhitelist: whitelisted && !isSpam, style: style)
    }
}
