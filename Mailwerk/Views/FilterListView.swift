//
//  FilterListView.swift
//  Mailwerk
//
//  Zweck: Pflege einer der beiden Filterlisten. Einträge lassen sich
//  einzeln löschen und mehrere auf einmal hinzufügen – getrennt durch
//  Komma, Semikolon, Zeilenumbruch oder Leerzeichen.
//
//  Die Ansicht lädt beim Öffnen und erneut, sobald der iCloud-Abgleich
//  Änderungen von einem anderen Gerät übernommen hat. So bleibt eine
//  geöffnete Liste aktuell, ohne dass man sie schließen muss.
//
//  Abgrenzung: Speicherung und Abgleich → FilterListRepository; Zerlegen
//  der Eingabe → FilterListInput; Export → FilterListExporter.
//
//  Abhängigkeiten: SwiftUI, FilterListRepository, FilterListInput,
//  FilterListExporter, FilterListCloudEvents, Dialogs, Log.
//

import SwiftUI
import os

/// Pflege der White- bzw. Blacklist.
struct FilterListView: View {
    /// Gepflegte Liste.
    let list: FilterList
    /// Speicher der Filterlisten.
    let repository: any FilterListRepository

    /// Einträge dieser Liste.
    @State private var entries: [FilterEntryItem] = []
    /// Eingabe für neue Einträge.
    @State private var input = ""
    /// Ergebnis des letzten Hinzufügens.
    @State private var statusMessage: String?
    /// Einziger Meldungskanal der Ansicht.
    @State private var activeAlert: AlertItem?
    /// Hinzufügen läuft.
    @State private var isWorking = false
    /// Textdatei der Liste für das Teilen-Menü; `nil` bei leerer Liste.
    @State private var exportURL: URL?

    /// Eingabe, Ergebnis und Einträge; Teilen in der Symbolleiste.
    var body: some View {
        List {
            Section {
                TextField(
                    list == .white ? "Adresse oder Domain vertrauen" : "Adresse oder Domain blockieren",
                    text: $input,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .emailInput()

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
        .onReceive(FilterListCloudEvents.remoteChangesImported) {
            Task { await reload() }
        }
        .alertItem($activeAlert)
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
    /// ab und erscheint als Meldung. Die Eingabe wird nur geleert, wenn
    /// alles übernommen wurde.
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
                report(error)
                break
            }
        }

        statusMessage = summary(added: added, invalid: parsed.invalid, conflicts: conflicts)
        if conflicts.isEmpty && parsed.invalid.isEmpty {
            input = ""
        }
        await reload()
    }

    /// Löscht die gewählten Einträge.
    ///
    /// - Parameter offsets: Positionen in `entries`.
    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { entries[$0].id }
        Task {
            do {
                for id in ids { try await repository.remove(id) }
                await reload()
            } catch {
                report(error)
            }
        }
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
