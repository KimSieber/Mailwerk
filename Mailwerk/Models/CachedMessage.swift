//
//  CachedMessage.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.09.2026
//  Geändert: 24.10.2026
//
//  Zweck: Datenmodell einer im lokalen Cache gespeicherten Nachricht samt
//  ihrer Kopfdaten (Adressen, Threading, Spam-Angabe des Servers) und
//  ihrer Anhänge.
//
//  Die Spam-Angabe ist optional: `nil` heißt „unbekannt“ (die Nachricht
//  wurde gespeichert, bevor Mailwerk die Angabe mitgeführt hat). Das ist
//  bewusst etwas anderes als „kein Spam“ – wer auf die Angabe vertraut
//  (z. B. das sofortige Laden externer Inhalte), muss „unbekannt“ wie
//  „nicht vertrauenswürdig“ behandeln.
//
//  Nebenläufigkeit: `nonisolated` und `Sendable` – reine Werte bzw. reine
//  Logik ohne Bezug zur Oberfläche. So kann die Ablage (MessageStore) sie
//  auch außerhalb des Hauptthreads nutzen (v0.2.3b).
//
//  Abgrenzung: Speichern und Lesen → MessageStore; Befüllen beim Abruf →
//  MailFetchService; Listeneinträge ohne Inhalt → MessageListItem;
//  Regeln für eingebettete Bilder → InlineImages.
//
//  Abhängigkeiten: Foundation, SpamHeaderVerdict.
//

import Foundation

/// Adress-, Threading- und Spam-Kopfdaten einer Nachricht.
/// Grundlage für Antworten, Allen antworten, Weiterleiten und für die
/// Entscheidung, ob externe Inhalte sofort geladen werden.
nonisolated struct CachedMessageHeaders: Equatable, Sendable {
    /// Empfänger (To) – je Eintrag eine formatierte Adresse, z. B. "Kim Sieber <kim@example.org>"
    var toList: [String] = []
    /// Kopie-Empfänger (Cc)
    var ccList: [String] = []
    /// Abweichende Antwortadresse(n) (Reply-To)
    var replyToList: [String] = []
    /// Message-ID inkl. spitzer Klammern, z. B. "<abc@example.org>"
    var rfcMessageID: String?
    /// Message-ID der Nachricht, auf die diese antwortet
    var rfcInReplyTo: String?
    /// References-Kette, durch Leerzeichen getrennt
    var rfcReferences: String?
    /// Spam-Einstufung des Servers (X-Spam, X-Spam-Flag, X-Spam-Status); `nil` = unbekannt.
    var spamVerdict: SpamHeaderVerdict?
}

/// Lokal zwischengespeicherte Nachricht inkl. Body.
/// Anhänge werden separat in CachedAttachment gehalten.
nonisolated struct CachedMessage: Identifiable, Sendable {
    /// Cache-Kennung "<accountUUID>-<folder>-<uid>" (siehe `makeID`).
    let id: String
    /// Postfach, zu dem die Nachricht gehört.
    let accountID: UUID
    /// Anzeigename des Postfachs zum Zeitpunkt des Speicherns.
    let accountDisplayName: String
    /// IMAP-Ordner, in dem die Nachricht liegt (z. B. "INBOX", "Junk").
    /// UIDs sind nur innerhalb eines Ordners eindeutig, deshalb gehört der
    /// Ordner zur Identität einer gecachten Nachricht.
    let folder: String
    /// IMAP-UID innerhalb des Ordners.
    let uid: UInt32
    /// Betreff.
    let subject: String
    /// Absender als formatierte Adresse.
    let from: String
    /// Anzeige-String der Empfänger; für Logik `headers.toList` verwenden.
    let to: String
    /// Datum der Nachricht; `nil`, wenn der Server keines liefert.
    let date: Date?
    /// Ungelesen (IMAP \Seen nicht gesetzt).
    var isUnread: Bool
    /// Gekennzeichnet (IMAP \Flagged).
    var isFlagged: Bool
    /// Beantwortet (IMAP \Answered).
    var isAnswered: Bool
    /// Weitergeleitet (IMAP-Keyword $Forwarded).
    var isForwarded: Bool
    /// RFC822.SIZE – entscheidet, ob Anhänge automatisch geladen werden.
    let totalSizeBytes: Int
    /// `true`, wenn die Mail mindestens einen Anhang hat.
    let hasAttachments: Bool
    /// Textteil der Mail.
    let textBody: String?
    /// HTML-Teil der Mail.
    let htmlBody: String?
    /// Zeitpunkt des Speicherns im Cache.
    let fetchedAt: Date
    /// Adress-, Threading- und Spam-Kopfdaten.
    let headers: CachedMessageHeaders

    /// Bildet die Cache-Kennung. Einzige Stelle, an der das Format entsteht –
    /// die Kennung wird nirgends wieder zerlegt, weil Ordnernamen selbst
    /// Bindestriche enthalten dürfen.
    ///
    /// - Parameters:
    ///   - accountID: Postfach.
    ///   - folder: IMAP-Ordner.
    ///   - uid: UID im Ordner.
    /// - Returns: Cache-Kennung.
    static func makeID(accountID: UUID, folder: String, uid: UInt32) -> String {
        "\(accountID.uuidString)-\(folder)-\(uid)"
    }
}

/// Ein einzelner gecachter Anhang, referenziert über die messageID.
///
/// Eingebettete Bilder (Inline-Teile, im HTML per `cid:` angesprochen)
/// liegen in derselben Tabelle mit `isInline` und ihrer Content-ID; ob sie
/// in der Anhangliste erscheinen, entscheidet `InlineImages`.
nonisolated struct CachedAttachment: Identifiable, Sendable {
    /// Kennung "<messageID>-<partSection>".
    let id: String
    /// Fremdschlüssel auf `CachedMessage.id`.
    let messageID: String
    /// Dateiname.
    let filename: String
    /// MIME-Typ.
    let contentType: String
    /// Größe in Bytes laut Server.
    let sizeBytes: Int
    /// Inhalt; `nil` = noch nicht heruntergeladen oder lokal gelöscht.
    let data: Data?
    /// Content-ID ohne spitze Klammern; `nil` = keine.
    var contentID: String? = nil
    /// `true` = eingebettetes Bild (Inline-Teil), kein echter Anhang.
    var isInline: Bool = false

    /// Derselbe Anhang mit anderen Daten (z. B. nach dem Nachladen).
    ///
    /// - Parameter data: Neue Daten.
    /// - Returns: Kopie mit den Daten; die Größe folgt den Daten.
    func with(data: Data) -> CachedAttachment {
        CachedAttachment(
            id: id, messageID: messageID, filename: filename, contentType: contentType,
            sizeBytes: data.count, data: data, contentID: contentID, isInline: isInline
        )
    }
}
