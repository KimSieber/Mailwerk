//
//  MailWebViewPoolTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Vorrat an Web-Ansichten (MailWebViewPool,
//  Prüfbericht P-12): Vorwärmen, Entnehmen, Zurücklegen, Höchstzahl.
//

import Foundation
import SwiftUI
import Testing
import WebKit
@testable import Mailwerk

/// Tests für MailWebViewPool.
@MainActor
struct MailWebViewPoolTests {

    /// Testhilfe: Vorrat mit zählender Fabrik.
    private final class Counter {
        /// Anzahl erzeugter Ansichten.
        var created = 0
    }

    /// Testhilfe: Vorrat mit gegebener Höchstzahl.
    private func pool(capacity: Int = 2, counter: Counter) -> MailWebViewPool {
        MailWebViewPool(capacity: capacity) {
            counter.created += 1
            return WKWebView(frame: .zero)
        }
    }

    /// Vorwärmen legt genau eine Ansicht bereit, auch bei mehrfachem Aufruf.
    @Test("Vorwärmen legt genau eine Ansicht bereit")
    func prewarmCreatesOne() {
        let counter = Counter()
        let pool = pool(counter: counter)
        pool.prewarm()
        pool.prewarm()
        #expect(pool.availableCount == 1)
        #expect(counter.created == 1)
    }

    /// Entnehmen nutzt die vorgewärmte Ansicht, ohne eine neue zu erzeugen.
    @Test("Entnehmen nutzt die vorgewärmte Ansicht")
    func takeUsesPrewarmed() {
        let counter = Counter()
        let pool = pool(counter: counter)
        pool.prewarm()
        _ = pool.take()
        #expect(counter.created == 1)
        #expect(pool.availableCount == 0)
    }

    /// Leerer Vorrat: Entnehmen erzeugt eine neue Ansicht.
    @Test("Leerer Vorrat erzeugt beim Entnehmen eine neue Ansicht")
    func takeCreatesWhenEmpty() {
        let counter = Counter()
        let pool = pool(counter: counter)
        _ = pool.take()
        #expect(counter.created == 1)
    }

    /// Zurückgelegte Ansicht wird wiederverwendet.
    @Test("Zurückgelegte Ansicht wird wiederverwendet")
    func recycledViewIsReused() {
        let counter = Counter()
        let pool = pool(counter: counter)
        let first = pool.take()
        pool.recycle(first)
        let second = pool.take()
        #expect(first === second)
        #expect(counter.created == 1)
    }

    /// Über der Höchstzahl werden zurückgelegte Ansichten verworfen.
    @Test("Über der Höchstzahl wird verworfen")
    func respectsCapacity() {
        let counter = Counter()
        let pool = pool(capacity: 1, counter: counter)
        let a = pool.take()
        let b = pool.take()
        pool.recycle(a)
        pool.recycle(b)
        #expect(pool.availableCount == 1)
    }

    /// Zurücksetzen löst die Verbindung zur alten Mail.
    @Test("Zurücklegen löst den Navigation-Delegate")
    func recycleClearsDelegate() {
        let counter = Counter()
        let pool = pool(counter: counter)
        let webView = pool.take()
        let delegate = HTMLMailView.Coordinator(HTMLMailView(html: "", contentHeight: .constant(0)))
        webView.navigationDelegate = delegate
        pool.recycle(webView)
        #expect(webView.navigationDelegate == nil)
    }
}
