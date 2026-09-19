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

    /// Holt neue Nachrichten aus INBOX (letzte 30 Tage), cacht Body
    /// und – bei Mails ≤ 5 MB – auch die Anhänge lokal.
    static func refreshAndCache(
        account: MailAccount,
        password: String
    ) async throws {
        let server = IMAPServer(host: account.imapHost, port: account.imapPort)
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

            // Welche UIDs haben wir schon im Cache?
            let alreadyCached = MessageStore.shared.cachedMessageIDs(
                forAccount: account.id
            )
            print("📬 [\(account.displayName)] Davon bereits im Cache: \(alreadyCached.count)")

            // Header für alle gefundenen UIDs holen (schlank)
            let infos = try await server.fetchMessageInfosBulk(
                using: UIDSet(uids), options: .slim
            )
            print("📬 [\(account.displayName)] fetchMessageInfosBulk lieferte \(infos.count) Infos")

            var savedCount = 0
            var skippedCount = 0

            for info in infos {
                guard let uid = info.uid else {
                    skippedCount += 1
                    continue
                }
                let msgID = "\(account.id.uuidString)-\(uid.value)"

                // Schon im Cache → nur Gelesen-Status aktualisieren
                if alreadyCached.contains(msgID) {
                    let isUnread = !info.flags.contains(where: {
                        if case .seen = $0 { return true }
                        return false
                    })
                    MessageStore.shared.updateFlags(messageID: msgID, isUnread: isUnread)
                    continue
                }

                // Neu: Body laden — Fehler bei einzelner Mail
                // überspringen, nicht den ganzen Account abbrechen
                do {
                    let message = try await server.fetchMessage(from: info)

                    let totalSize = info.size ?? 0
                    let isUnread = !info.flags.contains(where: {
                        if case .seen = $0 { return true }
                        return false
                    })
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
                        isUnread: isUnread,
                        totalSizeBytes: totalSize,
                        hasAttachments: hasAttachments,
                        textBody: message.textBody,
                        htmlBody: message.htmlBody,
                        fetchedAt: Date()
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

            print("📬 [\(account.displayName)] Fertig: \(savedCount) neu gespeichert, \(alreadyCached.count) aus Cache, \(skippedCount) übersprungen (keine UID)")

            try await server.logout()

            // Alte Nachrichten jenseits des 30-Tage-Fensters bereinigen
            MessageStore.shared.deleteMessagesOlderThan(sinceDate, forAccount: account.id)

        } catch {
            try? await server.disconnect()
            throw error
        }
    }
}
