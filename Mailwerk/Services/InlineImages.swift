//
//  InlineImages.swift
//  Mailwerk
//
//  Zweck: Regeln für eingebettete Bilder einer Mail (Inline-Teile, im HTML
//  per `cid:` angesprochen, z. B. Logos in Signaturen oder Bilder in
//  Newslettern).
//
//  - Welche Content-IDs das HTML anspricht (`referencedContentIDs`).
//  - Welche Anhänge sichtbar in der Anhangliste stehen: echte Anhänge und
//    Inline-Bilder, die das HTML nicht anspricht (z. B. von Apple Mail
//    mitgeschickte Fotos). Angesprochene Inline-Bilder sind Inhalt der Mail
//    und erscheinen im Text, nicht in der Liste (`visibleAttachments`).
//  - Für Anzeige, Druck und Teilen werden die `cid:`-Verweise durch
//    `data:`-Adressen ersetzt (`resolve`). Die Content-Security-Policy
//    erlaubt `data:`-Bilder auch bei gesperrten externen Inhalten; es wird
//    nichts aus dem Netz geladen. Eingesetzt werden nur Bilder (`image/*`).
//
//  Ersetzt wird per Textsuche nach `cid:…`; das HTML wird nicht zerlegt
//  oder umgebaut. Verweise ohne passendes Bild bleiben unverändert.
//
//  Content-IDs werden für den Vergleich vereinheitlicht: spitze Klammern
//  und Leerraum entfallen, Prozent-Kodierung (RFC 2392) wird aufgelöst,
//  Groß- und Kleinschreibung spielen keine Rolle.
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Laden der Bilder → MailFetchService (beim Abruf) und
//  InlineImageLoader (beim Öffnen); Speichern → MessageStore (Anhang-Tabelle
//  mit `isInline`, `contentID`); Versand → ComposeViewModel.
//
//  Abhängigkeiten: Foundation, CachedAttachment.
//

import Foundation

/// Regeln für eingebettete Bilder einer Mail.
nonisolated enum InlineImages {

    /// Muster für `cid:`-Verweise; die Content-ID endet vor Anführungszeichen,
    /// Leerraum, `>` oder `)`.
    private static let cidRegex = try? NSRegularExpression(
        pattern: #"cid:([^"'\s>)]+)"#,
        options: [.caseInsensitive]
    )

    /// Vereinheitlicht eine Content-ID für den Vergleich.
    ///
    /// - Parameter raw: Content-ID aus Kopfzeile oder HTML, z. B.
    ///   „<logo@example.org>“ oder „logo%40example.org“.
    /// - Returns: Vergleichswert, z. B. „logo@example.org“.
    static func normalizedContentID(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<") { value.removeFirst() }
        if value.hasSuffix(">") { value.removeLast() }
        value = value.removingPercentEncoding ?? value
        return value.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Content-ID zum Speichern: wie im Kopf der Mail, ohne spitze Klammern.
    ///
    /// - Parameter raw: Content-ID aus der Struktur der Mail; `nil` = keine.
    /// - Returns: Content-ID ohne Klammern; `nil`, wenn keine oder leer.
    static func storedContentID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<") { value.removeFirst() }
        if value.hasSuffix(">") { value.removeLast() }
        value = value.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Content-IDs, die das HTML per `cid:` anspricht.
    ///
    /// - Parameter html: HTML-Teil der Mail; `nil` = keiner.
    /// - Returns: Vereinheitlichte Content-IDs.
    static func referencedContentIDs(in html: String?) -> Set<String> {
        guard let html, let regex = cidRegex else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var result = Set<String>()
        for match in regex.matches(in: html, range: range) {
            if let idRange = Range(match.range(at: 1), in: html) {
                result.insert(normalizedContentID(String(html[idRange])))
            }
        }
        return result
    }

    /// Prüft, ob ein Anhang ein vom HTML angesprochenes Inline-Bild ist.
    ///
    /// - Parameters:
    ///   - attachment: Anhang.
    ///   - referenced: Angesprochene Content-IDs (`referencedContentIDs`).
    /// - Returns: `true`, wenn er im Text erscheint statt in der Anhangliste.
    static func isReferencedInline(_ attachment: CachedAttachment, in referenced: Set<String>) -> Bool {
        guard attachment.isInline, let contentID = attachment.contentID else { return false }
        return referenced.contains(normalizedContentID(contentID))
    }

    /// Anhänge für die Anhangliste: echte Anhänge und nicht angesprochene
    /// Inline-Bilder.
    ///
    /// - Parameters:
    ///   - attachments: Alle Anhänge der Mail aus dem Cache.
    ///   - html: HTML-Teil der Mail.
    /// - Returns: Sichtbare Anhänge in ihrer Reihenfolge.
    static func visibleAttachments(_ attachments: [CachedAttachment], html: String?) -> [CachedAttachment] {
        let referenced = referencedContentIDs(in: html)
        return attachments.filter { !isReferencedInline($0, in: referenced) }
    }

    /// Vom HTML angesprochene Inline-Bilder.
    ///
    /// - Parameters:
    ///   - attachments: Alle Anhänge der Mail aus dem Cache.
    ///   - html: HTML-Teil der Mail.
    /// - Returns: Angesprochene Inline-Bilder, mit oder ohne Daten.
    static func referencedImages(_ attachments: [CachedAttachment], html: String?) -> [CachedAttachment] {
        let referenced = referencedContentIDs(in: html)
        return attachments.filter { isReferencedInline($0, in: referenced) }
    }

    /// `true`, wenn das HTML ein Bild anspricht, dessen Daten fehlen
    /// (kein Eintrag oder Eintrag ohne Daten).
    ///
    /// - Parameters:
    ///   - attachments: Alle Anhänge der Mail aus dem Cache.
    ///   - html: HTML-Teil der Mail.
    /// - Returns: `true`, wenn Bilder nachzuladen sind.
    static func hasMissingImages(_ attachments: [CachedAttachment], html: String?) -> Bool {
        let referenced = referencedContentIDs(in: html)
        guard !referenced.isEmpty else { return false }
        let loaded = Set(attachments.compactMap { attachment -> String? in
            guard attachment.isInline, attachment.data != nil, let id = attachment.contentID else { return nil }
            return normalizedContentID(id)
        })
        return !referenced.isSubset(of: loaded)
    }

    /// Ersetzt `cid:`-Verweise durch `data:`-Adressen der geladenen Bilder.
    ///
    /// Verarbeitung: Nur Inline-Teile vom Typ `image/*` mit Daten werden
    /// eingesetzt. Verweise ohne passendes Bild bleiben unverändert stehen.
    ///
    /// - Parameters:
    ///   - html: HTML-Teil der Mail.
    ///   - images: Anhänge der Mail (Inline-Bilder werden herausgesucht).
    /// - Returns: HTML mit eingesetzten Bildern.
    static func resolve(_ html: String, images: [CachedAttachment]) -> String {
        var dataURLs: [String: String] = [:]
        for image in images where image.isInline {
            guard let contentID = image.contentID, let data = image.data else { continue }
            let mimeType = image.contentType
                .split(separator: ";", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            guard mimeType.hasPrefix("image/") else { continue }
            dataURLs[normalizedContentID(contentID)] = "data:\(mimeType);base64,\(data.base64EncodedString())"
        }
        guard !dataURLs.isEmpty, let regex = cidRegex else { return html }

        let source = html as NSString
        let result = NSMutableString(string: html)
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let id = normalizedContentID(source.substring(with: match.range(at: 1)))
            if let dataURL = dataURLs[id] {
                result.replaceCharacters(in: match.range, with: dataURL)
            }
        }
        return result as String
    }
}
