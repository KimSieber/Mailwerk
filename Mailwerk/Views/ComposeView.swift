//
//  ComposeView.swift
//  Mailwerk
//
//  Zweck: Verfassen-Fenster für neue Mails, Antworten und Weiterleitungen.
//  Aufbau von oben nach unten: Absender, An, Cc (immer sichtbar), Bcc auf
//  Knopfdruck, Betreff, Anhänge, Editor, gegebenenfalls der Block der
//  HTML-Signatur und darunter der zitierte Originaltext (schreibgeschützt,
//  aufklappbar).
//
//  Signatur: Beim Erscheinen setzt das ViewModel die Signatur des
//  Absende-Postfachs ein, beim Wechsel des Postfachs tauscht es sie aus.
//  Eine einfache Signatur steht im Editor, eine HTML-Signatur als eigener,
//  bearbeitbarer Block darunter (SignatureBlockView).
//
//  Alles oberhalb der unteren Leiste scrollt gemeinsam, wie in Apple Mail:
//  Der Editor wächst mit seinem Text, das Zitat erscheint in voller Höhe.
//  So ist auch ein langes Zitat bis zum Ende lesbar. Die untere Leiste
//  (Anhänge, Formatierung) bleibt fest stehen. Ein Tipp in die freie
//  Fläche unterhalb des Inhalts setzt die Schreibmarke ans Textende.
//  Auf dem iPhone blendet Herunterwischen im Inhalt die Tastatur aus.
//
//  Erscheinungsbild: Kopfbereich und untere Leiste liegen auf der getönten
//  Fläche der App, die Schreibfläche (Editor, Signatur, Zitat) ungetönt
//  auf der Kartenfarbe – so sieht die Mail aus wie beim Empfänger
//  (AppTheme).
//
//  Anhänge: Über den Knopf „Datei anhängen“ (Dateiauswahl) oder – auf dem
//  Mac – per Ziehen aus dem Finder bzw. vom Schreibtisch in das Fenster.
//  Beide Wege verarbeitet dieselbe Funktion (`handleFileImport`).
//
//  Senden mit leerem Betreff fragt nach: „Senden“ oder „Zurück“
//  (`requestSend`, alle Plattformen).
//
//  Schließen mit Eingaben fragt nach: „Als Entwurf sichern“ (ohne
//  Verbindung ausgegraut), „Verwerfen“ oder „Weiter bearbeiten“. Ohne
//  Absender wird zuerst um die Wahl eines Absenders gebeten; fehlt der
//  Entwürfe-Ordner, wird nach dem Anlegen gefragt.
//
//  Entwurf weiterbearbeiten: `init(accountStore:draft:attachments:)` öffnet
//  einen gesicherten Entwurf; fehlen dabei Bilder, erscheint beim Öffnen
//  ein Hinweis.
//
//  Meldungen und Rückfragen laufen über je einen Kanal (siehe
//  Dialogs.swift).
//
//  Teilen-Erweiterung: Dort ist das Fenster keine Sheet-Ansicht, die sich
//  per `dismiss` schließt. Die Erweiterung übergibt deshalb `onClose` und
//  beendet sich darin selbst; die geteilten Inhalte kommen über `shared`.
//
//  Mac: In der App wie in der Teilen-Erweiterung stehen
//  Schließen (✕, Esc) und Senden (blauer Kreis mit Papierflieger, ⌘Return)
//  gleich groß in einer festen Kopfleiste oben (SheetHeaderBar) – nicht
//  mehr in einer weißen Leiste am unteren Rand. Die Formatierungsleiste
//  bleibt unten.
//
//  Abgrenzung: Zustand, Versand und Vorbelegung → ComposeViewModel;
//  Editor → RichTextEditor; Formatierungsleiste → FormattingToolbar;
//  Darstellung des Zitats (mit eingesetzten Bildern) → HTMLMailView;
//  Empfängerfelder → RecipientField; HTML-Signatur → SignatureBlockView.
//
//  Abhängigkeiten: SwiftUI, UniformTypeIdentifiers, PhotosUI (iOS), Dialogs,
//  SignatureStore, SignatureBlockView, NetworkMonitor, AppTheme,
//  SheetHeaderBar.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

/// Fenster zum Verfassen einer Mail.
struct ComposeView: View {
    /// Zustand und Logik des Fensters.
    @State private var model: ComposeViewModel
    /// Wird nach erfolgreichem Versand oder Sichern eines Entwurfs
    /// aufgerufen (Liste aktualisieren).
    private let onSent: () -> Void
    /// Schließt das Fenster anstelle von `dismiss` (Teilen-Erweiterung);
    /// `nil` = als Sheet schließen.
    private let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// Speicher der Signaturen.
    @Environment(SignatureStore.self) private var signatureStore
    /// Einziger Meldungskanal des Fensters (Fehler, Hinweise nach dem Versand).
    @State private var activeAlert: AlertItem?
    /// Einziger Rückfragekanal des Fensters („Nachricht schließen?“ u. a.).
    @State private var activeConfirmation: ConfirmationRequest?
    /// Dateiauswahl sichtbar.
    @State private var showFileImporter = false
    /// Zitat aufgeklappt.
    @State private var showQuote = false
    /// Gemessene Höhe des Zitats.
    @State private var quoteHeight: CGFloat = 200
    /// Sichtbare Höhe des Scrollbereichs – für die freie Fläche unter dem Inhalt.
    @State private var visibleHeight: CGFloat = 0
    /// Höhe von Kopfbereich, Editor und Zitat – für die freie Fläche unter dem Inhalt.
    @State private var contentHeight: CGFloat = 0
    #if os(iOS)
    /// Fotoauswahl sichtbar.
    @State private var showPhotoPicker = false
    /// Gewähltes Foto, wird nach dem Laden zurückgesetzt.
    @State private var photoItem: PhotosPickerItem?
    #endif

    /// Legt das Fenster an.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Passwörter.
    ///   - kind: Neue Mail, Antwort, Antwort an alle oder Weiterleitung.
    ///   - original: Ursprungsmail bei Antwort/Weiterleitung.
    ///   - mailto: Vorbelegung aus einem mailto:-Link.
    ///   - senderAccountID: Absende-Postfach einer neuen Mail (Postfach des
    ///     gezeigten Ordners); `nil` = Standard-Postfach.
    ///   - shared: Aus einer anderen App geteilte Inhalte; `nil` = keine.
    ///   - onSent: Rückruf nach erfolgreichem Versand.
    ///   - onClose: Schließt das Fenster anstelle von `dismiss`; `nil` =
    ///     als Sheet schließen.
    init(
        accountStore: AccountStore,
        kind: ComposeKind,
        original: CachedMessage? = nil,
        mailto: MailtoLink? = nil,
        senderAccountID: UUID? = nil,
        shared: SharedContent? = nil,
        onSent: @escaping () -> Void = {},
        onClose: (() -> Void)? = nil
    ) {
        _model = State(
            initialValue: ComposeViewModel(
                accountStore: accountStore, kind: kind, original: original, mailto: mailto,
                senderAccountID: senderAccountID, shared: shared
            )
        )
        self.onSent = onSent
        self.onClose = onClose
    }

    /// Legt das Fenster für einen gesicherten Entwurf an.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Passwörter.
    ///   - draft: Entwurf aus dem Cache.
    ///   - attachments: Anhänge und Bilder des Entwurfs aus dem Cache.
    ///   - onSent: Rückruf nach Versand oder Sichern.
    init(
        accountStore: AccountStore,
        draft: CachedMessage,
        attachments: [CachedAttachment],
        onSent: @escaping () -> Void = {}
    ) {
        _model = State(
            initialValue: ComposeViewModel(accountStore: accountStore, draft: draft, attachments: attachments)
        )
        self.onSent = onSent
        self.onClose = nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scrollingContent
                bottomBar
            }
            // Kopf und untere Leiste auf der getönten Fläche; die
            // Schreibfläche liegt als Karte darauf (siehe scrollingContent).
            .appBackground()
            // Mac: feste Kopfleiste mit ✕ und Senden (App und Erweiterung).
            .macSheetHeader(title) {
                HeaderCircleButton.cancel("Schließen") { requestClose() }
                    .disabled(model.isSending || model.isSavingDraft)
            } trailing: {
                HeaderCircleButton.send(
                    isEnabled: model.canSend,
                    isBusy: model.isSending || model.isSavingDraft
                ) {
                    requestSend()
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            #endif
            .interactiveDismissDisabled(model.hasContent)
            .confirmationRequest($activeConfirmation)
            .task {
                model.attachSignatures(signatureStore)
                // Hinweis nach dem Wiederherstellen eines Entwurfs, einmal.
                if let notice = model.restoreNotice {
                    model.restoreNotice = nil
                    activeAlert = AlertItem(title: "Entwurf geöffnet", message: notice)
                }
            }
            .onChange(of: model.accountID) { _, _ in model.accountDidChange() }
            .onChange(of: model.errorMessage) { _, message in
                // Fehler des ViewModels in den Meldungskanal übernehmen.
                guard let message else { return }
                activeAlert = AlertItem(title: "Versand fehlgeschlagen", message: message)
                model.errorMessage = nil
            }
            .onChange(of: model.attachmentFailure?.attachment.id) { _, id in
                guard id != nil else { return }
                confirmSendWithoutFailedAttachment()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
            #if os(macOS)
            // Mac: Dateien aus dem Finder oder vom Schreibtisch in das Fenster
            // ziehen – gleiche Verarbeitung wie „Datei anhängen“. Nur Dateien:
            // Eine gezogene Web-Adresse würde beim Lesen sonst aus dem Netz
            // geladen.
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                handleFileImport(.success(files))
                return true
            }
            #endif
        }
        .alertItem($activeAlert)
        .macSheetFrame(.composer)
    }

    // MARK: - Scrollbereich

    /// Kopfbereich, Editor und Zitat in einem gemeinsamen Scrollbereich.
    ///
    /// Verarbeitung: Ist der Inhalt kürzer als der sichtbare Bereich, füllt
    /// eine freie Fläche den Rest. Ein Tipp dorthin setzt die Schreibmarke
    /// ans Textende – wie vorher, als der Editor den Rest ausfüllte. Editor
    /// und freie Fläche bilden zusammen die ungetönte Schreibfläche (Karte),
    /// der Kopfbereich darüber liegt auf der getönten Fläche.
    private var scrollingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider()
                    editor
                        .background(AppTheme.card)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }

                AppTheme.card
                    .frame(height: max(0, visibleHeight - contentHeight))
                    .contentShape(Rectangle())
                    .onTapGesture { model.controller.focusAtEnd() }
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            visibleHeight = height
        }
    }

    // MARK: - Kopfbereich

    /// Absender, Empfänger, Betreff und Anhänge.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            senderRow
            Divider()
            RecipientField(label: "An", addresses: $model.to)
            Divider()
            HStack(alignment: .top, spacing: 8) {
                RecipientField(label: "Cc", addresses: $model.cc)
                if !model.showBcc {
                    Button("Bcc") { model.showBcc = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
            if model.showBcc {
                Divider()
                RecipientField(label: "Bcc", addresses: $model.bcc)
            }
            Divider()
            HStack(spacing: 8) {
                Text("Betreff")
                    .foregroundStyle(.secondary)
                TextField("", text: $model.subject)
            }
            if !model.attachments.isEmpty || model.missingAttachmentCount > 0 {
                Divider()
                attachmentList
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Absenderzeile mit Postfachauswahl.
    private var senderRow: some View {
        HStack(spacing: 8) {
            Text("Von")
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Menu {
                ForEach(model.accounts) { account in
                    Button {
                        model.accountID = account.id
                    } label: {
                        if account.id == model.accountID {
                            Label(account.displayName, systemImage: "checkmark")
                        } else {
                            Text(account.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let hex = model.selectedAccount?.colorHex {
                        Circle().fill(Color(hex: hex)).frame(width: 10, height: 10)
                    }
                    Text(model.selectedAccount?.displayName ?? "Postfach wählen")
                        .foregroundStyle(model.selectedAccount == nil ? .secondary : .primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// Liste der eigenen Anhänge samt Größe und Entfernen-Knopf.
    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(model.attachments.enumerated()), id: \.offset) { _, attachment in
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.secondary)
                    Text(attachment.filename)
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(attachment.data.count), countStyle: .file
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.removeAttachment(attachment)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(attachment.filename) entfernen")
                }
            }
            if model.missingAttachmentCount > 0 {
                Text("\(model.missingAttachmentCount) Anhang/Anhänge werden beim Senden vom Server geladen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !model.attachments.isEmpty {
                Text("Gesamt: \(ByteCountFormatter.string(fromByteCount: Int64(model.totalAttachmentBytes), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Editor und Zitat

    /// Editor, gegebenenfalls die HTML-Signatur und das aufklappbare Zitat.
    ///
    /// Verarbeitung: Alle erscheinen in voller Höhe; gescrollt wird im
    /// umgebenden Scrollbereich. Die HTML-Signatur schließt direkt an den
    /// Text an. Das Zitat ist mindestens 120 Punkte hoch, solange seine
    /// Höhe noch nicht gemessen ist.
    private var editor: some View {
        VStack(spacing: 0) {
            // Mit HTML-Signatur ist der Editor anfangs niedriger, damit der
            // Block direkt unter dem Text steht statt unter einer Leerfläche.
            RichTextEditor(
                text: $model.body,
                controller: model.controller,
                minHeight: model.htmlSignature == nil ? 160 : 72
            )

            if let signature = model.htmlSignature {
                SignatureBlockView(
                    block: signature,
                    onChange: { model.updateHTMLSignature($0) },
                    onRemove: { model.removeHTMLSignature() }
                )
                .padding(.bottom, 8)
            }

            if let quoted = model.quotedHTML {
                Divider()
                DisclosureGroup(isExpanded: $showQuote) {
                    HTMLMailView(html: model.quotedPreviewHTML ?? quoted, contentHeight: $quoteHeight)
                        .frame(height: max(120, quoteHeight))
                } label: {
                    Label(
                        model.kind == .forward ? "Weitergeleitete Nachricht" : "Zitierter Text",
                        systemImage: "text.quote"
                    )
                    .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Toolbar

    /// Schließen – mit Rückfrage, wenn schon etwas eingegeben ist.
    private func requestClose() {
        if model.hasContent { confirmClose() } else { close() }
    }

    #if os(iOS)
    /// Schließen (mit Rückfrage bei Inhalt) und Senden.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { closeButton }
        ToolbarItem(placement: .primaryAction) { sendButton }
    }

    /// Knopf „Schließen“ (mit Rückfrage bei Inhalt).
    private var closeButton: some View {
        Button {
            requestClose()
        } label: {
            Image(systemName: "xmark")
        }
        .disabled(model.isSending || model.isSavingDraft)
        .help("Schließen")
    }

    /// Knopf „Senden“, während Versand oder Sichern eine Ladeanzeige.
    @ViewBuilder
    private var sendButton: some View {
        if model.isSending || model.isSavingDraft {
            ProgressView()
        } else {
            Button {
                requestSend()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(!model.canSend)
            .help("Senden")
        }
    }
    #endif

    /// Untere Leiste: Anhang als erste Gruppe, dahinter die Formatierung
    /// (scrollt bei Bedarf).
    private var bottomBar: some View {
        FormattingToolbar(controller: model.controller, leading: { attachmentMenu })
    }

    /// Menü zum Anhängen von Dateien und (iOS) Fotos.
    private var attachmentMenu: some View {
        Menu {
            Button {
                showFileImporter = true
            } label: {
                Label("Datei anhängen", systemImage: "doc")
            }
            #if os(iOS)
            // Fotos laufen über den System-Picker
            Button {
                showPhotoPicker = true
            } label: {
                Label("Foto anhängen", systemImage: "photo")
            }
            #endif
        } label: {
            FormatIcon(symbol: "paperclip")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Anhängen")
        .accessibilityLabel("Anhängen")
        .disabled(model.isSending)
        #if os(iOS)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        #endif
    }

    /// Fenstertitel je nach Art der Mail.
    private var title: String {
        switch model.kind {
        case .new:       return "Neue Nachricht"
        case .reply:     return "Antworten"
        case .replyAll:  return "Allen antworten"
        case .forward:   return "Weiterleiten"
        }
    }

    // MARK: - Aktionen

    /// Schließt das Fenster: über `onClose`, sonst als Sheet.
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    /// Fragt beim Schließen nach: als Entwurf sichern, verwerfen oder
    /// weiter bearbeiten.
    ///
    /// Verarbeitung: Ohne Verbindung ist „Als Entwurf sichern“ ausgegraut
    /// und der Text weist darauf hin.
    private func confirmClose() {
        let isOnline = NetworkMonitor.shared.isOnline
        var request = ConfirmationRequest(
            title: "Nachricht schließen?",
            message: isOnline
                ? "Die Nachricht wurde noch nicht gesendet. Du kannst sie als Entwurf sichern oder verwerfen."
                : "Die Nachricht wurde noch nicht gesendet. Ohne Verbindung kann kein Entwurf gesichert werden.",
            confirmLabel: "Verwerfen",
            cancelLabel: "Weiter bearbeiten"
        ) {
            close()
        }
        request.secondary = .init(label: "Als Entwurf sichern", isEnabled: isOnline) {
            Task { await saveDraft() }
        }
        activeConfirmation = request
    }

    /// Sichert die Nachricht als Entwurf und schließt das Fenster.
    ///
    /// Verarbeitung: Ohne Absender erscheint zuerst ein Hinweis. Fehlt der
    /// Entwürfe-Ordner, wird nach dem Anlegen gefragt und danach erneut
    /// gesichert. Bei einem Fehler bleibt das Fenster offen. Nach dem
    /// Sichern wird die Liste aktualisiert; Hinweise (alte Fassung nicht
    /// entfernt) erscheinen vor dem Schließen.
    ///
    /// - Parameter createFolder: `true` = fehlenden Entwürfe-Ordner anlegen.
    private func saveDraft(createFolder: Bool = false) async {
        guard model.accountID != nil else {
            activeAlert = AlertItem(
                title: "Kein Absender",
                message: "Bitte zuerst einen Absender wählen, damit der Entwurf im richtigen Postfach gesichert wird."
            )
            return
        }
        switch await model.saveDraft(createFolder: createFolder) {
        case .saved:
            if model.warnings.isEmpty {
                onSent()
                close()
            } else {
                activeAlert = AlertItem(
                    title: "Hinweis zum Entwurf",
                    message: model.warnings.joined(separator: "\n\n")
                ) {
                    onSent()
                    close()
                }
            }
        case .needsDraftsFolder:
            activeConfirmation = ConfirmationRequest(
                title: "Ordner „Entwürfe“ anlegen?",
                message: "Das Postfach hat noch keinen Ordner für Entwürfe. Mailwerk legt ihn an und sichert den Entwurf dort.",
                confirmLabel: "Anlegen und sichern",
                isDestructive: false
            ) {
                Task { await saveDraft(createFolder: true) }
            }
        case .failed(let message):
            activeAlert = AlertItem(title: "Entwurf nicht gesichert", message: message)
        }
    }

    /// Fragt nach, ob ohne den nicht ladbaren Anhang bzw. das nicht
    /// ladbare eingebettete Bild gesendet werden soll.
    ///
    /// Verarbeitung: „Ohne … senden“ verzichtet darauf und sendet erneut;
    /// „Abbrechen“ lässt die Mail unverändert – ein späteres Senden
    /// versucht es noch einmal.
    private func confirmSendWithoutFailedAttachment() {
        // Beim Sichern eines Entwurfs gilt die Rückfrage nicht (der Entwurf
        // meldet den Fehler selbst).
        guard !model.isSavingDraft, let failure = model.attachmentFailure else { return }
        let isImage = failure.attachment.isInline
        activeConfirmation = ConfirmationRequest(
            title: isImage ? "Bild nicht geladen" : "Anhang nicht geladen",
            message: isImage
                ? "Das eingebettete Bild „\(failure.attachment.filename)“ konnte nicht geladen werden: \(failure.reason)\n\nOhne dieses Bild senden?"
                : "„\(failure.attachment.filename)“ konnte nicht geladen werden: \(failure.reason)\n\nOhne diesen Anhang senden?",
            confirmLabel: isImage ? "Ohne Bild senden" : "Ohne Anhang senden",
            isDestructive: false,
            onCancel: { model.attachmentFailure = nil }
        ) {
            model.skipAttachment(failure.attachment)
            Task { await send() }
        }
    }

    /// Knopf „Senden“: fragt bei leerem Betreff nach, sonst wird sofort
    /// gesendet.
    ///
    /// Verarbeitung: Ein Betreff aus Leerzeichen gilt als leer. „Senden“
    /// in der Rückfrage verschickt die Mail ohne Betreff, „Zurück“ lässt
    /// das Fenster unverändert offen (z. B. um den Betreff nachzutragen).
    private func requestSend() {
        guard model.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task { await send() }
            return
        }
        activeConfirmation = ConfirmationRequest(
            title: "Ohne Betreff senden?",
            message: "Die Nachricht hat keinen Betreff.",
            confirmLabel: "Senden",
            isDestructive: false,
            cancelLabel: "Zurück"
        ) {
            Task { await send() }
        }
    }

    /// Sendet die Mail.
    ///
    /// Verarbeitung: Ohne Hinweise schließt das Fenster sofort; gibt es
    /// Hinweise (z. B. Gesendet-Kopie fehlgeschlagen), werden sie zuerst
    /// angezeigt und das Fenster schließt nach „OK“.
    private func send() async {
        let sent = await model.send()
        guard sent else { return }
        if model.warnings.isEmpty {
            onSent()
            close()
        } else {
            activeAlert = AlertItem(
                title: "Hinweis zum Versand",
                message: model.warnings.joined(separator: "\n\n")
            ) {
                onSent()
                close()
            }
        }
    }

    /// Übernimmt gewählte Dateien als Anhänge.
    ///
    /// Verarbeitung: Jede gewählte Datei wird einzeln angehängt
    /// (`attachFile`). Nicht lesbare oder zu große Dateien werden gemeldet,
    /// die übrigen trotzdem angehängt.
    ///
    /// - Parameter result: Ergebnis der Dateiauswahl.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls { attachFile(at: url) }
        case .failure(let error):
            activeAlert = .failure("Datei nicht angehängt", error)
        }
    }

    /// Hängt eine gewählte Datei an.
    ///
    /// Verarbeitung: Der Zugriff auf Dateien außerhalb der App wird geöffnet
    /// und wieder geschlossen. Die Größe wird vor dem Einlesen geprüft
    /// (`AttachmentManager.maxImportBytes`), damit eine sehr große Datei
    /// nicht erst vollständig in den Speicher geladen wird.
    ///
    /// - Parameter url: Gewählte Datei.
    private func attachFile(at url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard !AttachmentManager.exceedsImportLimit(sizeBytes: size) else {
            let limit = ByteCountFormatter.string(
                fromByteCount: Int64(AttachmentManager.maxImportBytes), countStyle: .file
            )
            activeAlert = AlertItem(
                title: "Datei nicht angehängt",
                message: "„\(url.lastPathComponent)“ ist größer als \(limit) und lässt sich nicht versenden."
            )
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let type = UTType(filenameExtension: url.pathExtension)
            model.addAttachment(
                filename: url.lastPathComponent,
                mimeType: type?.preferredMIMEType ?? "application/octet-stream",
                data: data
            )
        } catch {
            activeAlert = AlertItem(
                title: "Datei nicht angehängt",
                message: "„\(url.lastPathComponent)“ konnte nicht gelesen werden: \(error.localizedDescription)"
            )
        }
    }

    #if os(iOS)
    /// Lädt ein gewähltes Foto und hängt es an.
    ///
    /// - Parameter item: Gewähltes Foto aus der Fotoauswahl.
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let name = item.supportedContentTypes.first?.preferredFilenameExtension.map {
                "Foto.\($0)"
            } ?? "Foto.jpg"
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            model.addAttachment(filename: name, mimeType: mime, data: data)
        } catch {
            activeAlert = .failure("Foto nicht angehängt", error)
        }
    }
    #endif
}
