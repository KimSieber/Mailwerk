//
//  RecipientField.swift
//  Mailwerk
//
//  Eingabefeld für An/Cc/Bcc: bereits erfasste Adressen erscheinen als Chips,
//  während der Eingabe werden passende Kontakte vorgeschlagen.
//  Ungültige Adressen werden rot dargestellt, statt sie zu verwerfen.
//
//  Tastatur: Enter übernimmt den hervorgehobenen Vorschlag (außer die Eingabe
//  ist bereits eine vollständige Adresse), Pfeiltasten wechseln den Vorschlag,
//  Escape blendet die Vorschlagsliste aus. Nach dem Anlegen eines Chips bleibt
//  der Fokus im Feld, sodass direkt die nächste Adresse getippt werden kann.
//
//  Ein Tap auf einen Chip zeigt die E-Mail-Adresse, ein weiterer wieder den
//  Namen. Zu lange Adressen werden in der Mitte gekürzt.
//

import SwiftUI

struct RecipientField: View {
    let label: String
    @Binding var addresses: [MailAddress]

    /// Vorschlagsquelle – im Test/Preview austauschbar.
    var suggestionProvider: (String) async -> [ContactSuggestion] = {
        await ContactSuggestionService.shared.suggestions(matching: $0)
    }
    /// Wird beim ersten Fokus aufgerufen (Kontakte-Berechtigung).
    var requestAccess: () async -> Void = {
        _ = await ContactSuggestionService.shared.requestAccessIfNeeded()
    }

    @State private var input = ""
    @State private var suggestions: [ContactSuggestion] = []
    @State private var selectedSuggestion = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var hasRequestedAccess = false
    /// Chips, die gerade die vollständige Adresse zeigen
    @State private var expandedChips: Set<String> = []
    @FocusState private var isFocused: Bool

    /// Wartezeit, bevor nach einer Eingabe gesucht wird.
    private let searchDelay = Duration.milliseconds(250)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                    .padding(.top, 6)

                FlowLayout {
                    ForEach(addresses) { address in
                        RecipientChip(
                            address: address,
                            isExpanded: expandedChips.contains(address.normalizedAddress),
                            onTap: { toggleChip(address) },
                            onDelete: { remove(address) }
                        )
                    }
                    TextField(addresses.isEmpty ? "Name oder E-Mail" : "", text: $input)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .focused($isFocused)
                        .frame(minWidth: 140)
                        .onSubmit { submit() }
                        // Hardware-Tastatur: Eingabetaste selbst behandeln,
                        // damit SwiftUI dem Feld nicht den Fokus entzieht.
                        .onKeyPress(.return) {
                            submit()
                            return .handled
                        }
                        .onKeyPress(.downArrow) { moveSelection(by: 1) }
                        .onKeyPress(.upArrow) { moveSelection(by: -1) }
                        .onKeyPress(.escape) {
                            guard !suggestions.isEmpty else { return .ignored }
                            searchTask?.cancel()
                            suggestions = []
                            return .handled
                        }
                }
            }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            add(suggestion.mailAddress)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                if let name = suggestion.name {
                                    Text(name)
                                    Text(suggestion.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(suggestion.address)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                index == selectedSuggestion
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.leading, 42)
            }
        }
        .onChange(of: input) { _, newValue in handleInput(newValue) }
        .onChange(of: isFocused) { _, focused in
            if focused {
                guard !hasRequestedAccess else { return }
                hasRequestedAccess = true
                Task { await requestAccess() }
            } else {
                commitInput()
            }
        }
    }

    // MARK: - Tastatur

    /// Enter: hervorgehobenen Vorschlag übernehmen – es sei denn, die Eingabe
    /// ist bereits eine vollständige gültige Adresse.
    private func submit() {
        let typed = MailAddress(parsing: input)
        if typed?.isValid != true, suggestions.indices.contains(selectedSuggestion) {
            add(suggestions[selectedSuggestion].mailAddress)
        } else {
            commitInput()
        }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        let next = selectedSuggestion + offset
        selectedSuggestion = min(max(next, 0), suggestions.count - 1)
        return .handled
    }

    // MARK: - Eingabe

    /// Trennzeichen schließen eine Adresse ab, der Rest bleibt stehen.
    private func handleInput(_ text: String) {
        let result = RecipientInput.split(text)
        if !result.addresses.isEmpty {
            addresses = RecipientInput.appending(result.addresses, to: addresses)
            input = result.remainder
            suggestions = []
            return
        }
        scheduleSearch(for: text)
    }

    /// Übernimmt eine noch offene Eingabe, z. B. beim Verlassen des Felds.
    private func commitInput() {
        searchTask?.cancel()
        suggestions = []
        guard let address = RecipientInput.address(from: input) else { return }
        addresses = RecipientInput.appending([address], to: addresses)
        input = ""
    }

    private func add(_ address: MailAddress) {
        searchTask?.cancel()
        addresses = RecipientInput.appending([address], to: addresses)
        input = ""
        suggestions = []
        refocus()
    }

    /// Holt den Fokus zurück, nachdem ein Chip entstanden ist.
    /// Das System entzieht dem Feld beim Absenden den Fokus, ohne dass sich
    /// unser Merker ändert – ein erneutes "true" wäre daher wirkungslos.
    /// Deshalb erst ausdrücklich abwählen, dann wieder setzen.
    private func refocus() {
        Task { @MainActor in
            isFocused = false
            try? await Task.sleep(for: .milliseconds(50))
            isFocused = true
        }
    }

    private func remove(_ address: MailAddress) {
        addresses.removeAll { $0.normalizedAddress == address.normalizedAddress }
        expandedChips.remove(address.normalizedAddress)
    }

    /// Zeigt auf Tippen die vollständige Adresse – und wieder zurück.
    private func toggleChip(_ address: MailAddress) {
        let key = address.normalizedAddress
        if expandedChips.contains(key) {
            expandedChips.remove(key)
        } else {
            expandedChips.insert(key)
        }
    }

    // MARK: - Vorschläge

    private func scheduleSearch(for query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= ContactSuggestionService.minimumQueryLength else {
            suggestions = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: searchDelay)
            guard !Task.isCancelled else { return }
            let found = await suggestionProvider(trimmed)
            guard !Task.isCancelled else { return }
            // Bereits erfasste Adressen nicht erneut vorschlagen
            let existing = Set(addresses.map(\.normalizedAddress))
            suggestions = found.filter { !existing.contains($0.address.lowercased()) }
            selectedSuggestion = 0
        }
    }
}

// MARK: - Chip

private struct RecipientChip: View {
    let address: MailAddress
    let isExpanded: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                Text(isExpanded ? address.address : (address.name ?? address.address))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Zeigt die vollständige Adresse")
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(address.displayString) entfernen")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            address.isValid ? Color.accentColor.opacity(0.15) : Color.red.opacity(0.2),
            in: Capsule()
        )
        .foregroundStyle(address.isValid ? Color.primary : Color.red)
        .help(address.isValid ? address.displayString : "Ungültige Adresse")
    }
}

// MARK: - Vorschau

#Preview {
    @Previewable @State var to: [MailAddress] = [
        MailAddress(name: "Anna Muster", address: "anna@example.org")
    ]
    @Previewable @State var cc: [MailAddress] = []

    let demo: [ContactSuggestion] = [
        ContactSuggestion(name: "Bob Beispiel", address: "bob@example.org"),
        ContactSuggestion(name: "Sieber, Kim", address: "kim@example.org"),
        ContactSuggestion(name: nil, address: "info@example.org")
    ]

    Form {
        RecipientField(
            label: "An",
            addresses: $to,
            suggestionProvider: { query in
                demo.filter {
                    ($0.name ?? "").localizedCaseInsensitiveContains(query)
                        || $0.address.localizedCaseInsensitiveContains(query)
                }
            },
            requestAccess: {}
        )
        RecipientField(
            label: "Cc",
            addresses: $cc,
            suggestionProvider: { _ in [] },
            requestAccess: {}
        )
    }
}
