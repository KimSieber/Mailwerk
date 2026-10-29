//
//  MessageLanguageTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Spracherkennung – Mindestlänge, Deutsch liefert
//  keinen Treffer, fremde Sprachen werden erkannt, deutsche Sprachnamen.
//
//  `isTranslatable` ist nicht getestet: Es fragt Apples echtes, auf dem
//  Gerät installiertes Sprachmodell ab (kein Mock möglich) und wäre im
//  Testlauf langsam und vom jeweiligen Gerät abhängig.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MessageLanguageTests {

    /// Zu kurzer Text liefert keinen Treffer, auch bei eindeutiger Sprache.
    @Test func tooShortTextYieldsNoResult() {
        #expect(MessageLanguage.detectedLanguage(forBody: "Hello") == nil)
    }

    /// Deutscher Text liefert keinen Treffer – dafür gibt es keinen Hinweis.
    @Test func germanTextYieldsNoResult() {
        let text = "Guten Tag, anbei die gewünschten Unterlagen zu unserem Termin nächste Woche."
        #expect(MessageLanguage.detectedLanguage(forBody: text) == nil)
    }

    /// Englischer Text wird als solcher erkannt.
    @Test func englishTextIsDetected() {
        let text = "Dear team, please find attached the documents for our meeting next week."
        let language = MessageLanguage.detectedLanguage(forBody: text)
        #expect(language?.languageCode?.identifier == "en")
    }

    /// Französischer Text wird als solcher erkannt.
    @Test func frenchTextIsDetected() {
        let text = "Bonjour, veuillez trouver ci-joint les documents pour notre réunion de la semaine prochaine."
        let language = MessageLanguage.detectedLanguage(forBody: text)
        #expect(language?.languageCode?.identifier == "fr")
    }

    /// Deutsche Sprachnamen für den Übersetzungs-Hinweis.
    @Test func germanNames() {
        #expect(MessageLanguage.germanName(for: Locale.Language(identifier: "en")) == "Englisch")
        #expect(MessageLanguage.germanName(for: Locale.Language(identifier: "fr")) == "Französisch")
        #expect(MessageLanguage.germanName(for: Locale.Language(identifier: "sv")) == "Schwedisch")
    }

    /// Von Mailwerk selbst weitergeleitete Mail: Der deutsche Kopfblock
    /// (Von/Datum/Betreff/An) vor dem englischen Originalinhalt verfälscht
    /// die Erkennung nicht mehr (siehe `ReplyBuilder.forwardSeparator`).
    @Test func forwardedEnglishTextIsDetectedDespiteGermanHeader() {
        let text = """
        ---------- Weitergeleitete Nachricht ----------
        Von: Apple Developer <developer@email.apple.com>
        Datum: 21.10.2026 um 22:12
        Betreff: Your Default Mail App entitlement request status is ready.
        An: kim.sieber@example.com

        Hello Kim, thank you for your interest in Default Mail App. After careful \
        consideration, we regret that we're unable to approve your request at this time.
        """
        let language = MessageLanguage.detectedLanguage(forBody: text)
        #expect(language?.languageCode?.identifier == "en")
    }

    /// Dasselbe wie oben, aber ohne Leerzeile zwischen Kopfblock und
    /// Originalinhalt – so entsteht der Textteil einer formatiert
    /// verfassten Mail tatsächlich (`RichTextHTML.plainText`, einfacher
    /// Zeilenumbruch je Absatz statt einer Leerzeile wie im reinen
    /// Text-Pfad). Auch ohne Leerzeile muss die Inhaltszeile erkannt werden.
    @Test func forwardedEnglishTextIsDetectedWithoutBlankLineAfterHeader() {
        let text = """
        ---------- Weitergeleitete Nachricht ----------
        Von: Apple Developer <developer@email.apple.com>
        Datum: 21.10.2026 um 22:12
        Betreff: Your Default Mail App entitlement request status is ready.
        An: kim.sieber@example.com
        Hello Kim, thank you for your interest in Default Mail App. After careful \
        consideration, we regret that we're unable to approve your request at this time.
        """
        let language = MessageLanguage.detectedLanguage(forBody: text)
        #expect(language?.languageCode?.identifier == "en")
    }

    /// Wie eine echte Mail: Zeilenenden CRLF, davor die eigene deutsche
    /// Signatur. In Swift ist „\r\n“ ein einziges Zeichen – die Erkennung
    /// des Kopfblocks muss trotzdem greifen.
    @Test func forwardedEnglishTextWithCRLFAndSignatureIsDetected() {
        let lines = [
            "",
            "Kim Sieber",
            "Grünewaldstraße 4",
            "70192 Stuttgart",
            "",
            "---------- Weitergeleitete Nachricht ----------",
            "Von: Apple Developer <developer@email.apple.com>",
            "Datum: 21.10.2026 um 22:12",
            "Betreff: Your Default Mail App entitlement request status is ready.",
            "An: kim.sieber@example.com",
            "",
            "Hello Kim Jan,",
            "Thank you for your interest in Default Mail App. After careful consideration,",
            "we regret that we're unable to approve your request at this time.",
        ]
        let text = lines.joined(separator: "\r\n")
        let language = MessageLanguage.detectedLanguage(forBody: text)
        #expect(language?.languageCode?.identifier == "en")
    }

    /// Newsletter-Textteil wie bei einem Bank-Newsletter: hunderte `&zwnj;`
    /// als Text und viele Links, dazwischen deutscher Text. Ohne
    /// Bereinigung hielt die Erkennung das für Polnisch.
    @Test func entitiesAndLinksDoNotOutweighGermanText() {
        let filler = Array(repeating: "&zwnj;", count: 150).joined(separator: " ")
        let text = """
          Beispiel Bank
          \(filler)
          https://view.mailer.beispiel-bank.example/?vawpToken=ABCDEFGHIJKLMNOPQRSTUVWXYZ.000000
        Zur Webansicht
        https://de.beispiel-bank.example
         https://apps.apple.com/de/app/beispiel-bank-etf-aktien/id0000000000
         Derivate und Kryptowährungen bergen hohe Risiken. Der Wert Ihrer Kapitalanlage kann \
        schwanken, Verluste sind möglich. Frühere Wertentwicklungen sind kein Indikator für die Zukunft.
         Beispiel Bank GmbH, Musterstraße 1, 12345 Musterstadt
        """
        #expect(MessageLanguage.detectedLanguage(forBody: text) == nil)
    }

    /// Nur Füllzeichen und Links, kein Text: zu wenig für eine Erkennung.
    @Test func onlyEntitiesAndLinksYieldNoResult() {
        let filler = Array(repeating: "&zwnj;&nbsp;", count: 100).joined()
        let text = filler + " https://example.com/some/long/path?with=parameters info@example.com"
        #expect(MessageLanguage.detectedLanguage(forBody: text) == nil)
    }

    /// Ohne die Trennzeile (keine Weiterleitung oder aus einem anderen
    /// Mail-Programm) bleibt der gesamte Text Grundlage – hier überwiegt
    /// Deutsch, deshalb kein Treffer.
    @Test func textWithoutForwardSeparatorUsesWholeBody() {
        let text = """
        Guten Tag Herr Müller,

        anbei wie besprochen die Unterlagen. Viele Grüße
        Kim Sieber

        Hello, this is a short quoted line.
        """
        #expect(MessageLanguage.detectedLanguage(forBody: text) == nil)
    }
}
