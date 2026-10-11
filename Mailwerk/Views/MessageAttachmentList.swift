//
//  MessageAttachmentList.swift
//  Mailwerk
//
//  Zweck: Liste der Anhänge in der Mailansicht – Überschrift mit Anzahl,
//  darunter je Anhang eine Zeile mit Vorschau bzw. Nachladen und Teilen.
//
//  Abgrenzung: Laden, Vorschau und Teilen-Dateien verwaltet
//  MessageDetailView; eine einzelne Zeile → AttachmentRow.
//
//  Abhängigkeiten: SwiftUI, CachedAttachment, AttachmentRow.
//

import SwiftUI

/// Liste der Anhänge einer Mail.
struct MessageAttachmentList: View {
    /// Anhänge der Mail.
    let attachments: [CachedAttachment]
    /// Anhänge, die gerade nachgeladen werden.
    let downloadingIDs: Set<String>
    /// Temporäre Dateien zum Teilen, je Anhang-ID.
    let shareURLs: [String: URL]
    /// Tipp auf einen Anhang (Vorschau bzw. Nachladen).
    let onTap: (CachedAttachment) -> Void

    /// Überschrift und Zeilen.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Anhänge (\(attachments.count))", systemImage: "paperclip")
                .font(.headline)

            ForEach(attachments) { attachment in
                AttachmentRow(
                    attachment: attachment,
                    isDownloading: downloadingIDs.contains(attachment.id),
                    onTap: { onTap(attachment) },
                    shareURL: shareURLs[attachment.id]
                )
            }
        }
    }
}
