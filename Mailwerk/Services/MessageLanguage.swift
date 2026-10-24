//
//  MessageLanguage.swift
//  Mailwerk
//
//  Zweck: Erkennt die Sprache einer Mail (aus ihrem Text, nicht dem
//  Betreff) mit Apples on-device-Spracherkennung (NaturalLanguage) und
//  prüft, ob Apples on-device-Übersetzung dieses Sprachpaar nach Deutsch
//  überhaupt anbietet. Beides läuft vollständig lokal; die Prüfung der
//  Übersetzbarkeit braucht kein Netz, auch wenn das Sprachmodell selbst
//  noch nicht heruntergeladen ist.
//
//  Erkannt wird allein aus dem Text der Mail (`SearchText.body`), nicht
//  dem Betreff: Ein Betreff kann z. B. nur aus einem Firmennamen bestehen
//  und würde die Sprache des eigentlichen Texts falsch widerspiegeln.
//  Sehr kurze Mails (z. B. nur eine Signatur) werden bewusst nicht
//  bewertet – zu wenig Text für eine zuverlässige Erkennung.
//
//  Ein Fehlalarm (falsche oder keine Sprache erkannt) ist unkritisch: Es
//  erscheint nur ein unnötiger bzw. fehlender Übersetzungs-Knopf, nichts
//  wird automatisch geladen, gesendet oder gespeichert.
//
//  Erkennt Apple eine fremde Sprache, übersetzt sie aber nicht (Sprachpaar
//  nicht unterstützt, z. B. Isländisch), erscheint kein Knopf.
//
//  Von Mailwerk selbst weitergeleitete Mails: Vor dem eigentlich
//  weitergeleiteten Inhalt steht die eigene (meist deutsche) Signatur
//  sowie der Kopfblock der Weiterleitung (Von/Datum/Betreff/An/Cc,
//  ebenfalls deutsch) – das würde die Erkennung sonst zugunsten von
//  Deutsch verfälschen. Erkannt an `ReplyBuilder.forwardSeparator`, der
//  Trennzeile, die Mailwerk selbst einfügt; danach werden zeilenweise die
//  bekannten Kopfzeilen-Labels übersprungen, bis die erste Inhaltszeile
//  kommt – nur dieser Teil wird dann bewertet. Absichtlich ohne Annahme
//  einer Leerzeile dazwischen: Bei einer formatiert verfassten Mail
//  entsteht der Textteil aus dem Editor-Inhalt (`RichTextHTML.plainText`)
//  mit einfachem Zeilenumbruch zwischen den Absätzen, nicht mit einer
//  Leerzeile wie im reinen Text-Pfad (`ReplyBuilder.forwardText`).
//  Weiterleitungen anderer Mail-Programme (andere Trennzeilen) erkennt
//  das nicht – dort bleibt der gesamte Text Grundlage wie bisher.
//
//  Vor der Erkennung fällt weg, was keine Sprache trägt: HTML-Entitäten
//  (Newsletter füllen damit die Vorschauzeile, im Textteil bleiben sie
//  als Text stehen), Links, Mailadressen, unsichtbare Zeichen.
//
//  Abgrenzung: Reiner Text aus HTML → SearchText. Die eigentliche
//  Übersetzung (an Apples Translation-Framework gebunden, braucht eine
//  SwiftUI-Sitzung über `.translationTask`) → MessageDetailView.
//
//  Abhängigkeiten: Foundation, NaturalLanguage, Translation, SearchText,
//  ReplyBuilder (nur die Trennzeile `forwardSeparator`).
//

import Foundation
import NaturalLanguage
import Translation

/// Erkennt die Sprache einer Mail und prüft ihre Übersetzbarkeit.
nonisolated enum MessageLanguage {

    /// Mindestlänge des Texts, unter der keine Erkennung versucht wird.
    static let minimumTextLength = 20

    /// Ermittelt die dominante Sprache aus dem Text einer Mail.
    ///
    /// Verarbeitung: Zu kurzer Text liefert `nil`, bevor überhaupt
    /// erkannt wird. Deutsch (auch als Ergebnis der Erkennung) liefert
    /// ebenfalls `nil` – dafür gibt es keinen Übersetzungs-Hinweis.
    ///
    /// - Parameter body: Reiner Text der Mail, z. B. aus `SearchText.body`.
    /// - Returns: Erkannte fremde Sprache; `nil` ohne zuverlässigen Treffer
    ///   oder bei Deutsch.
    static func detectedLanguage(forBody body: String) -> Locale.Language? {
        let relevant = textForDetection(body)
        guard relevant.count >= minimumTextLength else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(relevant)
        guard let language = recognizer.dominantLanguage, language != .german else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }

    /// Text, der tatsächlich bewertet wird: ohne den Kopfblock einer
    /// Weiterleitung und ohne Bestandteile, die keine Sprache tragen.
    ///
    /// Verarbeitung: Erst `relevantText` (braucht die Zeilen), dann
    /// `withoutNoise`, zuletzt wird Leerraum zusammengefasst – sonst
    /// zählten bloße Leerzeilen für die Mindestlänge mit.
    ///
    /// - Parameter body: Reiner Text der Mail.
    /// - Returns: Bereinigter Text für die Erkennung.
    private static func textForDetection(_ body: String) -> String {
        replacing("\\s+", in: withoutNoise(relevantText(in: body)), with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Entfernt, was keine Sprache trägt, die Erkennung aber verfälscht.
    ///
    /// Verarbeitung: HTML-Entitäten (`&zwnj;`, `&nbsp;`, `&#228;` …),
    /// Links, Mailadressen und unsichtbare Zeichen fallen weg. Anlass:
    /// Newsletter füllen die Vorschauzeile mit hunderten `&zwnj;`, die
    /// im Textteil als reiner Text stehen bleiben – die Erkennung hielt
    /// das wiederholte „zwnj“ für Polnisch. Links bestehen aus
    /// englisch wirkenden Wortteilen und verschieben die Erkennung
    /// ebenso, ohne etwas über die Sprache der Mail zu sagen.
    ///
    /// - Parameter text: Text der Mail.
    /// - Returns: Text ohne diese Bestandteile.
    private static func withoutNoise(_ text: String) -> String {
        var result = text
        for pattern in [
            "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,30});",
            "(https?://|www\\.)\\S+",
            "\\S+@\\S+\\.\\S+",
        ] {
            result = replacing(pattern, in: result, with: " ")
        }
        return replacing("[\\u00AD\\u200B-\\u200D\\u2060\\uFEFF]", in: result, with: "")
    }

    /// Ersetzt alle Treffer eines regulären Ausdrucks (ohne
    /// Groß-/Kleinschreibung).
    ///
    /// - Parameters:
    ///   - pattern: Regulärer Ausdruck.
    ///   - text: Text.
    ///   - replacement: Ersatz.
    /// - Returns: Text mit Ersetzungen; unverändert bei ungültigem Ausdruck.
    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    /// Blendet bei einer von Mailwerk selbst weitergeleiteten Mail die
    /// eigene Signatur und den Kopfblock der Weiterleitung aus, damit
    /// deren Deutsch nicht die Erkennung des weitergeleiteten Inhalts
    /// verfälscht.
    ///
    /// Verarbeitung: Erkannt allein an `ReplyBuilder.forwardSeparator`.
    /// Steht die Trennzeile im Text, werden ab dort zeilenweise leere
    /// Zeilen und Kopfzeilen mit einem der bekannten Labels „Von“,
    /// „Datum“, „Betreff“, „An“, „Cc“ übersprungen (siehe
    /// `ReplyBuilder.forwardHeaderLines`); die erste Zeile, die weder
    /// leer ist noch mit einem dieser Labels beginnt, markiert den
    /// Beginn des eigentlichen Originalinhalts. Ohne Trennzeile (keine
    /// Weiterleitung oder von einem anderen Mail-Programm weitergeleitet)
    /// bzw. ohne eine solche Inhaltszeile bleibt der Text unverändert.
    ///
    /// - Parameter body: Reiner Text der Mail.
    /// - Returns: Nur der weitergeleitete Originalinhalt, falls erkannt;
    ///   sonst unverändert `body`.
    private static func relevantText(in body: String) -> String {
        // Mails kommen mit CRLF-Zeilenenden; in Swift ist „\r\n“ ein
        // einziges Zeichen und würde von `split(separator: "\n")` nicht
        // getrennt. Deshalb zuerst einheitlich auf LF bringen.
        let body = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let separatorRange = body.range(of: ReplyBuilder.forwardSeparator) else { return body }
        let headerLabels: Set<String> = ["Von", "Datum", "Betreff", "An", "Cc"]
        let afterSeparator = body[separatorRange.upperBound...]
        var remainingLines = afterSeparator.split(separator: "\n", omittingEmptySubsequences: false)[...]
        while let line = remainingLines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                remainingLines = remainingLines.dropFirst()
                continue
            }
            if let colonIndex = trimmed.firstIndex(of: ":"),
               headerLabels.contains(String(trimmed[trimmed.startIndex..<colonIndex])) {
                remainingLines = remainingLines.dropFirst()
                continue
            }
            break
        }
        let content = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? body : content
    }

    /// Kurzbeschreibung der Erkennung für das Protokoll – ohne Mailinhalt.
    ///
    /// Verarbeitung: Nennt die Länge des Texts, ob die Trennzeile einer
    /// Weiterleitung gefunden wurde, die Länge des tatsächlich bewerteten
    /// Teils und Apples drei wahrscheinlichste Sprachen mit Anteil. Dient
    /// allein der Fehleranalyse („kein Knopf, obwohl fremde Sprache“).
    ///
    /// - Parameter body: Reiner Text der Mail, wie für `detectedLanguage`.
    /// - Returns: z. B. „Text 2814, Trennzeile ja, bewertet 1932,
    ///   Hypothesen en 0.97 de 0.02“.
    static func diagnosis(forBody body: String) -> String {
        let relevant = textForDetection(body)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(relevant)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
            .sorted { $0.value > $1.value }
            .map { "\($0.key.rawValue) \(String(format: "%.2f", $0.value))" }
            .joined(separator: " ")
        let hasSeparator = body.contains(ReplyBuilder.forwardSeparator) ? "ja" : "nein"
        return "Text \(body.count), Trennzeile \(hasSeparator), bewertet \(relevant.count), "
            + "Hypothesen \(hypotheses.isEmpty ? "keine" : hypotheses)"
    }

    /// Prüft, ob Apples on-device-Übersetzung dieses Sprachpaar nach
    /// Deutsch kennt – unabhängig davon, ob das Sprachmodell schon
    /// heruntergeladen ist (das entscheidet erst der eigentliche
    /// Übersetzungsversuch).
    ///
    /// - Parameter language: Erkannte Sprache der Mail.
    /// - Returns: `true` bei `.supported` oder `.installed`; `false` bei
    ///   `.unsupported`.
    static func isTranslatable(_ language: Locale.Language) async -> Bool {
        let status = await LanguageAvailability().status(from: language, to: Locale.Language(identifier: "de"))
        return status != .unsupported
    }

    /// Deutscher Name einer Sprache für den Übersetzungs-Hinweis, z. B.
    /// „Schwedisch“.
    ///
    /// - Parameter language: Sprache, z. B. aus `detectedLanguage`.
    /// - Returns: Name auf Deutsch; der Sprachcode, falls kein Name
    ///   bekannt ist.
    static func germanName(for language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier else { return "Unbekannt" }
        return Locale(identifier: "de").localizedString(forLanguageCode: code) ?? code
    }
}
