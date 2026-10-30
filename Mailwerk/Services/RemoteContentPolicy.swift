//
//  RemoteContentPolicy.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 11.10.2026
//  Geändert: 11.10.2026
//
//  Zweck: Regeln für externe Inhalte in HTML-Mails (Bilder, Stylesheets,
//  Schriften, Medien von fremden Servern). Externe Inhalte verraten dem
//  Absender beim Laden Lesezeitpunkt und IP-Adresse (Tracking-Pixel).
//  Deshalb lädt Mailwerk sie nur nach ausdrücklicher Freigabe.
//
//  Zwei Bausteine:
//  - `headTags(allowsRemoteContent:)` liefert die Meta-Zeilen für den
//    Kopf eines HTML-Dokuments: eine Content-Security-Policy (CSP), die
//    der Browser selbst durchsetzt, und das Abschalten der DNS-Vorabfrage
//    für Links. Die CSP steht im Kopf vor dem Inhalt der Mail; eine
//    eigene CSP in der Mail kann sie nur weiter einschränken, nie
//    aufheben. Skripte, Frames, Formulare und `<base>` bleiben in beiden
//    Stufen verboten – die Freigabe betrifft nur Bilder, Stile, Schriften
//    und Medien.
//  - `containsRemoteReferences(_:)` erkennt, ob eine Mail überhaupt
//    externe Inhalte enthält, damit der Knopf zum Laden nur dann
//    erscheint. Die Erkennung entscheidet nur über die Anzeige des Knopfs;
//    geschützt wird allein durch die CSP. Ein Fehlalarm blendet den Knopf
//    unnötig ein, schwächt den Schutz aber nicht.
//
//  Eingebettete Bilder als `data:`-URL sind in beiden Stufen erlaubt; sie
//  kommen ohne Netzzugriff aus.
//
//  Abgrenzung: Anzeige → HTMLMailView; Druck und Teilen →
//  MailPrintFormatter; Freigabe je Mail → MessageDetailView.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Regeln für externe Inhalte in HTML-Mails.
nonisolated enum RemoteContentPolicy {

    /// CSP ohne externe Inhalte: nur eingebettete Bilder, Schriften und
    /// Medien (`data:`) sowie Stile aus der Mail selbst.
    static let blockedPolicy =
        "default-src 'none'; img-src data:; style-src 'unsafe-inline'; "
        + "font-src data:; media-src data:; form-action 'none'; base-uri 'none'"

    /// CSP nach Freigabe: zusätzlich Bilder, Stile, Schriften und Medien
    /// über http und https. Skripte und Frames bleiben verboten.
    static let allowedPolicy =
        "default-src 'none'; img-src data: https: http:; "
        + "style-src 'unsafe-inline' https: http:; font-src data: https: http:; "
        + "media-src data: https: http:; form-action 'none'; base-uri 'none'"

    /// Meta-Zeilen für den Kopf eines HTML-Dokuments.
    ///
    /// Verarbeitung: CSP je nach Freigabe; die DNS-Vorabfrage für Links ist
    /// immer aus, weil schon das Auflösen eines Link-Servers verraten kann,
    /// dass die Mail geöffnet wurde.
    ///
    /// - Parameter allowsRemoteContent: `true`, wenn externe Inhalte für
    ///   diese Anzeige freigegeben sind.
    /// - Returns: Zwei `<meta>`-Zeilen, bereit zum Einfügen in `<head>`.
    static func headTags(allowsRemoteContent: Bool) -> String {
        let policy = allowsRemoteContent ? allowedPolicy : blockedPolicy
        return """
            <meta http-equiv="Content-Security-Policy" content="\(policy)">
            <meta http-equiv="x-dns-prefetch-control" content="off">
            """
    }

    /// Muster für Verweise, die der Browser beim Anzeigen selbst nachlädt:
    /// `src`, `background`, `poster`, `srcset`, CSS-`url(…)`, `@import` und
    /// `<link href>`, jeweils mit `http:`, `https:` oder protokollrelativ
    /// (`//`). Gewöhnliche Links (`<a href>`) zählen nicht – sie laden erst
    /// beim Antippen.
    private static let remoteReferencePattern = [
        #"\b(?:src|background|poster)\s*=\s*["']?\s*(?:https?:)?//"#,
        #"\bsrcset\s*=\s*["'][^"']*(?:https?:)?//"#,
        #"url\(\s*["']?\s*(?:https?:)?//"#,
        #"@import\b"#,
        #"<link\b[^>]*\bhref\s*=\s*["']?\s*(?:https?:)?//"#
    ].joined(separator: "|")

    /// Übersetzter Ausdruck; einmal erzeugt, weil er bei jedem Öffnen
    /// einer Mail gebraucht wird.
    private static let remoteReferenceRegex = try? NSRegularExpression(
        pattern: remoteReferencePattern,
        options: [.caseInsensitive]
    )

    /// Prüft, ob eine Mail externe Inhalte enthält.
    ///
    /// Verarbeitung: Sucht nach dem ersten Verweis auf einen fremden
    /// Server, den der Browser beim Anzeigen laden würde. Lässt sich der
    /// Ausdruck nicht übersetzen, gilt die Mail als „mit externen
    /// Inhalten“ – dann erscheint der Knopf eher zu oft als zu selten.
    ///
    /// - Parameter html: HTML-Teil der Mail.
    /// - Returns: `true`, wenn mindestens ein externer Verweis gefunden wurde.
    static func containsRemoteReferences(_ html: String) -> Bool {
        guard let regex = remoteReferenceRegex else { return true }
        let range = NSRange(html.startIndex..., in: html)
        return regex.firstMatch(in: html, range: range) != nil
    }
}
