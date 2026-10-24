//
//  WatchMailbox.swift
//  Mailwerk
//
//  Zweck: Zustand der Mails auf der Apple Watch – die letzte Lieferung des
//  iPhones und darauf die Aktionen, die der Server noch nicht bestätigt
//  hat. Daraus entstehen die vier Sichten (Alle Eingänge, Ungelesen, Mit
//  Kennzeichnung, Spam) und die Zahl der ungelesenen Mails.
//
//  Regeln:
//  - Der Server ist das führende System. Jede Lieferung ersetzt den
//    bisherigen Stand vollständig; ältere Lieferungen als die vorhandene
//    werden übergangen.
//  - Eine Aktion wirkt sofort (gelesen, Kennzeichnung, Spam/Vertrauen) und
//    bleibt offen, bis das iPhone ihr Ergebnis meldet. Bis dahin wird sie
//    auf jede neue Lieferung erneut angewandt, damit nichts zurückspringt.
//  - Eine neuere Aktion derselben Art an derselben Mail ersetzt eine noch
//    offene ältere (z. B. gelesen, dann wieder ungelesen).
//  - Blockieren legt die Mail sofort in „Spam“ und trägt den Wert in die
//    Listen der Watch ein; Vertrauen holt sie aus „Spam“ zurück. Steht der
//    Wert schon auf der anderen Liste, wird abgelehnt – wie auf dem iPhone.
//
//  Reine Logik, deshalb `nonisolated`; vollständig per Unit-Test abgedeckt.
//
//  Abgrenzung: Speichern auf der Watch → WatchStore; Lieferungen →
//  WatchTransfer.
//
//  Abhängigkeiten: Foundation, WatchTransfer, FilterLists, FilterListError,
//  SpamMenuRequest.
//

import Foundation

/// Sicht der Mail-Liste auf der Watch.
nonisolated enum WatchView: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Alle Posteingänge.
    case allInboxes
    /// Ungelesene Mails der Posteingänge.
    case unread
    /// Gekennzeichnete Mails der Posteingänge.
    case flagged
    /// Spam-Ordner aller Postfächer.
    case spam

    /// Kennung für SwiftUI.
    var id: String { rawValue }

    /// Titel (wie auf dem iPhone).
    var title: String {
        switch self {
        case .allInboxes: return "Alle Eingänge"
        case .unread:     return "Ungelesen"
        case .flagged:    return "Mit Kennzeichnung"
        case .spam:       return "Spam"
        }
    }

    /// SF-Symbol (wie auf dem iPhone).
    var systemImage: String {
        switch self {
        case .allInboxes: return "tray.2"
        case .unread:     return "envelope.badge"
        case .flagged:    return "flag"
        case .spam:       return "xmark.bin"
        }
    }
}

/// Mails der Watch: Lieferung des iPhones plus offene Aktionen.
nonisolated struct WatchMailbox: Codable, Equatable, Sendable {
    /// Letzte Lieferung des iPhones; `nil` = noch keine.
    private(set) var snapshot: WatchSnapshot?
    /// Aktionen, deren Ergebnis noch aussteht, in ihrer Reihenfolge.
    private(set) var pending: [WatchAction] = []

    /// Leerer Zustand.
    init() {}

    // MARK: - Lieferungen

    /// Übernimmt eine Lieferung des iPhones.
    ///
    /// Verarbeitung: Eine Lieferung, die älter ist als die vorhandene, wird
    /// übergangen. Sonst ersetzt sie den Stand; Aktionen, deren Ergebnis sie
    /// meldet, sind erledigt.
    ///
    /// - Parameter snapshot: Lieferung.
    /// - Returns: Gescheiterte Aktionen mit ihrem Grund (für einen Hinweis);
    ///   leer, wenn nichts scheiterte oder die Lieferung übergangen wurde.
    @discardableResult
    mutating func receive(_ snapshot: WatchSnapshot) -> [(action: WatchAction, reason: String)] {
        if let current = self.snapshot, snapshot.createdAt < current.createdAt {
            return []
        }
        self.snapshot = snapshot
        let results = Dictionary(snapshot.outcomes.map { ($0.actionID, $0.result) }) { first, _ in first }
        var failures: [(action: WatchAction, reason: String)] = []
        pending.removeAll { action in
            guard let result = results[action.id] else { return false }
            if case .failed(let reason) = result {
                failures.append((action, reason))
            }
            return true
        }
        return failures
    }

    // MARK: - Aktionen

    /// Führt eine Aktion auf der Watch aus und merkt sie zum Nachholen vor.
    ///
    /// Verarbeitung: Spam-Aktionen werden abgelehnt, wenn der Wert schon auf
    /// der anderen Liste steht. Eine offene ältere Aktion derselben Art an
    /// derselben Mail entfällt.
    ///
    /// - Parameters:
    ///   - change: Änderung.
    ///   - mail: Betroffene Mail.
    ///   - now: Zeitpunkt (Tests).
    /// - Returns: Die vorgemerkte Aktion.
    /// - Throws: `FilterListError.alreadyOnOtherList`.
    @discardableResult
    mutating func perform(_ change: WatchAction.Change, on mail: WatchMail, now: Date = Date()) throws -> WatchAction {
        if case .spam(let kind, let entryKind, let value) = change, let lists = effectiveLists() {
            let request = SpamMenuRequest(kind: kind, entryKind: entryKind, value: value)
            if Self.contains(value, kind: entryKind, list: request.list.other, in: lists) {
                throw FilterListError.alreadyOnOtherList(request.list.other)
            }
        }
        pending.removeAll { $0.mailID == mail.id && Self.sameKind($0.change, change) }
        let action = WatchAction(change, on: mail, createdAt: now)
        pending.append(action)
        return action
    }

    // MARK: - Abfragen

    /// `true`, sobald eine Lieferung vorliegt.
    var hasSnapshot: Bool { snapshot != nil }

    /// Alle Mails mit angewandten offenen Aktionen, neueste zuerst.
    ///
    /// - Returns: Mails.
    func effectiveMails() -> [WatchMail] {
        guard let snapshot else { return [] }
        var mails = snapshot.mails
        var position: [String: Int] = [:]
        for (index, mail) in mails.enumerated() { position[mail.id] = index }
        for action in pending {
            guard let index = position[action.mailID] else { continue }
            Self.apply(action.change, to: &mails[index])
        }
        return mails.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Filterlisten mit den Einträgen offener Spam-Aktionen; `nil`, wenn
    /// das iPhone keine lesbaren Listen geliefert hat.
    ///
    /// - Returns: Listen.
    func effectiveLists() -> FilterLists? {
        guard var lists = snapshot?.lists?.lists else { return nil }
        for action in pending {
            guard let request = action.spamRequest else { continue }
            switch (request.list, request.entryKind) {
            case (.white, .address): lists.whiteAddresses.insert(request.value)
            case (.white, .domain): lists.whiteDomains.insert(request.value)
            case (.black, .address): lists.blackAddresses.insert(request.value)
            case (.black, .domain): lists.blackDomains.insert(request.value)
            }
        }
        return lists
    }

    /// Mails einer Sicht.
    ///
    /// - Parameters:
    ///   - view: Sicht.
    ///   - mails: Mails mit angewandten Aktionen (`effectiveMails()`).
    ///   - keeping: Sicht „Ungelesen“: Mails, die stehen bleiben, auch wenn
    ///     sie inzwischen gelesen sind.
    /// - Returns: Mails der Sicht, neueste zuerst.
    static func mails(in view: WatchView, from mails: [WatchMail], keeping: Set<String> = []) -> [WatchMail] {
        mails.filter { mail in
            switch view {
            case .allInboxes: return mail.box == .inbox
            case .unread:     return mail.box == .inbox && (mail.isUnread || keeping.contains(mail.id))
            case .flagged:    return mail.box == .inbox && mail.isFlagged
            case .spam:       return mail.box == .spam
            }
        }
    }

    /// Zahl der ungelesenen Mails in den Posteingängen.
    ///
    /// Verarbeitung: Gesamtzahl laut iPhone, bereinigt um die Änderungen
    /// auf der Watch – ungelesene Mails außerhalb der Auswahl zählen mit.
    ///
    /// - Returns: Anzahl.
    func unreadCount() -> Int {
        guard let snapshot else { return 0 }
        let delivered = snapshot.mails.filter { $0.box == .inbox && $0.isUnread }.count
        let outside = max(0, snapshot.unreadInboxTotal - delivered)
        let current = effectiveMails().filter { $0.box == .inbox && $0.isUnread }.count
        return outside + current
    }

    // MARK: - Intern

    /// Wendet eine Änderung auf eine Mail an.
    ///
    /// - Parameters:
    ///   - change: Änderung.
    ///   - mail: Mail.
    private static func apply(_ change: WatchAction.Change, to mail: inout WatchMail) {
        switch change {
        case .read(let isRead):
            mail.isUnread = !isRead
        case .flagged(let isFlagged):
            mail.isFlagged = isFlagged
        case .spam(let kind, _, _):
            switch kind {
            case .block: mail.box = .spam
            case .trust: if mail.box == .spam { mail.box = .inbox }
            }
        }
    }

    /// `true`, wenn zwei Änderungen dieselbe Art betreffen (und die neuere
    /// die ältere damit ersetzt).
    private static func sameKind(_ lhs: WatchAction.Change, _ rhs: WatchAction.Change) -> Bool {
        switch (lhs, rhs) {
        case (.read, .read), (.flagged, .flagged): return true
        case let (.spam(_, lKind, lValue), .spam(_, rKind, rValue)):
            return lKind == rKind && lValue == rValue
        default: return false
        }
    }

    /// `true`, wenn der Wert auf der angegebenen Liste steht.
    private static func contains(_ value: String, kind: FilterEntryKind, list: FilterList, in lists: FilterLists) -> Bool {
        switch (list, kind) {
        case (.white, .address): return lists.whiteAddresses.contains(value)
        case (.white, .domain): return lists.whiteDomains.contains(value)
        case (.black, .address): return lists.blackAddresses.contains(value)
        case (.black, .domain): return lists.blackDomains.contains(value)
        }
    }
}
