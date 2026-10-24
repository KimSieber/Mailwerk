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
//  Nebenläufigkeit: `nonisolated` und `Sendable` – reine Werte bzw. reine
//  Logik ohne Bezug zur Oberfläche. So kann die Ablage (MessageStore) sie
//  auch außerhalb des Hauptthreads nutzen (v0.2.3b).
//
//  Abgrenzung: Vollständige Nachricht → CachedMessage; Speichern und
//  Lesen → MessageStore.
//
//  Abhängigkeiten: SpamHeaderVerdict (reiner Datentyp).
//

import Foundation

/// Ein Eintrag der Nachrichtenliste ohne Mailinhalt.
nonisolated struct MessageListItem: Identifiable, Equatable, Sendable {
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
    /// Absender als formatierte Adresse.
    let from: String
    /// Empfänger (To) – je Eintrag eine formatierte Adresse. Gebraucht für
    /// Gesendet und Entwürfe, wo die Zeile den Empfänger zeigt.
    let recipients: [String]
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
    /// Gesamtgröße der Nachricht in Byte (Sortierung nach Größe).
    let sizeBytes: Int
    /// Spam-Einstufung des Servers; `nil` = unbekannt. Entscheidet mit den
    /// Filterlisten, ob die Zeile ein Absenderbild zeigen darf.
    let spamVerdict: SpamHeaderVerdict?
}
