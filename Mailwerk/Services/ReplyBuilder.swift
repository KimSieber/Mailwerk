//
//  ReplyBuilder.swift
//  Mailwerk
//
//  Reine Logik ohne Netzwerk und UI: erzeugt die Vorbelegung des Composers
//  für Neue Mail, Antworten, Allen antworten und Weiterleiten.
//  Vollständig durch ReplyBuilderTests abgedeckt.
//

import Foundation

/// Art der zu verfassenden Nachricht.
enum ComposeKind: Equatable {
    case new, reply, replyAll, forward
}

/// Vorbelegung des Composers.
struct ComposePrefill: Equatable {
    /// Absende-Postfach. nil = der Nutzer muss selbst wählen.
    var accountID: UUID?
    var to: [MailAddress] = []
    var cc: [MailAddress] = []
    var subject: String = ""
    /// Zitat bzw. weitergeleiteter Inhalt. Wird im Composer schreibgeschützt
    /// angezeigt und beim Senden unter den eigenen Text gesetzt.
    var quotedHTML: String?
    /// Nur-Text-Fassung desselben Inhalts (für den Textteil der Mail).
    var quotedText: String?
    /// Threading-Header der Antwort.
    var inReplyTo: String?
    var references: String?
}

enum ReplyBuilder {

    /// Platzhalter, den MailFetchService bei fehlendem Betreff speichert.
    static let missingSubjectPlaceholder = "(kein Betreff)"

    // MARK: - Einstieg

    /// Erzeugt die Vorbelegung für den Composer.
    /// - Parameters:
    ///   - kind: Art der Nachricht
    ///   - original: Bezugsnachricht (bei `.new` ignoriert)
    ///   - defaultAccountID: Standard-Postfach für neue Mails (darf nil sein)
    ///   - ownAddresses: alle eigenen Adressen – werden bei „Allen antworten" entfernt
    static func prefill(
        kind: ComposeKind,
        original: CachedMessage?,
        defaultAccountID: UUID?,
        ownAddresses: Set<String>
    ) -> ComposePrefill {
        guard kind != .new, let original else {
            return ComposePrefill(accountID: defaultAccountID)
        }

        // Antwort/Weiterleitung geht vom Postfach der Originalmail aus
        var prefill = ComposePrefill(accountID: original.accountID)

        switch kind {
        case .reply:
            prefill.to = replyRecipients(of: original)
            prefill.subject = replySubject(original.subject)
        case .replyAll:
            let recipients = replyAllRecipients(of: original, ownAddresses: ownAddresses)
            prefill.to = recipients.to
            prefill.cc = recipients.cc
            prefill.subject = replySubject(original.subject)
        case .forward:
            prefill.subject = forwardSubject(original.subject)
        case .new:
            break
        }

        if kind == .forward {
            prefill.quotedHTML = forwardHTML(original)
            prefill.quotedText = forwardText(original)
        } else {
            prefill.quotedHTML = replyQuoteHTML(original)
            prefill.quotedText = replyQuoteText(original)
            let threading = threadingHeaders(for: original)
            prefill.inReplyTo = threading.inReplyTo
            prefill.references = threading.references
        }
        return prefill
    }

    // MARK: - Betreff

    private static let replyPrefixPattern =
        #"^\s*(?:(?:re|aw|antw|sv|vs)(?:\[\d+\])?\s*:\s*)+"#
    private static let forwardPrefixPattern =
        #"^\s*(?:(?:fwd|fw|wg)(?:\[\d+\])?\s*:\s*)+"#

    /// "Hallo", "Re: Hallo", "AW: Re: Hallo" → "Re: Hallo"
    static func replySubject(_ subject: String) -> String {
        "Re: " + stripping(replyPrefixPattern, from: baseSubject(subject))
    }

    /// "Hallo", "WG: Hallo" → "Fwd: Hallo"; "Re: Hallo" → "Fwd: Re: Hallo"
    static func forwardSubject(_ subject: String) -> String {
        "Fwd: " + stripping(forwardPrefixPattern, from: baseSubject(subject))
    }

    private static func baseSubject(_ subject: String) -> String {
        subject == missingSubjectPlaceholder ? "" : subject
    }

    private static func stripping(_ pattern: String, from text: String) -> String {
        replacing(pattern, in: text, with: "", dotAll: false)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Empfänger

    /// Antwort an Reply-To, falls vorhanden, sonst an den Absender.
    static func replyRecipients(of message: CachedMessage) -> [MailAddress] {
        let source = message.headers.replyToList.isEmpty
            ? [message.from]
            : message.headers.replyToList
        return unique(source.compactMap { MailAddress(parsing: $0) })
    }

    /// Allen antworten: An = Absender (bzw. Reply-To) + ursprüngliche An-Empfänger,
    /// Cc = ursprüngliche Cc-Empfänger. Eigene Adressen und Doppelte entfallen.
    static func replyAllRecipients(
        of message: CachedMessage,
        ownAddresses: Set<String>
    ) -> (to: [MailAddress], cc: [MailAddress]) {
        var seen = Set(ownAddresses.map { $0.lowercased() })
        func take(_ list: [MailAddress]) -> [MailAddress] {
            list.filter { seen.insert($0.normalizedAddress).inserted }
        }

        let primary = replyRecipients(of: message)
        let to = take(primary + message.headers.toList.compactMap { MailAddress(parsing: $0) })
        let cc = take(message.headers.ccList.compactMap { MailAddress(parsing: $0) })

        switch (to.isEmpty, cc.isEmpty) {
        case (true, true):  return (primary, [])   // nur eigene Adressen beteiligt
        case (true, false): return (cc, [])        // An-Feld nicht leer lassen
        default:            return (to, cc)
        }
    }

    private static func unique(_ list: [MailAddress]) -> [MailAddress] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.normalizedAddress).inserted }
    }

    // MARK: - Threading

    /// In-Reply-To = Message-ID des Originals,
    /// References = bisherige Kette (oder In-Reply-To) + Message-ID des Originals.
    static func threadingHeaders(
        for message: CachedMessage
    ) -> (inReplyTo: String?, references: String?) {
        guard let id = message.headers.rfcMessageID, !id.isEmpty else {
            return (nil, nil)
        }
        let chain = message.headers.rfcReferences ?? message.headers.rfcInReplyTo ?? ""
        var seen = Set<String>()
        let references = (chain.split(whereSeparator: \.isWhitespace).map(String.init) + [id])
            .filter { seen.insert($0).inserted }
        return (id, references.joined(separator: " "))
    }

    // MARK: - Zitat (Antworten)

    static func quoteHeader(for message: CachedMessage) -> String {
        guard let date = message.date else { return "\(message.from) schrieb:" }
        return "Am \(formatted(date)) schrieb \(message.from):"
    }

    static func replyQuoteHTML(_ message: CachedMessage) -> String {
        """
        <div>\(escapeHTML(quoteHeader(for: message)))</div>\
        <blockquote type="cite" style="margin:0 0 0 0.8ex;border-left:2px solid #ccc;padding-left:1ex">\
        \(originalBodyHTML(message))\
        </blockquote>
        """
    }

    static func replyQuoteText(_ message: CachedMessage) -> String {
        let quoted = originalBodyText(message)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
        return quoteHeader(for: message) + "\n" + quoted
    }

    // MARK: - Weiterleiten

    private static let forwardSeparator = "---------- Weitergeleitete Nachricht ----------"

    private static func forwardHeaderLines(_ message: CachedMessage) -> [(String, String)] {
        var lines: [(String, String)] = [("Von", message.from)]
        if let date = message.date { lines.append(("Datum", formatted(date))) }
        lines.append(("Betreff", message.subject))
        if !message.to.isEmpty { lines.append(("An", message.to)) }
        if !message.headers.ccList.isEmpty {
            lines.append(("Cc", message.headers.ccList.joined(separator: ", ")))
        }
        return lines
    }

    static func forwardHTML(_ message: CachedMessage) -> String {
        let header = forwardHeaderLines(message)
            .map { "<b>\(escapeHTML($0.0)):</b> \(escapeHTML($0.1))" }
            .joined(separator: "<br>")
        return "<div>\(forwardSeparator)<br>\(header)</div><br>\(originalBodyHTML(message))"
    }

    static func forwardText(_ message: CachedMessage) -> String {
        let header = forwardHeaderLines(message)
            .map { "\($0.0): \($0.1)" }
            .joined(separator: "\n")
        return "\(forwardSeparator)\n\(header)\n\n\(originalBodyText(message))"
    }

    // MARK: - Inhalt der Originalmail

    /// HTML-Inhalt der Originalmail: bevorzugt der bereinigte HTML-Body,
    /// sonst der maskierte Text mit Zeilenumbrüchen.
    static func originalBodyHTML(_ message: CachedMessage) -> String {
        if let html = message.htmlBody, !html.isEmpty {
            return sanitizedBodyContent(html)
        }
        return textToHTML(message.textBody ?? "")
    }

    /// Text-Inhalt der Originalmail: bevorzugt der Textteil,
    /// sonst aus dem HTML gewonnener Text.
    static func originalBodyText(_ message: CachedMessage) -> String {
        if let text = message.textBody, !text.isEmpty { return text }
        if let html = message.htmlBody { return plainText(fromHTML: html) }
        return ""
    }

    // MARK: - HTML-Helfer

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func textToHTML(_ text: String) -> String {
        escapeHTML(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Nur der Inhalt von <body>, ohne <head>/Stylesheets, Skripte,
    /// Event-Handler und javascript:-Links.
    static func sanitizedBodyContent(_ html: String) -> String {
        var result = html
        if let body = firstCapture(#"<body[^>]*>(.*)</body\s*>"#, in: result) {
            result = body
        }
        result = replacing(#"<head\b[^>]*>.*?</head\s*>"#, in: result, with: "")
        result = replacing(#"<script\b[^>]*>.*?</script\s*>"#, in: result, with: "")
        result = replacing(#"</?(?:html|body)\b[^>]*>"#, in: result, with: "")
        result = replacing(#"\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#, in: result, with: "")
        result = replacing(#"(href|src)\s*=\s*(["']?)\s*javascript:[^"'\s>]*\2"#,
                           in: result, with: "$1=\"#\"")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Einfache Umwandlung von HTML in lesbaren Text (Fallback für den Textteil).
    static func plainText(fromHTML html: String) -> String {
        var text = replacing(#"<(script|style|head)\b[^>]*>.*?</\1\s*>"#, in: html, with: "")
        text = replacing(#"<br\s*/?>"#, in: text, with: "\n")
        text = replacing(#"</(?:p|div|li|tr|h[1-6])\s*>"#, in: text, with: "\n")
        text = replacing(#"<[^>]+>"#, in: text, with: "")
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        text = replacing(#"\n{3,}"#, in: text, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Allgemeine Helfer

    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy 'um' HH:mm"
        return formatter.string(from: date)
    }

    private static func replacing(
        _ pattern: String,
        in text: String,
        with template: String,
        dotAll: Bool = true
    ) -> String {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }
}
