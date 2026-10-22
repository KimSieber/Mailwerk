//
//  AttachmentRow.swift
//  Mailwerk
//
//  Zweck: Zeile eines Anhangs in der Mailansicht – Typ-Symbol, Dateiname,
//  Größe, Teilen-Knopf (wenn die Daten geladen sind) und Ladezustand.
//  Antippen öffnet die Vorschau bzw. lädt den Anhang nach.
//
//  Abgrenzung: Laden, Vorschau und Teilen-Dateien → MessageDetailView,
//  AttachmentManager.
//
//  Abhängigkeiten: SwiftUI, CachedAttachment, AttachmentFilename.
//

import SwiftUI

/// Zeigt einen einzelnen Anhang als Zeile: Typ-Icon, Dateiname, Größe,
/// Share-Button (wenn Daten vorhanden) und Download-Status.
struct AttachmentRow: View {
    /// Angezeigter Anhang.
    let attachment: CachedAttachment
    /// `true`, solange der Anhang nachgeladen wird.
    let isDownloading: Bool
    /// Antippen: Vorschau öffnen bzw. nachladen.
    let onTap: () -> Void
    /// Temporäre Datei zum Teilen; `nil`, solange keine vorliegt.
    let shareURL: URL?

    /// Zeile mit Symbol, Name, Größe und Teilen- bzw. Ladeanzeige.
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: attachment.contentType))
                    .font(.title2)
                    .foregroundStyle(attachment.data != nil ? .blue : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    // Mit passender Endung, wie die Datei beim Öffnen und
                    // Teilen heißt (AttachmentFilename).
                    Text(attachment.completedFilename)
                        .font(.subheadline)
                        .lineLimit(1)

                    if attachment.data == nil {
                        Text("\(formattedSize(attachment.sizeBytes)) – Tippen zum Laden")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else {
                        Text(formattedSize(attachment.sizeBytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isDownloading {
                    ProgressView()
                } else if attachment.data != nil, let url = shareURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                } else if attachment.data == nil {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helfer

    /// SF-Symbol passend zum MIME-Typ.
    ///
    /// - Parameter contentType: MIME-Typ.
    /// - Returns: Name des Symbols; unbekannte Typen ergeben die Büroklammer.
    private func iconName(for contentType: String) -> String {
        let ct = contentType.lowercased()
        if ct.hasPrefix("image/") { return "photo" }
        if ct.contains("pdf") { return "doc.richtext" }
        if ct.hasPrefix("text/") { return "doc.text" }
        if ct.hasPrefix("audio/") { return "waveform" }
        if ct.hasPrefix("video/") { return "film" }
        if ct.contains("zip") || ct.contains("compressed") || ct.contains("archive") {
            return "doc.zipper"
        }
        if ct.contains("spreadsheet") || ct.contains("excel") || ct.contains("csv") {
            return "tablecells"
        }
        if ct.contains("presentation") || ct.contains("powerpoint") {
            return "rectangle.split.3x1"
        }
        if ct.contains("word") || ct.contains("document") {
            return "doc.text"
        }
        return "paperclip"
    }

    /// Größe in B, KB oder MB.
    ///
    /// - Parameter bytes: Größe in Bytes.
    /// - Returns: Formatierte Größe.
    private func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
