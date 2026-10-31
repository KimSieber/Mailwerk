//
//  SpamSettingsView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 24.09.2026
//  Geändert: 31.10.2026
//
//  Zweck: Einstellungen des Spamfilters: Schalter, Score-Obergrenze und
//  Zugang zur Pflege der beiden Listen.
//
//  Knöpfe (Regel MW-60): Schalter und Score-Obergrenze speichern sofort,
//  deshalb nur ✕ links oben zum Schließen (iPhone/iPad: Systemknopf,
//  Rolle „close“); die Listen öffnen sich als Unterseite mit „<“.
//
//  Mac: feste Kopfleiste oben statt Symbolleiste; gruppiertes Formular (Karten wie iOS, „Score-Obergrenze“
//  vollständig links, Wert mit Plus/Minus rechts); Whitelist und
//  Blacklist als hohe Zeilen mit „>“ in einer Karte; kompaktes Sheet
//  (520 × 600 pt, Inhalt ohne Scrollen).
//
//  Abgrenzung: Speichern der Einstellungen → SpamSettings; Listenpflege →
//  FilterListView.
//
//  Abhängigkeiten: SwiftUI, SpamSettings, FilterListRepository,
//  FilterListView, PlatformSheetSize, AppTheme (getönte Fläche,
//  Abschnitte als Karten), SheetHeaderBar.
//

import SwiftUI

/// Sheet „Spamfilter“.
struct SpamSettingsView: View {
    /// Einstellungen des Filters.
    let settings: SpamSettings
    /// Zugriff auf die Listen.
    let filterLists: any FilterListRepository

    @Environment(\.dismiss) private var dismiss

    /// Formular mit Schalter, Listen und Score-Obergrenze.
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Spamfilter aktiv", isOn: Binding(
                        get: { settings.isEnabled },
                        set: { settings.isEnabled = $0 }
                    ))
                    // Einzelner Schalter: auf dem Mac als Schalter statt Häkchen.
                    .toggleStyle(.switch)
                } footer: {
                    Text("Beim Abrufen werden ungeprüfte Mails der letzten 30 Tage bewertet. Erkannter Spam wandert in den Spam-Ordner des jeweiligen Postfachs.")
                }
                .cardRowBackground()

                Section {
                    NavigationLink {
                        FilterListView(list: .white, repository: filterLists)
                    } label: {
                        Label("Whitelist", systemImage: "checkmark.shield")
                            .frame(minHeight: Self.listRowMinHeight)
                    }
                    NavigationLink {
                        FilterListView(list: .black, repository: filterLists)
                    } label: {
                        Label("Blacklist", systemImage: "xmark.shield")
                            .frame(minHeight: Self.listRowMinHeight)
                    }
                } footer: {
                    Text("Die Listen gelten für alle Postfächer gemeinsam und werden über iCloud abgeglichen.")
                }
                .cardRowBackground()

                Section {
                    Stepper(
                        value: Binding(
                            get: { settings.scoreLimit },
                            set: { settings.scoreLimit = $0 }
                        ),
                        in: 5...50,
                        step: 1
                    ) {
                        LabeledContent("Score-Obergrenze", value: scoreText)
                    }
                } footer: {
                    Text("Bewertet der Server eine Mail mit mindestens diesem Wert, wird sie auch dann aussortiert, wenn der Absender auf der Whitelist steht. Schutz gegen gefälschte Absenderadressen.")
                }
                .cardRowBackground()
            }
            .macGroupedForm()
            .appBackground()
            .navigationTitle("Spamfilter")
            .macSheetHeader("Spamfilter") {
                HeaderCircleButton.cancel("Schließen") { dismiss() }
            } trailing: {
                EmptyView()
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            #endif
        }
        .macSheetFrame(.compact)
    }

    /// Höhe der Zeilen „Whitelist“/„Blacklist“: auf dem Mac höher.
    private static var listRowMinHeight: CGFloat? {
        #if os(macOS)
        36
        #else
        nil
        #endif
    }

    /// Score-Obergrenze ohne Nachkommastellen.
    private var scoreText: String {
        settings.scoreLimit.formatted(.number.precision(.fractionLength(0)))
    }
}

#Preview {
    SpamSettingsView(
        settings: SpamSettings(),
        filterLists: InMemoryFilterListRepository()
    )
}
