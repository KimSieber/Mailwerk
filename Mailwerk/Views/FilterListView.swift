//
//  FilterListView.swift
//  Mailwerk
//
//  Pflege einer der beiden Filterlisten. Einträge lassen sich einzeln
//  löschen und mehrere auf einmal hinzufügen – getrennt durch Komma,
//  Semikolon, Zeilenumbruch oder Leerzeichen.
//

import SwiftUI

struct FilterListView: View {
    let list: FilterList
    let repository: any FilterListRepository

    @State private var entries: [FilterEntryItem] = []
    @State private var input = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section {
                TextField(
                    list == .white ? "Adresse oder Domain vertrauen" : "Adresse oder Domain blockieren",
                    text: $input,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #if !os(macOS)
                .keyboardType(.emailAddress)
                #endif

                Button("Hinzufügen") {
                    Task { await addEntries() }
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            } header: {
                Text("Neuer Eintrag")
            } footer: {
                Text("Mehrere Angaben auf einmal sind möglich. Eine Domain wie „firma.de“ gilt für alle Absender dieser Domain, eine Adresse nur für genau diesen Absender.")
            }

            if let statusMessage {
                Section { Text(statusMessage).font(.footnote) }
            }

            Section {
                if entries.isEmpty {
                    Text("Noch keine Einträge")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Image(systemName: entry.kind == .domain ? "globe" : "person")
                                .foregroundStyle(.secondary)
                            Text(entry.value)
                            Spacer()
                            Text(entry.kind == .domain ? "Domain" : "Adresse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                Text("\(entries.count) Einträge")
            }
        }
        .navigationTitle(list == .white ? "Whitelist" : "Blacklist")
        .toolbar {
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
        .task { await reload() }
        .alert(
            "Listenpflege fehlgeschlagen",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Aktionen

    private func reload() async {
        do {
            entries = try await repository.entries().filter { $0.list == list }
            updateExportFile()
        } catch {
            errorMessage = error.localizedDescription
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
            print("⚠️ Export der Liste fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func addEntries() async {
        isWorking = true
        defer { isWorking = false }

        let parsed = FilterListInput.parse(input)
        var added = 0
        var conflicts: [String] = []

        for entry in parsed.entries {
            do {
                try await repository.add(entry.value, kind: entry.kind, to: list)
                added += 1
            } catch FilterListError.alreadyOnOtherList {
                conflicts.append(entry.value)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }

        statusMessage = summary(added: added, invalid: parsed.invalid, conflicts: conflicts)
        if conflicts.isEmpty && parsed.invalid.isEmpty {
            input = ""
        }
        await reload()
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { entries[$0].id }
        Task {
            do {
                for id in ids { try await repository.remove(id) }
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Fasst zusammen, was beim Hinzufügen passiert ist. Abgelehnte Einträge
    /// werden benannt, damit klar ist, was noch zu tun ist.
    private func summary(added: Int, invalid: [String], conflicts: [String]) -> String {
        var parts: [String] = []
        if added > 0 {
            parts.append(added == 1 ? "1 Eintrag hinzugefügt" : "\(added) Einträge hinzugefügt")
        }
        if !conflicts.isEmpty {
            let other = list == .white ? "Blacklist" : "Whitelist"
            parts.append("Bereits auf der \(other): \(conflicts.joined(separator: ", "))")
        }
        if !invalid.isEmpty {
            parts.append("Nicht verwertbar: \(invalid.joined(separator: ", "))")
        }
        return parts.isEmpty ? "Nichts hinzugefügt" : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        FilterListView(list: .white, repository: InMemoryFilterListRepository())
    }
}
