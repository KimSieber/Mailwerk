//
//  MailFetchService.swift
//  Mailwerk
//

import Foundation
import SwiftMail
import NIOIMAPCore

enum MailFetchService {

    /// Maximale Nachrichtengröße (RFC822.SIZE) in Bytes, bis zu der
    /// Anhänge automatisch mitgeladen werden. Darüber: erst bei Tap.
    static let autoDownloadThreshold = 5 * 1024 * 1024  // 5 MB

    /// Sync-Zeitraum: nur Nachrichten der letzten 30 Tage abrufen.
    static let syncDays = 30

    /// IMAP-Keyword für weitergeleitete Nachrichten (kein Systemflag, aber
    /// von Apple Mail, Thunderbird u. a. verwendet).
    static let forwardedKeyword = "$Forwarded"

    /// Zusätzlich zum ENVELOPE angeforderte Header. References ist nicht
    /// Teil des ENVELOPE, wird aber für korrektes Threading gebraucht.
    private static let extraHeaderFields = ["References"]

    /// Holt neue Nachrichten aus INBOX (letzte 30 Tage), cacht Body
    /// und – bei Mails ≤ 5 MB – auch die Anhänge lokal.
    static func refreshAndCache(
        account: MailAccount,
        password: String
    ) async throws {
        let server = MailServerFactory.imapServer(for: account)
        do {
            try await server.connect()
            try await server.login(username: account.username, password: password)
            _ = try await server.selectMailbox("INBOX")

            // Serverseitig nur Mails der letzten 30 Tage suchen
            let sinceDate = Calendar.current.date(
                byAdding: .day, value: -syncDays, to: Date()
            )!
            let uids: [SwiftMail.UID] = try await server.search(
                criteria: [.since(sinceDate)],
                sortCriteria: [.descending(.date)],
                calendar: Calendar(identifier: .gregorian)
            )

            print("📬 [\(account.displayName)] SEARCH ergab \(uids.count) UIDs (seit \(sinceDate))")

            guard !uids.isEmpty else {
                print("📬 [\(account.displayName)] Keine UIDs → überspringe")
                try await server.logout()
                return
            }

            // Welche UIDs haben wir schon im Cache – und wem fehlen noch Header?
            let alreadyCached = MessageStore.shared.cachedMessageIDs(
                forAccount: account.id
            )
            let needsHeaders = MessageStore.shared.messageIDsNeedingHeaders(
                forAccount: account.id
            )
            print("📬 [\(account.displayName)] Davon bereits im Cache: \(alreadyCached.count)")

            // Header für alle gefundenen UIDs holen (schlank + References)
            let infos = try await server.fetchMessageInfosBulk(
                using: UIDSet(uids),
                options: .slim,
                headerFields: extraHeaderFields
            )
            print("📬 [\(account.displayName)] fetchMessageInfosBulk lieferte \(infos.count) Infos")

            var savedCount = 0
            var skippedCount = 0
            var headersBackfilled = 0

            for info in infos {
                guard let uid = info.uid else {
                    skippedCount += 1
                    continue
                }
                let msgID = "\(account.id.uuidString)-\(uid.value)"
                let flags = FlagState(info.flags)

                // Schon im Cache → Flags aktualisieren, ggf. Header nachfüllen
                if alreadyCached.contains(msgID) {
                    MessageStore.shared.updateServerFlags(
                        messageID: msgID,
                        isUnread: flags.isUnread,
                        isFlagged: flags.isFlagged,
                        isAnswered: flags.isAnswered,
                        isForwarded: flags.isForwarded
                    )
                    if needsHeaders.contains(msgID) {
                        MessageStore.shared.updateHeaders(
                            messageID: msgID, headers: headers(from: info)
                        )
                        headersBackfilled += 1
                    }
                    continue
                }

                // Neu: Body laden — Fehler bei einzelner Mail
                // überspringen, nicht den ganzen Account abbrechen
                do {
                    let message = try await server.fetchMessage(from: info)

                    let totalSize = info.size ?? 0
                    let hasAttachments = !message.attachments.isEmpty

                    let cached = CachedMessage(
                        id: msgID,
                        accountID: account.id,
                        accountDisplayName: account.displayName,
                        uid: uid.value,
                        subject: info.subject ?? "(kein Betreff)",
                        from: info.from ?? "(unbekannt)",
                        to: info.to.joined(separator: ", "),
                        date: info.date ?? info.internalDate,
                        isUnread: flags.isUnread,
                        isFlagged: flags.isFlagged,
                        isAnswered: flags.isAnswered,
                        isForwarded: flags.isForwarded,
                        totalSizeBytes: totalSize,
                        hasAttachments: hasAttachments,
                        textBody: message.textBody,
                        htmlBody: message.htmlBody,
                        fetchedAt: Date(),
                        headers: headers(from: info)
                    )

                    // Sofort speichern — nicht am Ende sammeln
                    MessageStore.shared.saveMessage(cached)
                    savedCount += 1

                    // Anhänge nur bei Mails ≤ 5 MB automatisch laden
                    let attCount = message.attachments.count
                    if attCount > 0 {
                        print("📎 [\(account.displayName)] Mail \(uid.value) hat \(attCount) Anhänge, Größe \(totalSize) B")
                    }

                    if totalSize <= autoDownloadThreshold {
                        for attachment in message.attachments {
                            let attID = "\(msgID)-\(attachment.section)"
                            let data = try await server.fetchAndDecodeMessagePartData(
                                messageInfo: info, part: attachment
                            )
                            let cachedAtt = CachedAttachment(
                                id: attID,
                                messageID: msgID,
                                filename: attachment.filename ?? "Anhang",
                                contentType: attachment.contentType,
                                sizeBytes: data.count,
                                data: data
                            )
                            MessageStore.shared.saveAttachment(cachedAtt)
                        }
                    } else {
                        // Nur Metadaten speichern, data = nil
                        for attachment in message.attachments {
                            let attID = "\(msgID)-\(attachment.section)"
                            let cachedAtt = CachedAttachment(
                                id: attID,
                                messageID: msgID,
                                filename: attachment.filename ?? "Anhang",
                                contentType: attachment.contentType,
                                sizeBytes: attachment.size ?? 0,
                                data: nil
                            )
                            MessageStore.shared.saveAttachment(cachedAtt)
                        }
                    }
                } catch {
                    // Einzelne kaputte Mail überspringen, Rest weiterholen
                    print("⚠️ Mail \(msgID) übersprungen: \(error.localizedDescription)")
                    continue
                }
            }

            print("📬 [\(account.displayName)] Fertig: \(savedCount) neu gespeichert, \(alreadyCached.count) aus Cache, \(headersBackfilled) Header nachgefüllt, \(skippedCount) übersprungen (keine UID)")

            try await server.logout()

            // Alte Nachrichten jenseits des 30-Tage-Fensters bereinigen
            MessageStore.shared.deleteMessagesOlderThan(sinceDate, forAccount: account.id)

        } catch {
            try? await server.disconnect()
            throw error
        }
    }

    // MARK: - Helfer

    /// Wertet die IMAP-Flags einer Nachricht in einem Durchlauf aus.
    /// `SwiftMail.Flag` voll qualifiziert, da NIOIMAPCore ebenfalls `Flag` definiert.
    private struct FlagState {
        let isUnread: Bool
        let isFlagged: Bool
        let isAnswered: Bool
        let isForwarded: Bool

        init(_ flags: [SwiftMail.Flag]) {
            var seen = false, flagged = false, answered = false, forwarded = false
            for flag in flags {
                switch flag {
                case .seen:     seen = true
                case .flagged:  flagged = true
                case .answered: answered = true
                case .custom(let keyword)
                    where keyword.caseInsensitiveCompare(MailFetchService.forwardedKeyword) == .orderedSame:
                    forwarded = true
                default:        break
                }
            }
            isUnread = !seen
            isFlagged = flagged
            isAnswered = answered
            isForwarded = forwarded
        }
    }

    /// Überführt Adress- und Threading-Header aus dem MessageInfo ins Cache-Modell.
    private static func headers(from info: MessageInfo) -> CachedMessageHeaders {
        let references = info.references?
            .map(\.description)
            .joined(separator: " ")
        return CachedMessageHeaders(
            toList: info.to,
            ccList: info.cc,
            replyToList: info.replyTo,
            rfcMessageID: info.messageId?.description,
            rfcInReplyTo: info.inReplyTo?.description,
            rfcReferences: (references?.isEmpty ?? true) ? nil : references
        )
    }
}
