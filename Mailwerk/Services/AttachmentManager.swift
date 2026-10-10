//
//  AttachmentManager.swift
//  Mailwerk
//
//  Zweck: Stellt Anhänge für Vorschau, Teilen und Weiterleiten bereit.
//
//  - Schreibt gecachte Anhang-Daten in temporäre Dateien, weil QuickLook
//    und das Teilen-Menü mit Datei-URLs arbeiten.
//  - Bereinigt Dateinamen, damit Pfadtrennzeichen im MIME-Dateinamen
//    (z. B. „../../Library/Caches/payload") nicht aus dem Temp-Verzeichnis
//    ausbrechen können (K3).
//  - Lädt Anhänge nach, die beim Abruf nur als Metadaten gespeichert wurden
//    (Mails über der Schwelle für den automatischen Download). Der Abruf
//    erfolgt im Ordner der Mail, weil UIDs nur innerhalb eines Ordners
//    eindeutig sind.
//
//  Abgrenzung: Der automatische Download beim Abruf liegt im
//  MailFetchService; hier geht es nur um Einzelzugriffe.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailSession (Verbindung und
//  Zugangsdaten), AccountStore, MessageStore (Cache),
//  MessageContentPlan (Einordnung der Teile).
//

import Foundation
import SwiftMail
import NIOIMAPCore

/// Anhänge für Vorschau und Teilen bereitstellen und bei Bedarf nachladen.
enum AttachmentManager {

    /// Fehler beim Bereitstellen oder Nachladen eines Anhangs.
    enum AttachmentError: LocalizedError {
        /// Die Daten des Anhangs sind noch nicht geladen.
        case noData
        /// Die Nachricht liegt nicht mehr im Ordner auf dem Server.
        case messageNotFound
        /// Der Anhang ist in der Nachricht auf dem Server nicht zu finden.
        case partNotFound

        /// Liefert die deutsche Meldung für den Nutzer.
        ///
        /// - Returns: Meldungstext für die Anzeige.
        var errorDescription: String? {
            switch self {
            case .noData: return "Keine Daten vorhanden"
            case .messageNotFound: return "Nachricht nicht auf dem Server gefunden"
            case .partNotFound: return "Anhang nicht auf dem Server gefunden"
            }
        }
    }

    /// Name des Unterordners im tmp-Verzeichnis für Anhang-Dateien.
    private static let tempSubdirectory = "Mailwerk-Attachments"

    // MARK: - Temp-Verzeichnis

    /// Löscht das Temp-Verzeichnis für Anhänge, falls es existiert.
    ///
    /// Verarbeitung: Entfernt den gesamten Ordner `Mailwerk-Attachments`
    /// im tmp-Verzeichnis der App. Das Verzeichnis wird bei Bedarf von
    /// `writeTempFile` neu angelegt. Fehler werden still ignoriert, weil
    /// das System das tmp-Verzeichnis ohnehin regelmäßig leert.
    ///
    /// Aufruf: Einmal beim App-Start (`MailwerkApp.init`).
    static func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempSubdirectory, isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Temporäre Datei für Vorschau / Teilen

    /// Schreibt die Daten eines Anhangs in eine temporäre Datei.
    ///
    /// Verarbeitung: Legt im tmp-Verzeichnis der App den Ordner
    /// `Mailwerk-Attachments` an und schreibt die Daten unter dem
    /// bereinigten Dateinamen dorthin; eine vorhandene Datei gleichen
    /// Namens wird ersetzt. Die Bereinigung entfernt Pfadtrennzeichen
    /// und Punkte am Anfang, damit der Name nicht aus dem Temp-Verzeichnis
    /// ausbrechen kann.
    ///
    /// - Parameter attachment: Anhang mit geladenen Daten.
    /// - Returns: URL der geschriebenen Datei.
    /// - Throws: `AttachmentError.noData`, wenn die Daten noch nicht geladen
    ///   sind, sowie Dateisystemfehler.
    static func writeTempFile(for attachment: CachedAttachment) throws -> URL {
        guard let data = attachment.data else {
            throw AttachmentError.noData
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempSubdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let safe = Self.sanitizedFilename(attachment.filename)
        let fileURL = tempDir.appendingPathComponent(safe)

        // Bestehende Datei überschreiben
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Dateinamen bereinigen

    /// Entfernt Pfadtrennzeichen und unsichere Zeichen aus einem Dateinamen.
    ///
    /// Verarbeitung: Nimmt nur den letzten Pfadbestandteil (alles nach
    /// dem letzten `/` oder `\`), entfernt führende Punkte (verhindert
    /// versteckte Dateien und `..`-Traversal) und ersetzt einen leeren
    /// Rest durch „Anhang". Die Dateiendung bleibt erhalten.
    ///
    /// - Parameter filename: Rohname aus dem MIME-Header.
    /// - Returns: Bereinigter Name, der sicher im Temp-Verzeichnis liegt.
    static func sanitizedFilename(_ filename: String) -> String {
        // Nur den letzten Bestandteil nehmen (entfernt „../../" usw.)
        var name = (filename as NSString).lastPathComponent
        // Backslash-Pfade (Windows) ebenfalls behandeln
        if let lastBackslash = name.lastIndex(of: "\\") {
            name = String(name[name.index(after: lastBackslash)...])
        }
        // Führende Punkte entfernen
        while name.hasPrefix(".") {
            name = String(name.dropFirst())
        }
        // Leerer Name → Fallback
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = "Anhang"
        }
        return name
    }

    // MARK: - On-demand-Download

    /// Lädt einen einzelnen Anhang vom IMAP-Server nach und speichert ihn im Cache.
    ///
    /// Verarbeitung: Meldet sich am Postfach der Nachricht an, wählt den
    /// **Ordner der Nachricht** und holt nur deren Struktur (ohne Inhalte)
    /// über die UID. Der passende Teil wird über Dateiname und Content-Type
    /// bestimmt; nur er wird geladen, dekodiert und im Cache abgelegt.
    ///
    /// - Parameters:
    ///   - attachment: Anhang, dessen Daten fehlen.
    ///   - message: Nachricht, zu der der Anhang gehört (liefert Postfach,
    ///     Ordner und UID).
    ///   - accountStore: Quelle für Postfach und Passwort.
    /// - Returns: Der Anhang mit geladenen Daten.
    /// - Throws: `MailCredentialError` (Postfach oder Passwort fehlt),
    ///   `AttachmentError` (Nachricht oder Teil nicht gefunden) sowie
    ///   Verbindungsfehler.
    static func downloadAttachment(
        _ attachment: CachedAttachment,
        message: CachedMessage,
        accountStore: AccountStore
    ) async throws -> CachedAttachment {
        let credentials = try accountStore.credentials(for: message.accountID)

        let data = try await MailSession.withIMAP(credentials) { server -> Data in
            _ = try await server.selectMailbox(message.folder)

            // MessageInfo für diese UID holen
            let uid = SwiftMail.UID(message.uid)
            let infos = try await server.fetchMessageInfosBulk(
                using: UIDSet([uid]), options: .slim
            )
            guard let info = infos.first else {
                throw AttachmentError.messageNotFound
            }

            // Nur die Struktur laden (ohne Inhalte), um den Anhang zu finden;
            // geladen wird danach genau dieser eine Teil.
            let structure = try await server.fetchStructure(uid)
            let plan = MessageContentPlan(
                structure: structure,
                totalSize: 0,
                threshold: 0
            )

            // Passenden Part über Dateiname und Content-Type identifizieren
            guard let part = plan.attachments.first(where: {
                $0.filename == attachment.filename
                    && $0.contentType == attachment.contentType
            }) else {
                throw AttachmentError.partNotFound
            }

            return try await server.fetchAndDecodeMessagePartData(
                messageInfo: info, part: part
            )
        }

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
    }
}
