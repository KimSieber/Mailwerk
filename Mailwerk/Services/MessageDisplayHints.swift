//
//  MessageDisplayHints.swift
//  Mailwerk
//
//  Zweck: Vorberechnete Anzeige-Hinweise einer Mail – ob sie externe
//  Inhalte enthält, ob sie eigene Farben mitbringt und welche fremde
//  Sprache sie hat. Bisher wurde das bei jedem Öffnen per Regex und
//  Spracherkennung neu ermittelt (v0.2.3d, Option 3 „beim Abruf
//  vorspeichern“).
//
//  Entstehung: beim Abruf für jede neue Mail (MailFetchService, vor dem
//  Speichern im Hintergrund) und als Rückfall beim Öffnen, wenn die Werte
//  fehlen oder ihre Version veraltet ist (MessageOpenPreparation).
//  Gespeichert in vier Spalten der Tabelle `message` (MessageStore,
//  Schema-Stufe 9) – so wandern sie beim Verschieben einer Mail mit.
//
//  Version: Ändert sich eine Erkennungsregel (RemoteContentPolicy,
//  MailAppearance, MessageLanguage), `currentVersion` erhöhen – gespeicherte
//  Werte älterer Version gelten dann als fehlend und werden beim nächsten
//  Öffnen neu berechnet.
//
//  Abhängigkeiten: RemoteContentPolicy, MailAppearance, SearchText,
//  MessageLanguage.
//

import Foundation

/// Vorberechnete Anzeige-Hinweise einer Mail.
nonisolated struct MessageDisplayHints: Equatable, Sendable {

    /// Version der Erkennungsregeln. Bei jeder Regeländerung erhöhen.
    static let currentVersion = 1

    /// `true`, wenn das HTML externe Verweise enthält.
    let hasRemoteContent: Bool
    /// `true`, wenn das HTML eigene Farben mitbringt (Anzeige bleibt hell).
    let usesOwnColors: Bool
    /// Sprachcode der erkannten fremden Sprache (z. B. „en“); `nil` =
    /// Deutsch, zu wenig Text oder nicht erkannt.
    let languageCode: String?

    /// Erkannte fremde Sprache als `Locale.Language`; `nil` = keine.
    var language: Locale.Language? {
        languageCode.map { Locale.Language(identifier: $0) }
    }

    /// Berechnet die Hinweise aus Text- und HTML-Teil.
    ///
    /// Verarbeitung: Externe Verweise und eigene Farben nur bei HTML;
    /// Sprache aus dem reinen Text (`SearchText.body`) über
    /// `MessageLanguage.detectedLanguage` (Deutsch ergibt `nil`).
    ///
    /// - Parameters:
    ///   - text: Textteil der Mail.
    ///   - html: HTML-Teil der Mail.
    /// - Returns: Berechnete Hinweise.
    static func compute(text: String?, html: String?) -> MessageDisplayHints {
        let body = SearchText.body(text: text, html: html)
        let language = MessageLanguage.detectedLanguage(forBody: body)
        return MessageDisplayHints(
            hasRemoteContent: html.map(RemoteContentPolicy.containsRemoteReferences) ?? false,
            usesOwnColors: html.map(MailAppearance.usesOwnColors) ?? false,
            languageCode: language.map { $0.minimalIdentifier }
        )
    }

    /// Berechnet die Hinweise einer Mail.
    ///
    /// - Parameter message: Mail.
    /// - Returns: Berechnete Hinweise.
    static func compute(for message: CachedMessage) -> MessageDisplayHints {
        compute(text: message.textBody, html: message.htmlBody)
    }
}
