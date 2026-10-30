//
//  FormattingToolbar.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 23.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Formatierungsleiste für den RichTextEditor. Zeigt an, welche
//  Formate an der Cursorposition aktiv sind, und schaltet sie um: Fett,
//  Kursiv, Unterstrichen, Schriftgröße, Farbe, Link, Aufzählung und
//  nummerierte Liste.
//
//  Gestaltung (Liquid Glass, iOS/macOS 26): nur Symbole, gleich große
//  Tippflächen, die Knöpfe in Gruppen als Glas-Kapseln
//  (`GlassEffectContainer`, `glassEffect`). Aktive Formate sind farbig
//  hinterlegt. Reihenfolge nach Häufigkeit: Anhang und Link | Fett,
//  Kursiv, Unterstrichen | Listen | Schriftgröße und Farbe (am seltensten,
//  ganz rechts, auf dem iPhone erst nach Scrollen). Eigene Knöpfe des
//  Aufrufers vorn (`leading`, z. B. Anhang) stehen in der Gruppe mit dem
//  Link, hinten (`trailing`, z. B. Logo) als eigene Gruppe; dafür gibt es
//  das gemeinsame Symbol `FormatIcon`.
//
//  „Link“ öffnet einen Eingabedialog für eine Web- oder E-Mail-Adresse
//  (vorbelegt, wenn die Marke in einem Link steht, dann auch mit „Link
//  entfernen“). Eine ungültige Adresse wird mit einem Hinweis abgelehnt.
//
//  Abgrenzung: Formatieren des Texts → RichTextController; Editor →
//  RichTextEditor.
//
//  Abhängigkeiten: SwiftUI, RichTextController, RichTextSize, LinkInput.
//

import SwiftUI

/// Symbol eines Knopfs der Formatierungsleiste – einheitliche Größe und
/// Tippfläche, farbig hinterlegt, wenn das Format aktiv ist.
struct FormatIcon: View {
    /// SF-Symbol.
    let symbol: String
    /// `true`, wenn das Format aktiv ist.
    var isOn = false

    /// Symbol mit Tippfläche.
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .frame(width: 40, height: 36)
            .background(
                isOn ? Color.accentColor.opacity(0.18) : .clear,
                in: Capsule()
            )
            .contentShape(Capsule())
    }
}

/// Leiste mit den Formatierungs-Knöpfen.
struct FormattingToolbar<Leading: View, Trailing: View>: View {
    /// Steuerung des Editors; liefert die aktiven Formate.
    let controller: RichTextController
    /// Eigene Knöpfe vor der Formatierung (in der Gruppe mit dem Link).
    private let leading: Leading
    /// Eigene Knöpfe nach der Formatierung (eigene Gruppe).
    private let trailing: Trailing

    /// `true`, solange der Link-Dialog offen ist.
    @State private var isLinkDialogShown = false
    /// Eingabe im Link-Dialog.
    @State private var linkInput = ""
    /// `true`, solange der Hinweis auf eine ungültige Adresse offen ist.
    @State private var isInvalidLinkShown = false

    /// Legt die Leiste mit eigenen Knöpfen vorn und hinten an.
    ///
    /// - Parameters:
    ///   - controller: Steuerung des Editors.
    ///   - leading: Knöpfe vor der Formatierung.
    ///   - trailing: Knöpfe nach der Formatierung.
    init(
        controller: RichTextController,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.controller = controller
        self.leading = leading()
        self.trailing = trailing()
    }

    /// Auswahlfarben – bewusst wenige, damit die Leiste schmal bleibt.
    /// Der farbige Punkt ist ein Emoji: Systemmenüs stellen SF-Symbole
    /// grundsätzlich einfarbig dar.
    private static var colors: [(name: String, swatch: String, color: Color)] {
        [
            ("Standard", "",    .primary),
            ("Rot",      "🔴", .red),
            ("Orange",   "🟠", .orange),
            ("Grün",     "🟢", .green),
            ("Blau",     "🔵", .blue),
            ("Violett",  "🟣", .purple)
        ]
    }

    /// Waagerecht scrollbare Leiste mit Glas-Gruppen.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: AppSpacing.regular) {
                HStack(spacing: AppSpacing.regular) {
                    // Reihenfolge nach Häufigkeit: das Seltenste ganz rechts,
                    // dort muss auf dem iPhone gescrollt werden.
                    group {
                        leading
                        toggle("Link", "link", isOn: controller.link != nil) {
                            linkInput = controller.link.map(LinkInput.displayText(for:)) ?? ""
                            isLinkDialogShown = true
                        }
                    }
                    group {
                        toggle("Fett", "bold", isOn: controller.isBold) {
                            controller.toggleBold()
                        }
                        toggle("Kursiv", "italic", isOn: controller.isItalic) {
                            controller.toggleItalic()
                        }
                        toggle("Unterstrichen", "underline", isOn: controller.isUnderlined) {
                            controller.toggleUnderline()
                        }
                    }
                    group {
                        toggle("Aufzählung", "list.bullet", isOn: controller.listStyle == .bulleted) {
                            controller.toggleList(.bulleted)
                        }
                        toggle("Nummerierte Liste", "list.number", isOn: controller.listStyle == .numbered) {
                            controller.toggleList(.numbered)
                        }
                    }
                    group {
                        sizeMenu
                        colorMenu
                    }
                    if Trailing.self != EmptyView.self {
                        group { trailing }
                    }
                }
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .alert("Link", isPresented: $isLinkDialogShown) {
            TextField("www.beispiel.de", text: $linkInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Übernehmen") { applyLink() }
            if controller.link != nil {
                Button("Link entfernen", role: .destructive) { controller.setLink(nil) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Web-Adresse oder E-Mail-Adresse, z. B. www.beispiel.de oder name@beispiel.de")
        }
        .alert("Ungültige Adresse", isPresented: $isInvalidLinkShown) {
            Button("OK") {}
        } message: {
            Text("„\(linkInput)“ ist keine Web- oder E-Mail-Adresse. Beispiele: www.beispiel.de, name@beispiel.de")
        }
    }

    /// Menü „Schriftgröße“ – nur Symbol.
    private var sizeMenu: some View {
        Menu {
            Picker("Schriftgröße", selection: sizeBinding) {
                ForEach(RichTextSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
        } label: {
            FormatIcon(symbol: "textformat.size")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Schriftgröße")
        .accessibilityLabel("Schriftgröße")
    }

    /// Menü „Farbe“ – nur Symbol.
    private var colorMenu: some View {
        Menu {
            ForEach(Self.colors, id: \.name) { entry in
                Button {
                    controller.setColor(platformColor(entry.color))
                } label: {
                    Text(entry.swatch.isEmpty ? entry.name : "\(entry.swatch) \(entry.name)")
                }
            }
        } label: {
            FormatIcon(symbol: "paintpalette")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Farbe")
        .accessibilityLabel("Farbe")
    }

    /// Übernimmt die Eingabe des Link-Dialogs.
    ///
    /// Verarbeitung: Gültige Adressen werden ergänzt (https://, mailto:)
    /// und gesetzt; eine leere Eingabe entfernt einen vorhandenen Link;
    /// alles andere führt zum Hinweis.
    private func applyLink() {
        let trimmed = linkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if controller.link != nil { controller.setLink(nil) }
            return
        }
        guard let target = LinkInput.normalize(trimmed) else {
            // Erst nach dem Schließen des Link-Dialogs zeigen
            DispatchQueue.main.async { isInvalidLinkShown = true }
            return
        }
        controller.setLink(target)
    }

    // MARK: - Bausteine

    /// Gruppe von Knöpfen als Glas-Kapsel.
    ///
    /// - Parameter content: Knöpfe der Gruppe.
    /// - Returns: Gruppe mit Glas-Hintergrund.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: AppSpacing.tiny) { content() }
            .padding(.horizontal, AppSpacing.xSmall)
            .padding(.vertical, AppSpacing.tiny)
            .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Umschalt-Knopf mit Symbol, hinterlegt, wenn das Format aktiv ist.
    ///
    /// - Parameters:
    ///   - title: Bezeichnung für Hilfe und VoiceOver.
    ///   - symbol: SF-Symbol.
    ///   - isOn: `true`, wenn das Format aktiv ist.
    ///   - action: Umschalten.
    /// - Returns: Knopf.
    private func toggle(
        _ title: String,
        _ symbol: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            FormatIcon(symbol: symbol, isOn: isOn)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Bindung der Schriftgröße an den Controller.
    private var sizeBinding: Binding<RichTextSize> {
        Binding(
            get: { controller.size },
            set: { controller.setSize($0) }
        )
    }

    /// Plattformfarbe zu einer Auswahlfarbe; „Standard“ ergibt die
    /// Standard-Textfarbe des Editors.
    ///
    /// - Parameter color: Auswahlfarbe.
    /// - Returns: Farbe für den Editor.
    private func platformColor(_ color: Color) -> PlatformColor {
        color == .primary
            ? RichTextController.defaultTextColor
            : PlatformColor(color)
    }
}

// MARK: - Bequeme Initialisierer

extension FormattingToolbar where Leading == EmptyView, Trailing == EmptyView {
    /// Leiste ohne eigene Knöpfe.
    ///
    /// - Parameter controller: Steuerung des Editors.
    init(controller: RichTextController) {
        self.init(controller: controller, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension FormattingToolbar where Trailing == EmptyView {
    /// Leiste mit eigenen Knöpfen vorn.
    ///
    /// - Parameters:
    ///   - controller: Steuerung des Editors.
    ///   - leading: Knöpfe vor der Formatierung.
    init(controller: RichTextController, @ViewBuilder leading: () -> Leading) {
        self.init(controller: controller, leading: leading, trailing: { EmptyView() })
    }
}

extension FormattingToolbar where Leading == EmptyView {
    /// Leiste mit eigenen Knöpfen hinten.
    ///
    /// - Parameters:
    ///   - controller: Steuerung des Editors.
    ///   - trailing: Knöpfe nach der Formatierung.
    init(controller: RichTextController, @ViewBuilder trailing: () -> Trailing) {
        self.init(controller: controller, leading: { EmptyView() }, trailing: trailing)
    }
}

// MARK: - Vorschau

#Preview {
    @Previewable @State var text = NSAttributedString(
        string: "Hallo Welt\nZweite Zeile\nDritte Zeile",
        attributes: RichTextController.defaultAttributes
    )
    let controller = RichTextController()

    VStack(spacing: 0) {
        RichTextEditor(text: $text, controller: controller)
            .frame(minHeight: 240)
        Divider()
        FormattingToolbar(controller: controller)
    }
}
