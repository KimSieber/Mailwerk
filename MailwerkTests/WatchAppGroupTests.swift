//
//  WatchAppGroupTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den gemeinsamen Speicher der Watch-App und ihrer
//  Komplikation (WatchAppGroup, WatchBadge) – Kennung der App Group aus der
//  Bundle-ID, Speichern und Lesen der Zahl der ungelesenen Mails.
//

import Foundation
import Testing
@testable import Mailwerk

@MainActor
struct WatchAppGroupTests {

    /// Watch-App und Komplikation, auch in der Dev-Variante.
    @Test func groupFromBundleID() {
        #expect(WatchAppGroup.identifier(forBundleID: "de.sieber-bw.Mailwerk.watchkitapp") == "group.de.sieber-bw.Mailwerk")
        #expect(WatchAppGroup.identifier(forBundleID: "de.sieber-bw.Mailwerk.dev.watchkitapp") == "group.de.sieber-bw.Mailwerk.dev")
        #expect(WatchAppGroup.identifier(forBundleID: "de.sieber-bw.Mailwerk.watchkitapp.MailwerkWatchWidget") == "group.de.sieber-bw.Mailwerk")
    }

    /// Fremde Bundle-IDs ergeben keine Gruppe.
    @Test func noGroupForOtherBundleIDs() {
        #expect(WatchAppGroup.identifier(forBundleID: "de.sieber-bw.Mailwerk") == nil)
        #expect(WatchAppGroup.identifier(forBundleID: ".watchkitapp") == nil)
    }

    /// Speichern und Lesen; unveränderte Zahl wird nicht neu geschrieben.
    @Test func badgeRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchBadgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(WatchBadge.load(from: directory) == .empty)
        let badge = WatchBadge(unread: 7, updatedAt: Date(timeIntervalSince1970: 1_000))
        #expect(badge.save(to: directory))
        #expect(WatchBadge.load(from: directory) == badge)
        #expect(!badge.save(to: directory))
    }
}
