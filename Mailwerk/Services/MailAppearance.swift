//
//  MailAppearance.swift
//  Mailwerk
//
//  Zweck: Entscheidet, ob eine HTML-Mail im Dunkelmodus hell dargestellt
//  wird. Regel wie in Apple Mail: Bringt die Mail eigene Farben mit
//  (Hintergrund oder Schriftfarbe), bleibt sie hell – weißer Grund, dunkle
//  Standardschrift. Nur Mails ohne eigene Farben folgen dem Dunkelmodus.
//
//  Hintergrund: Das Grundgerüst färbt die Schrift im Dunkelmodus hell. Hat
//  eine Mail einen eigenen weißen Hintergrund, aber keine eigene
//  Schriftfarbe, stand dann hellgraue Schrift auf Weiß. Umgekehrt kann
//  eine Mail mit eigener dunkler Schrift auf dem dunklen App-Hintergrund
//  unlesbar werden. Beides vermeidet die helle Darstellung.
//
//  Erkannt wird per einfacher Textsuche im HTML, ohne Parser und ohne das
//  HTML zu verändern:
//  - Attribute `bgcolor=`, `background=`, `<font … color=`, `<body … text=`
//  - CSS-Eigenschaften `color:`, `background:` und `background-color:`
//    (inline oder im `<style>`-Block); `border-color:` u. Ä. zählen nicht.
//  Ein Fehlalarm (z. B. „color:“ im Fließtext) stellt die Mail nur hell
//  dar – unschädlich für die Lesbarkeit.
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Grundgerüst und Darstellung → HTMLMailView; Druck und
//  Teilen sind immer hell → MailPrintFormatter.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Regel für die Darstellung von HTML-Mails im Dunkelmodus.
nonisolated enum MailAppearance {

    /// Muster für eigene Farben einer Mail.
    private static let ownColorPattern = [
        #"\bbgcolor\s*="#,
        #"(?<![\w-])background\s*="#,
        #"<font\b[^>]*\bcolor\s*="#,
        #"<body\b[^>]*\btext\s*="#,
        #"(?<![\w-])color\s*:"#,
        #"(?<![\w-])background(?:-color)?\s*:"#
    ].joined(separator: "|")

    /// Übersetzter Ausdruck; einmal erzeugt, weil er bei jedem Öffnen
    /// einer Mail gebraucht wird.
    private static let ownColorRegex = try? NSRegularExpression(
        pattern: ownColorPattern,
        options: [.caseInsensitive]
    )

    /// Prüft, ob eine HTML-Mail eigene Farben mitbringt.
    ///
    /// Verarbeitung: Sucht die erste Farbangabe für Hintergrund oder
    /// Schrift. Lässt sich der Ausdruck nicht übersetzen, gilt die Mail als
    /// „mit eigenen Farben“ – sie bleibt dann hell und damit lesbar.
    ///
    /// - Parameter html: HTML-Teil der Mail.
    /// - Returns: `true`, wenn die Mail hell dargestellt werden soll.
    static func usesOwnColors(_ html: String) -> Bool {
        guard let regex = ownColorRegex else { return true }
        let range = NSRange(html.startIndex..., in: html)
        return regex.firstMatch(in: html, range: range) != nil
    }
}
