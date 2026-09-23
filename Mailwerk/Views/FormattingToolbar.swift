//
//  FormattingToolbar.swift
//  Mailwerk
//
//  Formatierungsleiste für den RichTextEditor. Zeigt an, welche Formate
//  an der Cursorposition aktiv sind, und schaltet sie um.
//

import SwiftUI

struct FormattingToolbar: View {
    let controller: RichTextController

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
    }

    // MARK: - Bausteine

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

    private var sizeBinding: Binding<RichTextSize> {
        Binding(
            get: { controller.size },
            set: { controller.setSize($0) }
        )
    }

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
