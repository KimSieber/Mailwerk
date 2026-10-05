//
//  MailFetchService.swift
//  Mailwerk
//
//  Zweck: Holt Mails von IMAP-Servern und legt sie im lokalen Cache ab.
//
//  Drei Zugangspunkte:
//  - `refreshAndCache`: Abruf der letzten 30 Tage (plus gekennzeichnete
//    im Posteingang) mit anschließendem Abgleich.
//  - `fetchOlder`: Zeitfenster blockweise zurückschieben.
//  - `reconcile` (privat): Vergleicht den ganzen Ordner mit dem Cache,
//    entfernt Gelöschtes und aktualisiert Flags.
//
//  Bekannte Einschränkung: Eine im Webmail in einen Ordner verschobene
//  oder kopierte Mail mit altem Eingangsdatum findet der zeitfenster-
//  basierte Abruf nicht. Die Lösung folgt mit dem Sync-Zustand je
//  Ordner (UIDVALIDITY und höchste gesehene UID).
//
//  Abgrenzung: `MailActionService` setzt Flags und verschiebt Mails;
//  `MailSendService` versendet. Die Darstellung liegt im ViewModel.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailServerFactory (TLS-Vorgaben),
//  MessageStore (Cache), ServerReconciliation (Abgleichslogik).
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

    /// Name des Posteingangs. IMAP schreibt genau diese Schreibweise vor.
    /// `nonisolated`, weil die Konstante als Standardwert eines Parameters
    /// dient – solche Ausdrücke wertet Swift außerhalb des Main-Actors aus.
    nonisolated static let inboxFolder = "INBOX"

    /// IMAP-Keyword für weitergeleitete Nachrichten (kein Systemflag, aber
    /// von Apple Mail, Thunderbird u. a. verwendet).
    static let forwardedKeyword = "$Forwarded"

    /// Zusätzlich zum ENVELOPE angeforderte Header. References ist nicht
    /// Teil des ENVELOPE, wird aber für korrektes Threading gebraucht.
    private static let extraHeaderFields = ["References"]

    // MARK: - Abruf

    /// Holt neue Nachrichten eines Ordners und gleicht den Cache ab.
    ///
    /// Verarbeitung:
    /// 1. SEARCH SINCE der letzten 30 Tage → UIDs der aktuellen Mails.
    ///    Im Posteingang zusätzlich alle gekennzeichneten Mails.
    /// 2. `cacheMessages` speichert neue Mails samt Body und Anhängen
    ///    (≤ 5 MB) und aktualisiert Flags bekannter Mails.
    /// 3. `reconcile` vergleicht den ganzen Ordner mit dem Cache: entfernt
    ///    Gelöschtes und aktualisiert Flags.
    ///
    /// - Parameters:
    ///   - account: Postfach.
    ///   - password: Passwort des Postfachs.
    ///   - folder: IMAP-Ordner (Standard: INBOX).
    /// - Throws: Verbindungsfehler oder IMAP-Fehler.
    static func refreshAndCache(
        account: MailAccount,
        password: String,
        folder: String = inboxFolder
    ) async throws {
        let server = MailServerFactory.imapServer(for: account)
        do {
            try await server.connect()
            try await server.login(username: account.username, password: password)
            _ = try await server.selectMailbox(folder)

            // Serverseitig nur Mails der letzten 30 Tage suchen
            let sinceDate = Calendar.current.date(
                byAdding: .day, value: -syncDays, to: Date()
            )!
            var uids: [SwiftMail.UID] = try await server.search(
                criteria: [.since(sinceDate)],
                sortCriteria: [.descending(.date)],
                calendar: Calendar(identifier: .gregorian)
            )

            print("📬 [\(account.displayName)/\(folder)] SEARCH ergab \(uids.count) UIDs (seit \(sinceDate))")

            // Gekennzeichnete Mails des Posteingangs, auch ältere. Die Menge
            // ist klein, die Antwort bleibt weit unter den Puffergrenzen.
            // Bereits gecachte Mails bekommen dabei ihre Flags abgeglichen.
            if folder == inboxFolder {
                let flagged: [SwiftMail.UID] = try await server.search(
                    criteria: [.flagged],
                    sortCriteria: [.descending(.date)],
                    calendar: Calendar(identifier: .gregorian)
                )
                let known = Set(uids.map(\.value))
                let older = flagged.filter { !known.contains($0.value) }
                uids += older
                print("📬 [\(account.displayName)/\(folder)] Gekennzeichnet: \(flagged.count), davon älter: \(older.count)")
            }

            guard !uids.isEmpty else {
                print("📬 [\(account.displayName)] Keine UIDs → überspringe")
                try await reconcile(server: server, account: account, folder: folder)
                try await server.logout()
                // Auch ein leerer Ordner ist erfolgreich abgerufen.
                MessageStore.shared.recordSync(accountID: account.id, folder: folder)
                return
            }

            try await cacheMessages(uids: uids, server: server, account: account, folder: folder)

            try await reconcile(server: server, account: account, folder: folder)

            try await server.logout()

            // Stand vermerken – erst hier, nach vollständigem Abruf.
            MessageStore.shared.recordSync(accountID: account.id, folder: folder)

        } catch {
            try? await server.disconnect()
            throw error
        }
    }

    // MARK: - Server-Abgleich

    /// Gleicht den Cache eines Ordners mit dem Server ab.
    ///
    /// Verarbeitung: Holt alle UIDs mit Flags in einer einzigen Abfrage
    /// (`UID FETCH 1:* (FLAGS)`). Daraus ergibt sich:
    /// - welche Mails es auf dem Server nicht mehr gibt → werden entfernt,
    /// - welche Flags sich geändert haben → werden übernommen.
    ///
    /// Mails, die nur auf dem Server liegen, lädt der Abgleich nicht nach;
    /// neue Mails holt der Abruf.
    ///
    /// Der Ordner muss bereits ausgewählt sein. Schlägt die Abfrage fehl,
    /// wirft die Methode – gelöscht wird dann nichts.
    ///
    /// - Parameters:
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    ///   - account: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Throws: IMAP-Fehler.
    private static func reconcile(
        server: SwiftMail.IMAPServer,
        account: MailAccount,
        folder: String
    ) async throws {
        let started = Date()

        // Alle Mails des Ordners mit ihren Flags – eine einzige Abfrage.
        let infos = try await server.fetchMessageInfos(
            uidRange: SwiftMail.UID(1)...,
            options: [.flags]
        )
        let fetchDone = Date()

        var state = ServerFolderState(all: [], unseen: [], flagged: [], answered: [], forwarded: [])
        for info in infos {
            guard let uid = info.uid?.value else { continue }
            let flags = FlagState(info.flags)
            state.all.insert(uid)
            if flags.isUnread { state.unseen.insert(uid) }
            if flags.isFlagged { state.flagged.insert(uid) }
            if flags.isAnswered { state.answered.insert(uid) }
            if flags.isForwarded { state.forwarded?.insert(uid) }
        }

        let plan = ServerReconciliation.plan(
            cached: MessageStore.shared.cachedFlagStates(
                accountID: account.id, folder: folder, since: .distantPast
            ),
            server: state,
            keepUIDsAbove: ServerReconciliation.highestUID(in: state)
        )
        MessageStore.shared.apply(plan)

        let fetchMillis = Int(fetchDone.timeIntervalSince(started) * 1000)
        let totalMillis = Int(Date().timeIntervalSince(started) * 1000)
        print("""
            🔁 [\(account.displayName)/\(folder)] Abgleich: \(state.all.count) Mails im Ordner, \
            \(state.forwarded?.count ?? 0) mit \(forwardedKeyword), \
            \(plan.removedIDs.count) entfernt, \(plan.flagUpdates.count) Flags geändert \
            (Abfrage \(fetchMillis) ms, gesamt \(totalMillis) ms)
            """)
    }


    // MARK: - Ältere Nachrichten

    /// Lädt den nächsten Zeitraum (30 Tage) vor dem bisherigen Fensterbeginn
    /// eines Ordners nach.
    ///
    /// Verarbeitung: Schiebt den Fensterbeginn blockweise zurück und sucht
    /// per SEARCH SINCE/BEFORE. Leere Zeiträume werden übersprungen, bis
    /// Mails gefunden sind – sonst sähe ein Tipp auf „Ältere laden" aus,
    /// als passiere nichts. Der neue Fensterbeginn wird dauerhaft
    /// gespeichert.
    ///
    /// - Parameters:
    ///   - account: Postfach.
    ///   - password: Passwort des Postfachs.
    ///   - folder: IMAP-Ordner (Standard: INBOX).
    /// - Returns: Ergebnis mit Anzahl geladener Mails und ob es noch
    ///   Älteres gibt.
    /// - Throws: Verbindungsfehler oder IMAP-Fehler.
    static func fetchOlder(
        account: MailAccount,
        password: String,
        folder: String = inboxFolder
    ) async throws -> OlderFetchResult {
        let server = MailServerFactory.imapServer(for: account)
        let searchCalendar = Calendar(identifier: .gregorian)
        do {
            try await server.connect()
            try await server.login(username: account.username, password: password)
            let selection = try await server.selectMailbox(folder)

            var start = MessageStore.shared.windowStart(accountID: account.id, folder: folder)
                ?? SyncWindow.standardStart(now: Date(), days: syncDays)

            let messageCount = selection.messageCount

            // Gibt es überhaupt Älteres? Nicht per SEARCH über den ganzen
            // Ordner – bei großen Postfächern sprengt die Liste aller UIDs
            // den Antwortpuffer (siehe hasMessages).
            guard try await hasMessages(
                on: server, before: start, messageCount: messageCount, calendar: searchCalendar
            ) else {
                try await server.logout()
                print("📬 [\(account.displayName)/\(folder)] Keine älteren Nachrichten")
                return .noOlder
            }

            var loaded = 0
            for _ in 0..<SyncWindow.maxBlocksPerLoad {
                let block = SyncWindow.nextBlock(before: start, days: syncDays)
                let uids: [SwiftMail.UID] = try await server.search(
                    criteria: [.since(block.since), .before(block.before)],
                    sortCriteria: [.descending(.date)],
                    calendar: searchCalendar
                )
                start = block.since
                print("📬 [\(account.displayName)/\(folder)] Zeitraum ab \(block.since): \(uids.count) UIDs")
                if !uids.isEmpty {
                    loaded = try await cacheMessages(
                        uids: uids, server: server, account: account, folder: folder
                    )
                    break
                }
                // Leerer Zeitraum: nur weiter zurück, wenn es noch Älteres gibt.
                guard try await hasMessages(
                    on: server, before: start, messageCount: messageCount, calendar: searchCalendar
                ) else { break }
            }

            // Fensterbeginn merken – schützt die Mails vor dem Aufräumen.
            MessageStore.shared.setWindowStart(start, accountID: account.id, folder: folder)

            let hasMore = try await hasMessages(
                on: server, before: start, messageCount: messageCount, calendar: searchCalendar
            )
            try await server.logout()
            return .loaded(count: loaded, windowStart: start, hasMore: hasMore)
        } catch {
            try? await server.disconnect()
            throw error
        }
    }

    /// Größe der Abschnitte (Sequenznummern), in denen `hasMessages` sucht.
    /// 1000 Nummern ergeben höchstens rund 6 KB Antwort – sicher unter den
    /// Puffergrenzen des IMAP-Parsers.
    private static let probeChunkSize = 1000

    /// Prüft, ob es im ausgewählten Ordner Mails vor einem Datum gibt.
    ///
    /// Verarbeitung: Sucht abschnittsweise über die Sequenznummern und
    /// endet beim ersten Treffer. Eine SEARCH über den ganzen Ordner
    /// würde bei großen Postfächern eine einzige riesige Antwortzeile
    /// liefern (PayloadTooLargeError). Die Ablagereihenfolge sagt nichts
    /// Verlässliches über das Datum, deshalb wird der ganze Ordner
    /// geprüft, bis ein Treffer vorliegt oder alle Abschnitte durch sind.
    ///
    /// - Parameters:
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    ///   - date: Datum (IMAP-Eingangsdatum, tagesgenau; BEFORE schließt
    ///     den Tag aus).
    ///   - messageCount: Anzahl der Nachrichten im Ordner (aus SELECT).
    ///   - calendar: Kalender für die IMAP-Suche.
    /// - Returns: true, wenn mindestens eine Mail vor `date` liegt.
    /// - Throws: IMAP-Fehler.
    private static func hasMessages(
        on server: SwiftMail.IMAPServer,
        before date: Date,
        messageCount: Int,
        calendar: Calendar
    ) async throws -> Bool {
        var lower = 1
        while lower <= messageCount {
            let upper = min(lower + probeChunkSize - 1, messageCount)
            let chunk = SwiftMail.SequenceNumberSet(
                SwiftMail.SequenceNumber(lower)...SwiftMail.SequenceNumber(upper)
            )
            let result: SwiftMail.ExtendedSearchResult<SwiftMail.SequenceNumber> = try await server.extendedSearch(
                identifierSet: chunk,
                criteria: [.before(date)],
                calendar: calendar
            )
            let hits = result.count
                ?? result.all?.count
                ?? result.ordered?.count
                ?? 0
            if hits > 0 { return true }
            lower = upper + 1
        }
        return false
    }

    // MARK: - Gemeinsames Caching

    /// Holt Header und Body der übergebenen UIDs und legt neue Nachrichten
    /// samt Anhängen (≤ 5 MB) im Cache ab.
    ///
    /// Verarbeitung: Prüft zuerst, welche UIDs schon im Cache liegen.
    /// Bekannte Mails erhalten nur aktuelle Flags (und ggf. nachgefüllte
    /// Header). Neue Mails werden einzeln geladen und sofort gespeichert;
    /// schlägt eine einzelne Mail fehl, wird sie übersprungen.
    ///
    /// Gemeinsamer Teil von `refreshAndCache` und `fetchOlder`.
    ///
    /// - Parameters:
    ///   - uids: IMAP-UIDs der zu ladenden Mails.
    ///   - server: Angemeldete IMAP-Verbindung mit ausgewähltem Ordner.
    ///   - account: Postfach.
    ///   - folder: IMAP-Ordner.
    /// - Returns: Anzahl neu gespeicherter Nachrichten.
    /// - Throws: IMAP-Fehler bei der Bulk-Abfrage (Fehler einzelner Mails
    ///   werden übersprungen).
    @discardableResult
    private static func cacheMessages(
        uids: [SwiftMail.UID],
        server: SwiftMail.IMAPServer,
        account: MailAccount,
        folder: String
    ) async throws -> Int {
        // Welche UIDs haben wir schon im Cache – und wem fehlen noch Header?
        let alreadyCached = MessageStore.shared.cachedMessageIDs(
            forAccount: account.id, folder: folder
        )
        let needsHeaders = MessageStore.shared.messageIDsNeedingHeaders(
            forAccount: account.id, folder: folder
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
            let msgID = CachedMessage.makeID(
                accountID: account.id, folder: folder, uid: uid.value
            )
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
                    folder: folder,
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

        return savedCount
    }

    // MARK: - Fehlerarten

    /// Prüft, ob ein Fehler nur „keine Verbindung" bedeutet.
    ///
    /// Verarbeitung: Erkennt `IMAPError.connectionFailed` und `.timeout`
    /// sowie die Fälle des `ConnectionErrorClassifier`. Bei reinen
    /// Verbindungsfehlern meldet die App das still im Titel statt per Alert.
    ///
    /// - Parameter error: Zu prüfender Fehler.
    /// - Returns: true bei einem reinen Verbindungsfehler.
    static func isConnectionError(_ error: Error) -> Bool {
        if let imapError = error as? SwiftMail.IMAPError {
            switch imapError {
            case .connectionFailed, .timeout:
                return true
            default:
                break
            }
        }
        return ConnectionErrorClassifier.isConnectionError(error)
    }

    // MARK: - Helfer

    /// Wertet die IMAP-Flags einer Nachricht in einem Durchlauf aus.
    ///
    /// Verarbeitung: Iteriert einmal über die Flags und setzt die
    /// vier booleschen Werte. `SwiftMail.Flag` voll qualifiziert, da
    /// NIOIMAPCore ebenfalls `Flag` definiert.
    ///
    /// - Parameter flags: IMAP-Flags der Nachricht.
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

    /// Überführt Adress- und Threading-Header aus dem MessageInfo ins
    /// Cache-Modell.
    ///
    /// - Parameter info: IMAP-Antwort mit Envelope-Daten.
    /// - Returns: Aufbereitete Header für den Cache.
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
