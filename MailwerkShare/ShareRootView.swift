//
//  ShareRootView.swift
//  MailwerkShare
//
//  Zweck: Wurzelansicht der Teilen-Erweiterung. Liest die Abschrift der
//  App (Postfächer, Standard-Postfach, Signaturen), übernimmt die geteilten
//  Inhalte und zeigt dann das gewohnte Verfassen-Fenster von Mailwerk –
//  mit Standard-Postfach als Absender, dessen Signatur und den Inhalten als
//  Anhänge bzw. Text.
//
//  Ohne Abschrift (Mailwerk noch nie geöffnet) oder ohne Postfach erscheint
//  ein Hinweis mit „Schließen“. Inhalte, die sich nicht lesen ließen,
//  meldet ein Hinweis; der Rest wird trotzdem übernommen.
//
//  Geschlossen wird über `onDone`: nach dem Versand bzw. Sichern eines
//  Entwurfs mit `true`, beim Verwerfen oder Abbrechen mit `false`.
//
//  Abgrenzung: Einlesen der Inhalte → SharedItemLoader; Verfassen und
//  Versand → ComposeView/ComposeViewModel; Einbettung in das System →
//  ShareViewController (iPhone/iPad: MailwerkShare, Mac: MailwerkShareMac).
//
//  Abhängigkeiten: SwiftUI, ShareContext, AccountStore, SignatureStore,
//  InMemorySignatureStorage, SharedItemLoader, ComposeView, Dialogs,
//  MacSheetSize.
//

import SwiftUI

/// Wurzelansicht der Teilen-Erweiterung.
struct ShareRootView: View {
    /// Geteilte Elemente aus dem System.
    let inputs: [SharedInput]
    /// Beendet die Erweiterung; `true` = gesendet bzw. als Entwurf gesichert.
    let onDone: (Bool) -> Void

    /// Stand der Vorbereitung.
    @State private var phase: Phase = .loading
    /// `true`, sobald gesendet oder als Entwurf gesichert wurde.
    @State private var completed = false
    /// Hinweis zu nicht übernommenen Inhalten; `nil` = keiner.
    @State private var loadNotice: AlertItem?

    /// Stand der Vorbereitung.
    private enum Phase {
        /// Inhalte werden übernommen.
        case loading
        /// Bereit zum Verfassen.
        case ready(Prepared)
        /// Teilen nicht möglich, mit Hinweistext.
        case unavailable(String)
    }

    /// Alles, was das Verfassen-Fenster braucht.
    private struct Prepared {
        /// Nur lesender Store mit den Postfächern der Abschrift.
        let accountStore: AccountStore
        /// Signaturen der Abschrift.
        let signatures: SignatureStore
        /// Geteilte Inhalte.
        let content: SharedContent
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                NavigationStack {
                    ProgressView("Inhalte werden übernommen …")
                        .toolbar { closeButton }
                }
            case .ready(let prepared):
                ComposeView(
                    accountStore: prepared.accountStore,
                    kind: .new,
                    shared: prepared.content,
                    onSent: { completed = true },
                    onClose: { onDone(completed) }
                )
                .environment(prepared.signatures)
            case .unavailable(let message):
                NavigationStack {
                    ContentUnavailableView(
                        "Teilen nicht möglich",
                        systemImage: "tray",
                        description: Text(message)
                    )
                    .toolbar { closeButton }
                }
            }
        }
        // Auf dem Mac richtet sich das Fenster der Erweiterung nach dem
        // Inhalt; Laden und Hinweis bekommen dieselbe Größe wie das
        // Verfassen-Fenster.
        .macSheetFrame(.composer)
        .task { await prepare() }
        .alertItem($loadNotice)
    }

    /// Knopf „Schließen“ für Laden und Hinweis.
    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                onDone(false)
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Schließen")
        }
    }

    /// Liest die Abschrift und die geteilten Inhalte.
    ///
    /// Verarbeitung: Ohne Abschrift oder ohne Postfach erscheint ein
    /// Hinweis. Sonst entstehen ein nur lesender Postfach-Store und ein
    /// Signatur-Store im Speicher (ohne iCloud), und das Verfassen-Fenster
    /// erscheint mit den geteilten Inhalten.
    private func prepare() async {
        guard case .loading = phase else { return }
        let context: ShareContext
        let read = ShareContextFile.defaultURL.map { ShareContextFile.read(from: $0) } ?? .missing
        switch read {
        case .loaded(let loaded):
            context = loaded
        case .missing, .unreadable:
            phase = .unavailable("Bitte öffne Mailwerk einmal, damit deine Postfächer hier zur Verfügung stehen.")
            return
        }
        guard !context.accounts.isEmpty else {
            phase = .unavailable("Bitte richte zuerst in Mailwerk ein Postfach ein.")
            return
        }

        let result = await SharedItemLoader.load(inputs)
        phase = .ready(Prepared(
            accountStore: AccountStore(shareContext: context),
            signatures: SignatureStore(
                storage: InMemorySignatureStorage(items: context.signatures),
                observesCloud: false
            ),
            content: result.content
        ))
        if result.failedCount > 0 {
            loadNotice = AlertItem(
                title: "Nicht alles übernommen",
                message: result.failedCount == 1
                    ? "Ein geteilter Inhalt konnte nicht übernommen werden."
                    : "\(result.failedCount) geteilte Inhalte konnten nicht übernommen werden."
            )
        }
    }
}
