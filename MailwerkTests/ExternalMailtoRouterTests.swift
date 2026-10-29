//
//  ExternalMailtoRouterTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Annahme von mailto:-Links von außen
//  (ExternalMailtoRouter): vormerken, nur letzter Link, Warten auf
//  offene Fenster, kein Postfach.
//

import Foundation
import Testing
@testable import Mailwerk

/// Tests für ExternalMailtoRouter.
@MainActor
struct ExternalMailtoRouterTests {

    /// Testhilfe: Link als URL.
    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    /// Ein mailto:-Link wird angenommen und ist bei freiem Bildschirm dran.
    @Test func acceptsMailtoLink() {
        let router = ExternalMailtoRouter()
        #expect(router.receive(url("mailto:a@example.org")))
        #expect(router.isReadyToPresent)
        guard case .compose(let request) = router.takePending(hasAccounts: true) else {
            Issue.record("Verfassen erwartet"); return
        }
        #expect(request.link?.to == ["a@example.org"])
        #expect(router.pending == nil)
    }

    /// Andere Schemata werden abgelehnt.
    @Test func rejectsOtherSchemes() {
        let router = ExternalMailtoRouter()
        #expect(!router.receive(url("https://example.org")))
        #expect(!router.receive(url("msauth.de.sieber-bw.Mailwerk://auth?code=1")))
        #expect(router.pending == nil)
    }

    /// Das Schema wird ohne Groß-/Kleinschreibung erkannt.
    @Test func schemeIsCaseInsensitive() {
        let router = ExternalMailtoRouter()
        #expect(router.receive(url("MAILTO:a@example.org")))
    }

    /// Ein Link ohne Inhalt öffnet eine leere neue Mail.
    @Test func emptyLinkOpensEmptyCompose() {
        let router = ExternalMailtoRouter()
        #expect(router.receive(url("mailto:")))
        guard case .compose(let request) = router.takePending(hasAccounts: true) else {
            Issue.record("Verfassen erwartet"); return
        }
        #expect(request.link == nil)
    }

    /// Nur der zuletzt eingegangene Link zählt.
    @Test func lastLinkWins() {
        let router = ExternalMailtoRouter()
        router.receive(url("mailto:erster@example.org"))
        router.receive(url("mailto:zweiter@example.org"))
        guard case .compose(let request) = router.takePending(hasAccounts: true) else {
            Issue.record("Verfassen erwartet"); return
        }
        #expect(request.link?.to == ["zweiter@example.org"])
    }

    /// Bei offenem Fenster wartet der Link bis zum Schließen.
    @Test func waitsForOpenWindow() {
        let router = ExternalMailtoRouter()
        router.windowDidAppear()
        router.receive(url("mailto:a@example.org"))
        #expect(!router.isReadyToPresent)
        #expect(router.takePending(hasAccounts: true) == nil)
        #expect(router.pending != nil)

        router.windowDidDisappear()
        #expect(router.isReadyToPresent)
    }

    /// Verschachtelte Fenster: erst nach dem letzten Schließen dran.
    @Test func waitsForNestedWindows() {
        let router = ExternalMailtoRouter()
        router.windowDidAppear()
        router.windowDidAppear()
        router.receive(url("mailto:a@example.org"))
        router.windowDidDisappear()
        #expect(!router.isReadyToPresent)
        router.windowDidDisappear()
        #expect(router.isReadyToPresent)
    }

    /// Der Zähler fällt nie unter null.
    @Test func counterNeverNegative() {
        let router = ExternalMailtoRouter()
        router.windowDidDisappear()
        #expect(router.openWindowCount == 0)
        router.windowDidAppear()
        #expect(router.openWindowCount == 1)
    }

    /// Ohne Postfach: Hinweis, der Link wird verworfen.
    @Test func noAccountShowsNoticeAndDropsLink() {
        let router = ExternalMailtoRouter()
        router.receive(url("mailto:a@example.org"))
        #expect(router.takePending(hasAccounts: false) == .noAccount)
        #expect(router.pending == nil)
        #expect(router.takePending(hasAccounts: true) == nil)
    }
}
