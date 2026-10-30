//
//  ServerSearchPlan.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 30.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Logik der Suche auf dem Server ohne die Verbindung selbst –
//  welche Suchkriterien gesendet werden, für welche Treffer Kopfdaten
//  geholt werden und welche Treffer die Suche zeigt.
//
//  Regeln:
//  - Kriterien: TEXT (Eingabe ab drei Zeichen, siehe SearchText) und für
//    eine gewählte Person FROM/TO/CC – beides zusammen muss zutreffen.
//  - Treffer, die schon im Cache liegen, entfallen (die findet die lokale
//    Suche). Von den übrigen zählen die höchsten UIDs bis zur Grenze für
//    Kopfdaten; UIDs sagen nichts über das Datum (z. B. nach einem Umzug
//    per IMAPSYNC), deshalb entscheidet erst das Datum der Kopfdaten.
//  - Gezeigt werden die neuesten Treffer bis zur Anzeigegrenze; gab es
//    mehr Treffer außerhalb des Caches, meldet das Ergebnis `hasMore`.
//
//  Reine Logik ohne IMAP- und Datenbankzugriff (Code-Review v0.3.1,
//  Regel 4); Verbindung und Abfragen bleiben im MailFetchService.
//
//  Abhängigkeiten: SwiftMail (SearchCriteria), SearchText,
//  MessageListItem, MailFetchService.ServerSearchResult.
//

import Foundation
import SwiftMail

/// Planung und Auswahl der Suche auf dem Server.
nonisolated enum ServerSearchPlan {

    /// Suchkriterien für Eingabe und gewählte Person.
    ///
    /// - Parameters:
    ///   - query: Eingabe im Suchfeld; zu kurz = kein Textkriterium.
    ///   - address: Adresse einer gewählten Person; `nil` oder leer = keine.
    /// - Returns: Kriterien; leer, wenn nichts zu suchen ist.
    static func criteria(query: String, address: String?) -> [SwiftMail.SearchCriteria] {
        var criteria: [SwiftMail.SearchCriteria] = []
        if let address, !address.isEmpty {
            criteria.append(.or(.from(address), .or(.to(address), .cc(address))))
        }
        if SearchText.isSearchable(query) {
            criteria.append(.text(query))
        }
        return criteria
    }

    /// Treffer außerhalb des Caches, deren Kopfdaten geholt werden.
    ///
    /// - Parameters:
    ///   - uids: Treffer des Servers, höchste UID zuerst.
    ///   - cached: UIDs des Ordners im Cache.
    ///   - limit: Höchstzahl der Treffer, deren Kopfdaten geholt werden.
    /// - Returns: Zu holende UIDs (Reihenfolge der Eingabe) und die Zahl
    ///   aller Treffer außerhalb des Caches.
    static func candidates(
        _ uids: [UInt32],
        cached: Set<UInt32>,
        limit: Int
    ) -> (uids: [UInt32], missingCount: Int) {
        let missing = uids.filter { !cached.contains($0) }
        return (Array(missing.prefix(max(limit, 0))), missing.count)
    }

    /// Wählt die gezeigten Treffer aus.
    ///
    /// - Parameters:
    ///   - hits: Listeneinträge der geholten Kopfdaten.
    ///   - missingCount: Zahl aller Treffer außerhalb des Caches.
    ///   - limit: Höchstzahl gezeigter Treffer.
    /// - Returns: Neueste Treffer zuerst (ohne Datum zuletzt); `hasMore`,
    ///   wenn es mehr Treffer außerhalb des Caches gab als gezeigt werden.
    static func result(
        hits: [MessageListItem],
        missingCount: Int,
        limit: Int
    ) -> MailFetchService.ServerSearchResult {
        let newestFirst = hits.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return MailFetchService.ServerSearchResult(
            hits: Array(newestFirst.prefix(max(limit, 0))),
            hasMore: missingCount > limit
        )
    }
}
