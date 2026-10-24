//
//  AttachmentFilename.swift
//  Mailwerk
//
//  Zweck: Dateiname eines Anhangs mit passender Endung. Manche Mails
//  liefern Anhänge ohne Endung („Kundendokumente“), aber mit Typangabe
//  (`Content-Type: application/pdf`). iOS erkennt den Dateityp für
//  Vorschau, Teilen und Sichern an der Endung – ohne sie lässt sich die
//  Datei nicht öffnen. Fehlt die Endung, wird die zum Typ passende
//  angehängt („Kundendokumente.pdf“), wie es andere Mailprogramme tun.
//
//  Regeln:
//  - Hat der Name schon eine bekannte Endung, bleibt er unverändert –
//    auch wenn sie nicht zum Typ passt.
//  - Eine unbekannte „Endung“ (etwa „Rechnung 2026.10“) zählt nicht; dann
//    wird die passende angehängt.
//  - Ohne bekannte Endung zum Typ (z. B. `application/octet-stream`)
//    bleibt der Name unverändert.
//  Die Endung kommt aus Apples Typ-Verzeichnis (UTType), nicht aus einer
//  eigenen Tabelle.
//
//  Gespeichert wird weiterhin der Name aus der Mail; die Endung entsteht
//  erst beim Verwenden (Anzeige, Öffnen, Teilen, Weiterleiten).
//
//  Abgrenzung: Bereinigen gegen Pfadangaben → AttachmentManager
//  (`sanitizedFilename`).
//
//  Abhängigkeiten: Foundation, UniformTypeIdentifiers, CachedAttachment.
//

import Foundation
import UniformTypeIdentifiers

/// Dateiname eines Anhangs mit passender Endung. Reine Logik ohne Zustand,
/// deshalb an keinen Actor gebunden.
nonisolated enum AttachmentFilename {

    /// Ergänzt die zum Typ passende Endung, falls dem Namen eine fehlt.
    ///
    /// - Parameters:
    ///   - filename: Dateiname aus der Mail.
    ///   - contentType: MIME-Typ aus der Mail, ggf. mit Parametern
    ///     (`application/pdf; name=…`).
    /// - Returns: Name mit Endung bzw. unverändert, wenn er schon eine
    ///   bekannte hat oder zum Typ keine bekannt ist.
    static func completed(_ filename: String, contentType: String) -> String {
        guard !hasKnownExtension(filename),
              let suffix = preferredExtension(for: contentType) else { return filename }
        return "\(filename).\(suffix)"
    }

    /// Prüft, ob ein Name eine Endung trägt, die das System kennt.
    ///
    /// - Parameter filename: Dateiname.
    /// - Returns: `true` bei bekannter Endung (z. B. „pdf“, „PDF“, „gz“).
    static func hasKnownExtension(_ filename: String) -> Bool {
        let suffix = (filename as NSString).pathExtension
        guard !suffix.isEmpty, let type = UTType(filenameExtension: suffix) else { return false }
        return !type.isDynamic
    }

    /// Bevorzugte Endung zu einem MIME-Typ.
    ///
    /// - Parameter contentType: MIME-Typ, ggf. mit Parametern.
    /// - Returns: Endung ohne Punkt; `nil`, wenn keine bekannt ist.
    static func preferredExtension(for contentType: String) -> String? {
        let mimeType = contentType
            .split(separator: ";", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        guard !mimeType.isEmpty else { return nil }
        return UTType(mimeType: mimeType)?.preferredFilenameExtension
    }
}

extension CachedAttachment {
    /// Dateiname mit passender Endung – für Anzeige, Öffnen, Teilen und
    /// Weiterleiten (AttachmentFilename).
    var completedFilename: String {
        AttachmentFilename.completed(filename, contentType: contentType)
    }
}
