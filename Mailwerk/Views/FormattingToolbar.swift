//
//  FormattingToolbar.swift
//  Mailwerk
//
//  Zweck: Formatierungsleiste für den RichTextEditor. Zeigt an, welche
//  Formate an der Cursorposition aktiv sind, und schaltet sie um: Fett,
//  Kursiv, Unterstrichen, Schriftgröße, Farbe, Link, Aufzählung und
//  nummerierte Liste.
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

/// Leiste mit den Formatierungs-Knöpfen.
struct FormattingToolbar: View {
    /// Steuerung des Editors; liefert die aktiven Formate.
    let controller: RichTextController

    /// `true`, solange der Link-Dialog offen ist.
    @State private var isLinkDialogShown = false
    /// Eingabe im Link-Dialog.
    @State private var linkInput = ""
    /// `true`, solange der Hinweis auf eine ungültige Adresse offen ist.
    @State private var isInvalidLinkShown = false

    /// Auswahlfarben – bewusst wenige, damit die Leiste schmal bleibt.
    /// Der farbige Punkt ist ein Emoji: Systemmenüs stellen SF-Symbole
    /// grundsätzlich einfarbig dar.
    private static let colors: [(name: String, swatch: String, color: Color)] = [
        ("Standard", "",    .primary),
        ("Rot",      "🔴", .red),
        ("Orange",   "🟠", .orange),
        ("Grün",     "🟢", .green),
        ("Blau",     "🔵", .blue),
        ("Violett",  "🟣", .purple)
    ]

    /// Waagerecht scrollbare Leiste mit Knöpfen und Menüs.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                toggle("Fett", "bold", isOn: controller.isBold) {
                    controller.toggleBold()
                }
                toggle("Kursiv", "italic", isOn: controller.isItalic) {
                    controller.toggleItalic()
                }
                toggle("Unterstrichen", "underline", isOn: controller.isUnderlined) {
                    controller.toggleUnderline()
                }

                Divider().frame(height: 20)

                Menu {
                    Picker("Schriftgröße", selection: sizeBinding) {
                        ForEach(RichTextSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                } label: {
                    Label("Schriftgröße", systemImage: "textformat.size")
                }
                .fixedSize()

                Menu {
                    ForEach(Self.colors, id: \.name) { entry in
                        Button {
                            controller.setColor(platformColor(entry.color))
                        } label: {
                            Text(entry.swatch.isEmpty ? entry.name : "\(entry.swatch) \(entry.name)")
                        }
                    }
                } label: {
                    Label("Farbe", systemImage: "paintpalette")
                }
                .fixedSize()

                toggle("Link", "link", isOn: controller.link != nil) {
                    linkInput = controller.link.map(LinkInput.displayText(for:)) ?? ""
                    isLinkDialogShown = true
                }

                Divider().frame(height: 20)

                toggle("Aufzählung", "list.bullet", isOn: controller.listStyle == .bulleted) {
                    controller.toggleList(.bulleted)
                }
                toggle("Nummerierte Liste", "list.number", isOn: controller.listStyle == .numbered) {
                    controller.toggleList(.numbered)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
            Image(systemName: symbol)
                .frame(width: 28, height: 24)
                .background(
                    isOn ? Color.accentColor.opacity(0.2) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
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
