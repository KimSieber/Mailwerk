//
//  DraftFormat.swift
//  Mailwerk
//
//  Zweck: Aufbau des HTML-Teils eines Entwurfs, damit Mailwerk ihn später
//  wieder in seine Teile zerlegen kann – eigener Text, Signatur, Zitat –
//  und weiß, worauf er sich bezieht.
//
//  Der Entwurf ist eine gewöhnliche Mail; andere Programme zeigen ihn wie
//  gewohnt. Zusätzlich stehen im HTML unsichtbare Kommentar-Marken:
//  - `<!--mailwerk-entwurf:daten …-->` mit einem kleinen Datenblock
//    (JSON, Base64): Art (neu, Antwort, …), Bcc, Bezug zur Originalmail,
//    Threading-Kopfzeilen, Art der Signatur.
//  - Beginn und Ende je Teil, z. B. `<!--mailwerk-entwurf:text-->` …
//    `<!--/mailwerk-entwurf:text-->`.
//  Zerlegt wird ausschließlich per Textsuche nach diesen Marken; das HTML
//  dazwischen bleibt unberührt. Ein Entwurf ohne Datenblock (etwa aus dem
//  Webmail) liefert `nil` – er wird dann als Ganzes übernommen.
//
//  Beim Wiederherstellen liefert `quotedText` den Zitat-Text aus dem
//  Textteil des Entwurfs (dort steht er hinter dem eigenen Text).
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Ablage auf dem Server → DraftService; Zusammenstellen und
//  Wiederherstellen im Verfassen-Fenster → ComposeViewModel.
//
//  Abhängigkeiten: Foundation, os, Log.
//

import Foundation
import os

/// Datenblock eines Entwurfs.
nonisolated struct DraftMetadata: Codable, Equatable {
    /// Art des Verfassens.
    enum Kind: String, Codable { case new, reply, replyAll, forward }
    /// Art der Signatur im Entwurf.
    enum SignatureKind: String, Codable { case none, simple, html }

    /// Bezug auf die Originalmail (für „Beantwortet“/„Weitergeleitet“).
    struct Origin: Codable, Equatable {
        /// Kennung im lokalen Cache.
        var cachedMessageID: String
        /// Postfach der Originalmail.
        var accountID: UUID
        /// Ordner der Originalmail.
        var folder: String
        /// UID der Originalmail im Ordner.
        var uid: UInt32
    }

    /// Version des Formats.
    var version = 1
    /// Art des Verfassens.
    var kind: Kind
    /// Blindkopie-Empfänger als formatierte Adressen.
    var bcc: [String] = []
    /// Bezug zur Originalmail; `nil` bei einer neuen Mail.
    var origin: Origin?
    /// Message-ID der beantworteten Mail (In-Reply-To).
    var inReplyTo: String?
    /// References-Kette.
    var references: String?
    /// Art der Signatur.
    var signature: SignatureKind = .none
}

/// Teile eines Entwurfs.
nonisolated struct DraftParts: Equatable {
    /// Datenblock.
    var metadata: DraftMetadata
    /// Eigener Text vor der Signatur (HTML aus dem Editor).
    var textBefore: String
    /// Signatur (HTML); `nil` = keine.
    var signature: String?
    /// Eigener Text nach der Signatur (HTML aus dem Editor).
    var textAfter: String
    /// Zitat bzw. weitergeleiteter Inhalt (HTML); `nil` = keines.
    var quote: String?
}

/// Aufbau und Zerlegung des Entwurfs-HTML.
nonisolated enum DraftFormat {

    /// Gängige Namen des Entwürfe-Ordners (letztes Segment, Kleinschreibung).
    static let draftsFolderNames: Set<String> = ["drafts", "draft", "entwürfe", "entwuerfe"]

    /// Name eines neu angelegten Entwürfe-Ordners.
    static let newDraftsFolderName = "Drafts"

    /// Präfix aller Marken.
    private static let prefix = "mailwerk-entwurf"

    /// Baut das HTML eines Entwurfs.
    ///
    /// Verarbeitung: Reihenfolge wie beim Senden – eigener Text, Signatur,
    /// Text nach der Signatur, dann (nach einem Umbruch) das Zitat. Jeder
    /// Teil steht zwischen seinen Marken; der Datenblock steht vorn.
    ///
    /// - Parameter parts: Teile des Entwurfs.
    /// - Returns: HTML des Entwurfs.
    static func html(_ parts: DraftParts) -> String {
        var result = "<!--\(prefix):daten \(encode(parts.metadata))-->"
        result += wrap("text", parts.textBefore)
        if let signature = parts.signature { result += wrap("signatur", signature) }
        result += wrap("text-nach", parts.textAfter)
        if let quote = parts.quote { result += "<br>" + wrap("zitat", quote) }
        return result
    }

    /// Zerlegt das HTML eines Mailwerk-Entwurfs.
    ///
    /// - Parameter html: HTML-Teil der Mail.
    /// - Returns: Teile oder `nil`, wenn das HTML keinen (lesbaren)
    ///   Datenblock enthält.
    static func parse(_ html: String) -> DraftParts? {
        guard let metadata = metadata(in: html) else { return nil }
        return DraftParts(
            metadata: metadata,
            textBefore: section("text", in: html) ?? "",
            signature: section("signatur", in: html),
            textAfter: section("text-nach", in: html) ?? "",
            quote: section("zitat", in: html)
        )
    }

    /// Zitat-Text aus dem Textteil eines Entwurfs.
    ///
    /// Verarbeitung: Der Textteil eines Entwurfs ist wie beim Senden gebaut –
    /// eigener Text, eine Leerzeile, dann das Zitat. Steht der wieder
    /// hergestellte eigene Text vorn, ist der Rest das Zitat. Zeilenenden
    /// werden vorher vereinheitlicht (der Server liefert CRLF). Passt der
    /// Anfang nicht (z. B. Text eines anderen Programms), gibt es kein
    /// Ergebnis; der Aufrufer bildet den Text dann aus dem Zitat-HTML.
    ///
    /// - Parameters:
    ///   - draftText: Textteil des Entwurfs; `nil` = keiner.
    ///   - ownText: Wieder hergestellter eigener Text samt Signatur.
    /// - Returns: Zitat als Text oder `nil`.
    static func quotedText(draftText: String?, ownText: String) -> String? {
        guard let draftText else { return nil }
        let text = unifiedLineEndings(draftText)
        let prefix = unifiedLineEndings(ownText) + "\n\n"
        guard text.hasPrefix(prefix) else { return nil }
        let quote = String(text.dropFirst(prefix.count))
        return quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : quote
    }

    // MARK: - Intern

    /// Vereinheitlicht Zeilenenden auf LF.
    ///
    /// - Parameter text: Text mit beliebigen Zeilenenden.
    /// - Returns: Text mit LF.
    private static func unifiedLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// Setzt einen Teil zwischen seine Marken.
    ///
    /// - Parameters:
    ///   - name: Name des Teils.
    ///   - content: HTML des Teils.
    /// - Returns: Markierter Teil.
    private static func wrap(_ name: String, _ content: String) -> String {
        "<!--\(prefix):\(name)-->\(content)<!--/\(prefix):\(name)-->"
    }

    /// Inhalt zwischen den Marken eines Teils.
    ///
    /// - Parameters:
    ///   - name: Name des Teils.
    ///   - html: HTML des Entwurfs.
    /// - Returns: Inhalt oder `nil`, wenn eine der Marken fehlt.
    private static func section(_ name: String, in html: String) -> String? {
        let start = "<!--\(prefix):\(name)-->"
        let end = "<!--/\(prefix):\(name)-->"
        guard let startRange = html.range(of: start),
              let endRange = html.range(of: end, range: startRange.upperBound..<html.endIndex)
        else { return nil }
        return String(html[startRange.upperBound..<endRange.lowerBound])
    }

    /// Liest den Datenblock.
    ///
    /// - Parameter html: HTML des Entwurfs.
    /// - Returns: Datenblock oder `nil`.
    private static func metadata(in html: String) -> DraftMetadata? {
        let start = "<!--\(prefix):daten "
        guard let startRange = html.range(of: start),
              let endRange = html.range(of: "-->", range: startRange.upperBound..<html.endIndex),
              let data = Data(base64Encoded: String(html[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return try? JSONDecoder().decode(DraftMetadata.self, from: data)
    }

    /// Kodiert den Datenblock (JSON, Base64 – enthält so nie „-->“).
    ///
    /// - Parameter metadata: Datenblock.
    /// - Returns: Base64-Text.
    private static func encode(_ metadata: DraftMetadata) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return try encoder.encode(metadata).base64EncodedString()
        } catch {
            // Praktisch ausgeschlossen (nur Zeichenketten und Kennungen). Der
            // Entwurf wird trotzdem gespeichert – ohne Datenblock öffnet er
            // sich wie eine fremde Mail, der Text bleibt erhalten.
            Log.send.error("⚠️ Datenblock des Entwurfs nicht kodierbar: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }
}
