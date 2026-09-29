//
//  MailShareSheet.swift
//  Mailwerk
//
//  Teilen-Dialog für eine Nachricht. Geteilt werden:
//  - die Mail als temporäre HTML-Datei (mit Header und Body)
//  - lokal vorhandene Anhänge als Dateien
//
//  NSAttributedString(data:options:.html) ist für komplexe HTML-Mails
//  (Google, Newsletter) unzuverlässig und scheitert still. Deshalb
//  erzeugen wir eine temporäre .html-Datei, die jeder Empfänger
//  öffnen oder die das System als PDF rendern kann.
//

import SwiftUI

#if os(iOS)
struct MailShareSheet: UIViewControllerRepresentable {
    let message: CachedMessage
    let attachments: [CachedAttachment]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = []

        // Mail als temporäre HTML-Datei
        let html = MessageDetailView.printableHTML(for: message, attachments: attachments)
        let filename = safeFilename(message.subject) + ".html"
        let tempDir = FileManager.default.temporaryDirectory
        let htmlURL = tempDir.appendingPathComponent(filename)
        try? html.data(using: .utf8)?.write(to: htmlURL)
        items.append(htmlURL)

        // Lokale Anhänge als Dateien
        for attachment in attachments where attachment.data != nil {
            if let url = try? AttachmentManager.writeTempFile(for: attachment) {
                items.append(url)
            }
        }

        let controller = UIActivityViewController(
            activityItems: items, applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    private func safeFilename(_ subject: String) -> String {
        let cleaned = subject
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Mail" : String(cleaned.prefix(60))
    }
}
#else
struct MailShareSheet: View {
    let message: CachedMessage
    let attachments: [CachedAttachment]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear { shareMac() }
    }

    private func shareMac() {
        var items: [Any] = []

        let html = MessageDetailView.printableHTML(for: message, attachments: attachments)
        let filename = safeFilename(message.subject) + ".html"
        let tempDir = FileManager.default.temporaryDirectory
        let htmlURL = tempDir.appendingPathComponent(filename)
        try? html.data(using: .utf8)?.write(to: htmlURL)
        items.append(htmlURL)

        for attachment in attachments where attachment.data != nil {
            if let url = try? AttachmentManager.writeTempFile(for: attachment) {
                items.append(url)
            }
        }

        guard !items.isEmpty else { dismiss(); return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let picker = NSSharingServicePicker(items: items)
            if let window = NSApp.keyWindow,
               let contentView = window.contentView {
                picker.show(
                    relativeTo: contentView.bounds,
                    of: contentView,
                    preferredEdge: .minY
                )
            }
            dismiss()
        }
    }

    private func safeFilename(_ subject: String) -> String {
        let cleaned = subject
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Mail" : String(cleaned.prefix(60))
    }
}
#endif
