//
//  MessageListItem.swift
//  Mailwerk
//
//  Zweck: Eintrag der Nachrichtenliste – alles, was eine Listenzeile und
//  die Wischaktionen brauchen, aber ohne Text- und HTML-Inhalt der Mail.
//
//  Die Liste lädt damit je Mail nur wenige hundert Byte statt des ganzen
//  Mailtexts (im Mittel rund 40 KB). Die vollständige Nachricht
//  (`CachedMessage`) wird erst beim Öffnen aus dem Cache geholt.
//
//  Bewusst ein eigener Typ: Der Compiler verhindert so, dass eine Stelle
//  versehentlich mit einem Listeneintrag statt der vollständigen Mail
//  arbeitet – etwa eine Antwort ohne Zitat.
//
//  Abgrenzung: Vollständige Nachricht → CachedMessage; Speichern und
//  Lesen → MessageStore.
//
//  Abhängigkeiten: keine (reiner Datentyp).
//

import Foundation

/// Ein Eintrag der Nachrichtenliste ohne Mailinhalt.
struct MessageListItem: Identifiable, Equatable {
    /// Cache-ID der Nachricht (`CachedMessage.id`).
    let id: String
    /// Postfach der Nachricht.
    let accountID: UUID
    /// IMAP-Ordner der Nachricht.
    let folder: String
    /// UID der Nachricht im Ordner.
    let uid: UInt32
    /// Betreff.
    let subject: String
    /// Absender als Anzeigetext.
    let from: String
    /// Datum der Nachricht; `nil`, wenn unbekannt.
    let date: Date?
    /// `true` = ungelesen.
    let isUnread: Bool
    /// `true` = gekennzeichnet.
    let isFlagged: Bool
    /// `true` = beantwortet.
    let isAnswered: Bool
    /// `true` = weitergeleitet.
    let isForwarded: Bool
    /// `true`, wenn die Nachricht Anhänge hat.
    let hasAttachments: Bool
    /// Anfang des Textteils (höchstens 200 Zeichen) für die zweite
    /// Zeile; `nil`, wenn die Mail keinen Textteil hat.
    let preview: String?
}
