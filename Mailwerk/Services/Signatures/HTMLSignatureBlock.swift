//
//  HTMLSignatureBlock.swift
//  Mailwerk
//
//  Zweck: Eine HTML-Signatur beim Verfassen – der eigene Block unter dem
//  Mailtext, in dem sich Text ändern und löschen lässt, ohne die
//  Gestaltung (Tabellen, Ausrichtung) zu verlieren.
//
//  - Für die Anzeige wird der Logo-Platzhalter durch eine `data:`-Adresse
//    ersetzt (kein Netz nötig, sofort sichtbar).
//  - Änderungen im Block kommen als HTML aus der Web-Ansicht zurück
//    (`editedHTML`).
//  - Beim Senden wird genau diese `data:`-Adresse per Textsuche durch
//    `cid:<Content-ID>` ersetzt; das Logo geht als Inline-Teil mit
//    (`sendHTML`, `logoAttachment`).
//
//  Aus einem gesicherten Entwurf entsteht der Block mit
//  `init(restoredHTML:images:)`: das Logo steht dort als `cid:` und wird
//  für die Anzeige wieder zur `data:`-Adresse.
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Anzeige und Bearbeitung → SignatureBlockView; Zustand beim
//  Verfassen → ComposeViewModel; Platzhalter → SignatureRules.
//
//  Abhängigkeiten: Foundation, SignatureItem, SignatureRules,
//  OutgoingAttachment, CachedAttachment, InlineImages.
//

import Foundation

/// HTML-Signatur als eigener Block beim Verfassen.
struct HTMLSignatureBlock: Equatable, Identifiable {
    /// Kennung; eine neue Kennung lädt die Anzeige neu (z. B. nach
    /// Wechsel des Postfachs).
    let id: UUID
    /// HTML für die Anzeige (Logo als `data:`).
    let displayHTML: String
    /// Aktueller Stand nach Änderungen im Block (Logo weiterhin als `data:`).
    var editedHTML: String
    /// `data:`-Adresse des Logos in der Anzeige; `nil` = kein Logo.
    let logoDataURI: String?
    /// Logo als Inline-Teil mit Content-ID; `nil` = kein Logo.
    let logoAttachment: OutgoingAttachment?

    /// Bildet den Block aus einer gespeicherten HTML-Signatur.
    ///
    /// Verarbeitung: `nonisolated`, weil nur mit Texten und Daten gerechnet
    /// wird – so lässt er sich auch außerhalb des Main-Actors aufrufen.
    ///
    /// - Parameter signature: Signatur der Art HTML.
    nonisolated init(signature: SignatureItem) {
        id = UUID()
        if let data = signature.logoData, SignatureRules.containsLogo(signature.html) {
            let mimeType = signature.logoMimeType ?? "image/png"
            let dataURI = SignatureRules.dataURI(data, mimeType: mimeType)
            let ext = mimeType.split(separator: "/").last.map(String.init) ?? "png"
            logoDataURI = dataURI
            logoAttachment = OutgoingAttachment(
                filename: "logo.\(ext == "jpeg" ? "jpg" : ext)",
                mimeType: mimeType,
                data: data,
                contentID: "logo-\(UUID().uuidString.lowercased())@mailwerk"
            )
            displayHTML = SignatureRules.replacingLogo(in: signature.html, with: dataURI)
        } else {
            logoDataURI = nil
            logoAttachment = nil
            displayHTML = signature.html
        }
        editedHTML = displayHTML
    }

    /// Bildet den Block aus der HTML-Signatur eines gesicherten Entwurfs.
    ///
    /// Verarbeitung: Im Entwurf steht die Signatur so, wie sie gesendet
    /// würde – das Logo als `cid:<Content-ID>`, das Bild als Inline-Teil
    /// des Entwurfs. Das erste Bild unter `images`, das die Signatur so
    /// anspricht, wird für die Anzeige als `data:`-Adresse eingesetzt und
    /// behält beim Senden seine Content-ID. Ohne passendes Bild bleibt das
    /// HTML unverändert. `nonisolated` wie `init(signature:)`.
    ///
    /// - Parameters:
    ///   - restoredHTML: HTML der Signatur aus dem Entwurf.
    ///   - images: Anhänge des Entwurfs (Inline-Bilder werden herausgesucht).
    nonisolated init(restoredHTML html: String, images: [CachedAttachment]) {
        id = UUID()
        let referenced = InlineImages.referencedContentIDs(in: html)
        let logo = images.first { image in
            guard image.isInline, image.data != nil, let contentID = image.contentID else { return false }
            return referenced.contains(InlineImages.normalizedContentID(contentID))
                && html.contains("cid:" + contentID)
        }
        if let logo, let data = logo.data, let contentID = logo.contentID {
            let mimeType = logo.contentType
                .split(separator: ";", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "image/png"
            let dataURI = SignatureRules.dataURI(data, mimeType: mimeType)
            logoDataURI = dataURI
            logoAttachment = OutgoingAttachment(
                filename: logo.filename, mimeType: mimeType, data: data, contentID: contentID
            )
            displayHTML = html.replacingOccurrences(of: "cid:" + contentID, with: dataURI)
        } else {
            logoDataURI = nil
            logoAttachment = nil
            displayHTML = html
        }
        editedHTML = displayHTML
    }

    /// HTML zum Senden: der aktuelle Stand, das Logo als `cid:`.
    var sendHTML: String {
        guard let logoDataURI, let contentID = logoAttachment?.contentID else { return editedHTML }
        return editedHTML.replacingOccurrences(of: logoDataURI, with: "cid:" + contentID)
    }

    /// Inline-Teile zum Senden: das Logo, sofern es noch im Block steht.
    var attachments: [OutgoingAttachment] {
        guard let logoAttachment, let contentID = logoAttachment.contentID,
              sendHTML.contains("cid:" + contentID) else { return [] }
        return [logoAttachment]
    }

    /// Nur-Text-Fassung des aktuellen Stands.
    var plainText: String {
        SignatureRules.plainText(fromHTML: editedHTML)
    }
}
