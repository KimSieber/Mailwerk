//
//  HTMLEscaping.swift
//  Mailwerk
//
//  Zweck: Maskiert Text für HTML – eine einzige Regel für alle Stellen, die
//  Text in HTML einsetzen (Antwort-Zitat, Druck/Teilen, Textteile beim
//  Zusammensetzen einer Mail, Editor-Ausgabe, Link-Ziele).
//
//  Maskiert werden `&`, `<`, `>`, `"` und `'`. Die Anführungszeichen sind
//  nur in Attributwerten nötig, schaden im Fließtext aber nicht – so gilt
//  dieselbe Funktion für beides, und keine Stelle kann versehentlich die
//  schwächere Variante nehmen (Code-Review v0.3.1, Regel 2: bisher drei
//  Fassungen mit unterschiedlichem Zeichenumfang).
//
//  Reine Funktion, deshalb `nonisolated`.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Maskierung von Text für HTML.
nonisolated enum HTMLEscaping {

    /// Maskiert `&`, `<`, `>`, `"` und `'` für HTML (Text und Attributwerte).
    ///
    /// Verarbeitung: `&` zuerst, damit bereits erzeugte Entitäten nicht
    /// doppelt maskiert werden.
    ///
    /// - Parameter text: Rohtext.
    /// - Returns: Maskierter Text.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
