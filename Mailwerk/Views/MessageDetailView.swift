//
//  MessageDetailView.swift
//  Mailwerk
//

import SwiftUI

struct MessageDetailView: View {
    let message: CachedMessage
    @State private var webViewHeight: CGFloat = 100

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.subject)
                    .font(.title2)
                    .bold()
                Text("Von: \(message.from)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !message.to.isEmpty {
                    Text("An: \(message.to)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let date = message.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()

                if let html = message.htmlBody {
                    HTMLMailView(html: html, contentHeight: $webViewHeight)
                        .frame(height: max(100, webViewHeight))
                    
                } else if let text = message.textBody {
                    Text(text)
                } else {
                    Text("Kein Inhalt verfügbar").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(message.accountDisplayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

