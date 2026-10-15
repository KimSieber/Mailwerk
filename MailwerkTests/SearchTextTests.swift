//
//  SearchTextTests.swift
//  MailwerkTests
//
//  Zweck: Tests für SearchText – Text aus HTML, Vorrang des Textteils,
//  Kürzung, Personenzeilen und Suchausdruck.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct SearchTextTests {

    /// HTML: Tags, Stil, Skript und Kommentare fallen weg, Entitäten werden aufgelöst.
    @Test func htmlBecomesPlainText() {
        let html = """
            <html><head><title>T</title><style>p { color: red }</style></head>
            <body><!-- versteckt --><p>Gr&uuml;&szlig;e&nbsp;aus</p><script>alert(1)</script>
            <div>Stutt&#103;art &amp; &#xE4;</div></body></html>
            """
        #expect(SearchText.plainText(fromHTML: html) == "Grüße aus Stuttgart & ä")
    }

    /// Blockenden trennen Wörter benachbarter Zellen und Zeilen.
    @Test func blockEndsSeparateWords() {
        #expect(SearchText.plainText(fromHTML: "<td>Rechnung</td><td>Nummer</td>Zeile<br>neu")
                == "Rechnung Nummer Zeile neu")
    }

    /// Fehlerhaftes HTML führt zu keinem Fehler.
    @Test func brokenHTMLIsTolerated() {
        #expect(SearchText.plainText(fromHTML: "<p>offen <b>fett &unbekannt; <") == "offen fett &unbekannt; <")
    }

    /// Der Textteil hat Vorrang; ohne ihn zählt der HTML-Teil.
    @Test func textPartHasPrecedence() {
        #expect(SearchText.body(text: "Text", html: "<p>HTML</p>") == "Text")
        #expect(SearchText.body(text: "  \n", html: "<p>HTML</p>") == "HTML")
        #expect(SearchText.body(text: nil, html: nil) == "")
    }

    /// Sehr lange Texte werden gekürzt.
    @Test func bodyIsLimited() {
        let long = String(repeating: "a", count: SearchText.maxBodyLength + 10)
        #expect(SearchText.body(text: long, html: nil).count == SearchText.maxBodyLength)
    }

    /// Zerlegte Umlaute (z. B. vom Mac) werden zusammengesetzt.
    @Test func bodyIsComposed() {
        #expect(SearchText.body(text: "A\u{0308}rger", html: nil) == "\u{00C4}rger")
    }

    /// Personen: je Adresse eine Zeile `Name <adresse>`, Adresse klein.
    @Test func peopleLines() {
        let people = SearchText.people(
            from: "Anna Muster <Anna@Example.org>",
            to: ["ben@example.org"],
            cc: ["kein Adressformat", " "]
        )
        #expect(people == "Anna Muster <anna@example.org>\n<ben@example.org>\nkein Adressformat")
    }

    /// Ab drei Zeichen wird gesucht; Leerzeichen zählen mit.
    @Test func minimumLengthCountsSpaces() {
        #expect(!SearchText.isSearchable("IS"))
        #expect(SearchText.isSearchable("IS "))
        #expect(SearchText.isSearchable("Rec"))
    }

    /// Suchausdruck: Phrase mit verdoppelten Anführungszeichen, Person in der Spalte people.
    @Test func matchExpression() {
        #expect(SearchText.matchExpression(query: "ab", address: nil) == nil)
        #expect(SearchText.matchExpression(query: "IS ", address: nil) == "\"IS \"")
        #expect(SearchText.matchExpression(query: "a\"b-c", address: nil) == "\"a\"\"b-c\"")
        #expect(SearchText.matchExpression(query: "", address: "Anna@Example.org")
                == "people : \"<anna@example.org>\"")
        #expect(SearchText.matchExpression(query: "Rechnung", address: "a@b.de")
                == "people : \"<a@b.de>\" AND \"Rechnung\"")
    }
}
