//
//  ReplyBuilder.swift
//  Mailwerk
//
//  Zweck: Erzeugt die Vorbelegung des Composers für Neue Mail, Antworten,
//  Allen antworten und Weiterleiten – Absende-Postfach, Empfänger, Betreff,
//  Zitat bzw. weitergeleiteter Inhalt (HTML und Text) und Threading-Header.
//
//  Zitat aus HTML-Mails: Übernommen wird der gesamte Inhalt, unverändert.
//  Nur die Hüllen-Tags selbst (DOCTYPE, `<html>`, `<head>`, `<body>` mit
//  ihren End-Tags) entfallen, weil ein ganzes Dokument nicht in die eigene
//  Mail geschachtelt werden darf. Es wird nichts ausgeschnitten: Manche
//  Mails sind Fragmente mit einem vollständigen Dokument mittendrin
//  (Inhalt vor `<body>` und nach `</html>`); ein Browser übergeht die
//  falschen Tags und zeigt alles an – das Zitat tut dasselbe. Stile aus
//  dem `<head>` bleiben damit erhalten, wie in der Anzeige des Originals.
//  Eine Bereinigung (Skripte, Event-Handler, Stile) findet bewusst nicht
//  statt:
//  - In Mailwerk erscheint das Zitat in der Vorschau beim Verfassen und
//    später in der Gesendet-Kopie – beide Male über HTMLMailView, mit
//    abgeschaltetem JavaScript, gesperrter Navigation und gesperrten
//    externen Inhalten.
//  - Beim Empfänger schützt dessen Mailprogramm, das Skripte aus Mails
//    nicht ausführt und externe Inhalte selbst behandelt. Der Inhalt
//    stammt vom ursprünglichen Absender, nicht von Mailwerk.
//  Eine Bereinigung per Regex böte keinen verlässlichen Schutz und würde
//  die Mail verändern.
//
//  Reine Logik ohne Netzwerk und UI, vollständig durch ReplyBuilderTests
//  abgedeckt.
//
//  Abgrenzung: Anzeige des Zitats → ComposeView (HTMLMailView);
//  Zusammenbau der zu sendenden Mail → ComposeViewModel, MailSendService.
//
//  Abhängigkeiten: Foundation, CachedMessage, MailAddress, HTMLEscaping.
//

import Foundation

/// Art der zu verfassenden Nachricht.
enum ComposeKind: Equatable {
    /// Neue Mail ohne Bezug.
    case new
    /// Antwort an den Absender.
    case reply
    /// Antwort an alle Beteiligten.
    case replyAll
    /// Weiterleitung.
    case forward
}

/// Vorbelegung des Composers.
struct ComposePrefill: Equatable {
    /// Absende-Postfach. nil = der Nutzer muss selbst wählen.
    var accountID: UUID?
    /// Empfänger (An).
    var to: [MailAddress] = []
    /// Kopie-Empfänger (Cc).
    var cc: [MailAddress] = []
    /// Betreff.
    var subject: String = ""
    /// Zitat bzw. weitergeleiteter Inhalt. Wird im Composer schreibgeschützt
    /// angezeigt und beim Senden unter den eigenen Text gesetzt.
    var quotedHTML: String?
    /// Nur-Text-Fassung desselben Inhalts (für den Textteil der Mail).
    var quotedText: String?
    /// Threading-Header der Antwort: Message-ID des Originals.
    var inReplyTo: String?
    /// Threading-Header der Antwort: bisherige Kette plus Original.
    var references: String?
}

/// Erzeugt die Vorbelegung des Composers.
enum ReplyBuilder {

    /// Platzhalter, den MailFetchService bei fehlendem Betreff speichert.
    static let missingSubjectPlaceholder = "(kein Betreff)"

    // MARK: - Einstieg

    /// Erzeugt die Vorbelegung für den Composer.
    ///
    /// Verarbeitung: Neue Mail nutzt das Standard-Postfach; Antworten und
    /// Weiterleitungen gehen vom Postfach der Originalmail aus. Antworten
    /// bekommen Zitat und Threading-Header, Weiterleitungen den Kopfblock
    /// des Originals und keine Empfänger.
    ///
    /// - Parameters:
    ///   - kind: Art der Nachricht.
    ///   - original: Bezugsnachricht (bei `.new` ignoriert).
    ///   - defaultAccountID: Standard-Postfach für neue Mails (darf nil sein).
    ///   - ownAddresses: Alle eigenen Adressen – werden bei „Allen antworten“ entfernt.
    /// - Returns: Vorbelegung des Composers.
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

    /// Antwort-Präfixe (Re, AW, Antw, SV, VS), auch mehrfach und mit Zähler.
    private static let replyPrefixPattern =
        #"^\s*(?:(?:re|aw|antw|sv|vs)(?:\[\d+\])?\s*:\s*)+"#
    /// Weiterleitungs-Präfixe (Fwd, Fw, WG), auch mehrfach und mit Zähler.
    private static let forwardPrefixPattern =
        #"^\s*(?:(?:fwd|fw|wg)(?:\[\d+\])?\s*:\s*)+"#

    /// Betreff einer Antwort: alle Antwort-Präfixe zu genau einem „Re: “.
    ///
    /// Beispiel: "Hallo", "Re: Hallo", "AW: Re: Hallo" → "Re: Hallo".
    ///
    /// - Parameter subject: Betreff des Originals.
    /// - Returns: Betreff der Antwort.
    static func replySubject(_ subject: String) -> String {
        "Re: " + stripping(replyPrefixPattern, from: baseSubject(subject))
    }

    /// Betreff einer Weiterleitung: Weiterleitungs-Präfixe zu genau einem
    /// „Fwd: “; Antwort-Präfixe bleiben.
    ///
    /// Beispiel: "WG: Hallo" → "Fwd: Hallo"; "Re: Hallo" → "Fwd: Re: Hallo".
    ///
    /// - Parameter subject: Betreff des Originals.
    /// - Returns: Betreff der Weiterleitung.
    static func forwardSubject(_ subject: String) -> String {
        "Fwd: " + stripping(forwardPrefixPattern, from: baseSubject(subject))
    }

    /// Betreff ohne den Platzhalter für einen fehlenden Betreff.
    ///
    /// - Parameter subject: Gespeicherter Betreff.
    /// - Returns: Betreff oder leere Zeichenkette.
    private static func baseSubject(_ subject: String) -> String {
        subject == missingSubjectPlaceholder ? "" : subject
    }

    /// Entfernt ein Präfix-Muster am Anfang und Leerraum an den Rändern.
    ///
    /// - Parameters:
    ///   - pattern: Regulärer Ausdruck für die Präfixe.
    ///   - text: Betreff.
    /// - Returns: Betreff ohne Präfixe.
    private static func stripping(_ pattern: String, from text: String) -> String {
        replacing(pattern, in: text, with: "", dotAll: false)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Empfänger

    /// Antwort an Reply-To, falls vorhanden, sonst an den Absender.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: Empfänger ohne Doppelte.
    static func replyRecipients(of message: CachedMessage) -> [MailAddress] {
        let source = message.headers.replyToList.isEmpty
            ? [message.from]
            : message.headers.replyToList
        return unique(source.compactMap { MailAddress(parsing: $0) })
    }

    /// Empfänger für „Allen antworten“.
    ///
    /// Verarbeitung: An = Absender (bzw. Reply-To) + ursprüngliche
    /// An-Empfänger, Cc = ursprüngliche Cc-Empfänger. Eigene Adressen und
    /// Doppelte entfallen. Bleibt An leer, rücken die Cc-Empfänger nach;
    /// sind nur eigene Adressen beteiligt, geht die Antwort an den Absender.
    ///
    /// - Parameters:
    ///   - message: Originalmail.
    ///   - ownAddresses: Alle eigenen Adressen.
    /// - Returns: An- und Cc-Empfänger.
    static func replyAllRecipients(
        of message: CachedMessage,
        ownAddresses: Set<String>
    ) -> (to: [MailAddress], cc: [MailAddress]) {
        var seen = Set(ownAddresses.map { $0.lowercased() })
        /// Übernimmt nur Adressen, die noch nicht vorkamen (auch eigene nicht).
        ///
        /// - Parameter list: Kandidaten.
        /// - Returns: Neue Adressen in ursprünglicher Reihenfolge.
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

    /// Entfernt doppelte Adressen, die erste gewinnt.
    ///
    /// - Parameter list: Adressen.
    /// - Returns: Adressen ohne Doppelte.
    private static func unique(_ list: [MailAddress]) -> [MailAddress] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.normalizedAddress).inserted }
    }

    // MARK: - Threading

    /// Threading-Header einer Antwort.
    ///
    /// Verarbeitung: In-Reply-To = Message-ID des Originals; References =
    /// bisherige Kette (oder In-Reply-To) + Message-ID des Originals, ohne
    /// Doppelte.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: Beide Header; ohne Message-ID des Originals beide `nil`.
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

    /// Kopfzeile über dem Zitat, z. B. „Am 14.11.2023 um 22:13 schrieb Anna:“.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: Kopfzeile; ohne Datum nur „… schrieb:“.
    static func quoteHeader(for message: CachedMessage) -> String {
        guard let date = message.date else { return "\(message.from) schrieb:" }
        return "Am \(formatted(date)) schrieb \(message.from):"
    }

    /// HTML-Zitat einer Antwort: Kopfzeile und Original in einem
    /// `blockquote` mit Randlinie.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: HTML-Zitat.
    static func replyQuoteHTML(_ message: CachedMessage) -> String {
        """
        <div>\(HTMLEscaping.escaped(quoteHeader(for: message)))</div>\
        <blockquote type="cite" style="margin:0 0 0 0.8ex;border-left:2px solid #ccc;padding-left:1ex">\
        \(originalBodyHTML(message))\
        </blockquote>
        """
    }

    /// Text-Zitat einer Antwort: Kopfzeile und Original mit „> “ je Zeile.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: Text-Zitat.
    static func replyQuoteText(_ message: CachedMessage) -> String {
        let quoted = originalBodyText(message)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
        return quoteHeader(for: message) + "\n" + quoted
    }

    // MARK: - Weiterleiten

    /// Trennzeile über dem weitergeleiteten Inhalt. Nicht `private`, weil
    /// `MessageLanguage` daran erkennt, wo bei einer selbst
    /// weitergeleiteten Mail der eigentliche Originalinhalt beginnt (für
    /// die Spracherkennung, ohne die eigene Signatur und den Kopfblock).
    /// `nonisolated`, weil `MessageLanguage` nicht an den Main Actor
    /// gebunden ist; als unveränderlicher Text ist das unbedenklich.
    nonisolated static let forwardSeparator = "---------- Weitergeleitete Nachricht ----------"

    /// Zeilen des Kopfblocks einer Weiterleitung (Von, Datum, Betreff, An, Cc).
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: Bezeichnung und Wert je Zeile; leere Angaben entfallen.
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

    /// HTML-Inhalt einer Weiterleitung: Trennzeile, Kopfblock, Original.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: HTML-Inhalt.
    static func forwardHTML(_ message: CachedMessage) -> String {
        let header = forwardHeaderLines(message)
            .map { "<b>\(HTMLEscaping.escaped($0.0)):</b> \(HTMLEscaping.escaped($0.1))" }
            .joined(separator: "<br>")
        return "<div>\(forwardSeparator)<br>\(header)</div><br>\(originalBodyHTML(message))"
    }

    /// Text-Inhalt einer Weiterleitung: Trennzeile, Kopfblock, Original.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: Text-Inhalt.
    static func forwardText(_ message: CachedMessage) -> String {
        let header = forwardHeaderLines(message)
            .map { "\($0.0): \($0.1)" }
            .joined(separator: "\n")
        return "\(forwardSeparator)\n\(header)\n\n\(originalBodyText(message))"
    }

    // MARK: - Inhalt der Originalmail

    /// HTML-Inhalt der Originalmail: bevorzugt ihr HTML-Teil ohne
    /// Dokument-Hülle (siehe `withoutDocumentWrapper(_:)`), sonst der
    /// maskierte Text mit Zeilenumbrüchen.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: HTML zum Einfügen in die eigene Mail.
    static func originalBodyHTML(_ message: CachedMessage) -> String {
        if let html = message.htmlBody, !html.isEmpty {
            return withoutDocumentWrapper(html)
        }
        return textToHTML(message.textBody ?? "")
    }

    /// Text-Inhalt der Originalmail: bevorzugt der Textteil, sonst aus dem
    /// HTML gewonnener Text.
    ///
    /// - Parameter message: Originalmail.
    /// - Returns: Text des Originals.
    static func originalBodyText(_ message: CachedMessage) -> String {
        if let text = message.textBody, !text.isEmpty { return text }
        if let html = message.htmlBody { return plainText(fromHTML: html) }
        return ""
    }

    // MARK: - HTML-Helfer

    /// Wandelt Text in HTML: maskiert, Zeilenumbrüche als `<br>`.
    ///
    /// - Parameter text: Rohtext.
    /// - Returns: HTML.
    static func textToHTML(_ text: String) -> String {
        HTMLEscaping.escaped(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Entfernt die Hüllen-Tags eines HTML-Dokuments und behält allen Inhalt.
    ///
    /// Verarbeitung: Entfernt werden nur DOCTYPE sowie die Start- und
    /// End-Tags von `html`, `head` und `body` – an jeder Stelle, auch
    /// mitten im Text. Inhalt wird nie ausgeschnitten; alles andere, auch
    /// Stile, Skripte und Attribute, bleibt unverändert und in seiner
    /// Reihenfolge. Warum das sicher ist, steht im Dateikopf.
    ///
    /// - Parameter html: HTML-Teil der Originalmail.
    /// - Returns: Inhalt zum Einschachteln in die eigene Mail.
    static func withoutDocumentWrapper(_ html: String) -> String {
        var result = replacing(#"<!DOCTYPE[^>]*>"#, in: html, with: "")
        result = replacing(#"</?(?:html|head|body)\b[^>]*>"#, in: result, with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Einfache Umwandlung von HTML in lesbaren Text (Fallback für den
    /// Textteil, wenn die Mail keinen hat).
    ///
    /// Verarbeitung: Skripte, Stile und Kopf entfallen, Zeilenumbrüche an
    /// `<br>` und Blockenden, übrige Tags entfernt, häufige Entities
    /// übersetzt, mehrfache Leerzeilen zusammengefasst.
    ///
    /// - Parameter html: HTML.
    /// - Returns: Lesbarer Text.
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

    /// Datum im Format „dd.MM.yyyy um HH:mm“ (deutsch).
    ///
    /// - Parameter date: Datum.
    /// - Returns: Formatiertes Datum.
    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy 'um' HH:mm"
        return formatter.string(from: date)
    }

    /// Ersetzt alle Treffer eines regulären Ausdrucks (ohne Groß-/Kleinschreibung).
    ///
    /// - Parameters:
    ///   - pattern: Regulärer Ausdruck.
    ///   - text: Eingabe.
    ///   - template: Ersatz (mit `$1` usw.).
    ///   - dotAll: `true` = „.“ passt auch auf Zeilenumbrüche.
    /// - Returns: Text mit Ersetzungen; bei ungültigem Ausdruck unverändert.
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
}
