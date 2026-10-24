//
//  WatchTransfer.swift
//  Mailwerk
//
//  Zweck: Was iPhone und Apple Watch austauschen – die Mails für die Watch
//  samt Zustand (gelesen, gekennzeichnet, Eingang oder Spam), die
//  Filterlisten für die Spam-Einschätzung, Inhalte und Absenderbilder auf
//  Anfrage sowie die Aktionen, die auf der Watch entstehen.
//
//  Grundsatz: Die Watch spricht nie selbst mit den Mailservern (watchOS
//  erlaubt Apps keine eigenen IMAP-Verbindungen). Das iPhone ruft ab und
//  liefert; die Watch speichert alles selbst und bleibt ohne iPhone
//  bedienbar. Aktionen ohne iPhone wirken sofort auf der Watch und werden
//  nachgeholt. Der Server ist das führende System: Jede Lieferung des
//  iPhones ersetzt den Stand der Watch, noch offene Aktionen werden darauf
//  erneut angewandt (WatchMailbox).
//
//  Die Mailköpfe werden auf dem iPhone fertig aufbereitet (Name, Initialen,
//  Farbe, Absender für die Filterlisten), weil die Watch keinen Adressparser
//  (SwiftMail) hat.
//
//  Abgrenzung: Kodieren, Packen und Stückeln → WatchWire; Auswahl der Mails
//  → WatchMailSelection; Aufbau auf dem iPhone → WatchSnapshotBuilder;
//  Zustand auf der Watch → WatchMailbox.
//
//  Abhängigkeiten: Foundation, SpamHeaderVerdict, FilterLists,
//  FilterAddress, FilterEntryKind, SpamMenuRequest.
//

import Foundation

// MARK: - Mails

/// Ablageort einer Mail aus Sicht der Watch.
nonisolated enum WatchBox: String, Codable, Sendable {
    /// Posteingang eines Postfachs.
    case inbox
    /// Spam-Ordner eines Postfachs.
    case spam
}

/// Spam-Einstufung des Servers in übertragbarer Form.
nonisolated struct WatchVerdict: Codable, Equatable, Sendable {
    /// Der Server stuft die Mail als Spam ein.
    let isSpam: Bool
    /// Score des Servers; `nil` = keiner geliefert.
    let score: Double?

    /// Übernimmt den Befund der Kopfzeilen.
    ///
    /// - Parameter verdict: Befund des Servers.
    init(_ verdict: SpamHeaderVerdict) {
        self.isSpam = verdict.isSpam
        self.score = verdict.score
    }

    /// Befund in der Form des Spamfilters.
    var verdict: SpamHeaderVerdict {
        SpamHeaderVerdict(isSpam: isSpam, score: score)
    }
}

/// Hinweis auf einen Anhang: nur Name und Größe, nie der Inhalt.
nonisolated struct WatchAttachment: Codable, Equatable, Sendable {
    /// Dateiname.
    let name: String
    /// Größe in Byte laut Server.
    let sizeBytes: Int
}

/// Eine Mail für die Watch – Kopf, Zustand und Verweis auf das
/// Absenderbild, ohne Inhalt (der kommt als `WatchBody`).
nonisolated struct WatchMail: Codable, Equatable, Identifiable, Sendable {
    /// Cache-ID der Mail auf dem iPhone.
    let id: String
    /// Postfach.
    let accountID: UUID
    /// IMAP-Ordner.
    let folder: String
    /// UID im Ordner.
    let uid: UInt32
    /// Posteingang oder Spam-Ordner.
    var box: WatchBox
    /// Betreff.
    let subject: String
    /// Fett gezeigter Absender: Name, sonst Adresse.
    let senderTitle: String
    /// Adresse des Absenders ohne Namen; `nil`, wenn nicht auswertbar.
    let senderAddress: String?
    /// Absender in der Schreibweise der Filterlisten; `nil`, wenn nicht
    /// auswertbar (dann gibt es keine Spam-Aktionen).
    let filterAddress: String?
    /// Initialen für den Platzhalter.
    let initials: String
    /// Farbindex des Platzhalters in `AccountColor.allCases`.
    let colorIndex: Int
    /// Farbe des Postfachs als Hex-Wert; `nil` = keine gewählt.
    let accountColorHex: String?
    /// Absender als formatierte Adresse (Mailkopf).
    let from: String
    /// Empfänger (To), je Eintrag eine formatierte Adresse.
    let to: [String]
    /// Datum der Mail; `nil`, wenn unbekannt.
    let date: Date?
    /// `true` = ungelesen.
    var isUnread: Bool
    /// `true` = gekennzeichnet.
    var isFlagged: Bool
    /// Spam-Einstufung des Servers; `nil` = unbekannt.
    let verdict: WatchVerdict?
    /// `true`, wenn die Mail Anhänge hat (Namen kommen mit dem Inhalt).
    let hasAttachments: Bool
    /// Schlüssel des Absenderbilds (`WatchAvatarKey`); `nil` = keins vorhanden.
    let avatarKey: String?

    /// Absender für Spamfilter und Spam-Aktionen.
    var sender: FilterAddress? {
        filterAddress.flatMap { FilterAddress(normalizing: $0) }
    }
}

/// Schlüssel der Absenderbilder: Kontaktbild je Adresse, Logo je Domain.
nonisolated enum WatchAvatarKey {
    /// Präfix der Kontaktbilder.
    static let contactPrefix = "contact:"
    /// Präfix der Logos.
    static let logoPrefix = "logo:"

    /// Schlüssel eines Kontaktbilds.
    ///
    /// - Parameter address: Adresse (wird kleingeschrieben).
    /// - Returns: Schlüssel.
    static func contact(_ address: String) -> String {
        contactPrefix + address.lowercased()
    }

    /// Schlüssel eines Logos.
    ///
    /// - Parameter domain: Hauptdomain.
    /// - Returns: Schlüssel.
    static func logo(_ domain: String) -> String {
        logoPrefix + domain.lowercased()
    }

    /// `true`, wenn der Schlüssel ein Logo bezeichnet (eingepasst auf
    /// weißem Kreis statt rund zugeschnitten).
    ///
    /// - Parameter key: Schlüssel.
    /// - Returns: `true` bei einem Logo.
    static func isLogo(_ key: String) -> Bool {
        key.hasPrefix(logoPrefix)
    }
}

// MARK: - Filterlisten

/// Black- und Whitelist in übertragbarer Form (Mengen als sortierte Listen).
nonisolated struct WatchFilterLists: Codable, Equatable, Sendable {
    /// Exakte Adressen auf der Whitelist.
    var whiteAddresses: [String]
    /// Domains auf der Whitelist.
    var whiteDomains: [String]
    /// Exakte Adressen auf der Blacklist.
    var blackAddresses: [String]
    /// Domains auf der Blacklist.
    var blackDomains: [String]

    /// Übernimmt die Listen des Spamfilters.
    ///
    /// - Parameter lists: Momentaufnahme der Listen.
    init(_ lists: FilterLists) {
        whiteAddresses = lists.whiteAddresses.sorted()
        whiteDomains = lists.whiteDomains.sorted()
        blackAddresses = lists.blackAddresses.sorted()
        blackDomains = lists.blackDomains.sorted()
    }

    /// Listen in der Form des Spamfilters.
    var lists: FilterLists {
        FilterLists(
            whiteAddresses: Set(whiteAddresses),
            whiteDomains: Set(whiteDomains),
            blackAddresses: Set(blackAddresses),
            blackDomains: Set(blackDomains)
        )
    }
}

// MARK: - Lieferungen des iPhones

/// Stand des iPhones für die Watch: die ausgewählten Mails, Listen,
/// Einstellungen und das Ergebnis übermittelter Aktionen.
nonisolated struct WatchSnapshot: Codable, Equatable, Sendable {
    /// Zeitpunkt, zu dem das iPhone den Stand zusammengestellt hat.
    let createdAt: Date
    /// `true`, wenn unmittelbar vorher vom Server abgerufen wurde; `false`
    /// bei einer Zwischenlieferung aus dem Cache des iPhones.
    let isFresh: Bool
    /// Zeitpunkt des letzten erfolgreichen Abrufs aller Posteingänge
    /// (ältester beteiligter Posteingang); `nil` = noch nie.
    let lastServerSync: Date?
    /// `true`, wenn auf dem iPhone Postfächer mit eingeschaltetem Abruf
    /// eingerichtet sind.
    let hasAccounts: Bool
    /// Ausgewählte Mails (Eingänge und Spam), neueste zuerst.
    let mails: [WatchMail]
    /// Ungelesene Mails in allen Posteingängen, auch außerhalb der Auswahl.
    let unreadInboxTotal: Int
    /// Filterlisten; `nil`, wenn das iPhone sie nicht lesen konnte (die Watch
    /// entscheidet dann vorsichtig: keine Bilder, nichts automatisch laden).
    let lists: WatchFilterLists?
    /// Score-Obergrenze aus den Spam-Einstellungen.
    let scoreLimit: Double
    /// Ergebnis der mitgeschickten Aktionen.
    let outcomes: [WatchActionOutcome]
    /// Kurze Hinweise zu Postfächern, deren Abruf scheiterte.
    let problems: [String]
}

/// Inhalt einer Mail samt den Kopfdaten, die nur die geöffnete Mail
/// braucht.
nonisolated struct WatchBody: Codable, Equatable, Sendable {
    /// Cache-ID der Mail.
    let id: String
    /// HTML-Teil; `nil` = keiner bzw. zu groß.
    let html: String?
    /// Textteil; `nil` = keiner.
    let text: String?
    /// Kopie-Empfänger (Cc), je Eintrag eine formatierte Adresse.
    let cc: [String]
    /// Anhänge (ohne eingebettete Bilder), nur als Hinweis.
    let attachments: [WatchAttachment]
}

/// Ein Absenderbild, verkleinert für die Watch.
nonisolated struct WatchImage: Codable, Equatable, Sendable {
    /// Schlüssel (`WatchAvatarKey`).
    let key: String
    /// Bilddaten (PNG); `nil` = kein Bild vorhanden.
    let data: Data?
}

/// Inhalte und Bilder auf Anfrage der Watch.
nonisolated struct WatchContent: Codable, Equatable, Sendable {
    /// Inhalte der angefragten Mails, soweit noch vorhanden.
    let bodies: [WatchBody]
    /// Angefragte Absenderbilder.
    let images: [WatchImage]

    /// Keine Inhalte.
    static let empty = WatchContent(bodies: [], images: [])
}

// MARK: - Aktionen der Watch

/// Eine Aktion, die auf der Watch entstand und auf dem Server
/// auszuführen ist.
nonisolated struct WatchAction: Codable, Equatable, Identifiable, Sendable {
    /// Art der Änderung.
    nonisolated enum Change: Codable, Equatable, Sendable {
        /// Gelesen (`true`) bzw. ungelesen (`false`).
        case read(Bool)
        /// Kennzeichnung gesetzt (`true`) bzw. entfernt (`false`).
        case flagged(Bool)
        /// Blockieren oder Vertrauen für Adresse oder Domain.
        case spam(kind: SpamMenuRequest.Kind, entryKind: FilterEntryKind, value: String)
    }

    /// Eindeutige Kennung (Zuordnung des Ergebnisses).
    let id: UUID
    /// Zeitpunkt auf der Watch.
    let createdAt: Date
    /// Cache-ID der Mail.
    let mailID: String
    /// Postfach der Mail.
    let accountID: UUID
    /// Ordner der Mail.
    let folder: String
    /// UID der Mail im Ordner.
    let uid: UInt32
    /// Änderung.
    let change: Change

    /// Legt eine Aktion für eine Mail an.
    ///
    /// - Parameters:
    ///   - change: Änderung.
    ///   - mail: Betroffene Mail.
    ///   - id: Kennung (Standard: neu).
    ///   - createdAt: Zeitpunkt (Standard: jetzt).
    init(_ change: Change, on mail: WatchMail, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.mailID = mail.id
        self.accountID = mail.accountID
        self.folder = mail.folder
        self.uid = mail.uid
        self.change = change
    }

    /// Spam-Aktion als Anfrage des Menüs; `nil` bei anderen Änderungen.
    var spamRequest: SpamMenuRequest? {
        guard case .spam(let kind, let entryKind, let value) = change else { return nil }
        return SpamMenuRequest(kind: kind, entryKind: entryKind, value: value)
    }
}

/// Ergebnis einer Aktion der Watch auf dem iPhone.
nonisolated struct WatchActionOutcome: Codable, Equatable, Sendable {
    /// Ausgang.
    nonisolated enum Result: Codable, Equatable, Sendable {
        /// Auf dem Server ausgeführt.
        case done
        /// Verworfen, weil die Mail nicht mehr vorhanden ist (der Server
        /// gewinnt).
        case dropped
        /// Gescheitert; der Text erklärt den Grund.
        case failed(String)
    }

    /// Kennung der Aktion.
    let actionID: UUID
    /// Ausgang.
    let result: Result
}

// MARK: - Nachrichten

/// Anfrage der Watch an das iPhone. Die Antwort ist immer ein Stück
/// (`WatchChunk`) einer gepackten Lieferung (`WatchPayload`).
nonisolated enum WatchRequest: Codable, Sendable {
    /// Offene Aktionen übergeben und – mit `refresh` – alle Posteingänge
    /// abrufen. Antwort: der Stand aus dem Cache des iPhones; nach Aktionen
    /// und Abruf folgt der neue Stand als eigene Nachricht.
    case sync(actions: [WatchAction], refresh: Bool)
    /// Inhalte und Absenderbilder anfordern.
    case content(mailIDs: [String], imageKeys: [String])
    /// Weiteres Stück einer Lieferung anfordern.
    case chunk(token: UUID, index: Int)
}

/// Lieferung des iPhones an die Watch.
nonisolated enum WatchPayload: Codable, Sendable {
    /// Stand der Mails.
    case snapshot(WatchSnapshot)
    /// Angefragte Inhalte und Bilder.
    case content(WatchContent)
    /// Stand samt Inhalten in einem – Lieferung im Hintergrund nach einem
    /// Abruf auf dem iPhone.
    case package(WatchSnapshot, WatchContent)
}

// MARK: - Handoff

/// „Auf iPhone fortfahren“ für eine auf der Watch geöffnete Mail.
nonisolated enum WatchHandoff {
    /// Art der Aktivität (steht auch in `NSUserActivityTypes` der App).
    static let activityType = "de.sieber-bw.Mailwerk.mail"
    /// Schlüssel der Cache-ID in `userInfo`.
    static let messageIDKey = "messageID"
}
