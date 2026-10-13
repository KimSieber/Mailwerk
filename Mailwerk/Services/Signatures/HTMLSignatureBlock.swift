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
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Anzeige und Bearbeitung → SignatureBlockView; Zustand beim
//  Verfassen → ComposeViewModel; Platzhalter → SignatureRules.
//
//  Abhängigkeiten: Foundation, SignatureItem, SignatureRules,
//  OutgoingAttachment.
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
