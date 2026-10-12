//
//  InlineImageLoader.swift
//  Mailwerk
//
//  Zweck: Lädt eingebettete Bilder einer Mail nach, wenn ihr HTML Bilder
//  anspricht (`cid:`), deren Daten im Cache fehlen. Das betrifft Mails über
//  der Schwelle für das automatische Laden (5 MB), Bilder, deren Laden
//  beim Abruf scheiterte, und Mails, die gespeichert wurden, bevor Mailwerk
//  eingebettete Bilder kannte.
//
//  Ablauf: Struktur der Mail holen (ohne Inhalte), die eingebetteten Bilder
//  bestimmen (MessageContentPlan) und nur die angesprochenen, noch
//  fehlenden Bilder einzeln laden. Bilder ohne eigene Content-ID (Apple
//  Mail „Text – Bild – Text“) werden über die Content-ID aus ihrer
//  Abschnittsnummer erkannt, dieselbe wie beim Zusammensetzen der Mail. Für alle eingebetteten Bilder wird ein
//  Eintrag gespeichert – nicht angesprochene (z. B. mitgeschickte Fotos)
//  ohne Daten; sie erscheinen in der Anhangliste und laden per Antippen.
//
//  Der Ordner wird nur zum Lesen geöffnet (EXAMINE), Teile werden mit
//  `BODY.PEEK` geholt – am Server ändert sich nichts.
//
//  Abgrenzung: Laden beim Abruf → MailFetchService; welche Bilder
//  angesprochen sind → InlineImages; Aufruf beim Öffnen →
//  MessageDetailView.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailSession, AccountStore,
//  MessageContentPlan, InlineImages, MessageStore, Log.
//

import Foundation
import SwiftMail
import os

/// Nachladen eingebetteter Bilder einer Mail.
enum InlineImageLoader {

    /// Lädt die angesprochenen, noch fehlenden Bilder einer Mail und
    /// speichert sie.
    ///
    /// Verarbeitung: Ein Durchgang über eine Verbindung. Lässt sich ein
    /// einzelnes Bild nicht laden, wird es übersprungen (protokolliert);
    /// die anderen werden trotzdem gespeichert.
    ///
    /// - Parameters:
    ///   - message: Mail (liefert Postfach, Ordner, UID und HTML).
    ///   - existing: Bisherige Anhänge der Mail aus dem Cache.
    ///   - accountStore: Quelle für Postfach und Passwort.
    /// - Returns: Alle Anhänge der Mail nach dem Speichern.
    /// - Throws: `MailCredentialError` sowie Verbindungs- und IMAP-Fehler.
    static func loadMissing(
        for message: CachedMessage,
        existing: [CachedAttachment],
        accountStore: AccountStore
    ) async throws -> [CachedAttachment] {
        let credentials = try accountStore.credentials(for: message.accountID)
        let referenced = InlineImages.referencedContentIDs(in: message.htmlBody)
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let folder = message.folder
        let uid = SwiftMail.UID(message.uid)

        let images = try await MailSession.withIMAP(credentials) { server -> [CachedAttachment] in
            _ = try await server.examineMailbox(folder)
            let structure = try await server.fetchStructure(uid)
            let plan = MessageContentPlan(structure: structure, totalSize: 0, threshold: 0)

            var result: [CachedAttachment] = []
            for part in plan.inlineImages {
                let id = "\(message.id)-\(part.section)"
                let contentID = MessageContentPlan.contentID(for: part)
                var image = existingByID[id] ?? CachedAttachment(
                    id: id,
                    messageID: message.id,
                    filename: part.filename ?? "Bild",
                    contentType: part.contentType,
                    sizeBytes: part.size ?? 0,
                    data: nil,
                    contentID: contentID,
                    isInline: true
                )
                let isReferenced = referenced.contains(InlineImages.normalizedContentID(contentID))
                if isReferenced && image.data == nil {
                    do {
                        let raw = try await server.fetchPart(section: part.section, of: uid)
                        image = image.with(data: raw.decoded(for: part))
                    } catch {
                        Log.fetch.error("⚠️ Eingebettetes Bild \(part.section.description, privacy: .public) nicht geladen: \(error.localizedDescription, privacy: .public)")
                    }
                }
                result.append(image)
            }
            return result
        }

        for image in images {
            MessageStore.shared.saveAttachment(image)
        }
        let loaded = images.filter { $0.data != nil }.count
        Log.fetch.info("🖼 Eingebettete Bilder nachgeladen: \(loaded) von \(images.count), Ordner \(folder, privacy: .public)")
        return MessageStore.shared.attachments(forMessage: message.id)
    }
}
