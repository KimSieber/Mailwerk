//
//  AboutView.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 29.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: „Über Mailwerk“ – App-Icon, Name, Version mit Build-Nummer,
//  Urheberzeile, Kontaktadresse, Webseite und der Zugang zu den
//  Open-Source-Lizenzen.
//
//  - `AboutContent`: der gemeinsame Inhalt als Karte, auf iPhone, iPad
//    und Mac gleich aufgebaut.
//  - `AboutView` (iPhone/iPad): Blatt aus dem Einstellungsmenü der Liste
//    (Zahnrad → „Über Mailwerk“); darunter die Zeile
//    „Open-Source-Lizenzen“, die die Liste der Lizenzen öffnet.
//  - `AboutWindowView` (Mac): Inhalt des eigenen Fensters, das der
//    Menübefehl „Mailwerk → Über Mailwerk“ öffnet (MailwerkApp,
//    MacMenuCommands); die Lizenzen erscheinen dort als Blatt.
//
//  Kontaktadresse: Ein Tipp öffnet eine neue Mail in Mailwerk selbst
//  (nicht in einer anderen Mail-App). Der Link geht wie ein mailto:-Link
//  von außen an den ExternalMailtoRouter – Absender ist also das
//  Standard-Postfach, ohne Postfach erscheint der bekannte Hinweis.
//  „Über Mailwerk“ schließt sich dabei, damit das Verfassen-Fenster
//  sofort erscheinen kann (der Router wartet, bis kein Blatt mehr offen
//  ist). Die Webseite öffnet der Browser.
//
//  App-Icon: Mac aus dem Bundle über NSWorkspace (zeigt das fertige Icon
//  samt Glas-Effekt); iPhone/iPad über den Icon-Namen aus der Info.plist,
//  notfalls ein neutrales Briefsymbol auf Mailwerk-Blau.
//
//  Abgrenzung: Angaben (Version, Kontakt, Webseite) → AppInfo; Lizenzen →
//  LicenseListView, OpenSourceLicenses.
//
//  Abhängigkeiten: SwiftUI, UIKit bzw. AppKit (App-Icon), AppInfo,
//  ExternalMailtoRouter, LicenseListView, AppTheme, SheetHeaderBar,
//  PlatformSheetSize, ExternalMailtoPresenter (countsAsOpenWindow).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Gemeinsamer Inhalt

/// Karte mit Icon, Name, Version, Urheberzeile, Kontakt und Webseite.
struct AboutContent: View {
    /// Aktion beim Tipp auf die Kontaktadresse.
    let onContact: () -> Void

    /// Aufbau wie ein klassischer Info-Dialog: mittig, Trennlinie zwischen
    /// App-Angaben und Kontakt.
    var body: some View {
        VStack(spacing: 14) {
            AppIconImage(size: 96)

            VStack(spacing: AppSpacing.small) {
                Text(AppInfo.name)
                    .font(.title2.weight(.bold))
                Text(AppInfo.versionText)
                    .foregroundStyle(.secondary)
                    // Version lässt sich für Fehlermeldungen kopieren.
                    .textSelection(.enabled)
            }

            Divider()
                .padding(.vertical, AppSpacing.xSmall)

            VStack(spacing: AppSpacing.medium) {
                Text(AppInfo.copyright)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(AppInfo.contactAddress, action: onContact)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("Neue Mail an \(AppInfo.contactAddress)")
                Link(AppInfo.websiteText, destination: AppInfo.websiteURL)
                    .foregroundStyle(Color.accentColor)
                    .help("Webseite im Browser öffnen")
            }
        }
        .multilineTextAlignment(.center)
        .padding(AppSpacing.section)
        .frame(maxWidth: 420)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - App-Icon

/// Icon der App in der gewünschten Größe.
struct AppIconImage: View {
    /// Kantenlänge in Punkt.
    let size: CGFloat

    /// Icon aus dem Bundle; auf iPhone/iPad notfalls ein Ersatzsymbol.
    var body: some View {
        iconView
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    #if os(macOS)
    /// Mac: fertiges Icon des Bundles (Form und Glas-Effekt liefert das System).
    private var iconView: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
            .resizable()
            .interpolation(.high)
    }
    #else
    /// iPhone/iPad: Icon mit abgerundeten Ecken wie auf dem Home-Bildschirm.
    @ViewBuilder
    private var iconView: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        if let image = Self.bundleIcon() {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .clipShape(shape)
        } else {
            shape
                .fill(Color.accentColor)
                .overlay {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.white)
                }
        }
    }

    /// Lädt das App-Icon über die Namen aus der Info.plist.
    ///
    /// Verarbeitung: Probiert den Icon-Namen (`CFBundleIconName`), dann die
    /// Icon-Dateien (größte zuerst), zuletzt „AppIcon“.
    ///
    /// - Returns: Icon, oder `nil`, wenn keines gefunden wurde.
    private static func bundleIcon() -> UIImage? {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconName = primary?["CFBundleIconName"] as? String
        let iconFiles = (primary?["CFBundleIconFiles"] as? [String]) ?? []
        let candidates = [iconName].compactMap { $0 } + iconFiles.reversed() + ["AppIcon"]
        for name in candidates {
            if let image = UIImage(named: name) { return image }
        }
        return nil
    }
    #endif
}

// MARK: - iPhone/iPad

#if os(iOS)
/// Blatt „Über Mailwerk“ (iPhone/iPad).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    /// Karte, darunter die Zeile „Open-Source-Lizenzen“; ✕ schließt.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xxLarge) {
                    AboutContent(onContact: contact)
                    NavigationLink {
                        LicenseListView()
                    } label: {
                        licensesRow
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle("Über Mailwerk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
    }

    /// Zeile „Open-Source-Lizenzen“ als Karte in Breite der Info-Karte.
    private var licensesRow: some View {
        HStack {
            Label("Open-Source-Lizenzen", systemImage: "doc.text")
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(AppSpacing.xLarge)
        .frame(maxWidth: 420)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Öffnet eine neue Mail an die Kontaktadresse und schließt das Blatt.
    ///
    /// Verarbeitung: Übergabe an den ExternalMailtoRouter; das
    /// Verfassen-Fenster erscheint, sobald das Blatt geschlossen ist.
    private func contact() {
        ExternalMailtoRouter.shared.receive(AppInfo.contactURL)
        dismiss()
    }
}
#endif

// MARK: - Mac

#if os(macOS)
/// Kennung des Fensters „Über Mailwerk“.
enum AboutWindow {
    /// Kennung für `Window`, `openWindow` und `dismissWindow`.
    static let id = "about"
}

/// Inhalt des Fensters „Über Mailwerk“ (Mac).
struct AboutWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    /// Blatt mit den Lizenzen sichtbar.
    @State private var showingLicenses = false

    /// Karte auf Nebelblau, darunter der Link zu den Lizenzen.
    var body: some View {
        VStack(spacing: AppSpacing.xLarge) {
            AboutContent(onContact: contact)
            Button("Open-Source-Lizenzen …") {
                showingLicenses = true
            }
            .buttonStyle(.link)
        }
        // Oben Platz für die Fensterknöpfe (Fenster ohne Titelleiste).
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, AppSpacing.section)
        .frame(width: 400)
        .background(AppTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showingLicenses) {
            NavigationStack {
                LicenseListView(onDone: { showingLicenses = false })
            }
            .macSheetFrame(.list)
        }
    }

    /// Öffnet eine neue Mail an die Kontaktadresse im Hauptfenster und
    /// schließt dieses Fenster.
    private func contact() {
        ExternalMailtoRouter.shared.receive(AppInfo.contactURL)
        dismissWindow(id: AboutWindow.id)
    }
}
#endif
