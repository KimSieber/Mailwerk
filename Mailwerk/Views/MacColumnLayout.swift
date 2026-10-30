//
//  MacColumnLayout.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 27.10.2026
//  Geändert: 27.10.2026
//
//  Zweck: Reine Breitenlogik des Mac-Fensters.
//  Das Fenster übernimmt das Spaltengerüst des iPad: feste Ordnerleiste,
//  Mailliste und Mailansicht mit festen Breiten. Je nach Fensterbreite
//  gilt eine von drei Stufen:
//
//  1. Drei Spalten (Breite ≥ 280 + 380 + 450 = 1110 pt und Ordnerleiste
//     eingeschaltet): Ordnerleiste, Liste, Mailansicht. Beim Verkleinern
//     wird zuerst die Mailansicht schmaler.
//  2. Zwei Spalten (Breite ≥ 380 + 450 = 830 pt): Liste und Mailansicht;
//     die Ordnerleiste erscheint auf Knopfdruck als einblendbare Leiste.
//  3. Eine Spalte (darunter): wie auf dem iPhone – erst die Liste über die
//     volle Breite, eine geöffnete Mail verdeckt sie; ein Zurück-Knopf
//     schließt die Mail wieder.
//
//  Ohne geöffnete Mail reicht die Liste in allen Stufen bis zum rechten
//  Rand (neben der Ordnerleiste, falls diese fest steht).
//
//  Der Ordner-Knopf (und ⌥⌘S) schaltet in breiten Fenstern (≥ 1110 pt)
//  die feste Ordnerleiste ein und aus; in schmaleren Fenstern öffnet er
//  die einblendbare Leiste.
//
//  Die Logik ist frei von SwiftUI-Ansichten und plattformneutral, damit
//  sie sich ohne Oberfläche prüfen lässt (MacColumnLayoutTests).
//
//  Abgrenzung: Aufbau der Spalten → InboxView (`macColumns`).
//
//  Abhängigkeiten: CoreGraphics (CGFloat, CGSize).
//

import CoreGraphics

/// Breitenstufen und Spaltenaufteilung des Mac-Fensters.
nonisolated enum MacColumnLayout {

    // MARK: - Maße

    /// Breite der festen Ordnerleiste (wie iPad).
    static let sidebarWidth: CGFloat = 280
    /// Breite der Mailliste neben einer geöffneten Mail (wie iPad quer).
    static let listWidth: CGFloat = 380
    /// Mindestbreite der Mailansicht.
    static let detailMinWidth: CGFloat = 450
    /// Mindestbreite des Fensters (= eine Spalte).
    static let windowMinWidth: CGFloat = 380
    /// Mindesthöhe des Fensters.
    static let windowMinHeight: CGFloat = 500
    /// Standardgröße des Fensters.
    static let defaultSize = CGSize(width: 1200, height: 750)

    /// Ab dieser Breite stehen drei Spalten.
    static let threeColumnMinWidth: CGFloat = sidebarWidth + listWidth + detailMinWidth
    /// Ab dieser Breite stehen Liste und Mailansicht nebeneinander.
    static let twoColumnMinWidth: CGFloat = listWidth + detailMinWidth

    // MARK: - Stufen

    /// Breitenstufe des Fensters.
    nonisolated enum Stage: Equatable, Sendable {
        /// Ordnerleiste, Liste, Mailansicht.
        case threeColumns
        /// Liste und Mailansicht; Ordnerleiste einblendbar.
        case twoColumns
        /// Eine Spalte wie auf dem iPhone.
        case singleColumn
    }

    /// Wirkung des Ordner-Knopfs bzw. des Befehls ⌥⌘S.
    nonisolated enum FolderButtonAction: Equatable, Sendable {
        /// Feste Ordnerleiste ein- bzw. ausschalten.
        case toggleSidebar
        /// Einblendbare Ordnerleiste öffnen bzw. schließen.
        case toggleDrawer
    }

    /// Aufteilung des Fensters für eine Breite und einen Zustand.
    nonisolated struct Columns: Equatable, Sendable {
        /// Breitenstufe.
        let stage: Stage
        /// Feste Ordnerleiste steht links.
        let showsSidebar: Bool
        /// Breite der Liste; `nil` = bis zum rechten Rand.
        let listWidth: CGFloat?
        /// Liste ist sichtbar (in Stufe 3 mit geöffneter Mail verdeckt).
        let showsList: Bool
        /// Mailansicht ist sichtbar.
        let showsDetail: Bool
        /// Zurück-Knopf über der Mailansicht (nur Stufe 3).
        let showsBackButton: Bool
    }

    /// Breitenstufe für eine Fensterbreite.
    ///
    /// Verarbeitung: Ist die feste Ordnerleiste ausgeschaltet, gilt ein
    /// breites Fenster als Stufe 2.
    ///
    /// - Parameters:
    ///   - width: Breite des Fensterinhalts in Punkt.
    ///   - sidebarEnabled: Feste Ordnerleiste ist eingeschaltet.
    /// - Returns: Stufe.
    static func stage(width: CGFloat, sidebarEnabled: Bool) -> Stage {
        if width >= threeColumnMinWidth && sidebarEnabled { return .threeColumns }
        if width >= twoColumnMinWidth { return .twoColumns }
        return .singleColumn
    }

    /// Spaltenaufteilung für Breite, Ordnerleiste und geöffnete Mail.
    ///
    /// Verarbeitung: Ohne Mail füllt die Liste den Rest; mit Mail hat sie
    /// in Stufe 1 und 2 die feste Breite, in Stufe 3 tritt sie zurück
    /// (Breite 0, bleibt aber bestehen – Suche und Scrollposition bleiben
    /// erhalten).
    ///
    /// - Parameters:
    ///   - width: Breite des Fensterinhalts in Punkt.
    ///   - sidebarEnabled: Feste Ordnerleiste ist eingeschaltet.
    ///   - hasMessage: Eine Mail ist geöffnet.
    /// - Returns: Aufteilung.
    static func columns(width: CGFloat, sidebarEnabled: Bool, hasMessage: Bool) -> Columns {
        let stage = stage(width: width, sidebarEnabled: sidebarEnabled)
        let showsSidebar = stage == .threeColumns
        guard hasMessage else {
            return Columns(
                stage: stage, showsSidebar: showsSidebar, listWidth: nil,
                showsList: true, showsDetail: false, showsBackButton: false
            )
        }
        if stage == .singleColumn {
            return Columns(
                stage: stage, showsSidebar: false, listWidth: 0,
                showsList: false, showsDetail: true, showsBackButton: true
            )
        }
        return Columns(
            stage: stage, showsSidebar: showsSidebar, listWidth: listWidth,
            showsList: true, showsDetail: true, showsBackButton: false
        )
    }

    /// Wirkung des Ordner-Knopfs für eine Fensterbreite.
    ///
    /// Verarbeitung: Ab 1110 pt schaltet er die feste Leiste – auch wieder
    /// ein, wenn sie ausgeschaltet war; darunter öffnet er die
    /// einblendbare Leiste.
    ///
    /// - Parameter width: Breite des Fensterinhalts in Punkt.
    /// - Returns: Auszuführende Aktion.
    static func folderButtonAction(width: CGFloat) -> FolderButtonAction {
        width >= threeColumnMinWidth ? .toggleSidebar : .toggleDrawer
    }
}
