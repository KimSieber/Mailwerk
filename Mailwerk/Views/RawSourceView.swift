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
//  RawMessageFormatter; Menüeintrag → MessageDetailView.
//
//  Abhängigkeiten: SwiftUI, UIKit/AppKit, RawMessageService,
//  NetworkMonitor, ConnectionErrorClassifier, MailPrintFormatter
//  (Dateiname), PlatformSheetSize, Log.
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

    /// Aufbau: Inhalt je Zustand, oben Schließen, Kopieren und Teilen.
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Originalquelle")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
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
            MonospacedTextView(text: text)
        }
    }

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

#if os(macOS)
/// Nicht bearbeitbare, auswählbare Textansicht in Festbreitenschrift (macOS).
private struct MonospacedTextView: NSViewRepresentable {
    /// Anzuzeigender Text.
    let text: String

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

    /// Übernimmt einen geänderten Text.
    ///
    /// - Parameters:
    ///   - scrollView: Scrollansicht.
    ///   - context: Kontext.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? NSTextView, textView.string != text {
            textView.string = text
        }
    }
}
#else
/// Nicht bearbeitbare, auswählbare Textansicht in Festbreitenschrift (iOS).
private struct MonospacedTextView: UIViewRepresentable {
    /// Anzuzeigender Text.
    let text: String

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

    /// Übernimmt einen geänderten Text.
    ///
    /// - Parameters:
    ///   - textView: Textansicht.
    ///   - context: Kontext.
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
    }
}
#endif
