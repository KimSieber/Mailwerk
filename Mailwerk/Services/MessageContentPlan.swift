//
//  MessageContentPlan.swift
//  Mailwerk
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
//  - Anhänge einzeln, nur wenn die Mail die Schwelle nicht überschreitet,
//  - eingebettete Bilder (cid:) gar nicht – Mailwerk speichert sie nicht.
//
//  Welche Teile Text, HTML oder Anhang sind, entscheidet SwiftMails
//  `Message` (dieselbe Einordnung wie bisher); sie arbeitet nur mit den
//  Strukturangaben und braucht keine Inhalte.
//
//  Abgrenzung: Laden und Speichern → MailFetchService; Nachladen eines
//  einzelnen Anhangs → AttachmentManager.
//
//  Abhängigkeiten: SwiftMail (MessagePart, Message, Section).
//

import Foundation
import SwiftMail

/// Plan, welche Teile einer Mail geladen werden.
struct MessageContentPlan {
    /// Alle Teile der Mail laut Struktur, ohne Inhalt.
    let structure: [MessagePart]
    /// Text- und HTML-Teil der Mail selbst (höchstens je einer), zu laden.
    let bodyParts: [MessagePart]
    /// Anhänge der Mail (ohne eingebettete Bilder).
    let attachments: [MessagePart]
    /// `true`, wenn die Inhalte der Anhänge gleich mitgeladen werden sollen.
    let loadsAttachmentData: Bool

    /// Erstellt den Plan aus der Struktur einer Mail.
    ///
    /// Verarbeitung: Die Struktur wird als Mail ohne Inhalte betrachtet;
    /// deren Einordnung liefert Text-, HTML- und Anhangteile. Anhänge
    /// werden mitgeladen, wenn die Gesamtgröße der Mail die Schwelle nicht
    /// überschreitet.
    ///
    /// - Parameters:
    ///   - structure: Teile der Mail aus `fetchStructure`.
    ///   - totalSize: Gesamtgröße der Mail in Bytes (RFC822.SIZE).
    ///   - threshold: Schwelle für das Mitladen der Anhänge in Bytes.
    init(structure: [MessagePart], totalSize: Int, threshold: Int) {
        self.structure = structure
        let skeleton = Self.message(from: structure)
        self.bodyParts = [skeleton.findTextBodyPart(), skeleton.findHtmlBodyPart()]
            .compactMap { $0 }
        self.attachments = skeleton.attachments
        self.loadsAttachmentData = totalSize <= threshold
    }

    /// Abschnittsnummern der zu ladenden Text-/HTML-Teile (z. B. „1.1").
    var bodySections: [String] { bodyParts.map(\.section.description) }

    /// Abschnittsnummern der Anhänge (z. B. „2").
    var attachmentSections: [String] { attachments.map(\.section.description) }

    /// Setzt Text und HTML aus den geladenen Teilen zusammen.
    ///
    /// Verarbeitung: Die geladenen Rohdaten werden in die Struktur
    /// eingesetzt; Dekodierung (Base64, Quoted-Printable, Zeichensatz)
    /// übernimmt SwiftMail wie beim bisherigen Komplettabruf.
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
        let message = Self.message(from: filled)
        return (message.textBody, message.htmlBody)
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
