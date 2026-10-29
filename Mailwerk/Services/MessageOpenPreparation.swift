//
//  MessageOpenPreparation.swift
//  Mailwerk
//
//  Zweck: Bereitet das Öffnen einer Mail abseits des Hauptthreads vor
//  (Prüfbericht P-11). Bisher lief beim Öffnen alles synchron auf dem
//  Main-Actor: Mail und Anhänge (bis 5 MB) lesen, eingebettete Bilder als
//  Base64 ins HTML setzen, Text für die Spracherkennung per Regex
//  aufbereiten und die Sprache zweimal erkennen, externe Verweise suchen
//  sowie die Dateien zum Teilen schreiben. Das ließ die Push-Animation
//  stocken (Microhang 276 ms in Messung 2).
//
//  Ablauf:
//  - `loadMessage`: Mail aus dem Cache lesen.
//  - `prepare`: Anhänge lesen, Inhalt aufbereiten (`content`), externe
//    Inhalte und Sprache erkennen – ein fertiges Paket für die Ansicht.
//  - `content`: HTML mit Bildern und sichtbare Anhänge; auch nach dem
//    Nachladen eingebetteter Bilder oder dem lokalen Löschen von Anhängen.
//  - `writeShareFiles`: Mail als HTML-Datei und geladene Anhänge als
//    Dateien zum Teilen – nachdem die Mail schon angezeigt wird.
//
//  Anzeige-Hinweise (externe Inhalte, eigene Farben, Sprache): stehen
//  meist schon seit dem Abruf in der Datenbank (MessageDisplayHints) und
//  werden nur gelesen. Fehlen sie (Mails von vor Stufe 9) oder sind sie
//  veraltet, werden sie hier einmal berechnet und gespeichert.
//
//  Spracherkennung: Läuft höchstens einmal. Die Diagnose fürs Protokoll
//  (eine zweite Erkennung) gibt es nur im Debug-Build und nur, wenn
//  ohnehin neu berechnet wird.
//
//  Abgrenzung: Die Entscheidungen mit Filterlisten (externe Inhalte bei
//  vertrauenswürdigem Absender, Spam-Angabe) und die Prüfung der
//  Übersetzbarkeit bleiben in der MessageDetailView (SpamFilterService,
//  Translation). Angezeigt wird nur, was hier vorbereitet wurde.
//
//  Nebenläufigkeit: `nonisolated`; die Einstiege sind `@concurrent`. Die
//  Aufbereitung (`content`) ist eine reine Funktion und getestet.
//
//  Abhängigkeiten: MessageStore (Lesen, Hinweise speichern),
//  MessageDisplayHints, InlineImages, SearchText, MessageLanguage,
//  MailPrintFormatter, AttachmentManager, Log.
//

import Foundation
import os

/// Vorbereitung beim Öffnen einer Mail im Hintergrund.
nonisolated enum MessageOpenPreparation {

    // MARK: - Ergebnistypen

    /// Inhalt für die Anzeige: Anhänge, HTML mit Bildern, sichtbare Anhänge.
    struct Content: Sendable {
        /// Alle Anhänge der Mail aus dem Cache, einschließlich eingebetteter Bilder.
        let attachments: [CachedAttachment]
        /// Anhänge für die Liste: echte Anhänge und nicht angesprochene Inline-Bilder.
        let visibleAttachments: [CachedAttachment]
        /// HTML mit eingesetzten eingebetteten Bildern; `nil` = Mail ohne HTML.
        let resolvedHTML: String?
    }

    /// Ergebnis der Spracherkennung.
    struct LanguageResult: Sendable {
        /// Erkannte fremde Sprache; `nil` = Deutsch oder nicht erkannt.
        let language: Locale.Language?
        /// Protokollzeile (Quelle; im Debug-Build mit Diagnose), ohne Mailinhalt.
        let logLine: String
    }

    /// Fertiges Paket für die Ansicht.
    struct Prepared: Sendable {
        /// Anhänge und aufbereiteter Inhalt.
        let content: Content
        /// Anzeige-Hinweise (gespeichert oder eben berechnet).
        let hints: MessageDisplayHints
        /// `true`, wenn das HTML externe Verweise enthält.
        var hasRemoteContent: Bool { hints.hasRemoteContent }
        /// Spracherkennung; `nil`, wenn sie nicht angefordert war.
        let language: LanguageResult?
    }

    /// Geschriebene Dateien zum Teilen.
    struct ShareFiles: Sendable {
        /// Die Mail als HTML-Datei; `nil`, wenn sie nicht geschrieben werden konnte.
        let mailFile: URL?
        /// Dateien der geladenen sichtbaren Anhänge, je Anhang-ID.
        let attachmentFiles: [String: URL]
    }

    // MARK: - Einstiege

    /// Liest eine Mail aus dem Cache. Messpunkt für Instruments: „Mail aus Cache“.
    ///
    /// - Parameter id: Cache-ID der Mail.
    /// - Returns: Mail; `nil`, wenn sie nicht mehr im Cache liegt.
    @concurrent
    static func loadMessage(id: String) async -> CachedMessage? {
        let interval = Log.beginInterval(Log.Interval.loadMessage)
        defer { Log.endInterval(interval) }
        return MessageStore.shared.message(id: id)
    }

    /// Bereitet eine Mail für die Anzeige vor.
    ///
    /// Verarbeitung: Anhänge lesen, Inhalt aufbereiten (`content`) und die
    /// Anzeige-Hinweise holen (`displayHints`: gespeichert oder einmal
    /// berechnet). Die Sprache kommt aus den Hinweisen.
    ///
    /// - Parameters:
    ///   - message: Angezeigte Mail.
    ///   - detectLanguage: `true`, wenn die Sprache noch nicht entschieden ist.
    /// - Returns: Fertiges Paket für die Ansicht.
    @concurrent
    static func prepare(_ message: CachedMessage, detectLanguage: Bool) async -> Prepared {
        let attachments = MessageStore.shared.attachments(forMessage: message.id)
        let (hints, computed) = displayHints(for: message)
        return Prepared(
            content: content(for: message, attachments: attachments),
            hints: hints,
            language: detectLanguage ? languageResult(for: message, hints: hints, computed: computed) : nil
        )
    }

    /// Bereitet den Inhalt neu auf – nach geänderten Anhängen (eingebettete
    /// Bilder nachgeladen, Anhänge lokal gelöscht).
    ///
    /// - Parameters:
    ///   - message: Angezeigte Mail.
    ///   - attachments: Anhänge; `nil` = neu aus dem Cache lesen.
    /// - Returns: Aufbereiteter Inhalt.
    @concurrent
    static func refreshedContent(for message: CachedMessage, attachments: [CachedAttachment]?) async -> Content {
        let all = attachments ?? MessageStore.shared.attachments(forMessage: message.id)
        return content(for: message, attachments: all)
    }

    /// Schreibt die Dateien zum Teilen.
    ///
    /// Verarbeitung: Die Mail als HTML-Datei, passend zur Freigabe externer
    /// Inhalte; dazu jeder geladene sichtbare Anhang, der noch keine Datei
    /// hat. Fehler werden protokolliert – die betroffene Datei fehlt dann
    /// beim Teilen.
    ///
    /// - Parameters:
    ///   - message: Angezeigte Mail.
    ///   - content: Aufbereiteter Inhalt (Anhänge und sichtbare Anhänge).
    ///   - allowsRemoteContent: `true`, wenn externe Inhalte freigegeben sind.
    ///   - existing: IDs der Anhänge, die schon eine Datei haben.
    /// - Returns: Geschriebene Dateien.
    @concurrent
    static func writeShareFiles(
        for message: CachedMessage,
        content: Content,
        allowsRemoteContent: Bool,
        existing: Set<String>
    ) async -> ShareFiles {
        var mailFile: URL?
        do {
            mailFile = try MailPrintFormatter.writeTemporaryFile(
                for: message,
                attachments: content.visibleAttachments,
                inlineImages: content.attachments,
                allowsRemoteContent: allowsRemoteContent
            )
        } catch {
            Log.view.error("⚠️ Mail als Datei zum Teilen nicht geschrieben: \(error.localizedDescription, privacy: .public)")
        }
        var files: [String: URL] = [:]
        for attachment in content.visibleAttachments
        where attachment.data != nil && !existing.contains(attachment.id) {
            if let url = try? AttachmentManager.writeTempFile(for: attachment) {
                files[attachment.id] = url
            }
        }
        return ShareFiles(mailFile: mailFile, attachmentFiles: files)
    }

    // MARK: - Aufbereitung (rein, getestet)

    /// Bildet HTML mit eingesetzten Bildern und die sichtbaren Anhänge.
    ///
    /// - Parameters:
    ///   - message: Mail.
    ///   - attachments: Alle Anhänge der Mail.
    /// - Returns: Aufbereiteter Inhalt.
    static func content(for message: CachedMessage, attachments: [CachedAttachment]) -> Content {
        Content(
            attachments: attachments,
            visibleAttachments: InlineImages.visibleAttachments(attachments, html: message.htmlBody),
            resolvedHTML: message.htmlBody.map { InlineImages.resolve($0, images: attachments) }
        )
    }

    /// Anzeige-Hinweise einer Mail: gespeichert oder einmal berechnet.
    ///
    /// Verarbeitung: Liest die Hinweise aus dem Cache. Fehlen sie oder ist
    /// ihre Version veraltet, werden sie berechnet und gespeichert – ab dem
    /// nächsten Öffnen liegen sie vor.
    ///
    /// - Parameter message: Mail.
    /// - Returns: Hinweise und ob sie eben berechnet wurden.
    private static func displayHints(for message: CachedMessage) -> (MessageDisplayHints, computed: Bool) {
        if let stored = MessageStore.shared.displayHints(messageID: message.id) {
            return (stored, false)
        }
        let hints = MessageDisplayHints.compute(for: message)
        MessageStore.shared.saveDisplayHints(hints, messageID: message.id)
        return (hints, true)
    }

    /// Ergebnis der Spracherkennung für die Ansicht.
    ///
    /// Verarbeitung: Die Sprache kommt aus den Hinweisen. Die Diagnose
    /// (zweite Erkennung) nur im Debug-Build und nur, wenn die Hinweise
    /// eben neu berechnet wurden – sonst würde sie die gesparte Arbeit
    /// wieder verursachen.
    ///
    /// - Parameters:
    ///   - message: Mail.
    ///   - hints: Anzeige-Hinweise.
    ///   - computed: `true`, wenn die Hinweise eben berechnet wurden.
    /// - Returns: Erkannte Sprache und Protokollzeile.
    private static func languageResult(
        for message: CachedMessage,
        hints: MessageDisplayHints,
        computed: Bool
    ) -> LanguageResult {
        var logLine = "Textteil \(message.textBody == nil ? "nein" : "ja"), HTML \(message.htmlBody == nil ? "nein" : "ja"), "
            + (computed ? "eben berechnet" : "gespeichert")
        #if DEBUG
        if computed {
            let body = SearchText.body(text: message.textBody, html: message.htmlBody)
            logLine += "; " + MessageLanguage.diagnosis(forBody: body)
        }
        #endif
        return LanguageResult(language: hints.language, logLine: logLine)
    }
}
