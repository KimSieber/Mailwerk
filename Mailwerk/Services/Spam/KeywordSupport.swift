//
//  KeywordSupport.swift
//  Mailwerk
//
//  Zweck: Entscheidet, ob ein IMAP-Server in einem Ordner eigene
//  Schlüsselwörter (Keywords wie `$MailwerkChecked`) dauerhaft speichert.
//
//  Hintergrund: Der Server meldet beim Öffnen eines Ordners in
//  `PERMANENTFLAGS`, welche Kennzeichen er dauerhaft speichert. Steht dort
//  `\*`, darf der Client eigene Schlüsselwörter anlegen (RFC 3501). Outlook
//  (Exchange Online) meldet z. B. nur
//  `(\Seen \Answered \Flagged \Deleted \Draft $MDNSent)` und lehnt eine
//  Suche nach eigenen Schlüsselwörtern ab („BAD Command Argument“).
//
//  Regeln:
//  - Keine Angabe (leere Liste): der Server hat `PERMANENTFLAGS` nicht
//    gemeldet – laut RFC gelten dann alle Kennzeichen als dauerhaft; das
//    bisherige Verhalten bleibt.
//  - `\*` erlaubt jedes eigene Schlüsselwort. SwiftMail meldet es als
//    eigenes Kennzeichen „wildcard“; beide Schreibweisen zählen.
//  - Sonst nur ausdrücklich genannte Schlüsselwörter (ohne Beachtung der
//    Groß-/Kleinschreibung).
//
//  Abgrenzung: Verwendung → SpamFilterService.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Prüfung, ob ein Ordner eigene Schlüsselwörter speichert.
nonisolated enum KeywordSupport {

    /// Namen, unter denen `\*` in den Kennzeichen erscheinen kann.
    private static let wildcardNames: Set<String> = ["\\*", "wildcard"]

    /// Prüft, ob ein Schlüsselwort dauerhaft gespeichert werden kann.
    ///
    /// - Parameters:
    ///   - keyword: Schlüsselwort, z. B. `$MailwerkChecked`.
    ///   - permanentFlags: Gemeldete `PERMANENTFLAGS` als Namen (eigene
    ///     Kennzeichen mit ihrem Namen, `\*` als „wildcard“ oder „\*“).
    /// - Returns: `true`, wenn der Server das Schlüsselwort speichert.
    static func allows(_ keyword: String, permanentFlags: [String]) -> Bool {
        guard !permanentFlags.isEmpty else { return true }
        let names = Set(permanentFlags.map { $0.lowercased() })
        if !names.isDisjoint(with: wildcardNames) { return true }
        return names.contains(keyword.lowercased())
    }
}
