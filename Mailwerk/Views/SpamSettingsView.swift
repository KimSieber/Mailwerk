//
//  SpamSettingsView.swift
//  Mailwerk
//
//  Zweck: Einstellungen des Spamfilters: Schalter, Score-Obergrenze und
//  Zugang zur Pflege der beiden Listen.
//
//  Abgrenzung: Speichern der Einstellungen → SpamSettings; Listenpflege →
//  FilterListView.
//
//  Abhängigkeiten: SwiftUI, SpamSettings, FilterListRepository,
//  FilterListView, PlatformSheetSize.
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
                } footer: {
                    Text("Beim Abrufen werden ungeprüfte Mails der letzten 30 Tage bewertet. Erkannter Spam wandert in den Spam-Ordner des jeweiligen Postfachs.")
                }

                Section {
                    NavigationLink {
                        FilterListView(list: .white, repository: filterLists)
                    } label: {
                        Label("Whitelist", systemImage: "checkmark.shield")
                    }
                    NavigationLink {
                        FilterListView(list: .black, repository: filterLists)
                    } label: {
                        Label("Blacklist", systemImage: "xmark.shield")
                    }
                } footer: {
                    Text("Die Listen gelten für alle Postfächer gemeinsam und werden über iCloud abgeglichen.")
                }

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
            }
            .navigationTitle("Spamfilter")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .macSheetFrame(.list)
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
