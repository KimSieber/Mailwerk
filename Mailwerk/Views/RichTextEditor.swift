//
//  RichTextEditor.swift
//  Mailwerk
//
//  Zweck: Formatierbarer Texteditor für das Verfassen von Mails. Kapselt
//  UITextView (iOS) bzw. NSTextView (macOS) – beide auf Basis von
//  TextKit 2 – hinter einer gemeinsamen SwiftUI-Ansicht.
//
//  Bewusst unterstützt wird nur, was sich später verlustfrei nach HTML
//  übersetzen lässt: Fett, Kursiv, Unterstrichen, drei Schriftgrößen,
//  Textfarbe, Aufzählung und nummerierte Liste.
//
//  Der Editor scrollt nicht selbst, sondern wächst mit seinem Text. So
//  scrollt die Antwortansicht als Ganzes – Kopfbereich, eigener Text und
//  Zitat –, wie in Apple Mail. Die Textansicht misst ihre Höhe nach jeder
//  Änderung und meldet sie an die SwiftUI-Ansicht, die den Rahmen anpasst.
//  Weil der Editor nicht mehr selbst scrollt, rückt er die Schreibmarke
//  über die umgebende Scroll-Ansicht ins Bild (beim Tippen, beim Wachsen
//  und beim Versetzen der Marke).
//
//  Jede Formatierung einer Markierung ist ein eigener Rückgängig-Schritt.
//  „Widerrufen" nimmt also erst die Formatierung zurück, dann das Getippte.
//
//  Abgrenzung: Bedienleiste → FormattingToolbar; Aufbau des
//  Verfassen-Fensters → ComposeView; Umwandlung nach HTML → ComposeViewModel.
//
//  Abhängigkeiten: SwiftUI, UIKit (iOS) bzw. AppKit (macOS).
//

import SwiftUI

#if os(iOS)
import UIKit
/// Schriftart der Plattform.
typealias PlatformFont = UIFont
/// Farbe der Plattform.
typealias PlatformColor = UIColor
/// Textansicht der Plattform.
typealias PlatformTextView = UITextView
#else
import AppKit
/// Schriftart der Plattform.
typealias PlatformFont = NSFont
/// Farbe der Plattform.
typealias PlatformColor = NSColor
/// Textansicht der Plattform.
typealias PlatformTextView = NSTextView
#endif

// MARK: - Schriftgrößen

/// Die drei wählbaren Schriftgrößen in Punkt.
enum RichTextSize: CGFloat, CaseIterable, Identifiable {
    case small = 13
    case normal = 16
    case large = 20

    /// Kennung für SwiftUI (die Punktgröße).
    var id: CGFloat { rawValue }

    /// Beschriftung im Menü der Formatierungsleiste.
    var label: String {
        switch self {
        case .small:  return "Klein"
        case .normal: return "Normal"
        case .large:  return "Groß"
        }
    }
}

// MARK: - Listenart

/// Art einer Liste: Aufzählung oder nummeriert.
enum RichTextListStyle {
    case bulleted, numbered

    /// Formatvorlage der Listenmarke.
    ///
    /// Verarbeitung: Für nummerierte Listen eine eigene Vorlage, damit
    /// hinter der Ziffer ein Punkt steht („1." statt „1"). Das eingebaute
    /// Format `.decimal` erzeugt nur die nackte Ziffer.
    var markerFormat: NSTextList.MarkerFormat {
        switch self {
        case .bulleted: return .disc
        case .numbered: return NSTextList.MarkerFormat(rawValue: "{decimal}.")
        }
    }

    /// Erkennt die Listenart an der Formatvorlage eines Absatzes.
    ///
    /// - Parameter markerFormat: Formatvorlage der Liste, `nil` = keine Liste.
    /// - Returns: Listenart oder `nil`, wenn der Absatz keine Liste ist.
    static func from(markerFormat: NSTextList.MarkerFormat?) -> RichTextListStyle? {
        guard let raw = markerFormat?.rawValue else { return nil }
        return raw.contains("decimal") ? .numbered : .bulleted
    }
}

// MARK: - Steuerung

/// Bindeglied zwischen Formatierungsleiste und Textansicht.
///
/// Hält den Formatierungszustand an der Schreibmarke (für die Anzeige in
/// der Leiste) und wendet Formatierungen auf Markierung oder Eingabe an.
@Observable
final class RichTextController {

    /// Fett an der Schreibmarke aktiv.
    private(set) var isBold = false
    /// Kursiv an der Schreibmarke aktiv.
    private(set) var isItalic = false
    /// Unterstrichen an der Schreibmarke aktiv.
    private(set) var isUnderlined = false
    /// Schriftgröße an der Schreibmarke.
    private(set) var size: RichTextSize = .normal
    /// Listenart des Absatzes an der Schreibmarke, `nil` = keine Liste.
    private(set) var listStyle: RichTextListStyle?

    /// Gesteuerte Textansicht (schwach, gehört der SwiftUI-Ansicht).
    @ObservationIgnored weak var textView: PlatformTextView?
    /// Wird nach programmatischen Änderungen aufgerufen, damit die Bindung nachzieht.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Standardschrift für neuen Text.
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

    /// Schaltet Fett für Markierung bzw. Eingabe um.
    func toggleBold() { toggleTrait(.bold, actionName: "Fett") }

    /// Schaltet Kursiv für Markierung bzw. Eingabe um.
    func toggleItalic() { toggleTrait(.italic, actionName: "Kursiv") }

    /// Schaltet Unterstreichen für Markierung bzw. Eingabe um.
    func toggleUnderline() {
        applyToSelection(actionName: "Unterstreichen") { attributes in
            let isOn = (attributes[.underlineStyle] as? Int ?? 0) != 0
            attributes[.underlineStyle] = isOn ? 0 : NSUnderlineStyle.single.rawValue
        }
    }

    /// Setzt die Schriftgröße für Markierung bzw. Eingabe.
    ///
    /// - Parameter newSize: Gewünschte Größe.
    func setSize(_ newSize: RichTextSize) {
        applyToSelection(actionName: "Schriftgröße") { attributes in
            let font = (attributes[.font] as? PlatformFont) ?? Self.defaultFont
            attributes[.font] = font.withSize(newSize.rawValue)
        }
    }

    /// Setzt die Textfarbe für Markierung bzw. Eingabe.
    ///
    /// - Parameter color: Gewünschte Farbe.
    func setColor(_ color: PlatformColor) {
        applyToSelection(actionName: "Textfarbe") { attributes in
            attributes[.foregroundColor] = color
        }
    }

    /// Schaltet die Listenart für die markierten Absätze um.
    ///
    /// Verarbeitung: Ist die gewählte Art schon aktiv, wird die Liste
    /// aufgehoben; sonst erhalten alle betroffenen Absätze die Liste samt
    /// Einzug. Die Änderung ist ein eigener Rückgängig-Schritt.
    ///
    /// - Parameter style: Gewünschte Listenart.
    func toggleList(_ style: RichTextListStyle) {
        guard let storage = textView?.mwTextStorage else { return }
        let paragraphRange = paragraphRange(in: storage, for: selectedRange)
        let turnOff = listStyle == style

        performAttributeEdit(in: paragraphRange, actionName: "Liste") { storage in
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
        }
    }

    /// Setzt die Schreibmarke an das Textende und aktiviert den Editor.
    ///
    /// Verarbeitung: Wird aufgerufen, wenn unterhalb des Textes in die
    /// leere Fläche getippt wird – wie in Apple Mail landet die Marke dann
    /// hinter dem letzten Zeichen.
    func focusAtEnd() {
        guard let textView else { return }
        let end = NSRange(location: textView.mwTextStorage?.length ?? 0, length: 0)
        #if os(iOS)
        textView.becomeFirstResponder()
        textView.selectedRange = end
        #else
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(end)
        #endif
    }

    // MARK: Zustand

    /// Liest die Formatierung an der Schreibmarke aus und aktualisiert die
    /// beobachteten Werte für die Leiste.
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

    /// Aktuelle Markierung der Textansicht (leer, wenn keine Ansicht da ist).
    private var selectedRange: NSRange {
        #if os(iOS)
        textView?.selectedRange ?? NSRange(location: 0, length: 0)
        #else
        textView?.selectedRange() ?? NSRange(location: 0, length: 0)
        #endif
    }

    /// Attribute an der Schreibmarke.
    ///
    /// Verarbeitung: Bei einer Markierung zählt deren erstes Zeichen, sonst
    /// die Eingabeattribute (gelten für das nächste getippte Zeichen).
    ///
    /// - Parameter textView: Textansicht.
    /// - Returns: Wirksame Attribute.
    private func currentAttributes(of textView: PlatformTextView) -> [NSAttributedString.Key: Any] {
        let range = selectedRange
        if range.length > 0, let storage = textView.mwTextStorage, storage.length > range.location {
            return storage.attributes(at: range.location, effectiveRange: nil)
        }
        return textView.typingAttributes
    }

    /// Schaltet ein Schriftmerkmal (Fett/Kursiv) um.
    ///
    /// - Parameters:
    ///   - trait: Umzuschaltendes Merkmal.
    ///   - actionName: Name des Schritts im Menü „Widerrufen".
    private func toggleTrait(_ trait: FontTrait, actionName: String) {
        applyToSelection(actionName: actionName) { attributes in
            let font = (attributes[.font] as? PlatformFont) ?? Self.defaultFont
            attributes[.font] = font.togglingTrait(trait)
        }
    }

    /// Wendet eine Änderung auf die Markierung an – oder auf die
    /// Eingabeattribute, wenn nichts markiert ist.
    ///
    /// Verarbeitung: Bei einer Markierung wird jeder Teilbereich mit
    /// eigenen Attributen einzeln geändert, damit gemischte Formatierungen
    /// erhalten bleiben; die Änderung ist ein eigener Rückgängig-Schritt.
    /// Ohne Markierung ändern sich nur die Eingabeattribute – das ist kein
    /// Textinhalt und daher kein Rückgängig-Schritt (wie in Apple-Apps).
    ///
    /// - Parameters:
    ///   - actionName: Name des Schritts im Menü „Widerrufen".
    ///   - change: Änderung an den Attributen.
    private func applyToSelection(
        actionName: String,
        _ change: (inout [NSAttributedString.Key: Any]) -> Void
    ) {
        guard let textView else { return }
        let range = selectedRange

        if range.length == 0 {
            var attributes = textView.typingAttributes
            change(&attributes)
            textView.typingAttributes = attributes
            updateState()
            return
        }

        performAttributeEdit(in: range, actionName: actionName) { storage in
            storage.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
                var updated = attributes
                change(&updated)
                storage.setAttributes(updated, range: subRange)
            }
        }
    }

    // MARK: Rückgängig

    /// Ändert die Attribute eines Textbereichs als eigenen Rückgängig-Schritt.
    ///
    /// Verarbeitung: Eine direkte Änderung am Textspeicher geht an der
    /// Rückgängig-Verwaltung der Textansicht vorbei. Dann nähme „Widerrufen"
    /// statt der Formatierung das zuletzt Getippte zurück. Deshalb:
    /// - macOS: Die Änderung wird bei der Textansicht an- und abgemeldet
    ///   (`shouldChangeText` … `didChangeText`); `NSTextView` vermerkt sie
    ///   dann selbst.
    /// - iOS: `UITextView` bietet das nicht. Der vorherige Zustand des
    ///   Bereichs wird selbst beim `undoManager` der Textansicht hinterlegt.
    /// Danach zieht die Bindung nach.
    ///
    /// - Parameters:
    ///   - range: Betroffener Textbereich.
    ///   - actionName: Name des Schritts im Menü „Widerrufen".
    ///   - edit: Änderung am Textspeicher (nur Attribute, keine Zeichen).
    private func performAttributeEdit(
        in range: NSRange,
        actionName: String,
        _ edit: (NSTextStorage) -> Void
    ) {
        guard let textView, let storage = textView.mwTextStorage,
              range.length > 0, NSMaxRange(range) <= storage.length else { return }
        #if os(iOS)
        let before = storage.attributedSubstring(from: range)
        storage.beginEditing()
        edit(storage)
        storage.endEditing()
        registerAttributeUndo(in: range, restoring: before, actionName: actionName)
        #else
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        edit(storage)
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        #endif
        onChange?()
        updateState()
    }

    #if os(iOS)
    /// Hinterlegt den Zustand eines Bereichs als Rückgängig-Schritt (iOS).
    ///
    /// Verarbeitung: Wird der Schritt ausgeführt, stellt er den Zustand
    /// wieder her und hinterlegt dabei den aktuellen – so funktioniert
    /// auch „Wiederholen".
    ///
    /// - Parameters:
    ///   - range: Betroffener Textbereich.
    ///   - previous: Wiederherzustellender Zustand des Bereichs.
    ///   - actionName: Name des Schritts.
    private func registerAttributeUndo(
        in range: NSRange,
        restoring previous: NSAttributedString,
        actionName: String
    ) {
        guard let undoManager = textView?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.restoreAttributes(in: range, with: previous, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Stellt den hinterlegten Zustand eines Bereichs wieder her (iOS).
    ///
    /// Verarbeitung: Nur wenn der Bereich noch dieselben Zeichen enthält –
    /// so kann ein Rückgängig-Schritt nie Text überschreiben. Die
    /// Markierung bleibt erhalten.
    ///
    /// - Parameters:
    ///   - range: Betroffener Textbereich.
    ///   - previous: Wiederherzustellender Zustand.
    ///   - actionName: Name des Schritts (für „Wiederholen").
    private func restoreAttributes(
        in range: NSRange,
        with previous: NSAttributedString,
        actionName: String
    ) {
        guard let textView, let storage = textView.mwTextStorage,
              NSMaxRange(range) <= storage.length else { return }
        let current = storage.attributedSubstring(from: range)
        guard current.string == previous.string else { return }
        let selection = textView.selectedRange
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: previous)
        storage.endEditing()
        textView.selectedRange = selection
        registerAttributeUndo(in: range, restoring: current, actionName: actionName)
        onChange?()
        updateState()
    }
    #endif

    /// Bereich der Absätze, die eine Markierung berührt.
    ///
    /// Verarbeitung: Die Markierung wird zuerst auf den Text begrenzt, damit
    /// eine Marke hinter dem letzten Zeichen keinen Bereichsfehler auslöst.
    ///
    /// - Parameters:
    ///   - storage: Textspeicher.
    ///   - range: Markierung.
    /// - Returns: Bereich der betroffenen Absätze (leer bei leerem Text).
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

/// Umschaltbare Schriftmerkmale.
enum FontTrait { case bold, italic }

extension PlatformFont {
    /// Schaltet Fett bzw. Kursiv um und behält alle anderen Eigenschaften.
    ///
    /// - Parameter trait: Umzuschaltendes Merkmal.
    /// - Returns: Geänderte Schrift; unverändert, wenn die Schriftfamilie
    ///   das Merkmal nicht kennt.
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

/// Formatierbarer Editor, der mit seinem Text wächst.
///
/// Die Ansicht ist mindestens `minHeight` hoch und sonst so hoch wie ihr
/// Text. Sie gehört in eine umgebende `ScrollView`.
struct RichTextEditor: View {
    /// Bearbeiteter Text.
    @Binding var text: NSAttributedString
    /// Steuerung für die Formatierungsleiste.
    let controller: RichTextController
    /// Mindesthöhe, auch bei leerem oder kurzem Text.
    let minHeight: CGFloat

    /// Zuletzt gemessene Höhe des Textes samt Innenabstand.
    @State private var contentHeight: CGFloat = 0

    /// Legt den Editor an.
    ///
    /// - Parameters:
    ///   - text: Bindung an den bearbeiteten Text.
    ///   - controller: Steuerung für die Formatierungsleiste.
    ///   - minHeight: Mindesthöhe in Punkt.
    init(
        text: Binding<NSAttributedString>,
        controller: RichTextController,
        minHeight: CGFloat = 160
    ) {
        _text = text
        self.controller = controller
        self.minHeight = minHeight
    }

    var body: some View {
        RichTextViewRepresentable(
            text: $text, contentHeight: $contentHeight, controller: controller
        )
        .frame(height: max(minHeight, contentHeight))
    }
}

/// Plattform-Brücke zur Textansicht.
private struct RichTextViewRepresentable {
    /// Bearbeiteter Text.
    @Binding var text: NSAttributedString
    /// Gemessene Höhe des Textes (wird von der Textansicht gemeldet).
    @Binding var contentHeight: CGFloat
    /// Steuerung für die Formatierungsleiste.
    let controller: RichTextController

    /// Legt den Coordinator (Bindungen, Höhenmeldung) an.
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, contentHeight: $contentHeight, controller: controller)
    }

    /// Vermittelt zwischen Textansicht und SwiftUI.
    final class Coordinator: NSObject {
        /// Bindung an den bearbeiteten Text.
        @Binding private var text: NSAttributedString
        /// Bindung an die gemessene Höhe.
        @Binding private var contentHeight: CGFloat
        /// Steuerung für die Formatierungsleiste.
        let controller: RichTextController

        /// Legt den Coordinator an.
        ///
        /// - Parameters:
        ///   - text: Bindung an den Text.
        ///   - contentHeight: Bindung an die gemessene Höhe.
        ///   - controller: Steuerung für die Formatierungsleiste.
        init(
            text: Binding<NSAttributedString>,
            contentHeight: Binding<CGFloat>,
            controller: RichTextController
        ) {
            _text = text
            _contentHeight = contentHeight
            self.controller = controller
        }

        /// Verbindet Steuerung und Textansicht.
        ///
        /// Verarbeitung: Programmatische Änderungen der Steuerung (Liste,
        /// Formatierung einer Markierung) übernehmen den Text in die Bindung
        /// und messen die Höhe neu.
        ///
        /// - Parameter textView: Neu angelegte Textansicht.
        func attach(_ textView: PlatformTextView) {
            controller.textView = textView
            controller.onChange = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.pushText(from: textView)
            }
            controller.updateState()
        }

        /// Übernimmt den Text der Ansicht in die Bindung und misst neu.
        ///
        /// - Parameter textView: Textansicht.
        func pushText(from textView: PlatformTextView) {
            guard let storage = textView.mwTextStorage else { return }
            text = NSAttributedString(attributedString: storage)
            updateHeight(of: textView)
        }

        /// Misst die Höhe des Textes und meldet sie, wenn sie sich geändert hat.
        ///
        /// Verarbeitung: Die Meldung erfolgt verzögert auf dem Main-Thread,
        /// weil sie auch während einer Aktualisierung der Ansicht ausgelöst
        /// werden kann – dort darf der Zustand nicht geändert werden.
        /// Kleinstabweichungen werden ignoriert, damit keine Mess-Schleife
        /// entsteht.
        ///
        /// - Parameter textView: Zu messende Textansicht.
        func updateHeight(of textView: PlatformTextView) {
            #if os(iOS)
            guard let growing = textView as? GrowingTextView else { return }
            #else
            guard let growing = textView as? GrowingNSTextView else { return }
            #endif
            let height = growing.fittingHeight()
            guard height > 0, abs(height - contentHeight) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.contentHeight = height
            }
        }
    }
}

#if os(iOS)
/// Textansicht ohne eigenes Scrollen, die ihre Höhe misst (iOS).
final class GrowingTextView: UITextView {
    /// Wird nach jedem Layout aufgerufen, damit die Höhe neu gemessen wird
    /// (z. B. nach Drehen des Geräts).
    var onLayout: ((GrowingTextView) -> Void)?
    /// Höhe beim letzten Layout – erkennt, ob der Editor gewachsen ist.
    private var lastLayoutHeight: CGFloat = 0

    /// Misst nach dem Layout neu und rückt die Schreibmarke ins Bild, wenn
    /// sich die Höhe geändert hat (der Editor ist gewachsen).
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
        if bounds.height != lastLayoutHeight {
            lastLayoutHeight = bounds.height
            scrollCaretIntoView()
        }
    }

    /// Höhe, die der gesamte Text bei der aktuellen Breite braucht.
    ///
    /// - Returns: Höhe samt Innenabstand; 0, solange noch keine Breite feststeht.
    func fittingHeight() -> CGFloat {
        guard bounds.width > 0 else { return 0 }
        let size = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        return ceil(size.height)
    }

    /// Rückt die Schreibmarke in der umgebenden Scroll-Ansicht ins Bild.
    ///
    /// Verarbeitung: Nur wenn der Editor aktiv ist. Gesucht wird die
    /// nächste Scroll-Ansicht oberhalb (die SwiftUI-`ScrollView`); die
    /// Marke wird mit etwas Rand sichtbar gemacht. Die Tastatur ist schon
    /// berücksichtigt, weil SwiftUI die Scroll-Ansicht vor ihr verkleinert.
    func scrollCaretIntoView() {
        guard isFirstResponder, let range = selectedTextRange else { return }
        let caret = caretRect(for: range.end)
        guard !caret.isNull, !caret.isInfinite else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) {
            ancestor = view.superview
        }
        guard let scrollView = ancestor as? UIScrollView else { return }
        let target = convert(caret, to: scrollView).insetBy(dx: 0, dy: -16)
        scrollView.scrollRectToVisible(target, animated: false)
    }
}

extension RichTextViewRepresentable: UIViewRepresentable {

    /// Legt die Textansicht einmalig an.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Konfigurierte Textansicht ohne eigenes Scrollen.
    func makeUIView(context: Context) -> GrowingTextView {
        let textView = GrowingTextView()
        textView.allowsEditingTextAttributes = true
        textView.isEditable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.typingAttributes = RichTextController.defaultAttributes
        textView.attributedText = text
        textView.delegate = context.coordinator
        textView.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.updateHeight(of: view)
        }
        context.coordinator.attach(textView)
        return textView
    }

    /// Übernimmt eine von außen geänderte Bindung in die Ansicht.
    ///
    /// - Parameters:
    ///   - textView: Angezeigte Textansicht.
    ///   - context: Kontext mit dem Coordinator.
    func updateUIView(_ textView: GrowingTextView, context: Context) {
        // Nur setzen, wenn die Bindung von außen geändert wurde
        if textView.attributedText != text {
            let selection = textView.selectedRange
            textView.attributedText = text
            textView.selectedRange = selection
            context.coordinator.updateHeight(of: textView)
        }
    }

    /// Größe der Ansicht: die angebotene Breite und Höhe.
    ///
    /// Verarbeitung: Ohne eigenes Scrollen meldet eine Textansicht als
    /// natürliche Breite die Länge der längsten Zeile – die Ansicht würde
    /// über den Rand hinauswachsen. Deshalb gilt die angebotene Breite;
    /// die Höhe legt der Rahmen in `RichTextEditor` fest.
    ///
    /// - Parameters:
    ///   - proposal: Angebotene Größe.
    ///   - uiView: Textansicht.
    ///   - context: Kontext.
    /// - Returns: Größe oder `nil` (Standardverhalten), wenn keine Breite angeboten wird.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GrowingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? max(contentHeight, 1)
        return CGSize(width: width, height: height)
    }
}

extension RichTextViewRepresentable.Coordinator: UITextViewDelegate {
    /// Getippter Text: Bindung nachziehen und neu messen.
    ///
    /// - Parameter textView: Geänderte Textansicht.
    func textViewDidChange(_ textView: UITextView) {
        pushText(from: textView)
    }

    /// Marke versetzt: Leiste aktualisieren und Marke ins Bild rücken.
    ///
    /// Verarbeitung: Das Rücken geschieht verzögert, damit ein gleichzeitiges
    /// Wachsen des Editors schon berücksichtigt ist.
    ///
    /// - Parameter textView: Betroffene Textansicht.
    func textViewDidChangeSelection(_ textView: UITextView) {
        controller.updateState()
        DispatchQueue.main.async { [weak textView] in
            (textView as? GrowingTextView)?.scrollCaretIntoView()
        }
    }
}
#else
/// Textansicht ohne eigene Scroll-Ansicht, die ihre Höhe misst (macOS).
final class GrowingNSTextView: NSTextView {
    /// Wird bei geänderter Breite aufgerufen, damit die Höhe neu gemessen wird.
    var onLayout: ((GrowingNSTextView) -> Void)?

    /// Übernimmt eine neue Größe.
    ///
    /// Verarbeitung: Neue Breite → Zeilen brechen anders um, also neu
    /// messen. Neue Höhe → der Editor ist gewachsen, also die Schreibmarke
    /// ins Bild rücken.
    ///
    /// - Parameter newSize: Neue Größe.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        let heightChanged = newSize.height != frame.height
        super.setFrameSize(newSize)
        if widthChanged { onLayout?(self) }
        if heightChanged { scrollCaretIntoView() }
    }

    /// Höhe, die der gesamte Text bei der aktuellen Breite braucht.
    ///
    /// Verarbeitung: Misst über TextKit 2. Der Zugriff auf `layoutManager`
    /// wird bewusst vermieden – er schaltet die Ansicht auf TextKit 1 zurück.
    ///
    /// - Returns: Höhe samt Innenabstand; 0 ohne TextKit 2.
    func fittingHeight() -> CGFloat {
        guard let layoutManager = textLayoutManager else { return 0 }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let textHeight = layoutManager.usageBoundsForTextContainer.height
        return ceil(textHeight + textContainerInset.height * 2)
    }

    /// Rückt die Schreibmarke in der umgebenden Scroll-Ansicht ins Bild,
    /// sofern der Editor aktiv ist.
    func scrollCaretIntoView() {
        guard window?.firstResponder === self else { return }
        scrollRangeToVisible(selectedRange())
    }
}

extension RichTextViewRepresentable: NSViewRepresentable {

    /// Legt die Textansicht einmalig an.
    ///
    /// Verarbeitung: Die Ansicht liegt bewusst nicht in einer eigenen
    /// Scroll-Ansicht. Die Breite des Textbereichs folgt der Ansicht, die
    /// Höhe ist unbegrenzt; den Rahmen setzt SwiftUI.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Konfigurierte Textansicht.
    func makeNSView(context: Context) -> GrowingNSTextView {
        let textView = GrowingNSTextView(usingTextLayoutManager: true)
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        textView.typingAttributes = RichTextController.defaultAttributes
        textView.textStorage?.setAttributedString(text)
        textView.delegate = context.coordinator
        textView.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.updateHeight(of: view)
        }
        context.coordinator.attach(textView)
        return textView
    }

    /// Übernimmt eine von außen geänderte Bindung in die Ansicht.
    ///
    /// - Parameters:
    ///   - textView: Angezeigte Textansicht.
    ///   - context: Kontext mit dem Coordinator.
    func updateNSView(_ textView: GrowingNSTextView, context: Context) {
        guard let storage = textView.textStorage else { return }
        if storage != text {
            let selection = textView.selectedRange()
            storage.setAttributedString(text)
            textView.setSelectedRange(selection)
            context.coordinator.updateHeight(of: textView)
        }
    }

    /// Größe der Ansicht: die angebotene Breite und Höhe.
    ///
    /// Verarbeitung: Die Breite kommt vom Fenster, die Höhe legt der
    /// Rahmen in `RichTextEditor` fest.
    ///
    /// - Parameters:
    ///   - proposal: Angebotene Größe.
    ///   - nsView: Textansicht.
    ///   - context: Kontext.
    /// - Returns: Größe oder `nil` (Standardverhalten), wenn keine Breite angeboten wird.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GrowingNSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? max(contentHeight, 1)
        return CGSize(width: width, height: height)
    }
}

extension RichTextViewRepresentable.Coordinator: NSTextViewDelegate {
    /// Getippter Text: Bindung nachziehen und neu messen.
    ///
    /// - Parameter notification: Änderungsmeldung der Textansicht.
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        pushText(from: textView)
    }

    /// Marke versetzt: Leiste aktualisieren. Das Scrollen zur Marke
    /// übernimmt die Textansicht unter macOS selbst.
    ///
    /// - Parameter notification: Änderungsmeldung der Textansicht.
    func textViewDidChangeSelection(_ notification: Notification) {
        controller.updateState()
    }
}
#endif

// MARK: - Plattform-Hilfen

extension PlatformTextView {
    /// Einheitlicher Zugriff auf den Textspeicher.
    ///
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
