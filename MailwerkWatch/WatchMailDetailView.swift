//
//  WatchMailDetailView.swift
//  MailwerkWatch
//
//  Zweck: Eine geöffnete Mail auf der Watch – Kopf (Absenderbild,
//  Absender, Datum, An, Kopie, Spam-Einschätzung, Betreff), Inhalt,
//  Hinweise auf Anhänge und unten die Aktionen: gelesen/ungelesen,
//  Kennzeichen, „Spam / Vertrauen“.
//
//  Öffnen markiert die Mail als gelesen – wie in der App.
//
//  Externe Bilder: sofort bei vertrauenswürdigem Absender (dieselbe Regel
//  wie in der App, `SpamClassifier.trustsSender`), sonst erst nach
//  „Bilder laden“.
//
//  Liegt der Inhalt noch nicht auf der Watch, wird er beim iPhone
//  angefragt; ohne iPhone erscheint ein Hinweis.
//
//  „Auf iPhone fortfahren“: Die offene Mail wird als Aktivität angeboten
//  (Handoff, WatchHandoff); das iPhone öffnet sie dann in der App.
//
//  Abgrenzung: Darstellung des HTML → WatchRichTextView; Spam-Aktionen →
//  WatchSpamActionsView; Aktionen → WatchStore, WatchConnector.
//
//  Abhängigkeiten: SwiftUI, WatchStore, WatchConnector, WatchTransfer,
//  HTMLRichTextParser, SpamClassifier, SpamMark, ListDateFormatter,
//  WatchMailRow (WatchAvatarView).
//

import SwiftUI

/// Geöffnete Mail.
struct WatchMailDetailView: View {
    /// Cache-ID der Mail.
    let mailID: String

    /// Speicher der App.
    private let store = WatchStore.shared
    /// Schließt die Ansicht (nach Verschieben in Spam bzw. zurück).
    @Environment(\.dismiss) private var dismiss

    /// Inhalt der Mail; `nil`, solange er fehlt.
    @State private var content: WatchBody?
    /// Aufbereiteter HTML-Inhalt; `nil` = keiner bzw. noch nicht fertig.
    @State private var blocks: [WatchRichTextBlock]?
    /// `true`, solange der Inhalt beim iPhone angefragt wird.
    @State private var isLoading = false
    /// Externe Bilder freigegeben.
    @State private var allowsRemoteContent = false
    /// „Spam / Vertrauen“ geöffnet.
    @State private var showingSpamActions = false
    /// Die Mail wurde bei diesem Besuch schon geöffnet (gelesen markiert,
    /// Inhalt geladen) – die Rückkehr aus „Spam / Vertrauen“ wiederholt
    /// das nicht.
    @State private var hasOpened = false

    /// Mail oder Hinweis, wenn sie nicht mehr vorhanden ist.
    var body: some View {
        if let mail = store.mail(id: mailID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    header(mail)
                    Divider()
                    mailContent
                    attachments
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        perform(.read(mail.isUnread), on: mail)
                    } label: {
                        Image(systemName: mail.isUnread ? "envelope.open" : "envelope.badge")
                    }
                    .accessibilityLabel(mail.isUnread ? "Gelesen" : "Ungelesen")
                    Button {
                        perform(.flagged(!mail.isFlagged), on: mail)
                    } label: {
                        Image(systemName: mail.isFlagged ? "flag.slash" : "flag")
                    }
                    .accessibilityLabel(mail.isFlagged ? "Kennzeichen entfernen" : "Kennzeichnen")
                    Button {
                        showingSpamActions = true
                    } label: {
                        Image(systemName: "shield")
                    }
                    .accessibilityLabel("Spam / Vertrauen")
                    .disabled(mail.sender == nil)
                }
            }
            .navigationDestination(isPresented: $showingSpamActions) {
                WatchSpamActionsView(mail: mail) {
                    showingSpamActions = false
                    dismiss()
                }
            }
            .userActivity(WatchHandoff.activityType) { activity in
                activity.title = mail.subject
                activity.isEligibleForHandoff = true
                activity.addUserInfoEntries(from: [WatchHandoff.messageIDKey: mail.id])
            }
            .task(id: mailID) {
                await open(mail)
            }
        } else {
            ContentUnavailableView(
                "Nicht mehr vorhanden",
                systemImage: "envelope",
                description: Text("Die Mail wurde inzwischen gelöscht oder verschoben.")
            )
        }
    }

    // MARK: - Teile

    /// Kopf der Mail.
    ///
    /// - Parameter mail: Mail.
    /// - Returns: Absender, Datum, Empfänger, Spam-Einschätzung und Betreff.
    private func header(_ mail: WatchMail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                WatchAvatarView(mail: mail, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(mail.senderTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if let address = mail.senderAddress, address != mail.senderTitle {
                        Text(address)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            // Datum und Spam-Einschätzung je in einer eigenen Zeile, nie
            // umbrochen – nebeneinander wäre es auf der Watch zu eng.
            if let date = mail.date {
                Text(ListDateFormatter.string(for: date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let mark = spamMark(mail) {
                Text(mark)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if !mail.to.isEmpty {
                Text("An: \(mail.to.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let cc = content?.cc, !cc.isEmpty {
                Text("Kopie: \(cc.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(mail.subject.isEmpty ? "(kein Betreff)" : mail.subject)
                .font(.subheadline.bold())
                .padding(.top, 2)
        }
    }

    /// Inhalt: HTML, Text, Ladeanzeige oder Hinweis.
    @ViewBuilder
    private var mailContent: some View {
        if let blocks {
            if WatchRichTextView.hasRemoteImages(blocks) && !allowsRemoteContent {
                Button {
                    allowsRemoteContent = true
                } label: {
                    Label("Bilder laden", systemImage: "photo")
                }
            }
            WatchRichTextView(blocks: blocks, allowsRemoteContent: allowsRemoteContent)
        } else if let text = content?.text, !text.isEmpty {
            Text(text)
                .font(.footnote)
        } else if isLoading || (content?.html != nil && blocks == nil) {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if content != nil {
            Text("(kein Inhalt)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Der Inhalt liegt noch nicht auf der Watch. Das iPhone liefert ihn, sobald es erreichbar ist.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Hinweise auf Anhänge: nur Name und Größe.
    @ViewBuilder
    private var attachments: some View {
        if let list = content?.attachments, !list.isEmpty {
            Divider()
            ForEach(Array(list.enumerated()), id: \.offset) { _, attachment in
                Label {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(attachment.name)
                            .lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "paperclip")
                }
                .font(.caption2)
            }
        }
    }

    // MARK: - Abläufe

    /// Öffnet die Mail: als gelesen markieren, Inhalt laden und aufbereiten,
    /// externe Bilder bei vertrauenswürdigem Absender freigeben.
    ///
    /// - Parameter mail: Mail.
    private func open(_ mail: WatchMail) async {
        guard !hasOpened else { return }
        hasOpened = true
        if mail.isUnread {
            perform(.read(true), on: mail)
        }
        if let lists = store.lists {
            allowsRemoteContent = SpamClassifier.trustsSender(
                sender: mail.sender,
                verdict: mail.verdict?.verdict,
                lists: lists,
                scoreLimit: store.scoreLimit
            )
        }
        content = store.body(id: mail.id)
        if content == nil {
            isLoading = true
            await WatchConnector.shared.fetchBody(mail.id)
            content = store.body(id: mail.id)
            isLoading = false
        }
        if let html = content?.html {
            blocks = await Task.detached(priority: .userInitiated) {
                WatchRichTextView.blocks(from: HTMLRichTextParser.parse(html))
            }.value
        }
    }

    /// Führt eine Aktion aus und gibt sie an das iPhone weiter.
    ///
    /// - Parameters:
    ///   - change: Änderung.
    ///   - mail: Betroffene Mail.
    private func perform(_ change: WatchAction.Change, on mail: WatchMail) {
        try? store.perform(change, on: mail)
        WatchConnector.shared.sendPending()
    }

    /// Ausführliche Spam-Einschätzung (mit Score bzw. `[NoSpam]`).
    ///
    /// - Parameter mail: Mail.
    /// - Returns: Text oder `nil`; ohne Listen nichts.
    private func spamMark(_ mail: WatchMail) -> String? {
        guard let lists = store.lists else { return nil }
        return SpamMark.text(
            sender: mail.sender,
            verdict: mail.verdict?.verdict,
            rules: SpamRules(lists: lists, scoreLimit: store.scoreLimit),
            style: .detail
        )
    }
}
