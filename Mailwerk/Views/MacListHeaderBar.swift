//
//  MacListHeaderBar.swift
//  Mailwerk
//
//  Zweck: Kopf der Mailliste auf dem Mac – ein gewöhnlicher View statt
//  Einträgen der System-Symbolleiste. Dadurch fasst macOS keine Knöpfe
//  unter „»“ zusammen, und beim Mailwechsel flackert nichts.
//
//  Von oben nach unten, auf Nebelblau:
//  1. Knöpfe: Ordnerleiste, Aktualisieren (zeigt während des Abrufs
//     selbst den Kreisel), Sortieren (bei geänderter Sortierung blauer
//     Kreis), Suchen (blauer Kreis – Wiedererkennungsmerkmal), Neue Mail;
//     rechts außen Einstellungen. Alle als Kreise 32 × 32 pt.
//     Im Auswahlmodus ersetzt dieselbe Zeile „Alle auswählen / Auswahl
//     aufheben“, „n ausgewählt“ und „Fertig“ (gleiche Höhe, kein Springen).
//  2. Titel der Ansicht (bei einem Ordner mit Farbpunkt des Postfachs),
//     darunter klein Stand bzw. Verbindungshinweis; minütlich neu.
//  3. Suchfeld (MacSearchField) – nur solange die Suche aktiv ist.
//
//  Pfeile für vorige/nächste Mail gibt es auf dem Mac nicht;
//  weitergeschaltet wird mit den Pfeiltasten bzw. dem Menü „Postfach“.
//
//  Die Kürzel (⌘R, ⌘F, ⌘N) tragen die Menübefehle (InboxCommands); an den
//  Knöpfen stehen sie nur im Tooltip, sonst kollidierten beide.
//
//  Abgrenzung: Aktionen und Zustand liefert der Aufrufer (InboxView);
//  Suchfeld → MacSearchField; Kreisknöpfe → SheetHeaderBar.swift.
//
//  Abhängigkeiten: SwiftUI, HeaderCircleButton, HeaderCircleLabel,
//  MacSearchField, SearchViewModel, AppTheme.
//

#if os(macOS)
import SwiftUI

/// Zustand des Auswahlmodus für den Kopf der Mailliste (Mac).
struct MacListSelectionState {
    /// Alle Mails sind ausgewählt.
    let isAllSelected: Bool
    /// Anzahl ausgewählter Mails.
    let count: Int
    /// „Alle auswählen“ bzw. „Auswahl aufheben“.
    let onToggleAll: () -> Void
    /// „Fertig“ – beendet den Auswahlmodus.
    let onDone: () -> Void
}

/// Kopf der Mailliste (Mac): Knöpfe, Titel mit Stand, Suchfeld.
struct MacListHeaderBar<SortMenu: View, SettingsMenu: View>: View {
    /// Titel der Ansicht.
    let title: String
    /// SF-Symbol der Ansicht.
    let systemImage: String
    /// Farbe des Postfachs bei einem einzelnen Ordner; sonst `nil`.
    let accountColor: Color?
    /// Text der Standzeile; wird minütlich neu gebildet. `nil` = keine
    /// Standzeile.
    let statusText: (() -> String)?
    /// `true`, wenn die Standzeile einen Verbindungshinweis trägt (orange).
    let statusIsWarning: Bool
    /// Auswahlmodus; `nil` = gewöhnliche Knopfzeile.
    let selection: MacListSelectionState?
    /// Ordnerleiste ein-/ausblenden bzw. öffnen.
    let onFolders: () -> Void
    /// Ein Abruf läuft.
    let isLoading: Bool
    /// Aktualisieren möglich (mindestens ein Postfach).
    let canRefresh: Bool
    /// Aktualisieren.
    let onRefresh: () -> Void
    /// Sortierung weicht vom Standard ab.
    let isSortChanged: Bool
    /// Suche öffnen.
    let onSearch: () -> Void
    /// Neue Mail möglich (mindestens ein Postfach).
    let canCompose: Bool
    /// Neue Mail.
    let onCompose: () -> Void
    /// Zustand der Suche (Suchfeld).
    let search: SearchViewModel
    /// Fokus-Anstoß für das Suchfeld.
    let searchFocusTrigger: Int
    /// Inhalt des Sortiermenüs.
    @ViewBuilder let sortMenu: () -> SortMenu
    /// Inhalt des Einstellungsmenüs.
    @ViewBuilder let settingsMenu: () -> SettingsMenu

    /// Höhe der Knopfzeile in Punkt.
    private static var buttonRowHeight: CGFloat { 44 }

    /// Kopf in drei Zeilen.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let selection {
                    selectionRow(selection)
                } else {
                    buttonRow
                }
            }
            .frame(height: Self.buttonRowHeight)

            titleBlock
                .padding(.bottom, search.isPresented ? 8 : 10)

            if search.isPresented {
                MacSearchField(search: search, focusTrigger: searchFocusTrigger)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background)
        .animation(.snappy(duration: 0.25), value: search.isPresented)
    }

    // MARK: - Zeile 1

    /// Knöpfe 1–5 links, Einstellungen rechts außen.
    private var buttonRow: some View {
        HStack(spacing: 10) {
            HeaderCircleButton(
                title: "Ordner",
                systemImage: "sidebar.left",
                help: "Ordnerleiste ein-/ausblenden (⌥⌘S)",
                action: onFolders
            )
            HeaderCircleButton(
                title: isLoading ? "Wird aktualisiert" : "Aktualisieren",
                systemImage: "arrow.clockwise",
                help: isLoading ? "Wird aktualisiert …" : "Aktualisieren (⌘R)",
                isBusy: isLoading,
                isEnabled: canRefresh,
                action: onRefresh
            )
            Menu {
                sortMenu()
            } label: {
                HeaderCircleLabel(
                    systemImage: "arrow.up.arrow.down",
                    style: isSortChanged ? .accent : .plain
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(isSortChanged ? "Sortieren (geändert)" : "Sortieren")
            .accessibilityLabel(isSortChanged ? "Sortieren, geändert" : "Sortieren")
            HeaderCircleButton(
                title: "Suchen",
                systemImage: "magnifyingglass",
                style: .accent,
                help: "Suchen (⌘F)",
                action: onSearch
            )
            HeaderCircleButton(
                title: "Neue E-Mail",
                systemImage: "square.and.pencil",
                help: "Neue E-Mail (⌘N)",
                isEnabled: canCompose,
                action: onCompose
            )
            Spacer(minLength: 8)
            Menu {
                settingsMenu()
            } label: {
                HeaderCircleLabel(systemImage: "gearshape")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Einstellungen")
            .accessibilityLabel("Einstellungen")
        }
    }

    /// Zeile im Auswahlmodus: „Alle auswählen“, Anzahl, „Fertig“.
    ///
    /// - Parameter selection: Zustand des Auswahlmodus.
    /// - Returns: Zeile in der Höhe der Knopfzeile.
    private func selectionRow(_ selection: MacListSelectionState) -> some View {
        HStack {
            Button(selection.isAllSelected ? "Auswahl aufheben" : "Alle auswählen") {
                selection.onToggleAll()
            }
            Spacer()
            Text("\(selection.count) ausgewählt")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Fertig") {
                selection.onDone()
            }
        }
    }

    // MARK: - Zeile 2

    /// Titel der Ansicht und darunter die Standzeile.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                if let accountColor {
                    Circle()
                        .fill(accountColor)
                        .frame(width: 9, height: 9)
                }
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
            }
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)

            if let statusText {
                // Minütlich neu, damit „vor 5 Minuten“ mitläuft.
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(statusText())
                        .font(.caption)
                        .foregroundStyle(statusIsWarning ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
