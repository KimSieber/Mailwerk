//
//  FilterListView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 24.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Pflege einer der beiden Filterlisten.
//  - „Neuer Eintrag …“ (erste Zeile) öffnet ein Pop-up; mehrere Angaben auf
//    einmal sind möglich – getrennt durch Komma, Semikolon, Zeilenumbruch
//    oder Leerzeichen. Das Ergebnis erscheint als kurze Meldung.
//  - Langes Drücken auf einen Eintrag (Mac: Rechtsklick) öffnet
//    „Bearbeiten“ und „Löschen“. Bearbeiten zeigt ein Pop-up mit dem
//    Eintrag; gespeichert wird mit derselben Prüfung wie beim Anlegen
//    (nicht auf der anderen Liste), ohne den alten Eintrag zu verlieren
//    (FilterListEditing). Löschen – auch per Wischen – fragt vorher nach.
//  - „Importieren“ (Symbolleiste) liest eine Textdatei im Format des
//    Exports – eine Angabe je Zeile, Domains als `*firma.de` – in diese
//    Liste ein. Vorher nennt eine Rückfrage, wie viele Einträge neu sind;
//    jeder Eintrag wird wie bei „Neuer Eintrag …“ gegen die andere Liste
//    geprüft. Das Ergebnis erscheint als Meldung.
//  - Antippen allein bewirkt bewusst nichts: Bearbeiten ist die Ausnahme
//    und soll beim Scrollen nicht versehentlich ausgelöst werden.
//
//  Mac: feste Kopfleiste oben – „<“ zurück zum Spamfilter,
//  Titel, „Importieren“ und „Exportieren“ als graue Kreise
//  (SheetHeaderBar) – statt der Symbolleiste; der Inhalt als gruppiertes
//  Formular (Karten wie iOS) auf Nebelblau. „Exportieren“ ist wie auf iOS
//  ein Knopf: ein Menü mit „Als Datei sichern …“ (Sichern-Dialog des
//  Systems, `fileExporter` – das Teilen-Menü des Mac bietet das Ablegen
//  als Datei nicht an) und „Teilen“.
//
//  Domains erscheinen als `*firma.de`: Ein Domain-Eintrag gilt auch für alle
//  Subdomains (FilterDomain).
//
//  Die Ansicht lädt beim Öffnen und erneut, sobald der iCloud-Abgleich
//  Änderungen von einem anderen Gerät übernommen hat. So bleibt eine
//  geöffnete Liste aktuell, ohne dass man sie schließen muss.
//
//  Abgrenzung: Speicherung und Abgleich → FilterListRepository; Zerlegen
//  der Eingabe → FilterListInput; Export → FilterListExporter; Lesen und
//  Zusammenfassen des Imports → FilterListImport.
//
//  Abhängigkeiten: SwiftUI, FilterListRepository, FilterListInput,
//  FilterListEditing, PlatformInputModifiers,
//  FilterListExporter, FilterListImport, FilterListCloudEvents, FilterDomain,
//  Dialogs,
//  AppTheme (getönte Fläche, Abschnitte als Karten), SheetHeaderBar,
//  PlatformSheetSize, Log.
//

import SwiftUI
import UniformTypeIdentifiers
import os

/// Pflege der White- bzw. Blacklist.
struct FilterListView: View {
    /// Gepflegte Liste.
    let list: FilterList
    /// Speicher der Filterlisten.
    let repository: any FilterListRepository

    /// Offenes Pop-up: neuer Eintrag oder Bearbeiten eines Eintrags.
    private enum EditorRequest: Identifiable {
        /// Neue Einträge anlegen.
        case new
        /// Einen vorhandenen Eintrag bearbeiten.
        case edit(FilterEntryItem)

        /// Kennung für SwiftUI.
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let item): return item.id.uuidString
            }
        }
    }

    /// Einträge dieser Liste.
    @State private var entries: [FilterEntryItem] = []
    /// Offenes Pop-up; `nil` = keines.
    @State private var editor: EditorRequest?
    /// Eingabe im Pop-up.
    @State private var editorText = ""
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?
    /// Einziger Rückfragekanal der Ansicht (Löschen).
    @State private var activeConfirmation: ConfirmationRequest?
    /// Hinzufügen oder Speichern läuft.
    @State private var isWorking = false
    /// Textdatei der Liste für das Teilen-Menü; `nil` bei leerer Liste.
    @State private var exportURL: URL?
    /// Dateiauswahl für den Import geöffnet.
    @State private var showingImporter = false
    /// Schließt die Unteransicht („<“ auf dem Mac).
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    /// Datei für „Als Datei sichern …“; `nil` = Dialog nicht offen.
    @State private var exportDocument: FilterListTextFile?
    #endif

    /// Name dieser Liste – für Rückfragen.
    private var listName: String { list == .white ? "Whitelist" : "Blacklist" }

    /// Name der anderen Liste – für Hinweise auf Konflikte.
    private var otherListName: String { list == .white ? "Blacklist" : "Whitelist" }

    /// „Neuer Eintrag …“, Einträge mit Kontextmenü; Importieren und Teilen
    /// in der Symbolleiste.
    var body: some View {
        listContainer {
            Section {
                Button {
                    editorText = ""
                    editor = .new
                } label: {
                    Label("Neuer Eintrag …", systemImage: "plus.circle")
                }
                .disabled(isWorking)
            } footer: {
                Text("Mehrere Angaben auf einmal sind möglich. Eine Domain wie „*firma.de“ gilt für alle Absender dieser Domain und ihrer Subdomains (z. B. „news.firma.de“), eine Adresse nur für genau diesen Absender. Bearbeiten und Löschen per langem Drücken auf einen Eintrag.")
            }
            .cardRowBackground()

            Section {
                if entries.isEmpty {
                    Text("Noch keine Einträge")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            } header: {
                Text("\(entries.count) Einträge")
            }
            .cardRowBackground()
        }
        .appBackground()
        .navigationTitle(list == .white ? "Whitelist" : "Blacklist")
        #if os(macOS)
        .navigationBarBackButtonHidden(true)
        #endif
        .macSheetHeader(listName) {
            HeaderCircleButton.back { dismiss() }
        } trailing: {
            HeaderCircleButton(
                title: "Importieren",
                systemImage: "square.and.arrow.down",
                help: "Einträge aus einer Textdatei importieren",
                isEnabled: !isWorking
            ) {
                showingImporter = true
            }
            #if os(macOS)
            // Ein Knopf wie auf iOS: „Als Datei sichern …“ und „Teilen“ in
            // einem Menü – das Teilen-Menü des Mac kennt kein Sichern.
            Menu {
                Button {
                    exportDocument = FilterListTextFile(text: FilterListExporter.text(for: entries))
                } label: {
                    Label("Als Datei sichern …", systemImage: "arrow.down.doc")
                }
                if let exportURL {
                    ShareLink(
                        item: exportURL,
                        preview: SharePreview(FilterListExporter.filename(for: list))
                    ) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                HeaderCircleLabel(systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(entries.isEmpty)
            .opacity(entries.isEmpty ? 0.4 : 1)
            .help("Liste exportieren – als Datei sichern oder teilen")
            .accessibilityLabel("Liste exportieren")
            #endif
        }
        #if !os(macOS)
        .toolbar {
            ToolbarItem {
                Button {
                    showingImporter = true
                } label: {
                    Label("Importieren", systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking)
            }
            ToolbarItem {
                if let exportURL {
                    ShareLink(
                        item: exportURL,
                        preview: SharePreview(FilterListExporter.filename(for: list))
                    ) {
                        Label("Liste teilen", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        #endif
        #if os(macOS)
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: (FilterListExporter.filename(for: list) as NSString).deletingPathExtension
        ) { result in
            if case .failure(let error) = result {
                activeAlert = .failure("Liste nicht gesichert", error)
            }
        }
        #endif
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .text]
        ) { result in
            prepareImport(result)
        }
        .alert(
            editorTitle,
            isPresented: Binding(
                get: { editor != nil },
                set: { if !$0 { editor = nil } }
            ),
            presenting: editor
        ) { request in
            TextField("Adresse oder Domain", text: $editorText)
                .emailInput()
            Button("Abbrechen", role: .cancel) {}
            Button(saveLabel(for: request)) {
                Task { await submit(request) }
            }
            .disabled(editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { request in
            Text(editorMessage(for: request))
        }
        .confirmationRequest($activeConfirmation)
        .task { await reload() }
        .onReceive(FilterListCloudEvents.remoteChangesImported) {
            Task { await reload() }
        }
        .alertItem($activeAlert)
    }

    /// Behälter der Abschnitte: auf iPhone/iPad eine Liste, auf dem Mac ein
    /// gruppiertes Formular (Karten wie iOS).
    ///
    /// - Parameter content: Abschnitte.
    /// - Returns: Liste bzw. Formular.
    private func listContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let sections = content()
        #if os(macOS)
        return Form { sections }
            .macGroupedForm()
        #else
        return List { sections }
        #endif
    }

    // MARK: - Zeilen

    /// Ein Eintrag: Symbol, Wert und Art. Langes Drücken (Mac: Rechtsklick)
    /// öffnet „Bearbeiten“ und „Löschen“; Wischen löscht ebenfalls – beides
    /// mit Rückfrage. Antippen allein bewirkt bewusst nichts, damit beim
    /// Scrollen nichts versehentlich geöffnet wird.
    ///
    /// - Parameter entry: Eintrag.
    /// - Returns: Die Zeile.
    private func entryRow(_ entry: FilterEntryItem) -> some View {
        HStack {
            Image(systemName: entry.kind == .domain ? "globe" : "person")
                .foregroundStyle(.secondary)
            Text(FilterDomain.display(entry.value, kind: entry.kind))
            Spacer()
            Text(entry.kind == .domain ? "Domain" : "Adresse")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                editorText = FilterListEditing.editText(for: entry)
                editor = .edit(entry)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmDelete(entry)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Ohne Rolle „destruktiv“: Die Zeile soll erst nach der
            // Rückfrage verschwinden.
            Button {
                confirmDelete(entry)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            .tint(.red)
        }
        .disabled(isWorking)
    }

    // MARK: - Pop-up

    /// Titel des Pop-ups.
    private var editorTitle: String {
        switch editor {
        case .edit: return "Eintrag bearbeiten"
        case .new, nil: return "Neuer Eintrag"
        }
    }

    /// Beschriftung des bestätigenden Knopfs.
    ///
    /// - Parameter request: Offenes Pop-up.
    /// - Returns: „Hinzufügen“ bzw. „Speichern“.
    private func saveLabel(for request: EditorRequest) -> String {
        switch request {
        case .new: return "Hinzufügen"
        case .edit: return "Speichern"
        }
    }

    /// Erklärung im Pop-up.
    ///
    /// - Parameter request: Offenes Pop-up.
    /// - Returns: Hinweistext.
    private func editorMessage(for request: EditorRequest) -> String {
        switch request {
        case .new:
            return "Adresse oder Domain, z. B. „anna@firma.de“ oder „firma.de“ (gilt samt Subdomains). Mehrere getrennt durch Komma oder Leerzeichen."
        case .edit:
            return "Z. B. „*news.firma.de“ auf „*firma.de“ kürzen – dann gilt der Eintrag für die ganze Domain samt Subdomains."
        }
    }

    /// Führt das Pop-up aus: anlegen bzw. speichern.
    ///
    /// - Parameter request: Offenes Pop-up.
    private func submit(_ request: EditorRequest) async {
        let text = editorText
        switch request {
        case .new:
            await addEntries(text)
        case .edit(let item):
            await saveEdit(of: item, input: text)
        }
    }

    // MARK: - Aktionen

    /// Meldet einen Fehler der Listenpflege.
    ///
    /// - Parameter error: Aufgetretener Fehler.
    private func report(_ error: Error) {
        activeAlert = .failure("Listenpflege fehlgeschlagen", error)
    }

    /// Lädt die Einträge dieser Liste und erneuert die Exportdatei.
    private func reload() async {
        do {
            entries = try await repository.entries().filter { $0.list == list }
            updateExportFile()
        } catch {
            report(error)
        }
    }

    /// Hält die Textdatei für das Teilen-Menü aktuell. Geteilt wird eine
    /// Datei und kein reiner Text, damit sich die Liste auch als Anhang
    /// per Mail versenden lässt.
    private func updateExportFile() {
        guard !entries.isEmpty else {
            exportURL = nil
            return
        }
        do {
            exportURL = try FilterListExporter.writeTemporaryFile(for: entries, list: list)
        } catch {
            exportURL = nil
            Log.spam.error("⚠️ Export der Liste fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fügt die eingegebenen Einträge hinzu.
    ///
    /// Verarbeitung: Einträge, die schon auf der anderen Liste stehen,
    /// werden gesammelt und im Ergebnis benannt; ein anderer Fehler bricht
    /// ab und erscheint als Meldung. Das Ergebnis erscheint als kurze
    /// Meldung.
    ///
    /// - Parameter text: Eingabe aus dem Pop-up.
    private func addEntries(_ text: String) async {
        isWorking = true
        defer { isWorking = false }

        let parsed = FilterListInput.parse(text)
        guard let outcome = await add(parsed.entries) else { return }
        activeAlert = AlertItem(
            title: "Neuer Eintrag",
            message: summary(added: outcome.added, invalid: parsed.invalid, conflicts: outcome.conflicts)
        )
    }

    /// Trägt Einträge in diese Liste ein.
    ///
    /// Verarbeitung: Einträge, die schon auf der anderen Liste stehen,
    /// werden gesammelt; ein anderer Fehler bricht ab, erscheint als
    /// Meldung und liefert `nil`. Danach wird die Liste neu geladen.
    ///
    /// - Parameter entries: Erkannte Einträge.
    /// - Returns: Anzahl eingetragener Einträge und abgelehnte Angaben;
    ///   `nil` nach einem Fehler.
    private func add(_ entries: [FilterListInputEntry]) async -> (added: Int, conflicts: [String])? {
        var added = 0
        var conflicts: [String] = []
        for entry in entries {
            do {
                try await repository.add(entry.value, kind: entry.kind, to: list)
                added += 1
            } catch FilterListError.alreadyOnOtherList {
                conflicts.append(FilterDomain.display(entry.value, kind: entry.kind))
            } catch {
                report(error)
                await reload()
                return nil
            }
        }
        await reload()
        return (added, conflicts)
    }

    // MARK: - Import

    /// Liest den Text einer gewählten Datei.
    ///
    /// Verarbeitung: Die Datei liegt außerhalb der App (z. B. iCloud Drive)
    /// und wird nur für das Lesen freigegeben. Ist sie nicht lesbar oder
    /// keine Textdatei, erscheint eine Meldung.
    ///
    /// - Parameter url: Gewählte Datei.
    /// - Returns: Text oder `nil` (Meldung ist dann gesetzt).
    private func readImportFile(_ url: URL) -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let text = FilterListImport.text(from: try Data(contentsOf: url)) else {
                activeAlert = AlertItem(title: "Import", message: "Die Datei „\(url.lastPathComponent)“ ist keine lesbare Textdatei.")
                return nil
            }
            return text
        } catch {
            activeAlert = .failure("Import", error)
            return nil
        }
    }

    /// Liest die gewählte Datei und fragt vor dem Import nach.
    ///
    /// Verarbeitung: Lesen übernimmt `readImportFile`, die Auswertung
    /// `FilterListImport` (Plan, Texte). Enthält die Datei nichts Neues,
    /// erscheint gleich die Zusammenfassung; sonst nennt die Rückfrage die
    /// Zahl der neuen Einträge.
    ///
    /// - Parameter result: Ergebnis der Dateiauswahl.
    private func prepareImport(_ result: Result<URL, Error>) {
        let url: URL
        switch result {
        case .success(let picked): url = picked
        case .failure(let error):
            report(error)
            return
        }
        guard let text = readImportFile(url) else { return }

        let plan = FilterListImport.plan(text: text, existing: entries)
        guard !plan.entries.isEmpty else {
            activeAlert = AlertItem(
                title: "Import",
                message: FilterListImport.summary(
                    FilterListImport.Outcome(alreadyPresent: plan.alreadyPresent.count, invalid: plan.invalid),
                    otherListName: otherListName
                )
            )
            return
        }

        activeConfirmation = ConfirmationRequest(
            title: "In die \(listName) importieren?",
            message: FilterListImport.confirmationMessage(for: plan, fileName: url.lastPathComponent),
            confirmLabel: "Importieren",
            isDestructive: false
        ) {
            Task { await runImport(plan) }
        }
    }

    /// Trägt die neuen Einträge eines Imports ein und meldet das Ergebnis.
    ///
    /// - Parameter plan: Vorbereiteter Import.
    private func runImport(_ plan: FilterListImport.Plan) async {
        isWorking = true
        defer { isWorking = false }
        guard let outcome = await add(plan.entries) else { return }
        activeAlert = AlertItem(
            title: "Import",
            message: FilterListImport.summary(
                FilterListImport.Outcome(
                    added: outcome.added, alreadyPresent: plan.alreadyPresent.count,
                    conflicts: outcome.conflicts, invalid: plan.invalid
                ),
                otherListName: otherListName
            )
        )
    }

    /// Speichert einen bearbeiteten Eintrag.
    ///
    /// Verarbeitung: Prüft die Eingabe (`FilterListEditing.plan`).
    /// Unverändert: nichts zu tun. Ungültig oder mehrere Angaben: Hinweis,
    /// der Eintrag bleibt. Sonst wird der neue Wert wie beim Anlegen
    /// eingetragen und erst danach der alte entfernt – steht der neue Wert
    /// auf der anderen Liste, bleibt der alte erhalten.
    ///
    /// - Parameters:
    ///   - item: Bisheriger Eintrag.
    ///   - input: Eingabe aus dem Pop-up.
    private func saveEdit(of item: FilterEntryItem, input: String) async {
        switch FilterListEditing.plan(editing: item, input: input) {
        case .unchanged:
            return
        case .invalid:
            activeAlert = AlertItem(
                title: "Nicht gespeichert",
                message: "„\(input)“ ist keine gültige Adresse oder Domain. Der Eintrag bleibt unverändert."
            )
        case .multiple:
            activeAlert = AlertItem(
                title: "Nicht gespeichert",
                message: "Beim Bearbeiten ist genau eine Adresse oder Domain möglich. Weitere Einträge über „Neuer Eintrag …“."
            )
        case .replace(let entry):
            isWorking = true
            defer { isWorking = false }
            do {
                try await FilterListEditing.save(entry, replacing: item, in: repository)
            } catch FilterListError.alreadyOnOtherList {
                activeAlert = AlertItem(
                    title: "Nicht gespeichert",
                    message: "„\(FilterDomain.display(entry.value, kind: entry.kind))“ steht bereits auf der \(otherListName). Der Eintrag bleibt unverändert."
                )
            } catch {
                report(error)
            }
            await reload()
        }
    }

    /// Fragt vor dem Löschen eines Eintrags nach.
    ///
    /// - Parameter entry: Zu löschender Eintrag.
    private func confirmDelete(_ entry: FilterEntryItem) {
        activeConfirmation = ConfirmationRequest(
            title: "„\(FilterDomain.display(entry.value, kind: entry.kind))“ löschen?",
            message: "Der Eintrag wird von der \(list == .white ? "Whitelist" : "Blacklist") entfernt – auf allen Geräten.",
            confirmLabel: "Löschen"
        ) {
            Task { await delete(entry) }
        }
    }

    /// Löscht einen Eintrag.
    ///
    /// - Parameter entry: Zu löschender Eintrag.
    private func delete(_ entry: FilterEntryItem) async {
        do {
            try await repository.remove(entry.id)
        } catch {
            report(error)
        }
        await reload()
    }

    /// Fasst zusammen, was beim Hinzufügen passiert ist. Abgelehnte Einträge
    /// werden benannt, damit klar ist, was noch zu tun ist.
    ///
    /// - Parameters:
    ///   - added: Anzahl übernommener Einträge.
    ///   - invalid: Nicht verwertbare Angaben.
    ///   - conflicts: Angaben, die schon auf der anderen Liste stehen.
    /// - Returns: Zusammenfassung für die Anzeige.
    private func summary(added: Int, invalid: [String], conflicts: [String]) -> String {
        var parts: [String] = []
        if added > 0 {
            parts.append(added == 1 ? "1 Eintrag hinzugefügt" : "\(added) Einträge hinzugefügt")
        }
        if !conflicts.isEmpty {
            parts.append("Bereits auf der \(otherListName): \(conflicts.joined(separator: ", "))")
        }
        if !invalid.isEmpty {
            parts.append("Nicht verwertbar: \(invalid.joined(separator: ", "))")
        }
        return parts.isEmpty ? "Nichts hinzugefügt" : parts.joined(separator: "\n")
    }
}

#Preview {
    NavigationStack {
        FilterListView(list: .white, repository: InMemoryFilterListRepository())
    }
}

#if os(macOS)
/// Textdatei einer Filterliste für den Sichern-Dialog des Mac
/// (`fileExporter`). Inhalt im Format des Exports (FilterListExporter).
nonisolated private struct FilterListTextFile: FileDocument {
    /// Lesbare Dateiarten – nur zum Erfüllen des Protokolls.
    static var readableContentTypes: [UTType] { [.plainText] }

    /// Inhalt der Datei.
    let text: String

    /// Legt die Datei mit fertigem Text an.
    ///
    /// - Parameter text: Liste im Exportformat.
    init(text: String) {
        self.text = text
    }

    /// Liest eine Datei (vom Protokoll verlangt, hier nicht genutzt).
    ///
    /// - Parameter configuration: Lesekonfiguration des Systems.
    /// - Throws: `CocoaError.fileReadCorruptFile`, wenn kein UTF-8-Text.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    /// Schreibt den Text als UTF-8.
    ///
    /// - Parameter configuration: Schreibkonfiguration des Systems.
    /// - Returns: Dateiinhalt.
    /// - Throws: Nie; `throws` verlangt das Protokoll `FileDocument`.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
#endif
