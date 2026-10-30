//
//  WatchSnapshotBuilder.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 20.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Stellt auf dem iPhone zusammen, was die Apple Watch bekommt – den
//  Stand der Mails (Auswahl nach WatchMailSelection, Kopf fertig
//  aufbereitet), Inhalte auf Anfrage und verkleinerte Absenderbilder.
//
//  Kopf: Name, Initialen und Farbe kommen aus derselben Ermittlung wie die
//  Liste (MessageRowParty), der Absender für die Filterlisten aus
//  FilterAddress – die Watch hat dafür keinen Adressparser.
//
//  Absenderbilder: Kontaktbild vor Logo, wie in der Liste. Verweist eine
//  Mail auf ein Bild, schickt das iPhone es erst auf Anfrage, verkleinert
//  auf `avatarPixelSize` Pixel (PNG). Ob es gezeigt werden darf, entscheidet
//  die Watch selbst mit den mitgelieferten Listen (Spam: kein Bild).
//
//  Inhalt: HTML bis `maxHTMLBytes`, darüber nur der Textteil; Text bis
//  `maxTextBytes`, darüber gekürzt. Anhänge nur als Name und Größe,
//  eingebettete Bilder (cid) nie.
//
//  Stand: `cacheData` liest Cache und Bilderverzeichnis, `snapshot` stellt
//  daraus rein zusammen (Code-Review v0.3.1, Regel 4) – so ist die
//  Zusammenstellung ohne Datenbank testbar.
//
//  Abgrenzung: Auswahl → WatchMailSelection; Versand → WatchBridge;
//  Übertragungsform → WatchTransfer.
//
//  Abhängigkeiten: Foundation, ImageIO, UniformTypeIdentifiers,
//  MessageStore, MessageListItem, CachedMessage, MessageRowParty,
//  FilterAddress, SenderDomain, ContactImageDirectory, InlineImages,
//  MailAccount, FolderKey, MailFolder, WatchTransfer, WatchMailSelection.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Aufbau der Lieferungen an die Watch.
enum WatchSnapshotBuilder {

    /// Größtes HTML, das zur Watch geht (UTF-8-Byte).
    static let maxHTMLBytes = 1_000_000
    /// Größter Textteil, der zur Watch geht (UTF-8-Byte); länger wird gekürzt.
    static let maxTextBytes = 300_000
    /// Kantenlänge der Absenderbilder auf der Watch in Pixeln.
    static let avatarPixelSize = 96

    // MARK: - Stand

    /// Rahmen eines Stands – alles, was nicht aus dem Cache kommt.
    struct Frame {
        /// Postfächer mit eingeschaltetem Abruf.
        let accounts: [MailAccount]
        /// Filterlisten; `nil` = nicht lesbar.
        let lists: FilterLists?
        /// Score-Obergrenze.
        let scoreLimit: Double
        /// `true` direkt nach einem Abruf.
        let isFresh: Bool
        /// Ergebnisse mitgeschickter Aktionen.
        var outcomes: [WatchActionOutcome] = []
        /// Hinweise zu gescheiterten Abrufen.
        var problems: [String] = []
        /// Zeitpunkt (Tests).
        var now = Date()
    }

    /// Was ein Stand aus Cache und Bilderverzeichnis braucht.
    struct CacheData {
        /// Mails der Posteingänge.
        let inbox: [MessageListItem]
        /// Mails der Spam-Ordner.
        let spam: [MessageListItem]
        /// Letzter Abruf des Posteingangs je Postfach; `nil` = noch nie.
        let lastSyncs: [Date?]
        /// Ungelesene Mails in allen Posteingängen.
        let unreadInboxTotal: Int
        /// `true`, wenn es zur Adresse ein Kontaktbild gibt.
        let hasContactImage: (String) -> Bool
        /// `true`, wenn es zur Domain ein Logo gibt.
        let hasLogo: (String) -> Bool
    }

    /// Liest die Daten für einen Stand aus Cache und Bilderverzeichnis.
    ///
    /// - Parameters:
    ///   - accounts: Postfächer mit eingeschaltetem Abruf.
    ///   - spamFolders: Spam-Ordner dieser Postfächer.
    /// - Returns: Daten für `snapshot`.
    static func cacheData(accounts: [MailAccount], spamFolders: [FolderKey]) -> CacheData {
        let store = MessageStore.shared
        let accountIDs = accounts.map(\.id)
        return CacheData(
            inbox: store.allMessages(accountIDs: accountIDs, folder: MailFolder.inboxPath),
            spam: store.messages(in: spamFolders),
            lastSyncs: accountIDs.map { store.lastSync(accountID: $0, folder: MailFolder.inboxPath) },
            unreadInboxTotal: store.unreadInboxCount(accountIDs: accountIDs),
            hasContactImage: { ContactImageDirectory.shared.thumbnailData(for: $0) != nil },
            hasLogo: { store.senderIcon(domain: $0)?.imageData != nil }
        )
    }

    /// Stellt den Stand der Mails für die Watch zusammen.
    ///
    /// Verarbeitung: Auswahl der Mails nach `WatchMailSelection`, neueste
    /// zuerst. Der letzte Abruf gilt nur, wenn jedes Postfach schon einmal
    /// abgerufen wurde – dann der älteste. Reine Zusammenstellung; die Daten
    /// liest `cacheData`.
    ///
    /// - Parameters:
    ///   - frame: Postfächer, Listen, Anlass und Hinweise.
    ///   - cache: Daten aus Cache und Bilderverzeichnis.
    /// - Returns: Stand für die Watch.
    static func snapshot(_ frame: Frame, cache: CacheData) -> WatchSnapshot {
        let colors = Dictionary(frame.accounts.map { ($0.id, $0.colorHex) }) { first, _ in first }
        let inboxIDs = Set(WatchMailSelection.inbox(cache.inbox.map { candidate($0) }))
        let spamIDs = Set(WatchMailSelection.spam(cache.spam.map { candidate($0) }))
        let mails = cache.inbox.filter { inboxIDs.contains($0.id) }
            .map { mail(from: $0, box: .inbox, colors: colors, cache: cache) }
            + cache.spam.filter { spamIDs.contains($0.id) }
            .map { mail(from: $0, box: .spam, colors: colors, cache: cache) }
        let lastServerSync = cache.lastSyncs.contains(where: { $0 == nil })
            ? nil
            : cache.lastSyncs.compactMap { $0 }.min()

        return WatchSnapshot(
            createdAt: frame.now,
            isFresh: frame.isFresh,
            lastServerSync: lastServerSync,
            hasAccounts: !frame.accounts.isEmpty,
            mails: mails.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) },
            unreadInboxTotal: cache.unreadInboxTotal,
            lists: frame.lists.map(WatchFilterLists.init),
            scoreLimit: frame.scoreLimit,
            outcomes: frame.outcomes,
            problems: frame.problems
        )
    }

    /// Kandidat für die Auswahl aus einem Listeneintrag.
    ///
    /// - Parameter item: Listeneintrag.
    /// - Returns: Kandidat.
    static func candidate(_ item: MessageListItem) -> WatchMailSelection.Candidate {
        WatchMailSelection.Candidate(id: item.id, date: item.date, isUnread: item.isUnread, isFlagged: item.isFlagged)
    }

    /// Mail für die Watch aus einem Listeneintrag mit dem passenden
    /// Absenderbild.
    ///
    /// - Parameters:
    ///   - item: Listeneintrag.
    ///   - box: Posteingang oder Spam-Ordner.
    ///   - colors: Farbe je Postfach.
    ///   - cache: Nachschlagen von Kontaktbild und Logo.
    /// - Returns: Mail für die Watch.
    private static func mail(
        from item: MessageListItem,
        box: WatchBox,
        colors: [UUID: String?],
        cache: CacheData
    ) -> WatchMail {
        let party = MessageRowParty.make(for: item, showsRecipients: false)
        let key = avatarKey(
            forAddress: party.address,
            hasContactImage: cache.hasContactImage,
            hasLogo: cache.hasLogo
        )
        return mail(from: item, box: box, colorHex: colors[item.accountID] ?? nil, avatarKey: key)
    }

    /// Mail für die Watch aus einem Listeneintrag.
    ///
    /// - Parameters:
    ///   - item: Listeneintrag.
    ///   - box: Posteingang oder Spam-Ordner.
    ///   - colorHex: Farbe des Postfachs; `nil` = keine.
    ///   - avatarKey: Schlüssel des Absenderbilds; `nil` = keins.
    /// - Returns: Mail für die Watch.
    static func mail(from item: MessageListItem, box: WatchBox, colorHex: String?, avatarKey: String?) -> WatchMail {
        let party = MessageRowParty.make(for: item, showsRecipients: false)
        return WatchMail(
            id: item.id,
            accountID: item.accountID,
            folder: item.folder,
            uid: item.uid,
            box: box,
            subject: item.subject,
            senderTitle: party.title,
            senderAddress: party.address,
            filterAddress: FilterAddress.sender(fromHeader: item.from)?.address,
            initials: party.initials,
            colorIndex: party.colorIndex,
            accountColorHex: colorHex,
            from: item.from,
            to: item.recipients,
            date: item.date,
            isUnread: item.isUnread,
            isFlagged: item.isFlagged,
            verdict: item.spamVerdict.map(WatchVerdict.init),
            hasAttachments: item.hasAttachments,
            avatarKey: avatarKey
        )
    }

    /// Schlüssel des Absenderbilds: Kontaktbild vor Logo, wie in der Liste.
    ///
    /// - Parameters:
    ///   - address: Adresse des Absenders.
    ///   - hasContactImage: Gibt es ein Kontaktbild zur Adresse?
    ///   - hasLogo: Gibt es ein gespeichertes Logo zur Domain?
    /// - Returns: Schlüssel oder `nil`, wenn es kein Bild gibt.
    static func avatarKey(
        forAddress address: String?,
        hasContactImage: (String) -> Bool,
        hasLogo: (String) -> Bool
    ) -> String? {
        guard let address else { return nil }
        if hasContactImage(address) {
            return WatchAvatarKey.contact(address)
        }
        if let domain = SenderDomain.iconDomain(forAddress: address), hasLogo(domain) {
            return WatchAvatarKey.logo(domain)
        }
        return nil
    }

    // MARK: - Inhalte

    /// Inhalte und Bilder auf Anfrage der Watch.
    ///
    /// Verarbeitung: Nicht mehr vorhandene Mails fehlen in der Antwort;
    /// die Watch verwirft sie mit der nächsten Lieferung.
    ///
    /// - Parameters:
    ///   - mailIDs: Cache-IDs.
    ///   - imageKeys: Schlüssel der Absenderbilder.
    /// - Returns: Inhalte und Bilder.
    static func content(mailIDs: [String], imageKeys: [String]) -> WatchContent {
        let store = MessageStore.shared
        let bodies = mailIDs.compactMap { id -> WatchBody? in
            guard let message = store.message(id: id) else { return nil }
            return body(from: message, attachments: store.attachments(forMessage: id))
        }
        let images = imageKeys.map { WatchImage(key: $0, data: imageData(forKey: $0)) }
        return WatchContent(bodies: bodies, images: images)
    }

    /// Inhalt einer Mail für die Watch.
    ///
    /// Verarbeitung: HTML über `maxHTMLBytes` entfällt (dann zählt der
    /// Text); Text über `maxTextBytes` wird gekürzt. Anhänge ohne
    /// eingebettete Bilder, nur Name und Größe.
    ///
    /// - Parameters:
    ///   - message: Vollständige Mail.
    ///   - attachments: Anhänge der Mail.
    /// - Returns: Inhalt.
    static func body(from message: CachedMessage, attachments: [CachedAttachment]) -> WatchBody {
        let html = message.htmlBody.flatMap { $0.utf8.count <= maxHTMLBytes ? $0 : nil }
        let text = message.textBody.map { truncated($0, maxBytes: maxTextBytes) }
        let visible = InlineImages.visibleAttachments(attachments, html: message.htmlBody)
        return WatchBody(
            id: message.id,
            html: html,
            text: text,
            cc: message.headers.ccList,
            attachments: visible.map { WatchAttachment(name: $0.filename, sizeBytes: $0.sizeBytes) }
        )
    }

    /// Kürzt einen Text auf eine Byte-Grenze, ohne ein Zeichen zu zerteilen.
    ///
    /// - Parameters:
    ///   - text: Text.
    ///   - maxBytes: Größte Länge in UTF-8-Byte.
    /// - Returns: Text oder gekürzter Text mit „…“.
    static func truncated(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var result = ""
        var bytes = 0
        for character in text {
            let size = String(character).utf8.count
            guard bytes + size <= maxBytes else { break }
            result.append(character)
            bytes += size
        }
        return result + "…"
    }

    // MARK: - Bilder

    /// Verkleinertes Absenderbild zu einem Schlüssel.
    ///
    /// - Parameter key: Schlüssel (`WatchAvatarKey`).
    /// - Returns: PNG-Daten oder `nil`, wenn es kein Bild gibt.
    static func imageData(forKey key: String) -> Data? {
        let original: Data?
        if key.hasPrefix(WatchAvatarKey.contactPrefix) {
            original = ContactImageDirectory.shared.thumbnailData(for: String(key.dropFirst(WatchAvatarKey.contactPrefix.count)))
        } else if key.hasPrefix(WatchAvatarKey.logoPrefix) {
            original = MessageStore.shared.senderIcon(domain: String(key.dropFirst(WatchAvatarKey.logoPrefix.count)))?.imageData
        } else {
            original = nil
        }
        return original.flatMap { scaledPNG($0, maxPixelSize: avatarPixelSize) }
    }

    /// Verkleinert ein Bild auf eine Kantenlänge und liefert es als PNG.
    ///
    /// - Parameters:
    ///   - data: Bilddaten in einem von ImageIO lesbaren Format.
    ///   - maxPixelSize: Längste Kante in Pixeln.
    /// - Returns: PNG-Daten oder `nil`, wenn das Bild nicht lesbar ist.
    nonisolated static func scaledPNG(_ data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
