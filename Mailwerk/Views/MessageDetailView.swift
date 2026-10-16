//
//  MessageDetailView.swift
//  Mailwerk
//
//  Zweck: Ansicht einer einzelnen Mail – Kopfdaten, Inhalt (HTML oder
//  Text), Anhänge mit Vorschau, Teilen und Nachladen sowie das
//  Aktionsmenü (gemeinsamer Baustein `MessageMenuItems`, ergänzt um
//  Teilen, Drucken und Anlagen lokal löschen) und die Ausführung seiner
//  Aktionen.
//
//  Eine ungelesene Mail wird beim Öffnen als gelesen markiert.
//
//  Kopf und Anhänge liegen auf der getönten Fläche der App, der Inhalt
//  der Mail ungetönt auf einer Karte über die volle Breite (AppTheme).
//
//  Aktionen an der Mail laufen über `MessageActions` (Server und Cache
//  gemeinsam). Meldungen und Rückfragen haben je einen Kanal
//  (`activeAlert`, `activeConfirmation`, siehe Dialogs.swift).
//
//  Abgrenzung: Kopfbereich und Hinweis auf externe Inhalte →
//  MessageDetailHeader; Anhangliste → MessageAttachmentList; Menüeinträge
//  → MessageMenu; Rückfragen und Meldungen zu den Aktionen →
//  MessageActionDialogs; Laden der Mail aus dem Cache → MessageDetailLoader;
//  HTML-Darstellung → HTMLMailView; Verfassen → ComposeView; Ordnerwahl →
//  FolderMoveSheet; Anhang-Zeile → AttachmentRow; Druck → MailPrinter;
//  HTML für Druck und Teilen → MailPrintFormatter; Regeln für externe
//  Inhalte → RemoteContentPolicy; Originalquelle → RawSourceView.
//
//  Externe Inhalte (Bilder, Stylesheets von fremden Servern) sind
//  gesperrt. Ausnahme: Ist der Absender vertrauenswürdig (Whitelist und
//  Score unter der Obergrenze, siehe SpamClassifier.trustsSender), werden
//  sie sofort geladen. Sonst erscheint über dem Text ein schmaler Hinweis
//  mit dem Knopf „Laden“. Die Freigabe per Knopf gilt nur für diese
//  Anzeige der Mail; beim nächsten Öffnen ist wieder alles gesperrt.
//  Entschieden wird, bevor der HTML-Inhalt zum ersten Mal erscheint – so
//  wird nichts doppelt geladen. Drucken und Teilen folgen dem Zustand der
//  Anzeige.
//
//  Teilen läuft über `ShareLink` im Menü – auf iPhone/iPad das
//  Teilen-Blatt, auf dem Mac das Teilen-Untermenü des Systems. Die Dateien
//  (Mail als HTML, geladene Anhänge) liegen dafür schon beim Öffnen bereit.
//
//  Eingebettete Bilder (`cid:`) erscheinen im Text: Das HTML wird mit den
//  Bildern aus dem Cache aufgelöst (InlineImages), auch wenn externe
//  Inhalte gesperrt sind – sie gehören zur Mail. Fehlen Bilder, lädt die
//  Ansicht sie beim Öffnen im Hintergrund nach (InlineImageLoader); ohne
//  Netz bleiben sie still leer. Die Anhangliste zeigt nur echte Anhänge und
//  nicht angesprochene Inline-Bilder; „Anlagen lokal löschen“ lässt die
//  Bilder im Text stehen. Drucken und Teilen folgen der Anzeige.
//
//  Ganz unten im Menü, abgesetzt, steht „Originalquelle“ (RawSourceView):
//  die Mail als reiner Text mit allen Kopfzeilen, für Analysen. Mit
//  Tastatur auch per ⌥⌘U, wie in Apple Mail.
//
//  Abhängigkeiten: SwiftUI, QuickLook, MessageActions, MessageMenu,
//  MessageActionDialogs, MessageDetailHeader, MessageAttachmentList,
//  SpamFilterService,
//  AttachmentManager, MessageStore, MailPrintFormatter, RemoteContentPolicy,
//  RawSourceView, InlineImages, InlineImageLoader, NetworkMonitor, Dialogs,
//  AppTheme, Log.
//

import SwiftUI
import QuickLook
import WebKit
import os

/// Ansicht einer einzelnen Mail.
struct MessageDetailView: View {
    /// Angezeigte Mail.
    let message: CachedMessage
    /// Quelle für Postfächer und Zugangsdaten.
    let accountStore: AccountStore
    /// Spamfilter für Blockieren und Vertrauen sowie für die Prüfung
    /// vertrauenswürdiger Absender.
    let spamFilter: SpamFilterService
    /// Score-Obergrenze für vertrauenswürdige Absender.
    let scoreLimit: Double
    /// Wird nach jeder Änderung aufgerufen (Liste neu laden).
    let onChange: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Gemessene Höhe des HTML-Inhalts.
    @State private var webViewHeight: CGFloat = 100
    /// `true`, wenn die Mail externe Inhalte enthält (Hinweis anzeigen).
    @State private var hasRemoteContent = false
    /// `true`, wenn externe Inhalte für diese Anzeige freigegeben sind.
    @State private var allowsRemoteContent = false
    /// `true`, sobald über externe Inhalte entschieden ist; vorher wird
    /// der HTML-Inhalt nicht angezeigt.
    @State private var isRemoteContentDecided = false
    /// Alle Anhänge der Mail aus dem Cache, einschließlich eingebetteter
    /// Bilder.
    @State private var attachments: [CachedAttachment] = []
    /// HTML der Mail mit eingesetzten eingebetteten Bildern; `nil`, solange
    /// die Anhänge nicht gelesen sind. Wird nur bei geänderten Anhängen neu
    /// gebildet, weil das Einsetzen großer Bilder Zeit kostet.
    @State private var resolvedHTML: String?
    /// Datei für die QuickLook-Vorschau; `nil` = keine Vorschau offen.
    @State private var previewURL: URL?
    /// Temporäre Dateien der geladenen Anhänge zum Teilen, je Anhang-ID.
    @State private var shareURLs: [String: URL] = [:]
    /// Die Mail als temporäre HTML-Datei zum Teilen; `nil`, solange sie
    /// nicht geschrieben ist.
    @State private var mailFileURL: URL?
    /// Anhänge, die gerade nachgeladen werden.
    @State private var downloadingIDs: Set<String> = []
    /// Gelesen-Zustand (lokal nachgeführt).
    @State private var isUnread: Bool
    /// Kennzeichnung (lokal nachgeführt).
    @State private var isFlagged: Bool
    /// `true`, solange eine Aktion an der Mail läuft.
    @State private var isProcessingAction = false
    /// Ordnerwahl zum Verschieben sichtbar.
    @State private var showFolderPicker = false
    /// Blatt „Originalquelle“ sichtbar.
    @State private var showRawSource = false
    /// Zu verfassende Antwort bzw. Weiterleitung.
    @State private var composeRequest: ComposeRequest?
    /// Getippter mailto:-Link aus der Mail → neue Mail in Mailwerk.
    @State private var mailtoRequest: MailtoLink?
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?
    /// Einziger Rückfragekanal der Ansicht.
    @State private var activeConfirmation: ConfirmationRequest?

    /// Kapselt die Art der zu verfassenden Nachricht für das Sheet.
    private struct ComposeRequest: Identifiable {
        /// Kennung für SwiftUI.
        let id = UUID()
        /// Antworten, Allen antworten oder Weiterleiten.
        let kind: ComposeKind
    }

    /// Übernimmt die Mail und die Abhängigkeiten.
    ///
    /// - Parameters:
    ///   - message: Angezeigte Mail.
    ///   - accountStore: Quelle für Postfächer und Zugangsdaten.
    ///   - spamFilter: Spamfilter für Blockieren und Vertrauen.
    ///   - scoreLimit: Score-Obergrenze für vertrauenswürdige Absender.
    ///   - onChange: Wird nach jeder Änderung aufgerufen.
    init(
        message: CachedMessage,
        accountStore: AccountStore,
        spamFilter: SpamFilterService,
        scoreLimit: Double,
        onChange: (() -> Void)? = nil
    ) {
        self.message = message
        self.accountStore = accountStore
        self.spamFilter = spamFilter
        self.scoreLimit = scoreLimit
        self.onChange = onChange
        _isUnread = State(initialValue: message.isUnread)
        _isFlagged = State(initialValue: message.isFlagged)
    }

    /// Ziel der Aktionen an dieser Mail.
    private var target: MessageActions.Target { MessageActions.Target(message) }

    /// Aufbau: Kopfdaten, Inhalt, Anhänge; Symbolleiste mit Antworten und
    /// Menü; Sheets, Vorschau, Meldung und Rückfrage.
    var body: some View {
        content
            .navigationTitle(message.accountDisplayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .sheet(item: $mailtoRequest) { link in
                // Neue Mail aus einem Link: Absender ist das Postfach dieser Mail.
                ComposeView(
                    accountStore: accountStore,
                    kind: .new,
                    mailto: link,
                    senderAccountID: message.accountID,
                    onSent: { onChange?() }
                )
            }
            .sheet(item: $composeRequest) { request in
                ComposeView(
                    accountStore: accountStore,
                    kind: request.kind,
                    original: message,
                    onSent: { onChange?() }
                )
            }
            .sheet(isPresented: $showFolderPicker) {
                if let account = accountStore.accounts.first(where: { $0.id == message.accountID }) {
                    FolderMoveSheet(
                        account: account,
                        currentFolder: message.folder,
                        accountStore: accountStore
                    ) { path in
                        Task { await moveMessage(to: path) }
                    }
                }
            }
            .sheet(isPresented: $showRawSource) {
                RawSourceView(message: message, accountStore: accountStore)
            }
            .background { rawSourceShortcut }
            .quickLookPreview($previewURL)
            .confirmationRequest($activeConfirmation)
            .task { await prepareOnOpen() }
    }

    /// Unsichtbarer Knopf für ⌥⌘U (Originalquelle).
    ///
    /// Verarbeitung: Die Einträge eines Menüs in der Symbolleiste entstehen
    /// erst beim Öffnen; ein Tastenkürzel daran wirkte nur bei offenem
    /// Menü. Deshalb trägt ein eigener, unsichtbarer Knopf das Kürzel.
    private var rawSourceShortcut: some View {
        Button("Originalquelle") {
            showRawSource = true
        }
        .keyboardShortcut("u", modifiers: [.command, .option])
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Inhalt

    /// Kopfdaten, Inhalt und Anhänge in einem Scrollbereich. Trägt den
    /// Meldungskanal – getrennt vom Rückfragekanal am äußeren Element.
    ///
    /// Verarbeitung: Kopf und Anhänge liegen auf der getönten Fläche, der
    /// Inhalt der Mail auf einer Karte über die volle Breite – so bleibt
    /// die Mail ungetönt, und ihre Breite ist dieselbe wie ohne Karte.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MessageDetailHeader(message: message, isFlagged: isFlagged)
                    .padding()
                messageBody
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card)
                if !visibleAttachments.isEmpty {
                    MessageAttachmentList(
                        attachments: visibleAttachments,
                        downloadingIDs: downloadingIDs,
                        shareURLs: shareURLs,
                        onTap: { handleTap($0) }
                    )
                    .padding()
                }
            }
        }
        .appBackground()
        .alertItem($activeAlert)
    }

    /// Inhalt der Mail: HTML bevorzugt, sonst Text. Über einer HTML-Mail
    /// mit gesperrten externen Inhalten steht der Hinweis zum Laden. Bis
    /// über externe Inhalte entschieden ist, bleibt nur der Platz frei.
    @ViewBuilder
    private var messageBody: some View {
        if message.htmlBody != nil && !isRemoteContentDecided {
            Color.clear.frame(height: 100)
        } else if let html = message.htmlBody {
            if hasRemoteContent && !allowsRemoteContent {
                RemoteContentNotice(onLoad: allowRemoteContent)
            }
            HTMLMailView(
                html: resolvedHTML ?? html,
                contentHeight: $webViewHeight,
                allowsRemoteContent: allowsRemoteContent,
                onMailto: { mailtoRequest = $0 }
            )
            .frame(height: max(100, webViewHeight))
        } else if let text = message.textBody {
            Text(text)
        } else {
            Text("Kein Inhalt verfügbar").foregroundStyle(.secondary)
        }
    }

    // MARK: - Symbolleiste und Menü

    /// Antworten (Tipp antwortet direkt, langes Drücken zeigt alle
    /// Varianten) und das Aktionsmenü.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ReplyMenuButtons(onAction: handleMenuAction)
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            } primaryAction: {
                composeRequest = ComposeRequest(kind: .reply)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if isProcessingAction {
                ProgressView()
            } else {
                messageMenu
            }
        }
    }

    /// Aktionsmenü der Mail: der gemeinsame Baustein, ergänzt um Teilen,
    /// Drucken und Anlagen lokal löschen; ganz unten, als eigener
    /// Abschnitt, die selten gebrauchte Originalquelle.
    private var messageMenu: some View {
        Menu {
            MessageMenuItems(context: menuContext, onAction: handleMenuAction) {
                ShareLink(items: shareItems) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .disabled(shareItems.isEmpty)

                Button {
                    printMessage()
                } label: {
                    Label("Drucken", systemImage: "printer")
                }

                if hasLocalAttachmentData {
                    Button(role: .destructive) {
                        confirmDeleteLocalAttachments()
                    } label: {
                        Label("Anlagen lokal löschen", systemImage: "trash")
                    }
                }
            }
            Section {
                Button {
                    showRawSource = true
                } label: {
                    Label(MessageMenuLabels.source.title, systemImage: MessageMenuLabels.source.systemImage)
                }
                .accessibilityLabel(MessageMenuLabels.source.accessibility)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(isProcessingAction)
    }

    /// Zustand der Mail für das Menü.
    private var menuContext: MessageMenuContext {
        MessageMenuContext(
            isUnread: isUnread,
            isFlagged: isFlagged,
            sender: FilterAddress.sender(fromHeader: message.from)
        )
    }

    /// Führt eine Aktion aus dem Menü aus.
    ///
    /// Verarbeitung: Löschen und Spam-Aktionen fragen vorher nach;
    /// Verschieben öffnet die Ordnerwahl.
    ///
    /// - Parameter action: Gewählte Aktion.
    private func handleMenuAction(_ action: MessageMenuAction) {
        switch action {
        case .select:
            break  // gibt es nur im Kontextmenü der Liste
        case .reply(let kind):
            composeRequest = ComposeRequest(kind: kind)
        case .toggleFlag:
            Task { await toggleFlag() }
        case .toggleRead:
            Task { await toggleRead() }
        case .move:
            showFolderPicker = true
        case .spam(let request):
            activeConfirmation = MessageActionDialogs.spamConfirmation(request) {
                Task { await performSpamAction(request) }
            }
        case .delete:
            activeConfirmation = MessageActionDialogs.deleteConfirmation(count: 1) {
                Task { await deleteMessage() }
            }
        }
    }

    /// Anhänge für Liste, Teilen, Drucken und lokales Löschen: echte
    /// Anhänge und nicht angesprochene Inline-Bilder.
    private var visibleAttachments: [CachedAttachment] {
        InlineImages.visibleAttachments(attachments, html: message.htmlBody)
    }

    /// Dateien zum Teilen: die Mail als HTML, danach die geladenen Anhänge
    /// in ihrer Reihenfolge.
    private var shareItems: [URL] {
        [mailFileURL].compactMap { $0 } + visibleAttachments.compactMap { shareURLs[$0.id] }
    }

    /// `true`, wenn mindestens ein sichtbarer Anhang lokale Daten hat, die
    /// gelöscht werden könnten.
    private var hasLocalAttachmentData: Bool {
        visibleAttachments.contains { $0.data != nil }
    }

    // MARK: - Beim Öffnen

    /// Liest die Anhänge, setzt die eingebetteten Bilder ein, entscheidet
    /// über externe Inhalte, bereitet das Teilen vor, markiert eine
    /// ungelesene Mail als gelesen und lädt fehlende Bilder nach.
    ///
    /// Verarbeitung: Anhänge und Bilder kommen vor der Entscheidung über
    /// externe Inhalte, damit der HTML-Inhalt gleich mit Bildern erscheint
    /// und nicht zweimal geladen wird. Die Entscheidung über externe
    /// Inhalte fällt nur einmal je Anzeige – läuft die Aufgabe erneut
    /// (z. B. nach einer Vorschau), bleibt eine Freigabe per Knopf
    /// erhalten. Scheitert das Markieren, bleibt die Mail ungelesen; eine
    /// Meldung erscheint nicht, weil der Nutzer nichts ausgelöst hat.
    @MainActor
    private func prepareOnOpen() async {
        updateAttachments(MessageStore.shared.attachments(forMessage: message.id))
        if !isRemoteContentDecided {
            await decideRemoteContent()
        }
        writeMailFile()

        if isUnread {
            do {
                try await MessageActions.setRead(true, for: target, accountStore: accountStore)
                isUnread = false
                onChange?()
            } catch {
                Log.actions.error("⚠️ Gelesen-Markierung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }

        await loadMissingInlineImages()
    }

    /// Übernimmt die Anhänge und bildet das HTML mit eingesetzten Bildern
    /// neu; bereitet die Dateien zum Teilen vor.
    ///
    /// - Parameter all: Alle Anhänge der Mail aus dem Cache.
    private func updateAttachments(_ all: [CachedAttachment]) {
        attachments = all
        resolvedHTML = message.htmlBody.map { InlineImages.resolve($0, images: all) }
        prepareShareURLs()
    }

    /// Lädt angesprochene, noch fehlende eingebettete Bilder nach.
    ///
    /// Verarbeitung: Nur wenn Bilder fehlen und eine Verbindung besteht.
    /// Ein Fehler wird nur protokolliert – die Mail bleibt lesbar, die
    /// Bilder erscheinen leer. Danach werden Anzeige und Datei zum Teilen
    /// erneuert.
    @MainActor
    private func loadMissingInlineImages() async {
        guard InlineImages.hasMissingImages(attachments, html: message.htmlBody),
              NetworkMonitor.shared.isOnline else { return }
        do {
            let all = try await InlineImageLoader.loadMissing(
                for: message, existing: attachments, accountStore: accountStore
            )
            updateAttachments(all)
            writeMailFile()
        } catch {
            Log.view.error("⚠️ Eingebettete Bilder nicht nachgeladen: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Aktionen an der Mail

    /// Schaltet gelesen/ungelesen um.
    @MainActor
    private func toggleRead() async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        let markAsRead = isUnread
        do {
            try await MessageActions.setRead(markAsRead, for: target, accountStore: accountStore)
            isUnread = !markAsRead
            onChange?()
        } catch {
            activeAlert = .failure("Status ändern fehlgeschlagen", error)
        }
    }

    /// Schaltet die Kennzeichnung um.
    @MainActor
    private func toggleFlag() async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        let newFlagged = !isFlagged
        do {
            try await MessageActions.setFlagged(newFlagged, for: target, accountStore: accountStore)
            isFlagged = newFlagged
            onChange?()
        } catch {
            activeAlert = .failure("Kennzeichnen fehlgeschlagen", error)
        }
    }

    /// Löscht die Mail und kehrt zur Liste zurück.
    @MainActor
    private func deleteMessage() async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        do {
            try await MessageActions.delete(target, accountStore: accountStore)
            onChange?()
            dismiss()
        } catch {
            activeAlert = .failure("Löschen fehlgeschlagen", error)
        }
    }

    /// Verschiebt die Mail in den gewählten Ordner und kehrt zur Liste zurück.
    ///
    /// - Parameter path: Server-Pfad des Zielordners.
    @MainActor
    private func moveMessage(to path: String) async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        do {
            try await MessageActions.move(target, to: path, accountStore: accountStore)
            onChange?()
            dismiss()
        } catch {
            activeAlert = .failure("Verschieben fehlgeschlagen", error)
        }
    }

    // MARK: - Spam-Aktionen

    /// Trägt Adresse bzw. Domain in die Liste ein und verschiebt die Mail
    /// bei Bedarf.
    ///
    /// Verarbeitung: Wurde die Mail verschoben, zeigt diese Ansicht eine
    /// Mail, die hier nicht mehr liegt – also zurück zur Liste. Sonst
    /// bestätigt eine Meldung den Eintrag. Steht der Wert schon auf der
    /// anderen Liste, wird der Eintrag abgelehnt.
    ///
    /// - Parameter request: Spam-Aktion aus dem Menü.
    @MainActor
    private func performSpamAction(_ request: SpamMenuRequest) async {
        isProcessingAction = true
        defer { isProcessingAction = false }
        do {
            let moved = try await request.perform(on: message, using: spamFilter)
            onChange?()
            if moved {
                dismiss()
            } else {
                activeAlert = MessageActionDialogs.spamResultAlert(request)
            }
        } catch {
            activeAlert = MessageActionDialogs.spamFailureAlert(request, error)
        }
    }

    // MARK: - Externe Inhalte

    /// Prüft, ob die Mail externe Inhalte enthält, und gibt sie bei einem
    /// vertrauenswürdigen Absender sofort frei.
    ///
    /// Verarbeitung: Nur Mails mit externen Verweisen werden gegen die
    /// Listen geprüft. Danach erscheint der HTML-Inhalt.
    @MainActor
    private func decideRemoteContent() async {
        if let html = message.htmlBody,
           RemoteContentPolicy.containsRemoteReferences(html) {
            hasRemoteContent = true
            if await spamFilter.trustsRemoteContent(of: message, scoreLimit: scoreLimit) {
                allowsRemoteContent = true
                Log.view.info("🖼 Externe Inhalte sofort geladen (vertrauenswürdiger Absender)")
            }
        }
        isRemoteContentDecided = true
    }

    /// Gibt externe Inhalte für diese Anzeige frei.
    ///
    /// Verarbeitung: Die Mail wird mit gelockerter Regel neu geladen; die
    /// Datei zum Teilen wird neu geschrieben, damit sie der Anzeige folgt.
    private func allowRemoteContent() {
        allowsRemoteContent = true
        writeMailFile()
        Log.view.info("🖼 Externe Inhalte für diese Anzeige freigegeben")
    }

    // MARK: - Teilen & Drucken

    /// Schreibt die Mail als HTML-Datei zum Teilen, passend zur Freigabe
    /// externer Inhalte in der Anzeige.
    ///
    /// Verarbeitung: Lässt sich die Datei nicht schreiben, fehlt sie beim
    /// Teilen; das wird protokolliert.
    private func writeMailFile() {
        do {
            mailFileURL = try MailPrintFormatter.writeTemporaryFile(
                for: message,
                attachments: visibleAttachments,
                inlineImages: attachments,
                allowsRemoteContent: allowsRemoteContent
            )
        } catch {
            Log.view.error("⚠️ Mail als Datei zum Teilen nicht geschrieben: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Druckt die Mail samt Kopfdaten und Anhangliste, mit externen
    /// Inhalten nur, wenn sie in der Anzeige freigegeben sind.
    private func printMessage() {
        let html = MailPrintFormatter.html(
            for: message,
            attachments: visibleAttachments,
            inlineImages: attachments,
            allowsRemoteContent: allowsRemoteContent
        )
        MailPrinter().print(html: html)
    }

    // MARK: - Anlagen lokal löschen

    /// Fragt vor dem lokalen Löschen der Anhang-Daten nach.
    private func confirmDeleteLocalAttachments() {
        activeConfirmation = ConfirmationRequest(
            title: "Anlagen lokal löschen?",
            message: "Die Anhang-Daten werden lokal gelöscht, um Speicher freizugeben. Die Metadaten bleiben erhalten und die Anhänge können erneut vom Server geladen werden.",
            confirmLabel: "Löschen"
        ) {
            deleteLocalAttachments()
        }
    }

    /// Löscht die Daten der sichtbaren Anhänge dieser Mail aus dem Cache;
    /// die Einträge bleiben, die Daten lassen sich neu laden. Eingebettete
    /// Bilder im Text bleiben – sie sind Inhalt der Mail.
    private func deleteLocalAttachments() {
        for attachment in visibleAttachments {
            MessageStore.shared.deleteAttachmentData(id: attachment.id)
        }
        shareURLs.removeAll()
        updateAttachments(MessageStore.shared.attachments(forMessage: message.id))
        writeMailFile()
    }

    // MARK: - Anhänge öffnen

    /// Öffnet die Vorschau eines Anhangs; fehlen die Daten, werden sie
    /// zuerst nachgeladen.
    ///
    /// - Parameter attachment: Angetippter Anhang.
    private func handleTap(_ attachment: CachedAttachment) {
        if attachment.data != nil {
            openPreview(attachment)
        } else {
            Task { await downloadAndPreview(attachment) }
        }
    }

    /// Schreibt den Anhang in eine temporäre Datei und öffnet QuickLook.
    ///
    /// - Parameter attachment: Anhang mit Daten.
    private func openPreview(_ attachment: CachedAttachment) {
        do {
            previewURL = try AttachmentManager.writeTempFile(for: attachment)
        } catch {
            activeAlert = .failure("Vorschau nicht möglich", error)
        }
    }

    /// Lädt einen Anhang vom Server nach und öffnet danach die Vorschau.
    ///
    /// - Parameter attachment: Anhang ohne Daten.
    @MainActor
    private func downloadAndPreview(_ attachment: CachedAttachment) async {
        downloadingIDs.insert(attachment.id)
        defer { downloadingIDs.remove(attachment.id) }
        do {
            let updated = try await AttachmentManager.downloadAttachment(
                attachment,
                message: message,
                accountStore: accountStore
            )
            if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                attachments[index] = updated
            }
            prepareShareURLs()
            openPreview(updated)
        } catch {
            activeAlert = .failure("Download fehlgeschlagen", error)
        }
    }

    /// Schreibt alle geladenen sichtbaren Anhänge als temporäre Dateien,
    /// damit das Teilen ohne Verzögerung bereitsteht.
    private func prepareShareURLs() {
        for attachment in visibleAttachments where attachment.data != nil && shareURLs[attachment.id] == nil {
            if let url = try? AttachmentManager.writeTempFile(for: attachment) {
                shareURLs[attachment.id] = url
            }
        }
    }
}
