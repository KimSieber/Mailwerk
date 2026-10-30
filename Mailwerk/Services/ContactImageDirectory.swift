//
//  ContactImageDirectory.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 11.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Kontaktbilder für die Mailliste – Zuordnung von E-Mail-Adresse
//  zu Vorschaubild aus den Systemkontakten.
//
//  Ablauf: Beim ersten Anzeigen der Liste wird die Kontakte-Berechtigung
//  angefragt (falls noch nicht entschieden) und einmal im Hintergrund
//  gelesen, welche Kontakte ein Bild haben. Gemerkt werden nur deren
//  kleine Vorschaubilder je Adresse. Ändert sich das Adressbuch, wird die
//  Zuordnung neu aufgebaut; die Liste zeigt neue Bilder ohne Neustart.
//
//  Datenschutz: Die Zuordnung liegt nur im Speicher und wird nie in den
//  Cache geschrieben. Das Gerät verlässt ein Bild nur verkleinert zur
//  eigenen Apple Watch – für Absender der dorthin gelieferten Mails
//  (WatchBridge, `thumbnailData(for:)`). Ohne Berechtigung bleibt sie
//  leer – die Liste zeigt dann Initialen. Bei eingeschränktem Zugriff
//  gelten nur die freigegebenen Kontakte.
//
//  Bilder werden erst bei Bedarf aus den Daten erzeugt und dann gemerkt,
//  damit Kontakte ohne Mail in der Liste nichts kosten.
//
//  Mailliste (v0.2.3c, Prüfbericht P-09): Die Zeilen holen ihr Bild über
//  `thumbnail(for:)` – verkleinert und im Hintergrund dekodiert
//  (`DecodedImage.thumbnail`). Die Mailansicht nutzt weiter `image(for:)`.
//
//  Abgrenzung: Berechtigung anfragen → ContactSuggestionService (gemeinsam
//  mit den Adressvorschlägen); ob ein Bild gezeigt werden darf →
//  SpamClassifier.allowsSenderImage; Darstellung → SenderAvatarView.
//
//  Abhängigkeiten: Foundation, Contacts, Observation, SwiftUI (Image),
//  DecodedImage, ContactSuggestionService, Log.
//

import Foundation
import Contacts
import Observation
import SwiftUI
import os

/// Kontaktbilder je E-Mail-Adresse.
@Observable
final class ContactImageDirectory {
    /// Gemeinsame Instanz der App.
    static let shared = ContactImageDirectory()

    /// Wird bei jeder neu aufgebauten Zuordnung erhöht. Zeilen lesen ihn
    /// über `image(for:)` mit und werden dadurch neu gezeichnet.
    private(set) var revision = 0
    /// Vorschaubilder als Daten je Adresse (kleingeschrieben).
    @ObservationIgnored private var thumbnails: [String: Data] = [:]
    /// Bereits erzeugte Bilder je Adresse.
    @ObservationIgnored private var images: [String: Image] = [:]
    /// Verkleinerte Bilder für die Mailliste je Adresse.
    @ObservationIgnored private var listThumbnails: [String: Image] = [:]
    /// Kantenlänge der verkleinerten Bilder in Pixeln (40 pt, 3-fach).
    static let thumbnailPixelSize = 120
    /// `true`, sobald `start()` einmal lief.
    @ObservationIgnored private var started = false
    /// Laufender Aufbau der Zuordnung; ein neuer ersetzt ihn.
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Wartet auf Änderungen am Adressbuch und baut die Zuordnung neu auf.
    @ObservationIgnored private var changeTask: Task<Void, Never>?

    /// Nur die gemeinsame Instanz.
    private init() {}

    // MARK: - Steuerung

    /// Startet den Dienst einmalig: fragt die Berechtigung an, baut die
    /// Zuordnung auf und beobachtet danach Änderungen am Adressbuch.
    ///
    /// Verarbeitung: Weitere Aufrufe tun nichts. Die Systemabfrage zur
    /// Berechtigung erscheint nur, solange noch nicht entschieden ist.
    func start() async {
        guard !started else { return }
        started = true
        _ = await ContactSuggestionService.shared.requestAccessIfNeeded()
        // Läuft auf dem Main-Actor; die gemeinsame Instanz lebt so lange
        // wie die App, deshalb ohne schwache Referenz.
        changeTask = Task {
            for await _ in NotificationCenter.default.notifications(named: .CNContactStoreDidChange) {
                self.reload()
            }
        }
        reload()
    }

    /// Baut die Zuordnung im Hintergrund neu auf.
    ///
    /// Verarbeitung: Ohne Berechtigung wird sie geleert. Ein laufender
    /// Aufbau wird abgebrochen; sein Ergebnis wird verworfen.
    func reload() {
        loadTask?.cancel()
        guard ContactSuggestionService.shared.isAccessAllowed else {
            apply([:])
            return
        }
        loadTask = Task {
            let loaded = await Task.detached(priority: .utility) {
                Self.readThumbnails()
            }.value
            guard !Task.isCancelled else { return }
            apply(loaded)
        }
    }

    /// Übernimmt eine neue Zuordnung und verwirft erzeugte Bilder.
    ///
    /// - Parameter loaded: Vorschaubilder je Adresse.
    private func apply(_ loaded: [String: Data]) {
        thumbnails = loaded
        images = [:]
        listThumbnails = [:]
        revision += 1
        Log.view.info("👤 Kontaktbilder: \(loaded.count, privacy: .public) Adressen")
    }

    // MARK: - Abfrage

    /// Kontaktbild zu einer Adresse.
    ///
    /// Verarbeitung: Vergleich ohne Groß-/Kleinschreibung; das Bild wird
    /// beim ersten Zugriff aus den Daten erzeugt und gemerkt.
    ///
    /// - Parameter address: E-Mail-Adresse; `nil` ergibt kein Bild.
    /// - Returns: Bild oder `nil`, wenn der Kontakt fehlt oder kein Bild hat.
    func image(for address: String?) -> Image? {
        _ = revision
        guard let address else { return nil }
        let key = Self.normalized(address)
        if let image = images[key] { return image }
        guard let data = thumbnails[key], let image = DecodedImage.image(from: data) else { return nil }
        images[key] = image
        return image
    }

    /// Schon verkleinertes Bild zur Adresse, ohne zu dekodieren.
    ///
    /// - Parameter address: E-Mail-Adresse.
    /// - Returns: Bild oder `nil`.
    func cachedThumbnail(for address: String?) -> Image? {
        guard let address else { return nil }
        return listThumbnails[Self.normalized(address)]
    }

    /// Verkleinertes Kontaktbild zu einer Adresse für die Mailliste.
    ///
    /// Verarbeitung: Dekodiert einmal je Adresse im Hintergrund auf
    /// `thumbnailPixelSize` und hält das Bild im Speicher. Neu gelesene
    /// Kontakte leeren den Speicher (`apply`).
    ///
    /// - Parameter address: E-Mail-Adresse; `nil` ergibt kein Bild.
    /// - Returns: Bild oder `nil`, wenn der Kontakt fehlt oder kein Bild hat.
    func thumbnail(for address: String?) async -> Image? {
        guard let address else { return nil }
        let key = Self.normalized(address)
        if let image = listThumbnails[key] { return image }
        guard let data = thumbnails[key],
              let image = await DecodedImage.thumbnail(from: data, maxPixelSize: Self.thumbnailPixelSize)
        else { return nil }
        listThumbnails[key] = image
        return image
    }

    /// Vorschaubild zu einer Adresse als Daten – für die Apple Watch, die
    /// keinen Zugriff auf die Kontakte des iPhones hat.
    ///
    /// - Parameter address: E-Mail-Adresse; `nil` ergibt keine Daten.
    /// - Returns: Bilddaten oder `nil`, wenn der Kontakt fehlt oder kein Bild hat.
    func thumbnailData(for address: String?) -> Data? {
        guard let address else { return nil }
        return thumbnails[Self.normalized(address)]
    }

    // MARK: - Hilfen

    /// Einheitliche Schreibweise einer Adresse als Schlüssel.
    ///
    /// - Parameter address: Adresse.
    /// - Returns: Ohne Leerraum an den Rändern, kleingeschrieben.
    nonisolated static func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Bildet die Zuordnung aus Kontakten (Adressen und Vorschaubild).
    ///
    /// Verarbeitung: Kontakte ohne Bild oder mit leeren Bilddaten entfallen.
    /// Steht eine Adresse in mehreren Kontakten, gewinnt der erste.
    ///
    /// - Parameter contacts: Adressen und Bilddaten je Kontakt.
    /// - Returns: Vorschaubild je Adresse (kleingeschrieben).
    nonisolated static func thumbnailMap(
        from contacts: [(addresses: [String], thumbnail: Data?)]
    ) -> [String: Data] {
        var map: [String: Data] = [:]
        for contact in contacts {
            guard let data = contact.thumbnail, !data.isEmpty else { continue }
            for address in contact.addresses {
                let key = normalized(address)
                guard !key.isEmpty, map[key] == nil else { continue }
                map[key] = data
            }
        }
        return map
    }

    /// Liest alle Kontakte mit Bild aus dem Adressbuch.
    ///
    /// Verarbeitung: Läuft außerhalb des Main-Actors. Angefordert werden
    /// nur Adressen und Vorschaubild. Ein Lesefehler ergibt eine leere
    /// Zuordnung und wird protokolliert.
    ///
    /// - Returns: Vorschaubild je Adresse (kleingeschrieben).
    private nonisolated static func readThumbnails() -> [String: Data] {
        let keys: [CNKeyDescriptor] = [
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
        var contacts: [(addresses: [String], thumbnail: Data?)] = []
        do {
            try CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                guard contact.imageDataAvailable, !contact.emailAddresses.isEmpty else { return }
                contacts.append((
                    addresses: contact.emailAddresses.map { $0.value as String },
                    thumbnail: contact.thumbnailImageData
                ))
            }
        } catch {
            Log.view.error("⚠️ Kontaktbilder nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        return thumbnailMap(from: contacts)
    }
}
