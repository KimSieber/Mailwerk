//
//  AttachmentRow.swift
//  Mailwerk
//

import SwiftUI

/// Zeigt einen einzelnen Anhang als Zeile: Typ-Icon, Dateiname, Größe,
/// Share-Button (wenn Daten vorhanden) und Download-Status.
struct AttachmentRow: View {
    let attachment: CachedAttachment
    let isDownloading: Bool
    let onTap: () -> Void
    let shareURL: URL?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: attachment.contentType))
                    .font(.title2)
                    .foregroundStyle(attachment.data != nil ? .blue : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename)
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

    private func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
