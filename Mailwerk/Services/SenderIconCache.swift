//
//  SenderIconCache.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 11.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Liefert der Mailliste das Logo zur Adresse einer Zeile und sorgt
//  dafür, dass fehlende oder abgelaufene Logos im Hintergrund geladen
//  werden.
//
//  Ablauf: Fragt eine Zeile nach einem Logo, wird die Hauptdomain
//  ermittelt (Freemail: kein Logo) und der gespeicherte Eintrag gelesen –
//  einmal je Domain und Sitzung aus dem Cache, danach aus dem Speicher.
//  Fehlt er oder ist er abgelaufen (30/90 Tage), kommt die Domain in die
//  Warteschlange. Die Zeile wartet nie: Sie zeigt sofort, was vorliegt,
//  sonst Initialen, und das Logo erscheint, sobald es geladen ist.
//
//  Warteschlange: Höchstens drei Abrufe gleichzeitig. Jede Domain wird je
//  Sitzung nur einmal angefragt, auch wenn viele Zeilen sie zeigen.
//  Offline wird nichts angefragt. Gespeichert werden Logo und „kein Logo“;
//  „nicht erreichbar“ wird erst beim nächsten Start erneut versucht. Ergibt
//  das Auffrischen eines vorhandenen Logos „kein Logo“, bleibt das alte
//  Logo stehen, nur der Prüfzeitpunkt wird erneuert.
//
//  Mailliste (v0.2.3c, Prüfbericht P-09): Die Zeilen holen ihr Logo über
//  `thumbnail(forAddress:)` asynchron – der Eintrag wird abseits des
//  Hauptthreads gelesen und das Bild verkleinert auf Anzeigegröße im
//  Hintergrund dekodiert (`DecodedImage.thumbnail`). Ein neues Logo meldet
//  sich nur bei den Zeilen seiner Domain (`revision(forAddress:)`), nicht
//  mehr über einen Zähler für alle – die Liste baut sich nicht bei jedem
//  geladenen Logo vollständig neu auf. Gespeichert wird im Hintergrund,
//  damit ein laufender Abruf das Speichern nicht blockiert.
//  Die Mailansicht nutzt weiter `image(forAddress:)` (ein Bild, volle
//  Auflösung) und den Zähler `revision`.
//
//  Protokoll: Domains privat, Anzahlen und Ergebnisse öffentlich.
//
//  Abgrenzung: Welche Domain → SenderDomain; Abruf und Aufbereitung →
//  SenderIconFetcher; Ablage → MessageStore; ob ein Bild gezeigt werden
//  darf → SpamClassifier.allowsSenderImage (geprüft vom Aufrufer, bevor
//  er hier fragt – Spam löst also keinen Abruf aus).
//
//  Abhängigkeiten: Foundation, Observation, SwiftUI (Image), SenderDomain,
//  SenderIconFetcher, SenderIconRecord, MessageStore, NetworkMonitor,
//  DecodedImage, Log.
//

import Foundation
import Observation
import SwiftUI
import os

/// Logos je Domain für die Mailliste, mit Warteschlange für fehlende.
@Observable
final class SenderIconCache {
    /// Gemeinsame Instanz der App.
    static let shared = SenderIconCache()

    /// Höchstzahl gleichzeitiger Abrufe.
    static let maxConcurrentFetches = 3

    /// Wird erhöht, wenn ein neues Logo vorliegt. Die Mailansicht liest ihn
    /// über `image(forAddress:)` mit und wird dadurch neu gezeichnet.
    private(set) var revision = 0
    /// Stand je Domain; wird erhöht, wenn für die Domain ein neues Logo
    /// vorliegt. Die Zeilen der Liste lesen ihn über `revision(forAddress:)`.
    private(set) var domainRevisions: [String: Int] = [:]
    /// Kantenlänge der verkleinerten Logos in Pixeln (40 pt bei 3-facher
    /// Auflösung).
    static let thumbnailPixelSize = 120
    /// Verkleinerte Logos für die Liste je Domain.
    @ObservationIgnored private var thumbnails: [String: Image] = [:]
    /// Gelesene Einträge je Domain.
    @ObservationIgnored private var records: [String: SenderIconRecord] = [:]
    /// Domains, für die der Cache schon gelesen wurde (auch ohne Eintrag).
    @ObservationIgnored private var lookedUp: Set<String> = []
    /// Bereits erzeugte Bilder je Domain.
    @ObservationIgnored private var images: [String: Image] = [:]
    /// Wartende Domains in Reihenfolge der Anfrage.
    @ObservationIgnored private var queue: [String] = []
    /// In dieser Sitzung schon angefragte Domains (wartend, laufend, fertig).
    @ObservationIgnored private var requested: Set<String> = []
    /// Anzahl laufender Abrufe.
    @ObservationIgnored private var running = 0
    /// Sitzung für alle Logo-Abrufe (Konstante – wird nicht beobachtet).
    private let session = SenderIconFetcher.makeSession()

    /// Nur die gemeinsame Instanz.
    private init() {}

    // MARK: - Abfrage

    /// Logo zu einer Adresse; stößt bei Bedarf das Laden an.
    ///
    /// Verarbeitung: Freemail und unbrauchbare Adressen ergeben `nil`.
    /// Fehlt der Eintrag oder ist er abgelaufen, wird die Domain
    /// vorgemerkt; ein vorhandenes älteres Logo wird bis dahin gezeigt.
    ///
    /// - Parameter address: E-Mail-Adresse; `nil` ergibt kein Logo.
    /// - Returns: Logo oder `nil`, wenn (noch) keines vorliegt.
    func image(forAddress address: String?) -> Image? {
        _ = revision
        guard let address, let domain = SenderDomain.iconDomain(forAddress: address) else { return nil }
        let record = storedRecord(for: domain)
        if record?.isDue() ?? true {
            enqueue(domain)
        }
        guard let data = record?.imageData else { return nil }
        if let image = images[domain] { return image }
        guard let image = DecodedImage.image(from: data) else { return nil }
        images[domain] = image
        return image
    }

    // MARK: - Liste (asynchron, verkleinert)

    /// Stand des Logos zur Adresse – ändert sich, sobald für deren Domain
    /// ein neues Logo vorliegt.
    ///
    /// - Parameter address: E-Mail-Adresse.
    /// - Returns: Zähler der Domain (0 = noch keine Änderung).
    func revision(forAddress address: String?) -> Int {
        guard let address, let domain = SenderDomain.iconDomain(forAddress: address) else { return 0 }
        return domainRevisions[domain] ?? 0
    }

    /// Schon verkleinertes Logo zur Adresse, ohne zu lesen oder zu dekodieren.
    ///
    /// Verarbeitung: Für das erste Zeichnen einer Zeile – liegt das Bild
    /// schon im Speicher, erscheint es sofort.
    ///
    /// - Parameter address: E-Mail-Adresse.
    /// - Returns: Logo oder `nil`.
    func cachedThumbnail(forAddress address: String?) -> Image? {
        guard let address, let domain = SenderDomain.iconDomain(forAddress: address) else { return nil }
        return thumbnails[domain]
    }

    /// Verkleinertes Logo zur Adresse; stößt bei Bedarf das Laden an.
    ///
    /// Verarbeitung: Freemail und unbrauchbare Adressen ergeben `nil`. Der
    /// Eintrag wird einmal je Domain abseits des Hauptthreads gelesen;
    /// fehlt er oder ist er abgelaufen, wird die Domain vorgemerkt. Das
    /// Bild wird im Hintergrund auf `thumbnailPixelSize` verkleinert
    /// dekodiert und im Speicher gehalten.
    ///
    /// - Parameter address: E-Mail-Adresse.
    /// - Returns: Logo oder `nil`, wenn (noch) keines vorliegt.
    func thumbnail(forAddress address: String?) async -> Image? {
        guard let address, let domain = SenderDomain.iconDomain(forAddress: address) else { return nil }
        if let image = thumbnails[domain] { return image }
        let record: SenderIconRecord?
        if lookedUp.contains(domain) {
            record = records[domain]
        } else {
            let loaded = await Self.loadRecord(domain)
            lookedUp.insert(domain)
            if let loaded, records[domain] == nil { records[domain] = loaded }
            record = records[domain]
        }
        if record?.isDue() ?? true {
            enqueue(domain)
        }
        guard let data = record?.imageData,
              let image = await DecodedImage.thumbnail(from: data, maxPixelSize: Self.thumbnailPixelSize)
        else { return nil }
        thumbnails[domain] = image
        return image
    }

    /// Liest den gespeicherten Eintrag einer Domain abseits des Hauptthreads.
    ///
    /// - Parameter domain: Hauptdomain.
    /// - Returns: Eintrag oder `nil`.
    @concurrent
    nonisolated private static func loadRecord(_ domain: String) async -> SenderIconRecord? {
        MessageStore.shared.senderIcon(domain: domain)
    }

    // MARK: - Eintrag lesen (synchron, Mailansicht)

    /// Gespeicherter Eintrag einer Domain; der Cache wird je Domain nur
    /// einmal gelesen.
    ///
    /// - Parameter domain: Hauptdomain.
    /// - Returns: Eintrag oder `nil`, wenn die Domain noch nie geprüft wurde.
    private func storedRecord(for domain: String) -> SenderIconRecord? {
        if lookedUp.insert(domain).inserted,
           let record = MessageStore.shared.senderIcon(domain: domain) {
            records[domain] = record
        }
        return records[domain]
    }

    // MARK: - Warteschlange

    /// Merkt eine Domain zum Laden vor.
    ///
    /// Verarbeitung: Offline und bei schon angefragten Domains passiert
    /// nichts. Der Start der Abrufe wird aus dem Zeichnen der Zeile
    /// herausgelöst.
    ///
    /// - Parameter domain: Hauptdomain.
    private func enqueue(_ domain: String) {
        guard NetworkMonitor.shared.isOnline, requested.insert(domain).inserted else { return }
        queue.append(domain)
        Task { self.startFetches() }
    }

    /// Startet wartende Abrufe bis zur Höchstzahl.
    ///
    /// Verarbeitung: Der Abruf selbst läuft neben dem Main-Actor
    /// (`SenderIconFetcher.fetch` ist `@concurrent`); das Ergebnis wird
    /// auf dem Main-Actor übernommen.
    private func startFetches() {
        while running < Self.maxConcurrentFetches, !queue.isEmpty {
            let domain = queue.removeFirst()
            running += 1
            let session = self.session
            Task {
                let outcome = await SenderIconFetcher.fetch(domain: domain, session: session)
                self.finish(domain, outcome)
            }
        }
    }

    /// Übernimmt das Ergebnis eines Abrufs und startet den nächsten.
    ///
    /// - Parameters:
    ///   - domain: Hauptdomain.
    ///   - outcome: Ergebnis des Abrufs.
    private func finish(_ domain: String, _ outcome: SenderIconFetcher.Outcome) {
        running -= 1
        switch outcome {
        case .icon(let data):
            store(SenderIconRecord(domain: domain, imageData: data, checkedAt: Date()))
            Log.fetch.info("🖼️ Logo geladen: \(domain, privacy: .private)")
        case .noIcon:
            // Ein vorhandenes Logo bleibt stehen; nur der Prüfzeitpunkt wird neu.
            store(SenderIconRecord(domain: domain, imageData: records[domain]?.imageData, checkedAt: Date()))
            Log.fetch.info("🖼️ Kein Logo: \(domain, privacy: .private)")
        case .unreachable:
            Log.fetch.info("🖼️ Logo nicht erreichbar, nächster Versuch beim Neustart: \(domain, privacy: .private)")
        }
        startFetches()
    }

    /// Übernimmt einen Eintrag und meldet ihn den Zeilen seiner Domain.
    ///
    /// Verarbeitung: Gespeichert wird im Hintergrund – die Schreibverbindung
    /// kann gerade durch einen Abruf belegt sein, die Oberfläche soll darauf
    /// nicht warten. Im Speicher gilt der Eintrag sofort.
    ///
    /// - Parameter record: Neuer Eintrag der Domain.
    private func store(_ record: SenderIconRecord) {
        Task.detached(priority: .utility) {
            MessageStore.shared.saveSenderIcon(record)
        }
        records[record.domain] = record
        lookedUp.insert(record.domain)
        images[record.domain] = nil
        thumbnails[record.domain] = nil
        domainRevisions[record.domain, default: 0] += 1
        revision += 1
    }
}
