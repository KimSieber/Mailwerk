//
//  MailAppearanceTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Darstellung im Dunkelmodus – Erkennung eigener
//  Farben (MailAppearance) und die passenden Farbregeln im Grundgerüst
//  der Anzeige (HTMLMailView).
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct MailAppearanceTests {

    /// Schlichte Mail ohne Farben folgt dem Dunkelmodus.
    @Test func plainMailHasNoOwnColors() {
        #expect(!MailAppearance.usesOwnColors(#"<div dir="ltr">Hallo<br><b>Gruß</b></div>"#))
    }

    /// Hintergrund als Attribut oder CSS zählt als eigene Farbe.
    @Test func backgroundCountsAsOwnColor() {
        #expect(MailAppearance.usesOwnColors(##"<table bgcolor="#ffffff"><tr><td>x</td></tr></table>"##))
        #expect(MailAppearance.usesOwnColors(#"<div style="background-color: #fff">x</div>"#))
        #expect(MailAppearance.usesOwnColors(#"<div style="background:#F4F4F4">x</div>"#))
    }

    /// Schriftfarbe als CSS, `<font color>` oder `<body text>` zählt.
    @Test func textColorCountsAsOwnColor() {
        #expect(MailAppearance.usesOwnColors(#"<p style="COLOR:#000000">x</p>"#))
        #expect(MailAppearance.usesOwnColors(#"<style>a:link { color: #0563C1; }</style>"#))
        #expect(MailAppearance.usesOwnColors(#"<font face="Arial" color="red">x</font>"#))
        #expect(MailAppearance.usesOwnColors(##"<body text="#333333">x</body>"##))
    }

    /// Rahmenfarben u. Ä. sind keine Hintergrund- oder Schriftfarbe.
    @Test func borderColorIsNoOwnColor() {
        #expect(!MailAppearance.usesOwnColors(#"<td style="border-color:#ccc; border-bottom-color: red">x</td>"#))
    }

    /// Grundgerüst: mit eigenen Farben weiße Fläche im Dunkelmodus, sonst helle Schrift.
    @Test func documentChoosesColorRules() {
        let own = HTMLMailView.document(for: #"<p style="color:#000">x</p>"#, allowsRemoteContent: false)
        #expect(own.contains("html { background-color: #FFFFFF; }"))
        #expect(own.contains(#"<meta name="color-scheme" content="light">"#))
        #expect(!own.contains("#F0F0F0"))

        let plain = HTMLMailView.document(for: "<p>x</p>", allowsRemoteContent: false)
        #expect(plain.contains("body { color: #F0F0F0; }"))
        #expect(!plain.contains(#"name="color-scheme""#))
    }

    /// Grundgerüst begrenzt den Zoom nicht mehr.
    @Test func documentAllowsZoom() {
        let document = HTMLMailView.document(for: "<p>x</p>", allowsRemoteContent: false)
        #expect(document.contains(#"content="width=device-width, initial-scale=1""#))
        #expect(!document.contains("maximum-scale"))
    }
}
