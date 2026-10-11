//
//  UndoOffer.swift
//  Mailwerk
//
//  Zweck: Angebot „Rückgängig“ nach einer Änderung von Kennzeichnung oder
//  Gelesen-Status in der Liste – welche Änderung, an welchen Mails, und
//  der Text für den Hinweis am unteren Rand.
//
//  Enthalten sind nur die Mails, die sich tatsächlich geändert haben.
//  „Rückgängig“ nimmt genau diese Änderung zurück.
//
//  Abgrenzung: Anzeige und Zeitgeber → InboxView/InboxViewModel;
//  Ausführung → MessageActions.
//
//  Abhängigkeiten: MessageActions (Target, StateChange).
//

import Foundation

/// Angebot, eine eben ausgeführte Änderung zurückzunehmen.
struct UndoOffer: Identifiable {
    /// Kennung für SwiftUI; jedes Angebot ist neu.
    let id = UUID()
    /// Ausgeführte Änderung (mit dem gesetzten Wert).
    let change: MessageActions.StateChange
    /// Mails, an denen sie ausgeführt wurde.
    let targets: [MessageActions.Target]

    /// Text des Hinweises.
    var text: String { Self.text(for: change, count: targets.count) }

    /// Text des Hinweises zu einer Änderung.
    ///
    /// - Parameters:
    ///   - change: Ausgeführte Änderung.
    ///   - count: Anzahl der geänderten Mails.
    /// - Returns: Kurzer Text, ab zwei Mails mit Anzahl.
    static func text(for change: MessageActions.StateChange, count: Int) -> String {
        let isSingle = count <= 1
        switch change {
        case .flagged(true):
            return isSingle ? "Gekennzeichnet" : "\(count) Mails gekennzeichnet"
        case .flagged(false):
            return isSingle ? "Kennzeichnung entfernt" : "Kennzeichnung bei \(count) Mails entfernt"
        case .read(true):
            return isSingle ? "Als gelesen markiert" : "\(count) Mails als gelesen markiert"
        case .read(false):
            return isSingle ? "Als ungelesen markiert" : "\(count) Mails als ungelesen markiert"
        }
    }
}
