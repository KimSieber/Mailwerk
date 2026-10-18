//
//  WatchStore.swift
//  MailwerkWatch
//
//  Zweck: Speicher der Watch-App – die Mails (WatchMailbox: Lieferung des
//  iPhones plus offene Aktionen), ihre Inhalte und die Absenderbilder.
//  Alles liegt als Datei auf der Watch, damit die App ohne iPhone
//  bedienbar bleibt.
//
//  Ablage im gemeinsamen Speicher von App und Komplikation
//  (WatchAppGroup): `state.plist` (Mails, Listen, offene Aktionen),
//  `bodies/` (je Mail ein Inhalt), `images/` (je Schlüssel ein Bild) und
//  `badge.plist` (Zahl der ungelesenen Mails für die Komplikation).
//  Inhalte und Bilder, auf die keine Mail mehr verweist, werden nach jeder
//  Lieferung gelöscht – so bleibt es bei höchstens 120 Mails.
//
//  Zustand der Verbindung (`status`) für die Anzeige: aktualisiert gerade,
//  iPhone nicht erreichbar, Hinweise des iPhones.
//
//  Abgrenzung: Regeln des Zustands → WatchMailbox; Austausch mit dem
//  iPhone → WatchConnector; Komplikation → MailwerkWatchWidget.
//
//  Abhängigkeiten: Foundation, Observation, WidgetKit, WatchMailbox,
//  WatchTransfer, WatchAppGroup, WatchBadge, SpamClassifier, Log.
//

import Foundation
import Observation
import WidgetKit
import os

/// Speicher der Watch-App.
@Observable
final class WatchStore {
    /// Gemeinsame Instanz der App.
    static let shared = WatchStore()

    /// Zustand der Verbindung zum iPhone.
    enum Status: Equatable {
        /// Nichts läuft.
        case idle
        /// Aktualisierung läuft.
        case syncing
        /// iPhone nicht erreichbar.
        case unreachable
        /// Mailwerk ist auf dem iPhone nicht installiert.
        case companionMissing
    }

    /// Zustand der Verbindung.
    var status: Status = .idle
    /// Hinweis zu einer gescheiterten Aktion; `nil` = keiner. Die Anzeige
    /// setzt ihn nach dem Lesen zurück.
    var notice: String?

    /// Mails samt offenen Aktionen (gespeichert).
    private(set) var mailbox = WatchMailbox()
    /// Mails mit angewandten Aktionen, neueste zuerst.
    private(set) var mails: [WatchMail] = []
    /// Filterlisten mit offenen Einträgen; `nil` = unbekannt.
    private(set) var lists: FilterLists?
    /// Mails, deren Inhalt auf der Watch liegt.
    private(set) var bodyIDs: Set<String> = []
    /// Absenderbilder, die auf der Watch liegen (auch „kein Bild“).
    private(set) var imageKeys: Set<String> = []

    /// Bereits gelesene Bilder je Schlüssel.
    @ObservationIgnored private var imageCache: [String: Data] = [:]
    /// Ordner im gemeinsamen Speicher.
    @ObservationIgnored private let directory = WatchAppGroup.directory()

    /// Liest den gespeicherten Stand.
    private init() {
        try? FileManager.default.createDirectory(at: bodiesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: stateURL),
           let stored = try? PropertyListDecoder().decode(WatchMailbox.self, from: data) {
            mailbox = stored
        }
        bodyIDs = Self.storedNames(in: bodiesDirectory)
        imageKeys = Self.storedNames(in: imagesDirectory)
        recompute()
    }

    // MARK: - Abfragen

    /// Mails einer Sicht.
    ///
    /// - Parameters:
    ///   - view: Sicht.
    ///   - keeping: Sicht „Ungelesen“: Mails, die stehen bleiben.
    /// - Returns: Mails, neueste zuerst.
    func mails(in view: WatchView, keeping: Set<String> = []) -> [WatchMail] {
        WatchMailbox.mails(in: view, from: mails, keeping: keeping)
    }

    /// Eine Mail.
    ///
    /// - Parameter id: Cache-ID.
    /// - Returns: Mail oder `nil`, wenn sie nicht mehr vorhanden ist.
    func mail(id: String) -> WatchMail? {
        mails.first { $0.id == id }
    }

    /// Zahl der ungelesenen Mails in den Posteingängen.
    var unreadCount: Int { mailbox.unreadCount() }

    /// Zahl der gekennzeichneten Mails in den Posteingängen (auf der Watch).
    var flaggedCount: Int { mails(in: .flagged).count }

    /// `true`, sobald eine Lieferung des iPhones vorliegt.
    var hasSnapshot: Bool { mailbox.hasSnapshot }

    /// `true`, wenn auf dem iPhone Postfächer mit Abruf eingerichtet sind.
    var hasAccounts: Bool { mailbox.snapshot?.hasAccounts ?? true }

    /// Hinweis des iPhones zum letzten Abruf (z. B. keine Verbindung zum
    /// Mailserver); `nil` = keiner.
    var problem: String? { mailbox.snapshot?.problems.first }

    /// Letzter Abruf aller Posteingänge auf dem iPhone; `nil` = unbekannt.
    var lastServerSync: Date? { mailbox.snapshot?.lastServerSync }

    /// Score-Obergrenze aus den Spam-Einstellungen des iPhones.
    var scoreLimit: Double { mailbox.snapshot?.scoreLimit ?? SpamClassifier.defaultScoreLimit }

    /// Offene Aktionen in ihrer Reihenfolge.
    var pending: [WatchAction] { mailbox.pending }

    /// Mails, deren Inhalt noch fehlt, neueste zuerst.
    var missingBodyIDs: [String] {
        mails.map(\.id).filter { !bodyIDs.contains($0) }
    }

    /// Absenderbilder, die noch fehlen.
    var missingImageKeys: [String] {
        Array(Set(mails.compactMap(\.avatarKey)).subtracting(imageKeys)).sorted()
    }

    /// Inhalt einer Mail.
    ///
    /// - Parameter id: Cache-ID.
    /// - Returns: Inhalt oder `nil`, wenn er (noch) nicht auf der Watch liegt.
    func body(id: String) -> WatchBody? {
        guard bodyIDs.contains(id),
              let data = try? Data(contentsOf: fileURL(id, in: bodiesDirectory)) else { return nil }
        return try? PropertyListDecoder().decode(WatchBody.self, from: data)
    }

    /// Absenderbild zu einem Schlüssel.
    ///
    /// - Parameter key: Schlüssel.
    /// - Returns: Bilddaten oder `nil`, wenn keines vorliegt.
    func imageData(key: String) -> Data? {
        if let cached = imageCache[key] { return cached }
        guard imageKeys.contains(key),
              let data = try? Data(contentsOf: fileURL(key, in: imagesDirectory)),
              !data.isEmpty else { return nil }
        imageCache[key] = data
        return data
    }

    // MARK: - Lieferungen

    /// Übernimmt eine Lieferung des iPhones.
    ///
    /// - Parameter payload: Lieferung.
    func receive(_ payload: WatchPayload) {
        switch payload {
        case .snapshot(let snapshot):
            receive(snapshot)
        case .content(let content):
            receive(content)
        case .package(let snapshot, let content):
            receive(content)
            receive(snapshot)
        }
    }

    /// Übernimmt den Stand des iPhones.
    ///
    /// Verarbeitung: Gescheiterte Aktionen erscheinen als Hinweis. Danach
    /// werden nicht mehr gebrauchte Inhalte und Bilder gelöscht.
    ///
    /// - Parameter snapshot: Stand.
    private func receive(_ snapshot: WatchSnapshot) {
        if let failure = mailbox.receive(snapshot).last {
            notice = failure.reason
        }
        recompute()
        save()
        prune()
        Log.watch.info("⌚️ Stand übernommen: \(snapshot.mails.count, privacy: .public) Mails, frisch: \(snapshot.isFresh, privacy: .public)")
    }

    /// Speichert Inhalte und Bilder.
    ///
    /// - Parameter content: Inhalte und Bilder.
    private func receive(_ content: WatchContent) {
        for body in content.bodies {
            guard let data = try? PropertyListEncoder().encode(body) else { continue }
            if (try? data.write(to: fileURL(body.id, in: bodiesDirectory), options: .atomic)) != nil {
                bodyIDs.insert(body.id)
            }
        }
        for image in content.images {
            // Auch „kein Bild“ wird gemerkt (leere Datei), damit nicht
            // immer wieder danach gefragt wird.
            let data = image.data ?? Data()
            if (try? data.write(to: fileURL(image.key, in: imagesDirectory), options: .atomic)) != nil {
                imageKeys.insert(image.key)
                imageCache[image.key] = nil
            }
        }
    }

    // MARK: - Aktionen

    /// Führt eine Aktion auf der Watch aus und merkt sie zum Nachholen vor.
    ///
    /// - Parameters:
    ///   - change: Änderung.
    ///   - mail: Betroffene Mail.
    /// - Throws: `FilterListError.alreadyOnOtherList` bei Spam-Aktionen.
    func perform(_ change: WatchAction.Change, on mail: WatchMail) throws {
        try mailbox.perform(change, on: mail)
        recompute()
        save()
    }

    // MARK: - Intern

    /// Leitet Mails und Listen neu ab und aktualisiert die Komplikation.
    private func recompute() {
        mails = mailbox.effectiveMails()
        lists = mailbox.effectiveLists()
        let badge = WatchBadge(unread: mailbox.unreadCount(), updatedAt: mailbox.snapshot?.lastServerSync)
        if badge.save(to: directory) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Schreibt den Zustand.
    private func save() {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(mailbox).write(to: stateURL, options: .atomic)
        } catch {
            Log.watch.error("⚠️ Zustand der Watch nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Löscht Inhalte und Bilder, auf die keine Mail mehr verweist.
    private func prune() {
        let ids = Set(mails.map(\.id))
        for id in bodyIDs.subtracting(ids) {
            try? FileManager.default.removeItem(at: fileURL(id, in: bodiesDirectory))
            bodyIDs.remove(id)
        }
        let keys = Set(mails.compactMap(\.avatarKey))
        for key in imageKeys.subtracting(keys) {
            try? FileManager.default.removeItem(at: fileURL(key, in: imagesDirectory))
            imageKeys.remove(key)
            imageCache[key] = nil
        }
    }

    /// Datei des Zustands.
    private var stateURL: URL { directory.appendingPathComponent("state.plist") }
    /// Ordner der Inhalte.
    private var bodiesDirectory: URL { directory.appendingPathComponent("bodies", isDirectory: true) }
    /// Ordner der Bilder.
    private var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }

    /// Datei zu einer Kennung: die Kennung in Dateinamen-Schreibweise.
    ///
    /// - Parameters:
    ///   - name: Cache-ID bzw. Schlüssel.
    ///   - folder: Ordner.
    /// - Returns: Dateiadresse.
    private func fileURL(_ name: String, in folder: URL) -> URL {
        folder.appendingPathComponent(Self.fileName(for: name))
    }

    /// Dateiname zu einer Kennung: alles außer Buchstaben und Ziffern
    /// prozentkodiert (Ordnernamen dürfen „/“ enthalten).
    ///
    /// - Parameter name: Kennung.
    /// - Returns: Dateiname.
    private static func fileName(for name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
    }

    /// Kennungen der Dateien eines Ordners.
    ///
    /// - Parameter folder: Ordner.
    /// - Returns: Kennungen (Dateinamen entschlüsselt).
    private static func storedNames(in folder: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.compactMap { $0.removingPercentEncoding })
    }
}
