//
//  MessageDetailHeader.swift
//  Mailwerk
//
//  Zweck: Kopfbereich der Mailansicht – Betreff mit Kennzeichen, Absender,
//  Empfänger, Kopie und Datum – sowie der schmale Hinweis „Externe Inhalte
//  blockiert“ mit dem Knopf „Laden“.
//
//  Abgrenzung: Inhalt, Menü und Aktionen → MessageDetailView; Anhänge →
//  MessageAttachmentList.
//
//  Abhängigkeiten: SwiftUI, CachedMessage.
//

import SwiftUI

/// Kopfbereich einer Mail.
struct MessageDetailHeader: View {
    /// Angezeigte Mail.
    let message: CachedMessage
    /// Kennzeichnung (von der Ansicht nachgeführt).
    let isFlagged: Bool

    /// Betreff, Kennzeichnung, Absender, Empfänger, Kopie und Datum.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(message.subject)
                    .font(.title2)
                    .bold()
                if isFlagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                }
            }
            Text("Von: \(message.from)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !message.to.isEmpty {
                Text("An: \(message.to)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !message.headers.ccList.isEmpty {
                Text("Kopie: \(message.headers.ccList.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let date = message.date {
                Text(date, format: .dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits).year().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Schmaler Hinweis „Externe Inhalte blockiert“ mit kleinem Knopf zum
/// Laden – bewusst zurückhaltend, damit er die Mail nicht verdrängt.
struct RemoteContentNotice: View {
    /// Gibt externe Inhalte für diese Anzeige frei.
    let onLoad: () -> Void

    /// Symbol, Hinweis und Knopf in einer Zeile.
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            Text("Externe Inhalte blockiert")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Laden") {
                onLoad()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Externe Inhalte laden")
        }
        .font(.footnote)
    }
}
