//
//  FetchedMessageMapping.swift
//  Mailwerk
//
//  Zweck: Überführt, was der Server zu einer Mail liefert (Kopfdaten,
//  Flags, Struktur, geladene Teile), in die Modelle des Caches und der
//  Liste: `CachedMessage`, `CachedAttachment`, `CachedMessageHeaders` und
//  `MessageListItem`.
//
//  Regeln an einer Stelle: Ersatztexte für fehlenden Betreff und Absender,
//  Datum aus dem Kopf (sonst Eingangsdatum), Ersatznamen für Anhänge und
//  Bilder ohne Dateinamen, Content-ID eingebetteter Bilder, Auswertung der
//  Spam-Kopfzeilen.
//
//  Reine Abbildung ohne IMAP- und Datenbankzugriff (Code-Review v0.3.1,
//  Regel 4) – der MailFetchService lädt, diese Datei baut die Modelle.
//  Deshalb `nonisolated` und ohne Server testbar.
//
//  Abhängigkeiten: SwiftMail (MessageInfo, MessagePart), CachedMessage,
//  CachedAttachment, MessageListItem, FlagState, MessageContentPlan
//  (Content-ID), InlineImages, SpamHeaderParser.
//

import Foundation
import SwiftMail

/// Eine neue Mail aus der Kopfdaten-Abfrage, die noch geladen werden muss.
nonisolated struct FetchedMessage {
    /// Kopfdaten aus der Bulk-Abfrage.
    let info: MessageInfo
    /// UID der Mail im Ordner.
    let uid: SwiftMail.UID
    /// Cache-ID der Mail (`CachedMessage.makeID`).
    let messageID: String
    /// Ausgewertete IMAP-Flags.
    let flags: FlagState
}

/// Abbildung der Server-Daten einer Mail auf Cache- und Listenmodelle.
nonisolated enum FetchedMessageMapping {

    /// Ersatz für einen fehlenden Betreff.
    static let missingSubject = "(kein Betreff)"
    /// Ersatz für einen fehlenden Absender.
    static let missingSender = "(unbekannt)"
    /// Ersatzname eines Anhangs ohne Dateinamen.
    static let unnamedAttachment = "Anhang"
    /// Ersatzname eines eingebetteten Bildes ohne Dateinamen.
    static let unnamedInlineImage = "Bild"

    /// Geladener Inhalt einer Mail.
    struct Content {
        /// Textteil, dekodiert.
        let text: String?
        /// HTML-Teil, dekodiert.
        let html: String?
        /// `true`, wenn die Mail Anhänge hat (eingebettete Bilder zählen nicht).
        let hasAttachments: Bool
        /// Zeitpunkt des Ladens.
        let fetchedAt: Date
    }

    /// Baut die Mail für den Cache.
    ///
    /// - Parameters:
    ///   - fetched: Kopfdaten, UID, Cache-ID und Flags.
    ///   - account: Postfach.
    ///   - folder: IMAP-Ordner.
    ///   - content: Geladener Inhalt.
    /// - Returns: Mail für den Cache.
    static func message(
        _ fetched: FetchedMessage,
        account: MailAccount,
        folder: String,
        content: Content
    ) -> CachedMessage {
        let info = fetched.info
        return CachedMessage(
            id: fetched.messageID,
            accountID: account.id,
            accountDisplayName: account.displayName,
            folder: folder,
            uid: fetched.uid.value,
            subject: info.subject ?? missingSubject,
            from: info.from ?? missingSender,
            to: info.to.joined(separator: ", "),
            date: info.date ?? info.internalDate,
            isUnread: fetched.flags.isUnread,
            isFlagged: fetched.flags.isFlagged,
            isAnswered: fetched.flags.isAnswered,
            isForwarded: fetched.flags.isForwarded,
            totalSizeBytes: info.size ?? 0,
            hasAttachments: content.hasAttachments,
            textBody: content.text,
            htmlBody: content.html,
            fetchedAt: content.fetchedAt,
            headers: headers(from: info)
        )
    }

    /// Baut den Cache-Eintrag eines Anhangs oder eingebetteten Bildes.
    ///
    /// Verarbeitung: Ohne Dateinamen gilt „Anhang“ bzw. „Bild“. Die Größe
    /// ist die der geladenen Daten, sonst die Angabe der Struktur. Ein
    /// eingebettetes Bild bekommt seine Content-ID aus `MessageContentPlan`,
    /// ein Anhang die bereinigte Angabe des Kopfes (`InlineImages`).
    ///
    /// - Parameters:
    ///   - part: Teil aus der Struktur der Mail.
    ///   - data: Geladene Daten; `nil` = nur Eintrag, später nachladbar.
    ///   - isInline: `true` bei einem eingebetteten Bild.
    ///   - messageID: Cache-ID der Mail.
    /// - Returns: Eintrag für den Cache.
    static func attachment(
        for part: MessagePart,
        data: Data?,
        isInline: Bool,
        messageID: String
    ) -> CachedAttachment {
        CachedAttachment(
            id: "\(messageID)-\(part.section)",
            messageID: messageID,
            filename: part.filename ?? (isInline ? unnamedInlineImage : unnamedAttachment),
            contentType: part.contentType,
            sizeBytes: data?.count ?? part.size ?? 0,
            data: data,
            contentID: isInline
                ? MessageContentPlan.contentID(for: part)
                : InlineImages.storedContentID(part.contentId),
            isInline: isInline
        )
    }

    /// Listeneintrag aus den Kopfdaten einer Mail, die nicht im Cache liegt
    /// (Treffer der Serversuche).
    ///
    /// Verarbeitung: Dieselben Regeln wie beim Speichern (Ersatztexte,
    /// Datum aus dem Kopf, sonst Eingangsdatum). Die Cache-ID ist die, die
    /// die Mail beim Laden erhält. Anhänge sind vor dem Öffnen nicht bekannt.
    ///
    /// - Parameters:
    ///   - info: Kopfdaten.
    ///   - account: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Listeneintrag; `nil` ohne UID.
    static func listItem(from info: MessageInfo, account: MailAccount, folder: String) -> MessageListItem? {
        guard let uid = info.uid?.value else { return nil }
        let flags = FlagState(info.flags)
        let headers = headers(from: info)
        return MessageListItem(
            id: CachedMessage.makeID(accountID: account.id, folder: folder, uid: uid),
            accountID: account.id,
            folder: folder,
            uid: uid,
            subject: info.subject ?? missingSubject,
            from: info.from ?? missingSender,
            recipients: headers.toList,
            date: info.date ?? info.internalDate,
            isUnread: flags.isUnread,
            isFlagged: flags.isFlagged,
            isAnswered: flags.isAnswered,
            isForwarded: flags.isForwarded,
            hasAttachments: false,
            sizeBytes: info.size ?? 0,
            spamVerdict: headers.spamVerdict
        )
    }

    /// Überführt Adress-, Threading- und Spam-Kopfdaten ins Cache-Modell.
    ///
    /// Verarbeitung: Die Spam-Kopfzeilen kommen aus
    /// `additionalHeaderFields`, das Reihenfolge und Wiederholungen behält.
    /// Das Wörterbuch `additionalFields` wäre falsch: Bei mehreren
    /// X-Spam-Status-Zeilen gewänne dort die letzte – ein Absender könnte
    /// die Einstufung des Servers so überschreiben (wie im Spamfilter).
    ///
    /// - Parameter info: IMAP-Antwort mit Envelope-Daten und Zusatz-Headern.
    /// - Returns: Aufbereitete Kopfdaten für den Cache.
    static func headers(from info: MessageInfo) -> CachedMessageHeaders {
        let references = info.references?
            .map(\.description)
            .joined(separator: " ")
        let spamLines = (info.additionalHeaderFields ?? []).map {
            SpamHeaderLine(name: $0.name, value: $0.value)
        }
        return CachedMessageHeaders(
            toList: info.to,
            ccList: info.cc,
            replyToList: info.replyTo,
            rfcMessageID: info.messageId?.description,
            rfcInReplyTo: info.inReplyTo?.description,
            rfcReferences: (references?.isEmpty ?? true) ? nil : references,
            spamVerdict: SpamHeaderParser.parse(spamLines)
        )
    }
}
