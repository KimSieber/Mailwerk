//
//  MacSearchField.swift
//  Mailwerk
//
//  Zweck: Eigenes Suchfeld der Mailliste auf dem Mac. `.searchable` ist
//  auf dem Mac an die Symbolleiste des Fensters gebunden, die es dort nicht mehr gibt; dieses Feld bietet dieselben
//  Funktionen wie das Suchfeld von iPhone/iPad:
//  - Freitext (`SearchViewModel.text`),
//  - eine gewählte Person als Marke im Feld (`tokens`, mit ✕ entfernbar,
//    ⌫ im leeren Feld entfernt sie ebenfalls),
//  - Namensvorschläge unter dem Feld (`suggestions`): Auswahl per Klick
//    oder mit ↑/↓ und Return.
//
//  Esc bzw. das ✕ rechts im Feld beenden die Suche (`isPresented = false`)
//  – die Liste steht wieder wie vorher. Das Feld erhält beim Erscheinen
//  und bei jedem erneuten Öffnen (⌘F, Lupe) den Fokus (`focusTrigger`).
//
//  Die Logik der Suche bleibt unverändert im SearchViewModel; hier ist nur
//  die Anzeige.
//
//  Abgrenzung: Einbindung in die Kopfzeilen der Liste → MacListHeaderBar,
//  InboxView.
//
//  Abhängigkeiten: SwiftUI, SearchViewModel, SearchPerson, AppTheme.
//

#if os(macOS)
import SwiftUI

/// Suchfeld mit Personen-Marke und Namensvorschlägen (Mac).
struct MacSearchField: View {
    /// Zustand der Suche.
    @Bindable var search: SearchViewModel
    /// Ändert sich der Wert, erhält das Feld den Fokus (⌘F, Lupe).
    let focusTrigger: Int

    /// Fokus im Textfeld.
    @FocusState private var isFocused: Bool
    /// Per Pfeiltaste hervorgehobener Vorschlag; `nil` = keiner.
    @State private var highlighted: Int?

    /// Höchstzahl gezeigter Vorschläge.
    private static let maxSuggestions = 6

    /// Feld und darunter die Vorschläge.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field
            if !visibleSuggestions.isEmpty {
                suggestionList
            }
        }
        .onAppear { focusSoon() }
        .onChange(of: focusTrigger) { focusSoon() }
        .onChange(of: search.suggestions) { highlighted = nil }
    }

    /// Gezeigte Vorschläge (höchstens `maxSuggestions`).
    private var visibleSuggestions: [SearchPerson] {
        Array(search.suggestions.prefix(Self.maxSuggestions))
    }

    // MARK: - Feld

    /// Lupe, Marke, Textfeld und ✕ in einer abgerundeten Karte.
    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if let person = search.tokens.first {
                tokenChip(person)
            }
            TextField(search.tokens.isEmpty ? "Suchen" : "", text: $search.text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { selectHighlighted() }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                .onKeyPress(.delete) {
                    // ⌫ im leeren Feld entfernt die Marke.
                    guard search.text.isEmpty, !search.tokens.isEmpty else { return .ignored }
                    search.tokens = []
                    return .handled
                }
                .accessibilityLabel("Suchen")
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Suche beenden (Esc)")
            .accessibilityLabel("Suche beenden")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08))
        }
    }

    /// Marke der gewählten Person mit ✕ zum Entfernen.
    ///
    /// - Parameter person: Gewählte Person.
    /// - Returns: Kapsel mit Name.
    private func tokenChip(_ person: SearchPerson) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.caption)
            Text(person.title)
                .lineLimit(1)
            Button {
                search.tokens = []
                focusSoon()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Person entfernen")
        }
        .font(.callout)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
    }

    // MARK: - Vorschläge

    /// Namensvorschläge als Karte unter dem Feld.
    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleSuggestions.enumerated()), id: \.element.id) { index, person in
                Button {
                    select(person)
                } label: {
                    MacSuggestionRow(person: person)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == highlighted ? Color.accentColor.opacity(0.16) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < visibleSuggestions.count - 1 {
                    Divider()
                }
            }
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Abläufe

    /// Setzt den Fokus ins Feld – einen Durchlauf später, damit das Feld
    /// beim Einblenden schon steht.
    private func focusSoon() {
        Task { @MainActor in
            isFocused = true
        }
    }

    /// Bewegt die Hervorhebung in den Vorschlägen.
    ///
    /// - Parameter step: +1 = nach unten, −1 = nach oben.
    /// - Returns: `.handled`, wenn Vorschläge da sind; sonst `.ignored`.
    private func moveHighlight(by step: Int) -> KeyPress.Result {
        let count = visibleSuggestions.count
        guard count > 0 else { return .ignored }
        if let current = highlighted {
            let next = current + step
            highlighted = next < 0 ? nil : min(next, count - 1)
        } else if step > 0 {
            highlighted = 0
        }
        return .handled
    }

    /// Return: übernimmt den hervorgehobenen Vorschlag als Marke.
    private func selectHighlighted() {
        guard let index = highlighted, visibleSuggestions.indices.contains(index) else { return }
        select(visibleSuggestions[index])
    }

    /// Übernimmt eine Person als Marke (die Eingabe leert das ViewModel).
    ///
    /// - Parameter person: Gewählte Person.
    private func select(_ person: SearchPerson) {
        search.tokens = [person]
        highlighted = nil
        focusSoon()
    }

    /// Beendet die Suche; die Liste zeigt wieder alle Mails.
    private func close() {
        withAnimation(.snappy(duration: 0.25)) {
            search.isPresented = false
        }
    }
}

/// Namensvorschlag: Name fett, Adresse grau dahinter.
private struct MacSuggestionRow: View {
    /// Vorgeschlagene Person.
    let person: SearchPerson

    /// Name und Adresse in einer Zeile.
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            if let name = person.name {
                Text(name)
                    .fontWeight(.semibold)
                Text(person.address)
                    .foregroundStyle(.secondary)
            } else {
                Text(person.address)
            }
        }
        .lineLimit(1)
    }
}
#endif
