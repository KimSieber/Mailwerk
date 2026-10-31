//
//  SignatureEditorView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 13.10.2026
//  Geändert: 31.10.2026
//
//  Zweck: Pflege-Seite für die Signatur eines Postfachs (aus „Postfach
//  bearbeiten“ geöffnet). Von oben nach unten:
//  1. Art der Signatur: „Einfach“ oder „HTML“.
//  2. Einfach: Editor mit Formatierungsleiste und Knopf „Logo“.
//     HTML: Code-Feld bzw. Vorschau, umschaltbar oben rechts.
//  3. Logo: Bild aus Fotos (Fotomediathek, auch auf dem Mac) oder Dateien
//     wählen, Vorschau, Entfernen.
//  4. „Signatur entfernen“ (mit Rückfrage), wenn eine gespeichert ist.
//  „Sichern“ speichert in iCloud, „Abbrechen“ verwirft die Änderungen.
//  Auf dem Mac stehen beide als ✕ und ✓ in einer festen
//  Kopfleiste oben (SheetHeaderBar); Return bleibt dem Editor (kein
//  Kürzel an ✓), Esc bricht ab.
//
//  Beide Arten werden als HTML gespeichert; das Logo steht darin als
//  Platzhalter `<img src="logo">`. Wechsel der Art:
//  - Einfach → HTML: der erzeugte Code wird übernommen (verlustfrei).
//  - HTML → Einfach: mit Rückfrage, wenn dabei Gestaltung wegfiele.
//  Ein neues Logo ersetzt das Logo im Editor; Entfernen nimmt es heraus.
//  Weitere Bilder im Editor werden beim Sichern (nach Hinweis) verworfen.
//
//  Abgrenzung: Speichern → SignatureStore; Umwandlungen → SignatureEditing;
//  Platzhalter und Regeln → SignatureRules; Einsetzen beim Verfassen →
//  ComposeView/ComposeViewModel.
//
//  Abhängigkeiten: SwiftUI, PhotosUI, UniformTypeIdentifiers,
//  SignatureStore, SignatureEditing, SignatureRules, EditorImageData,
//  RichTextEditor, FormattingToolbar, CodeTextEditor, HTMLMailView,
//  DecodedImage, Dialogs, MailAccount, AppTheme (getönte Seite, Editor als
//  Karte), SheetHeaderBar.
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

/// Pflege-Seite der Signatur eines Postfachs.
struct SignatureEditorView: View {
    @Environment(\.dismiss) private var dismiss
    /// Speicher der Signaturen.
    @Environment(SignatureStore.self) private var signatureStore

    /// Postfach, zu dem die Signatur gehört.
    let account: MailAccount
    /// `true`, wenn beim Öffnen eine Signatur gespeichert war.
    private let hasStoredSignature: Bool

    /// Ansicht des HTML-Felds.
    enum CodeMode: Hashable { case code, preview }

    /// Gewählte Art.
    @State private var kind: SignatureKind
    /// Text im Editor (Art „Einfach“).
    @State private var text: NSAttributedString
    /// Steuerung des Editors.
    @State private var controller = RichTextController()
    /// HTML-Code (Art „HTML“).
    @State private var code: String
    /// Code oder Vorschau.
    @State private var codeMode: CodeMode = .code
    /// Gemessene Höhe der Vorschau.
    @State private var previewHeight: CGFloat = 0
    /// Bilddaten des Logos.
    @State private var logoData: Data?
    /// MIME-Typ des Logos.
    @State private var logoMimeType: String?

    /// Dateiauswahl für das Logo sichtbar.
    @State private var showFileImporter = false
    /// Fotoauswahl für das Logo sichtbar.
    @State private var showPhotoPicker = false
    /// Gewähltes Foto.
    @State private var photoItem: PhotosPickerItem?
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?
    /// Einziger Rückfragekanal der Ansicht.
    @State private var activeConfirmation: ConfirmationRequest?

    /// Belegt die Seite mit der gespeicherten Signatur vor.
    ///
    /// Verarbeitung: Eine einfache Signatur wird in den Editor geholt, eine
    /// HTML-Signatur ins Code-Feld. Ohne Signatur beginnt die Seite leer
    /// mit der Art „Einfach“.
    ///
    /// - Parameters:
    ///   - account: Postfach.
    ///   - signature: Gespeicherte Signatur oder `nil`.
    init(account: MailAccount, signature: SignatureItem?) {
        self.account = account
        hasStoredSignature = signature != nil
        let kind = signature?.kind ?? .simple
        _kind = State(initialValue: kind)
        _code = State(initialValue: signature?.html ?? "")
        _logoData = State(initialValue: signature?.logoData)
        _logoMimeType = State(initialValue: signature?.logoMimeType)
        let editorText = kind == .simple
            ? SignatureEditing.editorText(html: signature?.html ?? "", logoData: signature?.logoData).text
            : NSAttributedString(string: "", attributes: RichTextController.defaultAttributes)
        _text = State(initialValue: editorText)
    }

    /// Aufbau der Seite.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxLarge) {
                Picker("Art der Signatur", selection: kindBinding) {
                    Text("Einfach").tag(SignatureKind.simple)
                    Text("HTML").tag(SignatureKind.html)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if kind == .simple {
                    simpleEditor
                } else {
                    htmlEditor
                }

                logoSection

                if hasStoredSignature {
                    Button("Signatur entfernen", role: .destructive) { confirmRemove() }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        // Seite getönt, Editor bzw. Code-Feld ungetönt als Karte.
        .appBackground()
        .navigationTitle("Signatur")
        .navigationBarBackButtonHidden(true)
        .macSheetHeader("Signatur") {
            HeaderCircleButton.cancel { dismiss() }
        } trailing: {
            // Ohne Return: Return gehört dem Editor (neue Zeile).
            HeaderCircleButton.confirm("Sichern", usesReturn: false) { save() }
        }
        #if !os(macOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) { save() }
            }
        }
        #endif
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            handleFileImport(result)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .confirmationRequest($activeConfirmation)
        .alertItem($activeAlert)
    }

    // MARK: - Bereiche

    /// Editor für die einfache Signatur samt Formatierungsleiste und Logo-Knopf.
    private var simpleEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Signatur").font(.headline)
            VStack(spacing: 0) {
                RichTextEditor(text: $text, controller: controller, minHeight: 140)
                Divider()
                FormattingToolbar(controller: controller, trailing: {
                    Button {
                        insertLogo()
                    } label: {
                        FormatIcon(symbol: "photo")
                    }
                    .buttonStyle(.plain)
                    .disabled(logoData == nil)
                    .help("Logo einsetzen")
                    .accessibilityLabel("Logo einsetzen")
                })
            }
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppCornerRadius.regular))
            .background(RoundedRectangle(cornerRadius: AppCornerRadius.regular).stroke(.separator))
            Text("Das Logo erscheint an der Stelle der Schreibmarke (Knopf mit dem Bild-Symbol).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Code-Feld bzw. Vorschau für die HTML-Signatur.
    private var htmlEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Text("HTML-Code").font(.headline)
                Spacer()
                Picker("Ansicht", selection: $codeMode) {
                    Text("Code").tag(CodeMode.code)
                    Text("Vorschau").tag(CodeMode.preview)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Group {
                if codeMode == .code {
                    CodeTextEditor(text: $code)
                        .frame(height: 260)
                } else {
                    HTMLMailView(html: previewHTML, contentHeight: $previewHeight, allowsRemoteContent: true)
                        .frame(height: max(80, previewHeight))
                }
            }
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppCornerRadius.regular))
            .background(RoundedRectangle(cornerRadius: AppCornerRadius.regular).stroke(.separator))
            if logoData != nil, !SignatureRules.containsLogo(code) {
                Text("Das Logo erscheint erst, wenn der Code den Platzhalter <img src=\"logo\"> enthält.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Auswahl, Vorschau und Entfernen des Logos.
    private var logoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            Text("Logo").font(.headline)
            HStack(alignment: .center, spacing: AppSpacing.large) {
                if let logoData, let image = DecodedImage.image(from: logoData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 120, maxHeight: 60)
                        .padding(AppSpacing.small)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: AppCornerRadius.small))
                        .overlay(RoundedRectangle(cornerRadius: AppCornerRadius.small).stroke(.separator))
                } else {
                    Text("Kein Logo")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Aus Fotos", systemImage: "photo")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Aus Dateien", systemImage: "doc")
                    }
                } label: {
                    Text(logoData == nil ? "Bild wählen" : "Ersetzen")
                }
                .fixedSize()
                if logoData != nil {
                    Button("Entfernen", role: .destructive) { removeLogo() }
                }
            }
            Text("Im HTML-Code steht das Logo als <img src=\"logo\">, die Breite optional mit width=\"150\" (ohne Angabe 150 pt). Große Bilder werden auf 600 Pixel verkleinert.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Abgeleitete Werte

    /// Vorschau-HTML: Platzhalter durch das Logo (als `data:`) ersetzt.
    private var previewHTML: String {
        guard let logoData else { return code }
        let source = SignatureRules.dataURI(logoData, mimeType: logoMimeType ?? "image/png")
        return SignatureRules.replacingLogo(in: code, with: source)
    }

    /// Bindung der Art; ein Wechsel läuft über `requestKind`.
    private var kindBinding: Binding<SignatureKind> {
        Binding(get: { kind }, set: { requestKind($0) })
    }

    // MARK: - Aktionen

    /// Wechselt die Art der Signatur.
    ///
    /// Verarbeitung: Einfach → HTML übernimmt den erzeugten Code. HTML →
    /// Einfach liest den Code in den Editor; fiele dabei Gestaltung weg,
    /// wird vorher gefragt. Bei „Abbrechen“ bleibt die Art unverändert.
    ///
    /// - Parameter newKind: Gewünschte Art.
    private func requestKind(_ newKind: SignatureKind) {
        guard newKind != kind else { return }
        switch newKind {
        case .html:
            code = SignatureEditing.html(from: text)
            codeMode = .code
            kind = .html
        case .simple:
            let result = SignatureEditing.editorText(html: code, logoData: logoData)
            let apply = {
                text = result.text
                kind = .simple
            }
            if result.isLossless {
                apply()
            } else {
                activeConfirmation = ConfirmationRequest(
                    title: "In einfache Signatur umwandeln?",
                    message: "Die Gestaltung wird vereinfacht: Tabellen, Schriftarten, Abstände und Ausrichtung gehen verloren. Text, Formate, Links und Logo bleiben erhalten.",
                    confirmLabel: "Umwandeln",
                    onConfirm: apply
                )
            }
        }
    }

    /// Setzt das Logo an der Schreibmarke ein.
    private func insertLogo() {
        guard let logoData, let image = SignatureEditing.logoAttachment(data: logoData) else { return }
        controller.insertImage(image)
    }

    /// Übernimmt neue Logo-Daten.
    ///
    /// Verarbeitung: Das Bild wird auf höchstens 600 Pixel verkleinert
    /// (EditorImageData). Steht das Logo schon im Editor, wird es dort
    /// ersetzt. Unlesbare Daten werden gemeldet.
    ///
    /// - Parameter data: Gewählte Bilddaten.
    private func setLogo(_ data: Data) {
        guard let prepared = EditorImageData.prepare(data, maxPixelSize: SignatureRules.maxLogoPixelSize) else {
            activeAlert = AlertItem(title: "Logo nicht übernommen", message: "Die Datei ist kein lesbares Bild.")
            return
        }
        logoData = prepared.data
        logoMimeType = prepared.mimeType
        text = SignatureEditing.replacingLogo(in: text, with: prepared.data)
    }

    /// Entfernt das Logo – auch aus dem Editor.
    private func removeLogo() {
        logoData = nil
        logoMimeType = nil
        text = SignatureEditing.replacingLogo(in: text, with: nil)
    }

    /// Speichert die Signatur und schließt die Seite.
    ///
    /// Verarbeitung: Einfach → HTML aus dem Editor (Logo als Platzhalter),
    /// HTML → Code unverändert. Enthält der Editor weitere Bilder, wird
    /// vorher darauf hingewiesen, dass sie entfallen. Eine leere Signatur
    /// entfernt die gespeicherte (SignatureStore). Ein Fehler lässt die
    /// Seite offen.
    private func save() {
        let html = kind == .simple ? SignatureEditing.html(from: text) : code
        let item = SignatureItem(
            accountID: account.id,
            kind: kind,
            html: html,
            logoData: logoData,
            logoMimeType: logoData == nil ? nil : logoMimeType,
            modifiedAt: Date()
        )
        let store = signatureStore
        let commit = {
            do {
                try store.save(item)
                dismiss()
            } catch {
                activeAlert = .failure("Signatur nicht gespeichert", error)
            }
        }

        let foreignImages = kind == .simple ? SignatureEditing.foreignImageCount(in: text) : 0
        if foreignImages > 0 {
            activeConfirmation = ConfirmationRequest(
                title: "Weitere Bilder entfallen",
                message: "Eine Signatur enthält nur das Logo. \(foreignImages == 1 ? "Ein weiteres Bild wird" : "\(foreignImages) weitere Bilder werden") nicht übernommen.",
                confirmLabel: "Sichern",
                isDestructive: false,
                onConfirm: commit
            )
        } else {
            commit()
        }
    }

    /// Fragt nach und entfernt dann die Signatur des Postfachs.
    private func confirmRemove() {
        let store = signatureStore
        let accountID = account.id
        activeConfirmation = ConfirmationRequest(
            title: "Signatur entfernen?",
            message: "Die Signatur dieses Postfachs wird auf allen Geräten gelöscht.",
            confirmLabel: "Entfernen"
        ) {
            do {
                try store.remove(accountID: accountID)
                dismiss()
            } catch {
                activeAlert = .failure("Signatur nicht entfernt", error)
            }
        }
    }

    /// Übernimmt eine gewählte Bilddatei als Logo.
    ///
    /// - Parameter result: Ergebnis der Dateiauswahl.
    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                setLogo(try Data(contentsOf: url))
            } catch {
                activeAlert = .failure("Logo nicht übernommen", error)
            }
        case .failure(let error):
            activeAlert = .failure("Logo nicht übernommen", error)
        }
    }

    /// Lädt ein gewähltes Foto als Logo.
    ///
    /// - Parameter item: Gewähltes Foto.
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            setLogo(data)
        } catch {
            activeAlert = .failure("Logo nicht übernommen", error)
        }
    }
}
