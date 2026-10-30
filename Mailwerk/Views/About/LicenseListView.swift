//
//  LicenseListView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 29.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: „Open-Source-Lizenzen“ – Mailwerk selbst und die verwendeten
//  Komponenten mit ihrer Lizenz; ein Tipp zeigt den vollständigen
//  Lizenztext (LicenseDetailView), bei Apache 2.0 samt NOTICE.
//
//  Aufruf: iPhone/iPad aus „Über Mailwerk“ (Navigation im Blatt), Mac als
//  Blatt über dem Fenster „Über Mailwerk“ – dort mit Kopfleiste und ✓
//  (Fertig), der Lizenztext mit „<“ (SheetHeaderBar).
//
//  Abgrenzung: Verzeichnis und Texte → OpenSourceLicenses; Aufruf →
//  AboutView.
//
//  Abhängigkeiten: SwiftUI, OpenSourceLicenses, AppTheme, SheetHeaderBar,
//  PlatformSheetSize.
//

import SwiftUI

/// Liste der Lizenzen.
struct LicenseListView: View {
    /// Schließt das Blatt (Mac, ✓); `nil` = kein eigener Knopf (iPhone/iPad,
    /// dort führt „Zurück“ der Navigation heraus).
    var onDone: (() -> Void)? = nil

    /// Abschnitte „Mailwerk“ und „Verwendete Komponenten“.
    var body: some View {
        listContainer {
            Section {
                row(OpenSourceLicenses.mailwerk)
            } header: {
                Text("Mailwerk")
            } footer: {
                Text("Der Name „Mailwerk“ und das App-Icon sind von der Lizenz ausgenommen.")
            }
            .cardRowBackground()

            Section {
                ForEach(OpenSourceLicenses.components) { component in
                    row(component)
                }
            } header: {
                Text("Verwendete Komponenten")
            } footer: {
                Text("Vielen Dank an alle, die diese Komponenten entwickeln und pflegen.")
            }
            .cardRowBackground()
        }
        .appBackground()
        .navigationTitle("Open-Source-Lizenzen")
        .macSheetHeader("Open-Source-Lizenzen") {
            EmptyView()
        } trailing: {
            if let onDone {
                HeaderCircleButton.confirm("Fertig", action: onDone)
            }
        }
    }

    /// Behälter: auf iPhone/iPad eine Liste, auf dem Mac ein gruppiertes
    /// Formular (Karten wie iOS).
    ///
    /// - Parameter content: Abschnitte.
    /// - Returns: Liste bzw. Formular.
    private func listContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let rows = content()
        #if os(macOS)
        return Form { rows }
            .macGroupedForm()
        #else
        return List { rows }
        #endif
    }

    /// Zeile einer Komponente: Name, darunter Lizenz und Herkunft.
    ///
    /// - Parameter component: Komponente.
    /// - Returns: Zeile, die den Lizenztext öffnet.
    private func row(_ component: OpenSourceComponent) -> some View {
        NavigationLink {
            LicenseDetailView(component: component)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.tiny) {
                Text(component.name)
                    .font(.headline)
                Text([component.licenseName, component.origin].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, AppSpacing.tiny)
        }
    }
}

/// Vollständiger Lizenztext einer Komponente.
struct LicenseDetailView: View {
    /// Komponente.
    let component: OpenSourceComponent
    /// Text, einmal beim Öffnen aus dem Bundle gelesen.
    private let text: String

    @Environment(\.dismiss) private var dismiss

    /// Liest den Text der Komponente.
    ///
    /// - Parameter component: Komponente.
    init(component: OpenSourceComponent) {
        self.component = component
        self.text = OpenSourceLicenses.fullText(for: component)
    }

    /// Webseite der Komponente, darunter der Text in fester Schriftbreite
    /// (die Lizenztexte sind von Hand umbrochen).
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Link(component.websiteURL.absoluteString, destination: component.websiteURL)
                    .font(.footnote)
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding()
        }
        .appBackground()
        .navigationTitle(component.name)
        #if os(macOS)
        .navigationBarBackButtonHidden(true)
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .macSheetHeader(component.name) {
            HeaderCircleButton.back { dismiss() }
        } trailing: {
            EmptyView()
        }
    }
}
