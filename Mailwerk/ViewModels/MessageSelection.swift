//
//  MessageSelection.swift
//  Mailwerk
//
//  Zweck: Regeln für Aktionen an mehreren ausgewählten Mails.
//
//  - Gemischte Auswahl: Ist mindestens eine Mail nicht gekennzeichnet,
//    kennzeichnet die Aktion; sonst entfernt sie die Kennzeichnung.
//    Ebenso beim Gelesen-Status: Ist mindestens eine ungelesen, markiert
//    die Aktion als gelesen; sonst als ungelesen.
//  - Geändert werden nur Mails, deren Zustand abweicht – genau diese
//    nimmt „Rückgängig“ später zurück.
//  - Verschieben geht nur, wenn alle Mails aus demselben Postfach stammen.
//  - Ziehen auf einen Ordner (iPad): nur Mails aus der Liste, nur in einen
//    gültigen Ordner desselben Postfachs.
//
//  Abgrenzung: Ausführung → MessageActions; Zustand der Auswahl →
//  InboxViewModel; Darstellung → InboxView, SelectionActionBar.
//
//  Abhängigkeiten: MessageListItem, MessageActions (Target, StateChange),
//  FolderNode.
//

import Foundation

/// Regeln für Aktionen an mehreren Mails.
enum MessageSelection {

    /// Kennzeichnungs-Änderung für eine Auswahl.
    ///
    /// - Parameter items: Ausgewählte Mails.
    /// - Returns: `.flagged(true)`, wenn mindestens eine nicht
    ///   gekennzeichnet ist, sonst `.flagged(false)`.
    static func flagChange(for items: [MessageListItem]) -> MessageActions.StateChange {
        .flagged(items.contains { !$0.isFlagged })
    }

    /// Gelesen-Änderung für eine Auswahl.
    ///
    /// - Parameter items: Ausgewählte Mails.
    /// - Returns: `.read(true)`, wenn mindestens eine ungelesen ist, sonst
    ///   `.read(false)`.
    static func readChange(for items: [MessageListItem]) -> MessageActions.StateChange {
        .read(items.contains { $0.isUnread })
    }

    /// Mails, an denen eine Änderung tatsächlich etwas bewirkt.
    ///
    /// - Parameters:
    ///   - change: Geplante Änderung.
    ///   - items: Ausgewählte Mails.
    /// - Returns: Ziele der Mails mit abweichendem Zustand.
    static func targets(for change: MessageActions.StateChange, in items: [MessageListItem]) -> [MessageActions.Target] {
        items.filter { item in
            switch change {
            case .flagged(let value): return item.isFlagged != value
            case .read(let value): return item.isUnread == value
            }
        }
        .map { MessageActions.Target($0) }
    }

    /// Prüft, ob die Auswahl verschoben werden kann.
    ///
    /// - Parameter items: Ausgewählte Mails.
    /// - Returns: `true`, wenn sie nicht leer ist und alle Mails aus
    ///   demselben Postfach stammen.
    static func canMove(_ items: [MessageListItem]) -> Bool {
        Set(items.map(\.accountID)).count == 1
    }

    /// Gemeinsamer Ordner der Auswahl – im Verschieben-Dialog ausgegraut.
    ///
    /// - Parameter items: Ausgewählte Mails.
    /// - Returns: Ordnerpfad, wenn alle Mails im selben Ordner liegen, sonst `nil`.
    static func commonFolder(_ items: [MessageListItem]) -> String? {
        let folders = Set(items.map(\.folder))
        return folders.count == 1 ? folders.first : nil
    }

    /// Mails, die per Ziehen in einen Ordner verschoben werden.
    ///
    /// Verarbeitung: Gezogen wird nur die Kennung einer Mail. Berücksichtigt
    /// werden ausschließlich Kennungen, die in der Liste stehen – fremde
    /// Texte, die jemand auf einen Ordner zieht, bewirken nichts. Wie beim
    /// Verschieben per Menü nur innerhalb des Postfachs und nur in einen
    /// gültigen Zielordner (nicht der eigene, kein reiner Container).
    ///
    /// - Parameters:
    ///   - ids: Gezogene Kennungen.
    ///   - items: Einträge der Liste.
    ///   - accountID: Postfach des Zielordners.
    ///   - folder: Zielordner.
    /// - Returns: Zu verschiebende Mails in der Reihenfolge der Liste.
    static func dropTargets(
        ids: [String],
        in items: [MessageListItem],
        accountID: UUID,
        folder: FolderNode
    ) -> [MessageListItem] {
        let dragged = Set(ids)
        return items.filter { item in
            dragged.contains(item.id)
                && item.accountID == accountID
                && folder.isMoveTarget(from: item.folder)
        }
    }
}
