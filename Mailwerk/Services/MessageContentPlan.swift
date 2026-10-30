//
//  MessageContentPlan.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 08.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Legt anhand der Struktur einer Mail (BODYSTRUCTURE) fest, welche
//  Teile vom Server geladen werden, und setzt Text und HTML aus den
//  geladenen Teilen zusammen.
//
//  Hintergrund: SwiftMails `fetchMessage` lädt jeden Teil einer Mail mit
//  Inhalt – Anhänge, eingebettete Bilder und weitergeleitete Mails
//  (letztere sogar doppelt: als Ganzes und in Einzelteilen). Mailwerk
//  braucht davon nur Text und HTML; Anhänge nur bei Mails bis 5 MB, und
//  diese wurden danach ohnehin noch einmal einzeln geladen. Deshalb wird
//  zuerst nur die Struktur geholt (ohne Inhalt) und dann gezielt:
//  - Text- und HTML-Teil der Mail selbst (nicht der weitergeleiteten),
//  - Anhänge und eingebettete Bilder einzeln, nur wenn die Mail die
//    Schwelle nicht überschreitet.
//
//  Welche Teile Text, HTML oder Anhang sind, entscheidet SwiftMails
//  `Message` (dieselbe Einordnung wie bisher); sie arbeitet nur mit den
//  Strukturangaben und braucht keine Inhalte.
//
//  Eingebettete Bilder sind alle übrigen Bildteile der Mail selbst: keine
//  Anhänge laut SwiftMail und nicht Teil einer weitergeleiteten Mail. Das
//  sind die per `cid:` angesprochenen Bilder, aber auch Fotos, die z. B.
//  Apple Mail „inline“ ohne Verweis mitschickt; ob sie im Text oder in der
//  Anhangliste erscheinen, entscheidet die Anzeige (InlineImages).
//
//  Mails als Folge von Teilen: Apple Mail verschickt ein Foto mitten im
//  Text nicht per `cid:`, sondern als Folge „Text – Bild – Text“ (bzw.
//  „HTML – Bild – HTML“) in einem `multipart/mixed`, ohne Verweis auf das
//  Bild. Apple Mail zeigt diese Teile einfach nacheinander. SwiftMail
//  liefert nur den jeweils ersten Text- und HTML-Teil; der Rest der Mail
//  fehlte. Deshalb setzt der Plan solche Folgen selbst zusammen
//  (`Layout`):
//  - mehrere HTML-Teile: aneinandergehängt, Bilder zwischen ihnen an ihrer
//    Stelle;
//  - kein HTML, aber mehrere Textteile oder eingebettete Bilder: ein HTML
//    wird aus den Textteilen (maskiert, Zeilen erhalten) und den Bildern in
//    ihrer Reihenfolge gebaut.
//  Die eingesetzten Bilder bekommen einen `cid:`-Verweis – die eigene
//  Content-ID oder, ohne sie, eine aus der Abschnittsnummer gebildete
//  (`contentID(for:)`). Damit laufen Anzeige, Druck, Teilen, Antworten und
//  Weiterleiten über denselben Weg wie bei `cid:`-Bildern. Der Textteil ist
//  in diesen Fällen alle Textteile, aneinandergehängt.
//
//  Nebenläufigkeit (v0.2.3b): `nonisolated` – reine Werte bzw. Logik ohne
//  Bezug zur Oberfläche, damit der Abruf sie abseits des Hauptthreads
//  nutzen kann.
//
//  Abgrenzung: Laden und Speichern → MailFetchService; Nachladen eines
//  einzelnen Anhangs → AttachmentManager; Nachladen eingebetteter Bilder
//  beim Öffnen → InlineImageLoader.
//
//  Abhängigkeiten: SwiftMail (MessagePart, Message, Section), InlineImages,
//  HTMLEscaping.
//

import Foundation
import SwiftMail

/// Plan, welche Teile einer Mail geladen werden.
nonisolated struct MessageContentPlan {
    /// Alle Teile der Mail laut Struktur, ohne Inhalt.
    let structure: [MessagePart]
    /// Text- und HTML-Teile der Mail selbst in Reihenfolge, zu laden.
    let bodyParts: [MessagePart]
    /// Wie Text und HTML zusammengesetzt werden.
    let layout: Layout

    /// Zusammensetzung von Text und HTML.
    enum Layout: Equatable {
        /// Gewöhnlich: je ein Text- und HTML-Teil (wie SwiftMail).
        case single
        /// Mehrere HTML-Teile, Bilder dazwischen an ihrer Stelle.
        case htmlSequence
        /// Kein HTML: HTML aus Textteilen und Bildern in Reihenfolge.
        case textSequence
    }
    /// Anhänge der Mail (ohne eingebettete Bilder).
    let attachments: [MessagePart]
    /// Eingebettete Bilder der Mail selbst (Inline-Teile).
    let inlineImages: [MessagePart]
    /// `true`, wenn die Inhalte der Anhänge gleich mitgeladen werden sollen.
    let loadsAttachmentData: Bool

    /// Erstellt den Plan aus der Struktur einer Mail.
    ///
    /// Verarbeitung: Die Struktur wird als Mail ohne Inhalte betrachtet;
    /// deren Einordnung liefert Text-, HTML- und Anhangteile. Eingebettete
    /// Bilder sind die übrigen Bildteile außerhalb weitergeleiteter Mails.
    /// Anhänge und eingebettete Bilder werden mitgeladen, wenn die
    /// Gesamtgröße der Mail die Schwelle nicht überschreitet.
    ///
    /// - Parameters:
    ///   - structure: Teile der Mail aus `fetchStructure`.
    ///   - totalSize: Gesamtgröße der Mail in Bytes (RFC822.SIZE).
    ///   - threshold: Schwelle für das Mitladen der Anhänge in Bytes.
    init(structure: [MessagePart], totalSize: Int, threshold: Int) {
        self.structure = structure
        let skeleton = Self.message(from: structure)
        self.attachments = skeleton.attachments
        let attachmentSections = Set(skeleton.attachments.map(\.section))
        let ownBodies = skeleton.bodies.filter { !attachmentSections.contains($0.section) }
        let embedded = structure
            .filter { $0.contentType.lowercased().hasPrefix("message/rfc822") }
            .map(\.section.components)
        let inlineImages = structure.filter { part in
            let components = part.section.components
            let isInsideEmbedded = embedded.contains { prefix in
                components.count > prefix.count && Array(components.prefix(prefix.count)) == prefix
            }
            return part.contentType.lowercased().hasPrefix("image/")
                && !attachmentSections.contains(part.section)
                && !isInsideEmbedded
        }
        self.inlineImages = inlineImages
        self.loadsAttachmentData = totalSize <= threshold

        let htmlCount = ownBodies.filter { Self.isHTML($0) }.count
        let textCount = ownBodies.count - htmlCount
        let layout: Layout
        if htmlCount >= 2 {
            layout = .htmlSequence
        } else if htmlCount == 0 && textCount >= 1 && (textCount >= 2 || !inlineImages.isEmpty) {
            layout = .textSequence
        } else {
            layout = .single
        }
        self.layout = layout
        // Gewöhnlich nur der erste Text- und HTML-Teil, sonst alle.
        self.bodyParts = layout == .single
            ? [skeleton.findTextBodyPart(), skeleton.findHtmlBodyPart()].compactMap { $0 }
            : ownBodies
    }

    /// Content-ID, unter der ein eingebettetes Bild angesprochen wird: die
    /// eigene ohne spitze Klammern, sonst eine aus der Abschnittsnummer.
    ///
    /// - Parameter part: Bildteil.
    /// - Returns: z. B. „logo@example.org“ oder „teil-2@mailwerk“.
    static func contentID(for part: MessagePart) -> String {
        InlineImages.storedContentID(part.contentId) ?? "teil-\(part.section)@mailwerk"
    }

    /// `true` bei einem HTML-Teil.
    ///
    /// - Parameter part: Teil.
    /// - Returns: `true`, wenn der MIME-Typ `text/html` ist.
    private static func isHTML(_ part: MessagePart) -> Bool {
        part.contentType.lowercased().hasPrefix("text/html")
    }

    /// Abschnittsnummern der Anhänge (z. B. „2").
    var attachmentSections: [String] { attachments.map(\.section.description) }

    /// Setzt Text und HTML aus den geladenen Teilen zusammen.
    ///
    /// Verarbeitung: Die geladenen Rohdaten werden in die Struktur
    /// eingesetzt; Dekodierung (Base64, Quoted-Printable, Zeichensatz)
    /// übernimmt SwiftMail wie beim bisherigen Komplettabruf. Folgen von
    /// Teilen werden je nach `layout` zusammengesetzt (siehe Dateikopf).
    ///
    /// - Parameter data: Rohdaten je Abschnittsnummer (z. B. „1.1").
    /// - Returns: Text- und HTML-Inhalt, jeweils `nil`, wenn nicht vorhanden.
    func bodies(withData data: [String: Data]) -> (text: String?, html: String?) {
        let filled = structure.map { part -> MessagePart in
            var part = part
            if let content = data[part.section.description] {
                part.data = content
            }
            return part
        }
        guard layout != .single else {
            let message = Self.message(from: filled)
            return (message.textBody, message.htmlBody)
        }

        let content = Dictionary(filled.map { ($0.section, $0) }, uniquingKeysWith: { first, _ in first })
        let texts = bodyParts.filter { !Self.isHTML($0) }.compactMap { content[$0.section]?.textContent }
        let text = texts.isEmpty ? nil : texts.joined(separator: "\n")

        // Text- bzw. HTML-Teile und Bilder in der Reihenfolge der Struktur.
        let wanted = Set((bodyParts + inlineImages).map(\.section))
        let sequence = structure.filter { wanted.contains($0.section) }
        let isImage = Set(inlineImages.map(\.section))

        var pieces: [(html: String, isImage: Bool)] = []
        for part in sequence {
            if isImage.contains(part.section) {
                pieces.append((#"<img src="cid:\#(Self.contentID(for: part))">"#, true))
            } else if layout == .htmlSequence, Self.isHTML(part), let html = content[part.section]?.textContent {
                pieces.append((html, false))
            } else if layout == .textSequence, let plain = content[part.section]?.textContent {
                pieces.append(("<div style=\"white-space: pre-wrap\">\(HTMLEscaping.escaped(plain))</div>", false))
            }
        }

        if layout == .htmlSequence {
            // Nur Bilder zwischen den HTML-Teilen einsetzen, und keine, die
            // das HTML schon selbst per cid: anspricht.
            guard let first = pieces.firstIndex(where: { !$0.isImage }),
                  let last = pieces.lastIndex(where: { !$0.isImage }) else { return (text, nil) }
            let referenced = InlineImages.referencedContentIDs(
                in: pieces.filter { !$0.isImage }.map(\.html).joined()
            )
            pieces = pieces.enumerated().filter { index, piece in
                guard piece.isImage else { return true }
                let id = InlineImages.referencedContentIDs(in: piece.html)
                return index > first && index < last && id.isDisjoint(with: referenced)
            }.map(\.element)
        }
        let html = pieces.map(\.html).joined(separator: "\n")
        return (text, html.isEmpty ? nil : html)
    }

    /// Baut einen Strukturteil, z. B. für Tests.
    ///
    /// - Parameters:
    ///   - section: Abschnittsnummer, z. B. „1.2".
    ///   - contentType: MIME-Typ, z. B. „text/plain; charset=utf-8".
    ///   - disposition: „inline" oder „attachment".
    ///   - encoding: Transferkodierung, z. B. „base64".
    ///   - filename: Dateiname.
    ///   - contentId: Content-ID (eingebettete Bilder).
    ///   - size: Größe in Bytes.
    /// - Returns: Strukturteil ohne Inhalt.
    static func part(
        section: String,
        contentType: String,
        disposition: String? = nil,
        encoding: String? = nil,
        filename: String? = nil,
        contentId: String? = nil,
        size: Int? = nil
    ) -> MessagePart {
        MessagePart(
            sectionString: section,
            contentType: contentType,
            disposition: disposition,
            encoding: encoding,
            filename: filename,
            contentId: contentId,
            size: size
        )
    }

    /// Betrachtet Teile als Mail, um SwiftMails Einordnung zu nutzen.
    ///
    /// Verarbeitung: Die Kopfdaten spielen für die Einordnung keine Rolle
    /// und bleiben leer.
    ///
    /// - Parameter parts: Teile der Mail.
    /// - Returns: Mail mit diesen Teilen.
    private static func message(from parts: [MessagePart]) -> Message {
        Message(header: MessageInfo(sequenceNumber: SwiftMail.SequenceNumber(UInt32(0))), parts: parts)
    }
}
