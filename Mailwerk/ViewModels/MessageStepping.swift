//
//  MessageStepping.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 22.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Regeln für das Weiterschalten der geöffneten Mail im
//  Spaltenlayout des iPad – vorige und nächste Mail der Liste (Knöpfe in
//  der Mailansicht, Pfeiltasten) sowie die Mail, die an die Stelle einer
//  gelöschten oder verschobenen tritt.
//
//  „Nächste“ ist die Zeile darunter, „vorige“ die Zeile darüber – in der
//  Reihenfolge, in der die Liste gerade sortiert ist.
//
//  Verschwindet die geöffnete Mail aus der Liste (gelöscht, verschoben),
//  rückt die nächste nach; war sie die letzte, die vorige. So bleibt die
//  Detailspalte gefüllt, wie in Apple Mail.
//
//  Abgrenzung: Reine Regeln ohne Ansicht; Zustand und Darstellung →
//  InboxView.
//
//  Abhängigkeiten: keine.
//

import Foundation

/// Regeln für das Weiterschalten der geöffneten Mail. Reine Logik ohne
/// Zustand, deshalb an keinen Actor gebunden.
nonisolated enum MessageStepping {

    /// Richtung beim Weiterschalten.
    enum Direction: Sendable {
        /// Zeile darüber.
        case previous
        /// Zeile darunter.
        case next
    }

    /// Nachbar der geöffneten Mail in der Liste.
    ///
    /// Verarbeitung: Ist keine Mail geöffnet oder steht sie nicht mehr in
    /// der Liste, beginnt das Weiterschalten bei der ersten Zeile.
    ///
    /// - Parameters:
    ///   - currentID: ID der geöffneten Mail; `nil` = keine.
    ///   - ids: IDs der Liste in Anzeigereihenfolge.
    ///   - direction: Richtung.
    /// - Returns: ID der Nachbarmail; `nil`, wenn es in dieser Richtung
    ///   keine gibt oder die Liste leer ist.
    static func neighbor(of currentID: String?, in ids: [String], direction: Direction) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let currentID, let index = ids.firstIndex(of: currentID) else {
            return ids.first
        }
        let target = direction == .next ? index + 1 : index - 1
        return ids.indices.contains(target) ? ids[target] : nil
    }

    /// Mail, die nach einer Änderung der Liste geöffnet sein soll.
    ///
    /// Verarbeitung: Steht die geöffnete Mail noch in der Liste, bleibt sie.
    /// Sonst rückt die nächste noch vorhandene Mail nach, die in der alten
    /// Liste darunter stand; gibt es keine, die nächste darüber.
    ///
    /// - Parameters:
    ///   - currentID: ID der geöffneten Mail; `nil` = keine.
    ///   - oldIDs: IDs der Liste vor der Änderung, in Anzeigereihenfolge.
    ///   - newIDs: IDs der Liste nach der Änderung.
    /// - Returns: ID der dann geöffneten Mail; `nil` = keine (Liste wieder
    ///   auf voller Breite).
    static func replacement(for currentID: String?, oldIDs: [String], newIDs: [String]) -> String? {
        guard let currentID else { return nil }
        let remaining = Set(newIDs)
        if remaining.contains(currentID) { return currentID }
        guard let index = oldIDs.firstIndex(of: currentID) else { return nil }
        if let below = oldIDs[(index + 1)...].first(where: { remaining.contains($0) }) {
            return below
        }
        return oldIDs[..<index].last(where: { remaining.contains($0) })
    }
}
