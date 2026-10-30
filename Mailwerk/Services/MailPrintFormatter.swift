//
//  MailPrintFormatter.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 10.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Baut aus einer Mail ein eigenständiges HTML-Dokument für Druck
//  und Teilen – Kopfdaten (Von, An, Kopie, Datum, Betreff), Inhalt und
//  eine Liste der Anhänge. Fürs Teilen wird es als temporäre .html-Datei
//  abgelegt, benannt nach dem Betreff.
//
//  Geteilt wird eine Datei statt einer formatierten Zeichenkette:
//  NSAttributedString(data:options:.html) ist für komplexe HTML-Mails
//  (Google, Newsletter) unzuverlässig und scheitert still. Eine .html-Datei
//  kann jeder Empfänger öffnen, und das System kann sie als PDF rendern.
//
//  Externe Inhalte folgen der Anzeige: Sind sie dort nicht freigegeben,
//  sperrt dieselbe Content-Security-Policy wie in der Anzeige sie auch
//  beim Drucken und in der geteilten Datei (RemoteContentPolicy). Die
//  Regel steht in der Datei selbst und gilt damit auch, wenn der
//  Empfänger sie im Browser öffnet.
//
//  Eingebettete Bilder (`cid:`) folgen ebenfalls der Anzeige: Sie werden
//  als `data:`-Adressen eingesetzt (InlineImages), die Datei ist damit in
//  sich geschlossen.
//
//  Kopfdaten, Dateinamen und Textmails werden für HTML maskiert. Eine
//  reine Textmail erscheint als vorformatierter Block. Breite Tabellen
//  und Bilder werden auf die Seitenbreite begrenzt.
//
//  Ohne Oberfläche, deshalb ohne Gerät testbar.
//
//  Abgrenzung: Drucken → MailPrinter; Teilen-Menü → MessageDetailView
//  (`ShareLink`); Anzeige der Mail → HTMLMailView.
//
//  Nebenläufigkeit (v0.2.3d, P-11): `nonisolated` – reine Aufbereitung;
//  die Datei zum Teilen schreibt MessageOpenPreparation im Hintergrund.
//
//  Abhängigkeiten: CachedMessage, CachedAttachment, RemoteContentPolicy,
//  InlineImages, HTMLEscaping.
//

import Foundation

/// HTML-Fassung einer Mail für Druck und Teilen.
nonisolated enum MailPrintFormatter {

    /// Höchstlänge des Dateinamens aus dem Betreff (ohne Endung).
    static let maxFilenameLength = 60

    /// Vollständiges HTML-Dokument der Mail.
    ///
    /// Verarbeitung: Sicherheitsregeln im Kopf; Kopfdaten maskiert; Inhalt
    /// als HTML-Teil mit eingesetzten eingebetteten Bildern oder – bei
    /// reinen Textmails – maskiert in `<pre>`; am Ende die Anhangliste.
    ///
    /// - Parameters:
    ///   - message: Mail.
    ///   - attachments: Anhänge für die Liste am Ende.
    ///   - inlineImages: Anhänge der Mail, aus denen eingebettete Bilder
    ///     eingesetzt werden.
    ///   - allowsRemoteContent: `true`, wenn externe Inhalte in der Anzeige
    ///     freigegeben sind; sonst bleiben sie gesperrt.
    /// - Returns: HTML-Dokument.
    static func html(
        for message: CachedMessage,
        attachments: [CachedAttachment] = [],
        inlineImages: [CachedAttachment] = [],
        allowsRemoteContent: Bool = false
    ) -> String {
        let body = message.htmlBody.map { InlineImages.resolve($0, images: inlineImages) }
            ?? "<pre>\(HTMLEscaping.escaped(message.textBody ?? ""))</pre>"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(RemoteContentPolicy.headTags(allowsRemoteContent: allowsRemoteContent))
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(style)</style>
        </head>
        <body>
        <div class="mail-header">\(header(for: message))</div>
        \(body)
        \(attachmentSection(attachments))
        </body>
        </html>
        """
    }

    /// Legt die Mail als temporäre HTML-Datei zum Teilen ab.
    ///
    /// Verarbeitung: Dateiname aus dem Betreff plus „.html“ im temporären
    /// Verzeichnis; eine gleichnamige Datei wird überschrieben.
    ///
    /// - Parameters:
    ///   - message: Mail.
    ///   - attachments: Anhänge für die Liste am Ende.
    ///   - inlineImages: Anhänge der Mail, aus denen eingebettete Bilder
    ///     eingesetzt werden.
    ///   - allowsRemoteContent: `true`, wenn externe Inhalte in der Anzeige
    ///     freigegeben sind.
    /// - Returns: URL der Datei.
    /// - Throws: Fehler beim Schreiben.
    static func writeTemporaryFile(
        for message: CachedMessage,
        attachments: [CachedAttachment] = [],
        inlineImages: [CachedAttachment] = [],
        allowsRemoteContent: Bool = false
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(forSubject: message.subject) + ".html")
        let document = html(
            for: message, attachments: attachments,
            inlineImages: inlineImages, allowsRemoteContent: allowsRemoteContent
        )
        try Data(document.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Dateiname aus dem Betreff, ohne Endung.
    ///
    /// Verarbeitung: „/“ und „:“ werden zu „-“, Leerraum an den Rändern
    /// entfällt, gekürzt auf `maxFilenameLength` Zeichen. Leerer Betreff
    /// ergibt „Mail“.
    ///
    /// - Parameter subject: Betreff.
    /// - Returns: Dateiname.
    static func filename(forSubject subject: String) -> String {
        let cleaned = subject
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Mail" : String(cleaned.prefix(maxFilenameLength))
    }

    // MARK: - Teile

    /// Gestaltung des Dokuments: Schrift, Kopfbereich, Begrenzung breiter
    /// Inhalte auf die Seitenbreite.
    private static let style = """
        body {
            font-family: -apple-system, Helvetica, sans-serif;
            font-size: 12pt;
            color: #333;
            margin: 0;
            padding: 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        .mail-header {
            border-bottom: 1px solid #ccc;
            padding-bottom: 8pt;
            margin-bottom: 12pt;
            font-size: 10pt;
            line-height: 1.6;
        }
        table, div, td, th, img, video, object {
            max-width: 100% !important;
            height: auto !important;
        }
        table[width], td[width], th[width] {
            width: auto !important;
        }
        img { display: block; }
        pre, code {
            white-space: pre-wrap;
            word-wrap: break-word;
            max-width: 100%;
        }
        """

    /// Kopfdaten als HTML-Zeilen.
    ///
    /// - Parameter message: Mail.
    /// - Returns: Von, An, ggf. Kopie und Datum, Betreff – maskiert.
    private static func header(for message: CachedMessage) -> String {
        var lines = [
            "<b>Von:</b> \(HTMLEscaping.escaped(message.from))",
            "<b>An:</b> \(HTMLEscaping.escaped(message.to))"
        ]
        if !message.headers.ccList.isEmpty {
            lines.append("<b>Kopie:</b> \(HTMLEscaping.escaped(message.headers.ccList.joined(separator: ", ")))")
        }
        if let date = message.date {
            let style = Date.FormatStyle(
                date: .complete, time: .shortened, locale: Locale(identifier: "de_DE")
            )
            lines.append("<b>Datum:</b> \(date.formatted(style))")
        }
        lines.append("<b>Betreff:</b> \(HTMLEscaping.escaped(message.subject))")
        return lines.map { $0 + "<br>" }.joined()
    }

    /// Anhangliste.
    ///
    /// - Parameter attachments: Anhänge.
    /// - Returns: HTML-Abschnitt; leer ohne Anhänge.
    private static func attachmentSection(_ attachments: [CachedAttachment]) -> String {
        guard !attachments.isEmpty else { return "" }
        let rows = attachments.map { attachment in
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(attachment.sizeBytes), countStyle: .file
            )
            return "<tr><td style=\"padding:4pt 8pt 4pt 0\">\(icon(for: attachment.contentType))</td>"
                + "<td style=\"padding:4pt 0\">\(HTMLEscaping.escaped(attachment.filename))</td>"
                + "<td style=\"padding:4pt 0 4pt 12pt;color:#888\">\(size)</td></tr>"
        }.joined()
        return """
            <div style="border-top:1px solid #ccc;margin-top:16pt;padding-top:8pt;font-size:10pt">
            <b>Anlagen (\(attachments.count)):</b>
            <table style="margin-top:4pt">\(rows)</table>
            </div>
            """
    }

    /// Symbol für einen Anhang nach seinem MIME-Typ.
    ///
    /// - Parameter contentType: MIME-Typ.
    /// - Returns: Emoji für die Anhangliste.
    private static func icon(for contentType: String) -> String {
        let type = contentType.lowercased()
        if type.hasPrefix("image/") { return "🖼️" }
        if type.contains("pdf") { return "📄" }
        if type.contains("zip") || type.contains("archive") || type.contains("compressed") { return "📦" }
        if type.contains("text/") { return "📝" }
        if type.contains("audio/") { return "🎵" }
        if type.contains("video/") { return "🎬" }
        return "📎"
    }
}
