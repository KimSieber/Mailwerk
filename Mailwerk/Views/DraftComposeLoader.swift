//
//  DraftComposeLoader.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 14.10.2026
//  Geändert: 31.10.2026
//
//  Zweck: Öffnet einen gesicherten Entwurf im Verfassen-Fenster. Lädt den
//  Entwurf samt Anhängen aus dem Cache, holt fehlende eingebettete Bilder
//  (eigener Text, Signatur, Zitat) und fehlende Anhänge vom Server und
//  zeigt dann ComposeView – so stehen die Anhänge in der Liste und lassen
//  sich entfernen. Ohne Verbindung öffnet der Entwurf mit dem, was
//  vorliegt; fehlende Bilder meldet ComposeView, fehlende Anhänge werden
//  beim Senden bzw. Sichern nachgeladen. Ist der Entwurf nicht
//  mehr im Cache (anderswo gelöscht), erscheint ein Hinweis.
//
//  Abgrenzung: Wiederherstellen der Inhalte → ComposeViewModel; Nachladen
//  der Bilder → InlineImageLoader, der Anhänge → AttachmentManager;
//  Aufruf aus der Liste → InboxView.
//
//  Abhängigkeiten: SwiftUI, MessageStore, InlineImages, InlineImageLoader,
//  AttachmentManager, ComposeView, PlatformSheetSize, SheetHeaderBar, Log.
//

import SwiftUI
import os

/// Lädt einen Entwurf und öffnet ihn zum Weiterbearbeiten.
struct DraftComposeLoader: View {
    /// Cache-ID des Entwurfs.
    let messageID: String
    /// Quelle für Postfächer und Passwörter.
    let accountStore: AccountStore
    /// Wird nach Versand oder Sichern aufgerufen (Liste aktualisieren).
    let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Geladener Entwurf; `nil`, solange er lädt oder fehlt.
    @State private var loaded: Loaded?
    /// Der Entwurf liegt nicht mehr im Cache.
    @State private var isMissing = false

    /// Entwurf mit seinen Anhängen aus dem Cache.
    private struct Loaded {
        /// Entwurf.
        let draft: CachedMessage
        /// Anhänge und eingebettete Bilder des Entwurfs.
        let attachments: [CachedAttachment]
    }

    /// Verfassen-Fenster, Ladeanzeige oder Hinweis.
    var body: some View {
        if let loaded {
            ComposeView(
                accountStore: accountStore,
                draft: loaded.draft,
                attachments: loaded.attachments,
                onSent: onSent
            )
        } else {
            NavigationStack {
                Group {
                    if isMissing {
                        ContentUnavailableView(
                            "Entwurf nicht mehr vorhanden",
                            systemImage: "doc",
                            description: Text("Er wurde inzwischen gelöscht oder verschoben.")
                        )
                    } else {
                        ProgressView("Entwurf wird geöffnet …")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Mac: dieselbe Kopfleiste wie das Verfassen-Fenster.
                .macSheetHeader("Entwurf") {
                    HeaderCircleButton.cancel { dismiss() }
                } trailing: {
                    HeaderCircleButton.send(isEnabled: false, isBusy: false) {}
                }
                #if !os(macOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() }
                    }
                }
                #endif
            }
            .macSheetFrame(.composer)
            .task { await load() }
        }
    }

    /// Lädt den Entwurf einmalig.
    ///
    /// Verarbeitung: Entwurf und Anhänge kommen aus dem Cache. Spricht das
    /// HTML Bilder an, deren Daten fehlen (beim Abruf werden eingebettete
    /// Bilder nicht mitgeladen), werden sie in einem Durchgang nachgeladen.
    /// Danach wird jeder Anhang ohne Daten einzeln geladen. Scheitert etwas,
    /// öffnet der Entwurf trotzdem.
    @MainActor
    private func load() async {
        guard loaded == nil, !isMissing else { return }
        guard let draft = MessageStore.shared.message(id: messageID) else {
            isMissing = true
            return
        }
        var attachments = MessageStore.shared.attachments(forMessage: draft.id)
        if InlineImages.hasMissingImages(attachments, html: draft.htmlBody) {
            do {
                attachments = try await InlineImageLoader.loadMissing(
                    for: draft, existing: attachments, accountStore: accountStore
                )
            } catch {
                Log.send.error("⚠️ Bilder des Entwurfs nicht geladen: \(error.localizedDescription, privacy: .public)")
            }
        }
        let missing = InlineImages.visibleAttachments(attachments, html: draft.htmlBody)
            .filter { $0.data == nil }
        for attachment in missing {
            do {
                let loadedAttachment = try await AttachmentManager.downloadAttachment(
                    attachment, message: draft, accountStore: accountStore
                )
                if let index = attachments.firstIndex(where: { $0.id == loadedAttachment.id }) {
                    attachments[index] = loadedAttachment
                }
            } catch {
                Log.send.error("⚠️ Anhang des Entwurfs nicht geladen: \(error.localizedDescription, privacy: .public)")
            }
        }
        loaded = Loaded(draft: draft, attachments: attachments)
    }
}
