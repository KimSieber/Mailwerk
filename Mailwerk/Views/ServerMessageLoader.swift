//
//  ServerMessageLoader.swift
//  Mailwerk
//
//  Zweck: Öffnet einen Suchtreffer vom Server. Der Treffer liegt noch
//  nicht im Cache; beim Öffnen wird die Mail auf dem gewohnten Weg
//  geladen (Struktur, Text/HTML, Anhänge bis 5 MB), im Cache gespeichert
//  und dann in der Mailansicht gezeigt. Ab da ist sie ein ganz normaler
//  lokaler Treffer – auch offline und für die nächste Suche.
//
//  Beim Verlassen der Ansicht meldet sie das (`onReturn`), damit die Liste
//  den Treffer aus dem Abschnitt „Auf dem Server“ nimmt und neu lädt. Erst
//  dann – während die Mail offen ist, bliebe die Liste darunter sonst
//  nicht stehen.
//
//  Abgrenzung: Laden im MailFetchService, Anzeige in MessageDetailView.
//
//  Mac: Der Treffer öffnet sich in der Mailansicht neben der
//  Liste; solange er lädt, steht schon die Kopfleiste der Mailansicht
//  (MacDetailHeaderBar) mit ausgegrauten Knöpfen.
//
//  Abhängigkeiten: MailFetchService, MessageStore, MessageDetailContext
//  (Postfächer, Spamfilter), NetworkMonitor, MessageDetailView,
//  MessageListItem, AppTheme, MacDetailHeaderBar (nur Mac).
//

import SwiftUI

/// Lädt einen Suchtreffer vom Server und zeigt ihn an.
struct ServerMessageLoader: View {
    /// Treffer (Kopfdaten vom Server, Cache-ID wie nach dem Laden).
    let hit: MessageListItem
    /// Postfächer, Spamfilter und Rückmeldungen der Liste.
    let context: MessageDetailContext
    /// Wird beim Verlassen aufgerufen, wenn die Mail geladen wurde.
    let onReturn: () -> Void
    /// Zurück-Knopf der Mac-Kopfleiste (eine Spalte); `nil` = keiner.
    var onBack: (() -> Void)? = nil

    /// Geladene Mail; `nil`, solange sie lädt oder das Laden scheiterte.
    @State private var message: CachedMessage?
    /// Fehlertext des letzten Versuchs; `nil` = kein Fehler.
    @State private var failure: String?
    /// Netzzustand.
    private let network = NetworkMonitor.shared

    /// Mailansicht, Ladeanzeige oder Hinweis mit „Erneut versuchen“.
    var body: some View {
        Group {
            if let message {
                MessageDetailView(
                    message: message,
                    accountStore: context.accountStore,
                    spamFilter: context.spamFilter,
                    scoreLimit: context.scoreLimit,
                    onChange: context.onChange,
                    onSearchPerson: context.onSearchPerson,
                    showsRecipients: context.showsRecipients,
                    onBack: onBack
                )
            } else if let failure {
                ContentUnavailableView {
                    Label("Nachricht nicht geladen", systemImage: "envelope")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Erneut versuchen") {
                        Task { await load() }
                    }
                    .disabled(!network.isOnline)
                }
                .detailPlaceholder { placeholderHeader }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Nachricht wird geladen …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .detailPlaceholder { placeholderHeader }
            }
        }
        // Auch Lade- und Hinweiszustand auf der getönten Fläche.
        .appBackground()
        .task { await load() }
        .onDisappear {
            if message != nil { onReturn() }
        }
    }

    /// Kopfleiste mit ausgegrauten Knöpfen, solange die Mail lädt (nur Mac).
    @ViewBuilder
    private var placeholderHeader: some View {
        #if os(macOS)
        let account = context.accountStore.accounts.first { $0.id == hit.accountID }
        MacDetailHeaderBar(
            placeholderFor: account?.displayName ?? "",
            accountColor: account?.colorHex.map { Color(hex: $0) },
            onBack: onBack
        )
        #endif
    }

    /// Lädt die Mail und speichert sie im Cache.
    ///
    /// Verarbeitung: Liegt sie schon im Cache (z. B. inzwischen abgerufen),
    /// wird sie von dort gezeigt. Sonst ohne Netz ein Hinweis; mit Netz
    /// wird sie geladen. Scheitert das oder ist sie auf dem Server nicht
    /// mehr vorhanden, erscheint ein Hinweis mit „Erneut versuchen“.
    private func load() async {
        guard message == nil else { return }
        if let cached = MessageStore.shared.message(id: hit.id) {
            message = cached
            return
        }
        guard network.isOnline else {
            failure = "Ohne Verbindung lässt sich die Nachricht nicht vom Server laden."
            return
        }
        failure = nil
        do {
            let credentials = try context.accountStore.credentials(for: hit.accountID)
            let loaded = try await MailFetchService.loadMessage(
                credentials, folder: hit.folder, uid: hit.uid
            )
            if loaded, let stored = MessageStore.shared.message(id: hit.id) {
                message = stored
            } else {
                failure = "Die Nachricht ist auf dem Server nicht mehr vorhanden oder ließ sich nicht laden."
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}
