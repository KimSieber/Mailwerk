//
//  RichTextEditor.swift
//  Mailwerk
//
//  Formatierbarer Texteditor für das Verfassen von Mails.
//  Kapselt UITextView (iOS) bzw. NSTextView (macOS) – beide auf Basis von
//  TextKit 2 – hinter einer gemeinsamen SwiftUI-Ansicht.
//
//  Bewusst unterstützt wird nur, was sich später verlustfrei nach HTML
//  übersetzen lässt: Fett, Kursiv, Unterstrichen, drei Schriftgrößen,
//  Textfarbe, Aufzählung und nummerierte Liste.
//

import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformTextView = UITextView
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformTextView = NSTextView
#endif

// MARK: - Schriftgrößen

enum RichTextSize: CGFloat, CaseIterable, Identifiable {
    case small = 13
    case normal = 16
    case large = 20

    var id: CGFloat { rawValue }

    var label: String {
        switch self {
        case .small:  return "Klein"
        case .normal: return "Normal"
        case .large:  return "Groß"
        }
    }
}

// MARK: - Listenart

enum RichTextListStyle {
    case bulleted, numbered

    /// Eigene Formatvorlage für die Nummerierung, damit hinter der Ziffer
    /// ein Punkt steht ("1." statt "1"). Das eingebaute Format `.decimal`
    /// erzeugt nur die nackte Ziffer.
    var markerFormat: NSTextList.MarkerFormat {
        switch self {
        case .bulleted: return .disc
        case .numbered: return NSTextList.MarkerFormat(rawValue: "{decimal}.")
        }
    }

    /// Erkennt die Listenart an der Formatvorlage eines Absatzes.
    static func from(markerFormat: NSTextList.MarkerFormat?) -> RichTextListStyle? {
        guard let raw = markerFormat?.rawValue else { return nil }
        return raw.contains("decimal") ? .numbered : .bulleted
    }
}

// MARK: - Steuerung

/// Bindeglied zwischen Formatierungsleiste und Textansicht.
@Observable
final class RichTextController {

    /// Aktiver Zustand an der Cursorposition – für die Anzeige in der Leiste.
    private(set) var isBold = false
    private(set) var isItalic = false
    private(set) var isUnderlined = false
    private(set) var size: RichTextSize = .normal
    private(set) var listStyle: RichTextListStyle?

    @ObservationIgnored weak var textView: PlatformTextView?
    /// Wird nach programmatischen Änderungen aufgerufen, damit die Bindung nachzieht.
    @ObservationIgnored var onChange: (() -> Void)?

    static let defaultFont = PlatformFont.systemFont(ofSize: RichTextSize.normal.rawValue)

    /// Textfarbe des Systems (heißt je Plattform anders).
    static var defaultTextColor: PlatformColor {
        #if os(iOS)
        return .label
        #else
        return .labelColor
        #endif
    }

    /// Standard-Attribute für neuen Text.
    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: defaultTextColor]
    }

    // MARK: Formatierungen

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    func toggleUnderline() {
        applyToSelection { attributes in
            let isOn = (attributes[.underlineStyle] as? Int ?? 0) != 0
            attributes[.underlineStyle] = isOn ? 0 : NSUnderlineStyle.single.rawValue
        }
    }

    func setSize(_ newSize: RichTextSize) {
        applyToSelection { attributes in
            let font = (attributes[.font] as? PlatformFont) ?? Self.defaultFont
            attributes[.font] = font.withSize(newSize.rawValue)
        }
    }

    func setColor(_ color: PlatformColor) {
        applyToSelection { attributes in
            attributes[.foregroundColor] = color
        }
    }

    /// Schaltet die Listenart für die markierten Absätze um.
    func toggleList(_ style: RichTextListStyle) {
        guard let textView, let storage = textView.mwTextStorage else { return }
        let paragraphRange = paragraphRange(in: storage, for: selectedRange)
        let turnOff = listStyle == style

        storage.beginEditing()
        storage.enumerateAttribute(
            .paragraphStyle, in: paragraphRange, options: []
        ) { value, range, _ in
            let base = (value as? NSParagraphStyle) ?? .default
            guard let updated = base.mutableCopy() as? NSMutableParagraphStyle else { return }
            if turnOff {
                updated.textLists = []
                updated.firstLineHeadIndent = 0
                updated.headIndent = 0
            } else {
                updated.textLists = [NSTextList(markerFormat: style.markerFormat, options: 0)]
                updated.firstLineHeadIndent = 0
                updated.headIndent = 24
            }
            storage.addAttribute(.paragraphStyle, value: updated, range: range)
        }
        storage.endEditing()

        onChange?()
        updateState()
    }

    // MARK: Zustand

    /// Liest die Formatierung an der Cursorposition aus.
    func updateState() {
        guard let textView else { return }
        let attributes = currentAttributes(of: textView)
        let font = (attributes[.font] as? PlatformFont) ?? Self.defaultFont
        let traits = font.fontDescriptor.symbolicTraits

        #if os(iOS)
        isBold = traits.contains(.traitBold)
        isItalic = traits.contains(.traitItalic)
        #else
        isBold = traits.contains(.bold)
        isItalic = traits.contains(.italic)
        #endif

        isUnderlined = (attributes[.underlineStyle] as? Int ?? 0) != 0
        size = RichTextSize(rawValue: font.pointSize) ?? .normal

        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        listStyle = RichTextListStyle.from(markerFormat: paragraph?.textLists.first?.markerFormat)
    }

    // MARK: Interna

    private var selectedRange: NSRange {
        #if os(iOS)
        textView?.selectedRange ?? NSRange(location: 0, length: 0)
        #else
        textView?.selectedRange() ?? NSRange(location: 0, length: 0)
        #endif
    }

    private func currentAttributes(of textView: PlatformTextView) -> [NSAttributedString.Key: Any] {
        let range = selectedRange
        if range.length > 0, let storage = textView.mwTextStorage, storage.length > range.location {
            return storage.attributes(at: range.location, effectiveRange: nil)
        }
        return typingAttributes(of: textView)
    }

    private func typingAttributes(of textView: PlatformTextView) -> [NSAttributedString.Key: Any] {
        #if os(iOS)
        return textView.typingAttributes
        #else
        return textView.typingAttributes
        #endif
    }

    private func toggleTrait(_ trait: FontTrait) {
        applyToSelection { attributes in
            let font = (attributes[.font] as? PlatformFont) ?? Self.defaultFont
            attributes[.font] = font.togglingTrait(trait)
        }
    }

    /// Wendet eine Änderung auf die Markierung an – oder auf die
    /// Eingabeattribute, wenn nichts markiert ist.
    private func applyToSelection(
        _ change: (inout [NSAttributedString.Key: Any]) -> Void
    ) {
        guard let textView else { return }
        let range = selectedRange

        if range.length == 0 {
            var attributes = typingAttributes(of: textView)
            change(&attributes)
            textView.typingAttributes = attributes
            updateState()
            return
        }

        guard let storage = textView.mwTextStorage else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
            var updated = attributes
            change(&updated)
            storage.setAttributes(updated, range: subRange)
        }
        storage.endEditing()

        onChange?()
        updateState()
    }

    private func paragraphRange(in storage: NSTextStorage, for range: NSRange) -> NSRange {
        let text = storage.string as NSString
        let safe = NSRange(
            location: min(range.location, max(text.length - 1, 0)),
            length: min(range.length, max(text.length - range.location, 0))
        )
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        return text.paragraphRange(for: safe)
    }
}

// MARK: - Schrift-Hilfen

enum FontTrait { case bold, italic }

extension PlatformFont {
    /// Schaltet Fett bzw. Kursiv um und behält alle anderen Eigenschaften.
    func togglingTrait(_ trait: FontTrait) -> PlatformFont {
        #if os(iOS)
        let symbolic: UIFontDescriptor.SymbolicTraits = trait == .bold ? .traitBold : .traitItalic
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(symbolic) { traits.remove(symbolic) } else { traits.insert(symbolic) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
        #else
        let symbolic: NSFontDescriptor.SymbolicTraits = trait == .bold ? .bold : .italic
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(symbolic) { traits.remove(symbolic) } else { traits.insert(symbolic) }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
        #endif
    }
}

// MARK: - SwiftUI-Ansicht

struct RichTextEditor: View {
    @Binding var text: NSAttributedString
    let controller: RichTextController

    var body: some View {
        RichTextViewRepresentable(text: $text, controller: controller)
    }
}

private struct RichTextViewRepresentable {
    @Binding var text: NSAttributedString
    let controller: RichTextController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, controller: controller)
    }

    final class Coordinator: NSObject {
        @Binding private var text: NSAttributedString
        let controller: RichTextController

        init(text: Binding<NSAttributedString>, controller: RichTextController) {
            _text = text
            self.controller = controller
        }

        func attach(_ textView: PlatformTextView) {
            controller.textView = textView
            controller.onChange = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.pushText(from: textView)
            }
            controller.updateState()
        }

        func pushText(from textView: PlatformTextView) {
            guard let storage = textView.mwTextStorage else { return }
            text = NSAttributedString(attributedString: storage)
        }
    }
}

#if os(iOS)
extension RichTextViewRepresentable: UIViewRepresentable {

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.allowsEditingTextAttributes = true
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.typingAttributes = RichTextController.defaultAttributes
        textView.attributedText = text
        textView.delegate = context.coordinator
        context.coordinator.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Nur setzen, wenn die Bindung von außen geändert wurde
        if textView.attributedText != text {
            let selection = textView.selectedRange
            textView.attributedText = text
            textView.selectedRange = selection
        }
    }
}

extension RichTextViewRepresentable.Coordinator: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        pushText(from: textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        controller.updateState()
    }
}
#else
extension RichTextViewRepresentable: NSViewRepresentable {

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.autoresizingMask = [.width]
        textView.isRichText = true
        textView.isEditable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.typingAttributes = RichTextController.defaultAttributes
        textView.textStorage?.setAttributedString(text)
        textView.delegate = context.coordinator
        context.coordinator.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        if storage != text {
            let selection = textView.selectedRange()
            storage.setAttributedString(text)
            textView.setSelectedRange(selection)
        }
    }
}

extension RichTextViewRepresentable.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        pushText(from: textView)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        controller.updateState()
    }
}
#endif

// MARK: - Plattform-Hilfen

extension PlatformTextView {
    /// `textStorage` ist unter iOS nicht optional, unter macOS schon –
    /// dieser Zugriff funktioniert auf beiden Plattformen gleich.
    var mwTextStorage: NSTextStorage? {
        #if os(iOS)
        return textStorage
        #else
        return textStorage
        #endif
    }
}
