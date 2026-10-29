//
//  MacColumnLayoutTests.swift
//  MailwerkTests
//
//  Zweck: Tests für die Breitenstufen des Mac-Fensters (MacColumnLayout).
//

import CoreGraphics
import Testing
@testable import Mailwerk

struct MacColumnLayoutTests {

    /// Grenzen der Stufen: 1110 pt drei, 830 pt zwei Spalten.
    @Test func stageBoundaries() {
        #expect(MacColumnLayout.stage(width: 1200, sidebarEnabled: true) == .threeColumns)
        #expect(MacColumnLayout.stage(width: 1110, sidebarEnabled: true) == .threeColumns)
        #expect(MacColumnLayout.stage(width: 1109, sidebarEnabled: true) == .twoColumns)
        #expect(MacColumnLayout.stage(width: 830, sidebarEnabled: true) == .twoColumns)
        #expect(MacColumnLayout.stage(width: 829, sidebarEnabled: true) == .singleColumn)
        #expect(MacColumnLayout.stage(width: 380, sidebarEnabled: true) == .singleColumn)
    }

    /// Ausgeschaltete Ordnerleiste: breites Fenster verhält sich wie Stufe 2.
    @Test func disabledSidebarActsLikeTwoColumns() {
        #expect(MacColumnLayout.stage(width: 1400, sidebarEnabled: false) == .twoColumns)
        let columns = MacColumnLayout.columns(width: 1400, sidebarEnabled: false, hasMessage: true)
        #expect(!columns.showsSidebar)
        #expect(columns.listWidth == 380)
    }

    /// Ohne Mail reicht die Liste bis zum Rand, keine Mailansicht.
    @Test func noMessageListFillsWidth() {
        for width: CGFloat in [400, 900, 1300] {
            let columns = MacColumnLayout.columns(width: width, sidebarEnabled: true, hasMessage: false)
            #expect(columns.listWidth == nil)
            #expect(columns.showsList)
            #expect(!columns.showsDetail)
            #expect(!columns.showsBackButton)
        }
        #expect(MacColumnLayout.columns(width: 1300, sidebarEnabled: true, hasMessage: false).showsSidebar)
        #expect(!MacColumnLayout.columns(width: 900, sidebarEnabled: true, hasMessage: false).showsSidebar)
    }

    /// Mit Mail: drei bzw. zwei Spalten mit fester Listenbreite.
    @Test func messageInWideWindows() {
        let three = MacColumnLayout.columns(width: 1200, sidebarEnabled: true, hasMessage: true)
        #expect(three.showsSidebar && three.showsList && three.showsDetail)
        #expect(three.listWidth == 380)
        #expect(!three.showsBackButton)

        let two = MacColumnLayout.columns(width: 900, sidebarEnabled: true, hasMessage: true)
        #expect(!two.showsSidebar && two.showsList && two.showsDetail)
        #expect(two.listWidth == 380)
    }

    /// Eine Spalte: Mail über volle Breite, Liste tritt zurück, Zurück-Knopf.
    @Test func singleColumnWithMessage() {
        let columns = MacColumnLayout.columns(width: 600, sidebarEnabled: true, hasMessage: true)
        #expect(columns.stage == .singleColumn)
        #expect(!columns.showsList)
        #expect(columns.listWidth == 0)
        #expect(columns.showsDetail)
        #expect(columns.showsBackButton)
    }

    /// Ordner-Knopf: breit feste Leiste schalten, schmaler einblendbare Leiste.
    @Test func folderButtonAction() {
        #expect(MacColumnLayout.folderButtonAction(width: 1110) == .toggleSidebar)
        #expect(MacColumnLayout.folderButtonAction(width: 1109) == .toggleDrawer)
        #expect(MacColumnLayout.folderButtonAction(width: 500) == .toggleDrawer)
    }

    /// Maße wie vereinbart.
    @Test func agreedMeasures() {
        #expect(MacColumnLayout.threeColumnMinWidth == 1110)
        #expect(MacColumnLayout.twoColumnMinWidth == 830)
        #expect(MacColumnLayout.windowMinWidth == 380)
        #expect(MacColumnLayout.windowMinHeight == 500)
        #expect(MacColumnLayout.defaultSize == CGSize(width: 1200, height: 750))
    }
}
