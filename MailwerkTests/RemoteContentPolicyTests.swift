//
//  RemoteContentPolicyTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Regeln zu externen Inhalten – Content-Security-Policy
//  mit und ohne Freigabe, ihre Lage im Dokument der Anzeige und die
//  Erkennung externer Verweise.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct RemoteContentPolicyTests {

    /// Gesperrt: nur eingebettete Bilder, keine Quelle über http/https.
    @Test func blockedPolicyAllowsOnlyEmbeddedContent() {
        let tags = RemoteContentPolicy.headTags(allowsRemoteContent: false)
        #expect(tags.contains("default-src 'none'"))
        #expect(tags.contains("img-src data:;"))
        #expect(!tags.contains("https:"))
        #expect(tags.contains("x-dns-prefetch-control"))
    }

    /// Freigegeben: Bilder und Stile über https, Skripte und Frames weiter verboten.
    @Test func allowedPolicyKeepsScriptsAndFramesForbidden() {
        let tags = RemoteContentPolicy.headTags(allowsRemoteContent: true)
        #expect(tags.contains("img-src data: https: http:"))
        #expect(tags.contains("default-src 'none'"))
        #expect(!tags.contains("script-src"))
        #expect(!tags.contains("frame-src"))
        #expect(tags.contains("form-action 'none'"))
    }

    /// Die Regel steht im Kopf der Anzeige, vor dem Inhalt der Mail.
    @Test func documentPlacesPolicyBeforeMailContent() throws {
        let page = HTMLMailView.document(for: "<p>Hallo</p>", allowsRemoteContent: false)
        let policy = try #require(page.range(of: "Content-Security-Policy"))
        let body = try #require(page.range(of: "<body>"))
        #expect(policy.lowerBound < body.lowerBound)
        #expect(page.contains(RemoteContentPolicy.blockedPolicy))
    }

    /// Bilder über https, protokollrelativ und in `srcset` werden erkannt.
    @Test func detectsRemoteImages() {
        #expect(RemoteContentPolicy.containsRemoteReferences(#"<img src="https://t.example/p.gif">"#))
        #expect(RemoteContentPolicy.containsRemoteReferences(#"<IMG SRC='//cdn.example/a.png'>"#))
        #expect(RemoteContentPolicy.containsRemoteReferences(#"<img srcset="a.png 1x, https://x.example/b.png 2x">"#))
    }

    /// Hintergrund-Attribut und Video-Vorschaubild werden erkannt.
    @Test func detectsBackgroundAndPoster() {
        #expect(RemoteContentPolicy.containsRemoteReferences(#"<td background="http://x.example/bg.jpg">"#))
        #expect(RemoteContentPolicy.containsRemoteReferences(#"<video poster="https://x.example/v.jpg">"#))
    }

    /// CSS-`url(…)` und `@import` werden erkannt.
    @Test func detectsCSSReferences() {
        #expect(RemoteContentPolicy.containsRemoteReferences(#"<div style="background:url('https://x.example/a.png')">"#))
        #expect(RemoteContentPolicy.containsRemoteReferences("<style>@import 'x.css';</style>"))
    }

    /// Ein verlinktes Stylesheet wird erkannt.
    @Test func detectsLinkedStylesheet() {
        #expect(RemoteContentPolicy.containsRemoteReferences(#"<link rel="stylesheet" href="https://x.example/s.css">"#))
    }

    /// Gewöhnliche Links, eingebettete Bilder und reiner Text gelten nicht als extern.
    @Test func ignoresLinksEmbeddedImagesAndText() {
        #expect(!RemoteContentPolicy.containsRemoteReferences(#"<a href="https://example.org">Seite</a>"#))
        #expect(!RemoteContentPolicy.containsRemoteReferences(#"<img src="data:image/png;base64,AAAA">"#))
        #expect(!RemoteContentPolicy.containsRemoteReferences("<p>Siehe https://example.org</p>"))
    }
}
