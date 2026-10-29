//
//  WatchMailListView.swift
//  MailwerkWatch
//
//  Zweck: Mail-Liste einer Sicht (Alle Eingänge, Ungelesen, Mit
//  Kennzeichnung, Spam) mit den Wischaktionen der App: nach rechts
//  gelesen/ungelesen, nach links Kennzeichen setzen/entfernen. Löschen
//  gibt es auf der Watch bewusst nicht.
//
//  Sicht „Ungelesen“: Wie in der App bleiben Mails, die während des
//  Besuchs gelesen werden, bis zum Verlassen der Sicht stehen – die Liste
//  springt nicht unter dem Finger weg.
//
//  Abgrenzung: Zeile → WatchMailRow; Mailansicht → WatchMailDetailView;
//  Aktionen → WatchStore, WatchConnector.
//
//  Abhängigkeiten: SwiftUI, WatchStore, WatchConnector, WatchMailbox
//  (WatchView), WatchTransfer.
//

import SwiftUI

/// Mail-Liste einer Sicht.
struct WatchMailListView: View {
    /// Gezeigte Sicht.
    let view: WatchView

    /// Speicher der App.
    private let store = WatchStore.shared
    /// Sicht „Ungelesen“: bei diesem Besuch gezeigte Mails.
    @State private var kept: Set<String> = []

    /// Liste bzw. Hinweis, wenn sie leer ist.
    var body: some View {
        let mails = store.mails(in: view, keeping: kept)
        Group {
            if mails.isEmpty {
                ContentUnavailableView(
                    "Keine Mails",
                    systemImage: view.systemImage,
                    description: Text(store.hasSnapshot ? "In dieser Ansicht liegt nichts." : "Noch nichts vom iPhone erhalten.")
                )
            } else {
                List(mails) { mail in
                    NavigationLink {
                        WatchMailDetailView(mailID: mail.id)
                    } label: {
                        WatchMailRow(mail: mail)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            perform(.read(mail.isUnread), on: mail)
                        } label: {
                            Label(
                                mail.isUnread ? "Gelesen" : "Ungelesen",
                                systemImage: mail.isUnread ? "envelope.open" : "envelope.badge"
                            )
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            perform(.flagged(!mail.isFlagged), on: mail)
                        } label: {
                            Label(
                                mail.isFlagged ? "Entflaggen" : "Flaggen",
                                systemImage: mail.isFlagged ? "flag.slash" : "flag"
                            )
                        }
                        .tint(.orange)
                    }
                    .onAppear {
                        if view == .unread { kept.insert(mail.id) }
                    }
                }
            }
        }
        .navigationTitle(view.title)
        .refreshable {
            kept = []
            await WatchConnector.shared.refresh()
        }
    }

    /// Führt eine Wischaktion aus und gibt sie an das iPhone weiter.
    ///
    /// - Parameters:
    ///   - change: Änderung.
    ///   - mail: Betroffene Mail.
    private func perform(_ change: WatchAction.Change, on mail: WatchMail) {
        try? store.perform(change, on: mail)
        WatchConnector.shared.sendPending()
    }
}
