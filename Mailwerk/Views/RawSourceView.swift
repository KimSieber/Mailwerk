//
//  RawSourceView.swift
//  Mailwerk
//
//  Zweck: Blatt „Originalquelle“ – zeigt die Mail mit allen Kopfzeilen
//  sowie dem vollständigen Text- und HTML-Inhalt als reinen Text in
//  Festbreitenschrift. Für die Prüfung von Fehlern und die tiefere Analyse;
//  erreichbar über den letzten Eintrag im Menü der Mailansicht.
//
//  Der Text ist auswählbar. „Kopieren“ legt die ganze Quelle in die
//  Zwischenablage, „Teilen“ gibt sie als .txt-Datei weiter (keine .eml:
//  Anlagen sind ausgelassen). HTML wird nie dargestellt, aus der Mail wird
//  also nichts ausgeführt oder nachgeladen.
//
//  Suche: Über dem Text steht ein Suchfeld. Gesucht wird die Eingabe ohne
//  Rücksicht auf Groß- und Kleinschreibung (RawSourceSearch). Eingabetaste
//  bzw. „Weiter“ springt zum ersten Treffer, jedes weitere Mal zum
//  nächsten; nach dem letzten geht es wieder vorne los. Der aktuelle
//  Treffer ist gelb hinterlegt, daneben steht „2 von 5“ bzw. „Kein
//  Treffer“. Eine geänderte Eingabe beginnt die Suche neu.
//
//  Mac: Schließen (✕), Kopieren und Teilen stehen als Kreise in
//  einer festen Kopfleiste oben (SheetHeaderBar) statt in der
//  Symbolleiste.
//
//  Die Anzeige läuft über eine native Textansicht (UITextView bzw.
//  NSTextView) statt SwiftUI-`Text`: Quellen haben oft tausende Zeilen,
//  die eine Textansicht ohne Ruckeln scrollt.
//
//  Ohne Netz oder bei Mails über 5 MB erscheint ein Hinweis statt der
//  Quelle (RawMessageService.availability). Meldet das System das fehlende
//  Netz erst verzögert, zeigt der Verbindungsfehler beim Holen denselben
//  Hinweis (ConnectionErrorClassifier).
//
//  Abgrenzung: Abruf und Aufbereitung → RawMessageService,
//  RawMessageFormatter; Fundstellen → RawSourceSearch; Menüeintrag →
//  MessageDetailView.
//
//  Abhängigkeiten: SwiftUI, UIKit/AppKit, RawMessageService,
//  NetworkMonitor, ConnectionErrorClassifier, MailPrintFormatter
//  (Dateiname), RawSourceSearch, PlatformInputModifiers, PlatformSheetSize,
//  SheetHeaderBar, Log.
//

import SwiftUI
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Blatt mit der Originalquelle einer Mail.
struct RawSourceView: View {
    /// Mail, deren Quelle gezeigt wird.
    let message: CachedMessage
    /// Quelle für Postfach und Passwort.
    let accountStore: AccountStore

    @Environment(\.dismiss) private var dismiss

    /// Zustand des Blatts.
    private enum LoadState {
        /// Quelle wird geholt.
        case loading
        /// Quelle nicht verfügbar oder Fehler: Titel, Erklärung, Symbol.
        case unavailable(title: String, detail: String, systemImage: String)
        /// Quelle geladen.
        case loaded(String)
    }

    /// Aktueller Zustand.
    @State private var state: LoadState = .loading
    /// Quelle als temporäre .txt-Datei zum Teilen.
    @State private var fileURL: URL?
    /// `true` kurz nach dem Kopieren (Häkchen statt Kopiersymbol).
    @State private var didCopy = false
    /// Eingabe im Suchfeld.
    @State private var query = ""
    /// Begriff, zu dem `matches` gehört; `nil` = noch nicht gesucht.
    @State private var searchedQuery: String?
    /// Fundstellen zu `searchedQuery`.
    @State private var matches: [NSRange] = []
    /// Index des gezeigten Treffers in `matches`; `nil` = keiner.
    @State private var matchIndex: Int?

    /// Aufbau: Inhalt je Zustand, oben Schließen, Kopieren und Teilen.
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Originalquelle")
                .macSheetHeader("Originalquelle") {
                    HeaderCircleButton.cancel("Schließen") { dismiss() }
                } trailing: {
                    macHeaderTrailing
                }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                #endif
        }
        .macSheetFrame(.composer)
        .task { await load() }
    }

    /// Inhalt je Zustand.
    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Quelle wird geladen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let title, let detail, let systemImage):
            ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
        case .loaded(let text):
            VStack(spacing: 0) {
                searchBar(in: text)
                Divider()
                MonospacedTextView(text: text, highlight: currentMatch)
            }
        }
    }

    // MARK: - Suche

    /// Suchfeld, Trefferanzeige und „Weiter“ über dem Text.
    ///
    /// - Parameter text: Durchsuchte Quelle.
    /// - Returns: Die Suchleiste.
    private func searchBar(in text: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("In Quelle suchen", text: $query)
                    .textFieldStyle(.plain)
                    .plainTextInput()
                    .submitLabel(.search)
                    .onSubmit { findNext(in: text) }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suche leeren")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            if let searchStatus {
                Text(searchStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            Button("Weiter") {
                findNext(in: text)
            }
            .disabled(query.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        // Eine geänderte Eingabe beginnt die Suche neu.
        .onChange(of: query) {
            searchedQuery = nil
            matches = []
            matchIndex = nil
        }
    }

    /// Gezeigter Treffer; `nil` = keiner.
    private var currentMatch: NSRange? {
        guard let matchIndex, matches.indices.contains(matchIndex) else { return nil }
        return matches[matchIndex]
    }

    /// „2 von 5“, „Kein Treffer“ oder nichts, solange nicht gesucht wurde.
    private var searchStatus: String? {
        guard let searchedQuery, searchedQuery == query else { return nil }
        guard let matchIndex else { return "Kein Treffer" }
        return "\(matchIndex + 1) von \(matches.count)"
    }

    /// Springt zum nächsten Treffer.
    ///
    /// Verarbeitung: Beim ersten Mal (bzw. nach geänderter Eingabe) werden
    /// die Fundstellen ermittelt und der erste Treffer gezeigt, danach je
    /// der nächste; nach dem letzten wieder der erste.
    ///
    /// - Parameter text: Durchsuchte Quelle.
    private func findNext(in text: String) {
        guard !query.isEmpty else { return }
        if searchedQuery != query {
            matches = RawSourceSearch.matches(of: query, in: text)
            searchedQuery = query
            matchIndex = RawSourceSearch.nextIndex(after: nil, count: matches.count)
        } else {
            matchIndex = RawSourceSearch.nextIndex(after: matchIndex, count: matches.count)
        }
    }

    /// Kopieren und Teilen als Kreise der Mac-Kopfleiste, sobald die Quelle
    /// da ist.
    @ViewBuilder
    private var macHeaderTrailing: some View {
        if case .loaded(let text) = state {
            HeaderCircleButton(
                title: "Quelle kopieren",
                systemImage: didCopy ? "checkmark" : "doc.on.doc",
                help: "Kopieren"
            ) {
                copy(text)
            }
            if let fileURL {
                ShareLink(item: fileURL) {
                    HeaderCircleLabel(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Teilen")
                .accessibilityLabel("Quelle als Textdatei teilen")
            }
        }
    }

    #if os(iOS)
    /// Schließen links; Kopieren und Teilen rechts, sobald die Quelle da ist.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Schließen")
        }
        if case .loaded(let text) = state {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copy(text)
                } label: {
                    Label("Kopieren", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .accessibilityLabel("Quelle kopieren")
            }
            if let fileURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: fileURL) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Quelle als Textdatei teilen")
                }
            }
        }
    }
    #endif

    // MARK: - Laden

    /// Prüft die Voraussetzungen und holt die Quelle.
    ///
    /// Verarbeitung: Ohne Netz oder bei zu großer Mail erscheint ein
    /// Hinweis, ohne den Server zu fragen. Sonst wird die Quelle geholt
    /// und für das Teilen als Datei abgelegt. Ein Verbindungsfehler zeigt
    /// denselben Hinweis wie fehlendes Netz; jeder andere Fehler erscheint
    /// mit seinem Text im Blatt selbst.
    @MainActor
    private func load() async {
        guard case .loading = state else { return }
        let availability = RawMessageService.availability(
            sizeBytes: message.totalSizeBytes,
            isOnline: NetworkMonitor.shared.isOnline
        )
        switch availability {
        case .offline:
            state = Self.offlineState
            return
        case .tooLarge:
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(message.totalSizeBytes), countStyle: .file
            )
            state = .unavailable(
                title: "Mail zu groß",
                detail: "Die Originalquelle wird nur für Mails bis 5 MB angezeigt. Diese Mail hat \(size).",
                systemImage: "doc.badge.ellipsis"
            )
            return
        case .available:
            break
        }

        do {
            let text = try await RawMessageService.fetchSource(of: message, accountStore: accountStore)
            fileURL = writeFile(text)
            state = .loaded(text)
        } catch {
            Log.view.error("⚠️ Originalquelle nicht geholt: \(error.localizedDescription, privacy: .public)")
            if ConnectionErrorClassifier.isConnectionError(error) {
                // Der Netzstatus meldet ein fehlendes Netz manchmal erst
                // verzögert (z. B. direkt nach dem Flugmodus); dann zeigt
                // sich das erst hier, beim Verbindungsaufbau.
                state = Self.offlineState
            } else {
                state = .unavailable(
                    title: "Quelle nicht geladen",
                    detail: error.localizedDescription,
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    /// Hinweis ohne Verbindung – bei fehlendem Netz vorab ebenso wie bei
    /// einem Verbindungsfehler beim Holen.
    private static let offlineState = LoadState.unavailable(
        title: "Nur mit Internetverbindung verfügbar",
        detail: "Die Originalquelle wird bei Bedarf vom Server geladen.",
        systemImage: "wifi.slash"
    )

    /// Legt die Quelle als temporäre .txt-Datei ab, benannt nach dem
    /// Betreff.
    ///
    /// - Parameter text: Aufbereitete Quelle.
    /// - Returns: URL der Datei; `nil`, wenn sie sich nicht schreiben
    ///   ließ (Teilen entfällt dann, Anzeigen und Kopieren gehen weiter).
    private func writeFile(_ text: String) -> URL? {
        let name = MailPrintFormatter.filename(forSubject: message.subject) + " – Quelle.txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            Log.view.error("⚠️ Quelle als Datei nicht geschrieben: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Kopieren

    /// Legt die ganze Quelle in die Zwischenablage und zeigt kurz ein
    /// Häkchen.
    ///
    /// - Parameter text: Aufbereitete Quelle.
    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

// MARK: - Textansicht

/// Hinterlegung des aktuellen Treffers: Gelb mit schwarzer Schrift, damit
/// er auch im Dunkelmodus lesbar ist.
private enum MatchStyle {
    #if os(macOS)
    static let attributes: [NSAttributedString.Key: Any] = [
        .backgroundColor: NSColor.systemYellow,
        .foregroundColor: NSColor.black,
    ]
    #else
    static let attributes: [NSAttributedString.Key: Any] = [
        .backgroundColor: UIColor.systemYellow,
        .foregroundColor: UIColor.black,
    ]
    #endif
}

#if os(macOS)
/// Nicht bearbeitbare, auswählbare Textansicht in Festbreitenschrift (macOS).
private struct MonospacedTextView: NSViewRepresentable {
    /// Anzuzeigender Text.
    let text: String
    /// Hervorzuhebender Treffer der Suche; `nil` = keiner.
    var highlight: NSRange?

    /// Merkt sich den hervorgehobenen Treffer, um ihn wieder zu lösen.
    final class Coordinator {
        /// Zuletzt hervorgehobener Treffer.
        var highlighted: NSRange?
    }

    /// Legt den Merker an.
    ///
    /// - Returns: Merker.
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Legt eine scrollbare Textansicht an.
    ///
    /// - Parameter context: Kontext.
    /// - Returns: Scrollansicht mit der Textansicht.
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.string = text
        }
        return scrollView
    }

    /// Übernimmt einen geänderten Text und den hervorgehobenen Treffer.
    ///
    /// Verarbeitung: Der alte Treffer verliert die Hinterlegung, der neue
    /// bekommt sie und wird in den sichtbaren Bereich gescrollt.
    ///
    /// - Parameters:
    ///   - scrollView: Scrollansicht.
    ///   - context: Kontext.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.highlighted = nil
        }
        guard context.coordinator.highlighted != highlight else { return }
        let length = storage.length
        if let old = context.coordinator.highlighted, NSMaxRange(old) <= length {
            storage.removeAttribute(.backgroundColor, range: old)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: old)
        }
        context.coordinator.highlighted = nil
        if let highlight, NSMaxRange(highlight) <= length {
            storage.addAttributes(MatchStyle.attributes, range: highlight)
            textView.scrollRangeToVisible(highlight)
            context.coordinator.highlighted = highlight
        }
    }
}
#else
/// Nicht bearbeitbare, auswählbare Textansicht in Festbreitenschrift (iOS).
private struct MonospacedTextView: UIViewRepresentable {
    /// Anzuzeigender Text.
    let text: String
    /// Hervorzuhebender Treffer der Suche; `nil` = keiner.
    var highlight: NSRange?

    /// Merkt sich den hervorgehobenen Treffer, um ihn wieder zu lösen.
    final class Coordinator {
        /// Zuletzt hervorgehobener Treffer.
        var highlighted: NSRange?
    }

    /// Legt den Merker an.
    ///
    /// - Returns: Merker.
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Legt die Textansicht an; die Schrift folgt der Textgröße des Systems.
    ///
    /// - Parameter context: Kontext.
    /// - Returns: Textansicht.
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.dataDetectorTypes = []
        textView.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .monospacedSystemFont(ofSize: 12, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.text = text
        return textView
    }

    /// Übernimmt einen geänderten Text und den hervorgehobenen Treffer.
    ///
    /// Verarbeitung: Der alte Treffer verliert die Hinterlegung, der neue
    /// bekommt sie und wird in den sichtbaren Bereich gescrollt.
    ///
    /// - Parameters:
    ///   - textView: Textansicht.
    ///   - context: Kontext.
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
            context.coordinator.highlighted = nil
        }
        guard context.coordinator.highlighted != highlight else { return }
        let storage = textView.textStorage
        let length = storage.length
        if let old = context.coordinator.highlighted, NSMaxRange(old) <= length {
            storage.removeAttribute(.backgroundColor, range: old)
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: old)
        }
        context.coordinator.highlighted = nil
        if let highlight, NSMaxRange(highlight) <= length {
            storage.addAttributes(MatchStyle.attributes, range: highlight)
            textView.scrollRangeToVisible(highlight)
            context.coordinator.highlighted = highlight
        }
    }
}
#endif
