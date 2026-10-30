//
//  InlineImageLoader.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 12.10.2026
//  Geändert: 30.10.2026
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
//  MessageContentPlan, InlineImages, FetchedMessageMapping, MessageStore,
//  Log.
//

import Foundation
import SwiftMail
import os

/// Nachladen eingebetteter Bilder einer Mail.
enum InlineImageLoader {

    /// Ein eingebettetes Bild der Mail und ob seine Daten zu laden sind.
    nonisolated struct ImageTask {
        /// Teil der Mail.
        let part: MessagePart
        /// Eintrag für den Cache (vorhanden oder neu, ggf. ohne Daten).
        let entry: CachedAttachment
        /// `true`, wenn das HTML das Bild anspricht und die Daten fehlen.
        let needsData: Bool
    }

    /// Bestimmt, welche eingebetteten Bilder der Mail geladen werden.
    ///
    /// Verarbeitung: Je Bild der vorhandene Eintrag aus dem Cache, sonst ein
    /// neuer ohne Daten (`FetchedMessageMapping.attachment`). Zu laden ist
    /// ein Bild nur, wenn das HTML es per `cid:` anspricht und noch keine
    /// Daten vorliegen.
    ///
    /// - Parameters:
    ///   - plan: Teile der Mail.
    ///   - messageID: Cache-ID der Mail.
    ///   - existing: Bisherige Anhänge der Mail aus dem Cache.
    ///   - referenced: Normalisierte Content-IDs, die das HTML anspricht.
    /// - Returns: Je eingebettetem Bild Eintrag und Ladebedarf.
    nonisolated static func tasks(
        for plan: MessageContentPlan,
        messageID: String,
        existing: [CachedAttachment],
        referenced: Set<String>
    ) -> [ImageTask] {
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return plan.inlineImages.map { part in
            let entry = existingByID["\(messageID)-\(part.section)"]
                ?? FetchedMessageMapping.attachment(for: part, data: nil, isInline: true, messageID: messageID)
            let isReferenced = referenced.contains(
                InlineImages.normalizedContentID(MessageContentPlan.contentID(for: part))
            )
            return ImageTask(part: part, entry: entry, needsData: isReferenced && entry.data == nil)
        }
    }

    /// Lädt die Daten eines Bildes, falls nötig.
    ///
    /// Verarbeitung: Lässt sich das Bild nicht laden, bleibt der Eintrag
    /// ohne Daten (protokolliert).
    ///
    /// - Parameters:
    ///   - task: Bild und Ladebedarf.
    ///   - uid: UID der Mail.
    ///   - server: Verbindung mit ausgewähltem Ordner.
    /// - Returns: Eintrag, ggf. mit Daten.
    nonisolated private static func load(
        _ task: ImageTask,
        uid: SwiftMail.UID,
        on server: SwiftMail.IMAPServer
    ) async -> CachedAttachment {
        guard task.needsData else { return task.entry }
        do {
            let raw = try await server.fetchPart(section: task.part.section, of: uid)
            return task.entry.with(data: raw.decoded(for: task.part))
        } catch {
            Log.fetch.error("⚠️ Eingebettetes Bild \(task.part.section.description, privacy: .public) nicht geladen: \(error.localizedDescription, privacy: .public)")
            return task.entry
        }
    }

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
        let folder = message.folder
        let uid = SwiftMail.UID(message.uid)
        let messageID = message.id

        let images = try await MailSession.withIMAP(credentials) { server -> [CachedAttachment] in
            _ = try await server.examineMailbox(folder)
            let structure = try await server.fetchStructure(uid)
            let tasks = Self.tasks(
                for: MessageContentPlan(structure: structure, totalSize: 0, threshold: 0),
                messageID: messageID, existing: existing, referenced: referenced
            )
            var result: [CachedAttachment] = []
            for task in tasks {
                result.append(await Self.load(task, uid: uid, on: server))
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
