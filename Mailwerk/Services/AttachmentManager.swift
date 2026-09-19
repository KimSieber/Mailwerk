//
//  AttachmentManager.swift
//  Mailwerk
//

import Foundation
import SwiftMail
import NIOIMAPCore

/// Verwaltet temporäre Dateien für die Vorschau/das Teilen von Anhängen
/// und lädt fehlende Anhänge (> 5 MB) bei Bedarf vom IMAP-Server nach.
enum AttachmentManager {

    enum AttachmentError: LocalizedError {
        case noData
        case accountNotFound
        case noPassword
        case messageNotFound
        case partNotFound

        var errorDescription: String? {
            switch self {
            case .noData: return "Keine Daten vorhanden"
            case .accountNotFound: return "Konto nicht gefunden"
            case .noPassword: return "Kein Passwort im Keychain"
            case .messageNotFound: return "Nachricht nicht auf dem Server gefunden"
            case .partNotFound: return "Anhang nicht auf dem Server gefunden"
            }
        }
    }

    // MARK: - Temporäre Datei für Vorschau / Teilen

    /// Schreibt die Anhang-Daten in eine temporäre Datei und gibt deren URL zurück.
    /// Die Datei wird im systemeigenen tmp-Verzeichnis abgelegt und beim
    /// nächsten App-Neustart automatisch bereinigt.
    static func writeTempFile(for attachment: CachedAttachment) throws -> URL {
        guard let data = attachment.data else {
            throw AttachmentError.noData
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mailwerk-Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent(attachment.filename)

        // Bestehende Datei überschreiben
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - On-demand-Download

    /// Lädt einen einzelnen Anhang vom IMAP-Server nach (für Mails > 5 MB,
    /// bei denen nur Metadaten gecacht wurden). Speichert die Daten im
    /// lokalen Cache und gibt den aktualisierten Anhang zurück.
    static func downloadAttachment(
        _ attachment: CachedAttachment,
        message: CachedMessage,
        accountStore: AccountStore
    ) async throws -> CachedAttachment {
        guard let account = accountStore.accounts.first(where: { $0.id == message.accountID }) else {
            throw AttachmentError.accountNotFound
        }
        guard let password = try accountStore.password(for: account) else {
            throw AttachmentError.noPassword
        }

        let server = IMAPServer(host: account.imapHost, port: account.imapPort)
        do {
            try await server.connect()
            try await server.login(username: account.username, password: password)
            _ = try await server.selectMailbox("INBOX")

            // MessageInfo für diese UID holen
            let uid = SwiftMail.UID(message.uid)
            let infos = try await server.fetchMessageInfosBulk(
                using: UIDSet([uid]), options: .slim
            )
            guard let info = infos.first else {
                try await server.logout()
                throw AttachmentError.messageNotFound
            }

            // Vollständige Nachricht laden, um Anhang-Parts zu finden
            let fullMessage = try await server.fetchMessage(from: info)

            // Passenden Part über Dateiname und Content-Type identifizieren
            guard let part = fullMessage.attachments.first(where: {
                $0.filename == attachment.filename
                    && $0.contentType == attachment.contentType
            }) else {
                try await server.logout()
                throw AttachmentError.partNotFound
            }

            let data = try await server.fetchAndDecodeMessagePartData(
                messageInfo: info, part: part
            )

            try await server.logout()

            // Im Cache aktualisieren
            let updated = CachedAttachment(
                id: attachment.id,
                messageID: attachment.messageID,
                filename: attachment.filename,
                contentType: attachment.contentType,
                sizeBytes: data.count,
                data: data
            )
            MessageStore.shared.saveAttachment(updated)

            return updated
        } catch {
            try? await server.disconnect()
            throw error
        }
    }
}
