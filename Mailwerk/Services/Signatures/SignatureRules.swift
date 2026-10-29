//
//  SignatureRules.swift
//  Mailwerk
//
//  Zweck: Regeln rund um Signaturen, die ohne Oberfläche und Speicher
//  auskommen:
//  - Art einer Signatur und ihr Wert-Typ (`SignatureKind`, `SignatureItem`),
//  - Auswahl des neuesten Datensatzes, wenn der iCloud-Abgleich mehrere
//    für dasselbe Postfach liefert,
//  - Logo-Platzhalter im HTML (`<img src="logo">`): erkennen und durch
//    eine echte Quelle ersetzen (Vorschau: `data:`, Versand: `cid:`),
//  - lesbare Zeilenumbrüche, wenn eine einfache Signatur als HTML-Code
//    übernommen wird.
//
//  Ersetzt wird ausschließlich per Textsuche; das HTML wird nicht zerlegt
//  oder umgebaut (fremdes HTML kann fehlerhaft sein).
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Speicher → SignatureStore; Pflege-Seite → SignatureEditorView.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Art einer Signatur.
nonisolated enum SignatureKind: String, CaseIterable, Codable, Sendable {
    /// Im Editor gestaltet (Formate, Links, Logo); beim Verfassen frei bearbeitbar.
    case simple
    /// Als HTML-Code gepflegt (beliebige Gestaltung, z. B. Tabellen).
    case html
}

/// Signatur eines Postfachs als Wert – für Oberfläche, Tests und Versand.
/// Kodierbar für die Abschrift der Teilen-Erweiterung (ShareContext).
nonisolated struct SignatureItem: Equatable, Codable, Sendable {
    /// Kennung des Postfachs.
    var accountID: UUID
    /// Art der Signatur.
    var kind: SignatureKind
    /// HTML der Signatur; das Logo steht darin als Platzhalter `<img src="logo">`.
    var html: String
    /// Bilddaten des Logos; `nil` = kein Logo.
    var logoData: Data?
    /// MIME-Typ des Logos, z. B. „image/png“.
    var logoMimeType: String?
    /// Zeitpunkt der letzten Änderung.
    var modifiedAt: Date

    /// `true`, wenn weder Text noch Logo vorhanden sind.
    var isEmpty: Bool {
        HTMLRichTextParser.parse(html).lines.allSatisfy(\.runs.isEmpty) && logoData == nil
    }
}

/// Regeln für Signaturen.
nonisolated enum SignatureRules {

    /// Name des Logo-Platzhalters im HTML.
    static let logoPlaceholder = "logo"

    /// Breite des Logos in Punkt, wenn das HTML keine angibt.
    static let defaultLogoWidth = 150

    /// Größte Kantenlänge des Logos in Pixeln.
    static let maxLogoPixelSize = 600

    /// Muster für `src="logo"`, `src='logo'` und `src=logo`.
    private static let placeholderRegex = try? NSRegularExpression(
        pattern: #"\bsrc\s*=\s*(?:"logo"|'logo'|logo(?=[\s/>]))"#,
        options: [.caseInsensitive]
    )

    /// Der neueste Datensatz.
    ///
    /// Verarbeitung: CloudKit kennt keine eindeutigen Schlüssel; legen zwei
    /// Geräte gleichzeitig eine Signatur an, gibt es zwei Datensätze. Es
    /// gilt der zuletzt geänderte.
    ///
    /// - Parameter items: Datensätze desselben Postfachs.
    /// - Returns: Neuester Datensatz oder `nil` bei leerer Liste.
    static func newest(_ items: [SignatureItem]) -> SignatureItem? {
        items.max { $0.modifiedAt < $1.modifiedAt }
    }

    /// Je Postfach der neueste Datensatz.
    ///
    /// - Parameter items: Alle Datensätze.
    /// - Returns: Signaturen nach Postfach.
    static func byAccount(_ items: [SignatureItem]) -> [UUID: SignatureItem] {
        Dictionary(grouping: items, by: \.accountID).compactMapValues(newest)
    }

    /// `true`, wenn das HTML den Logo-Platzhalter enthält.
    ///
    /// - Parameter html: HTML der Signatur.
    /// - Returns: `true` bei mindestens einem Platzhalter.
    static func containsLogo(_ html: String) -> Bool {
        guard let regex = placeholderRegex else { return false }
        return regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil
    }

    /// Ersetzt den Logo-Platzhalter durch eine echte Quelle.
    ///
    /// - Parameters:
    ///   - html: HTML der Signatur.
    ///   - source: Neue Quelle, z. B. „data:image/png;base64,…“ oder „cid:…“.
    /// - Returns: HTML mit `src="<Quelle>"` an jeder Platzhalter-Stelle.
    static func replacingLogo(in html: String, with source: String) -> String {
        guard let regex = placeholderRegex else { return html }
        let escaped = source.replacingOccurrences(of: "\"", with: "&quot;")
        let template = NSRegularExpression.escapedTemplate(for: "src=\"\(escaped)\"")
        return regex.stringByReplacingMatches(
            in: html, range: NSRange(html.startIndex..., in: html), withTemplate: template
        )
    }

    /// `data:`-Adresse für Bilddaten (Vorschau ohne Netz).
    ///
    /// - Parameters:
    ///   - data: Bilddaten.
    ///   - mimeType: MIME-Typ.
    /// - Returns: „data:<Typ>;base64,…“.
    static func dataURI(_ data: Data, mimeType: String) -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    /// Nur-Text-Fassung einer HTML-Signatur für den Textteil der Mail.
    ///
    /// - Parameter html: HTML der Signatur.
    /// - Returns: Zeilen der Signatur ohne Bilder, mit Zeilenumbrüchen getrennt.
    static func plainText(fromHTML html: String) -> String {
        HTMLRichTextParser.parse(html).lines.map { line in
            line.runs.compactMap { run -> String? in
                if case .text(let text, _) = run { return text }
                return nil
            }.joined()
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bricht erzeugtes HTML nach jedem Absatz und jeder Liste um, damit
    /// der Code lesbar ist.
    ///
    /// - Parameter html: Einzeiliges HTML aus dem Editor.
    /// - Returns: Dasselbe HTML mit Zeilenumbrüchen (die Darstellung ändert sich nicht).
    static func readableHTML(_ html: String) -> String {
        var result = html
        for closing in ["</p>", "</ul>", "</ol>"] {
            result = result.replacingOccurrences(of: closing, with: closing + "\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
