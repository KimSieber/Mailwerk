//
//  CodeTextEditor.swift
//  Mailwerk
//
//  Zweck: Eingabefeld für Quelltext (z. B. den HTML-Code einer Signatur).
//  Festbreitenschrift, ohne Autokorrektur, ohne automatische
//  Großschreibung und – wichtig für HTML – ohne typografische
//  Anführungszeichen und Striche: Ein „schönes“ Anführungszeichen statt
//  `"` würde das HTML unbrauchbar machen. SwiftUIs `TextEditor` bietet
//  dafür keine Einstellung, deshalb kapselt diese Ansicht UITextView
//  (iOS) bzw. NSTextView (macOS).
//
//  Das Feld scrollt selbst; die Höhe legt der Aufrufer per `frame` fest.
//
//  Abgrenzung: Formatierter Text → RichTextEditor; Pflege der Signatur →
//  SignatureEditorView.
//
//  Abhängigkeiten: SwiftUI, UIKit bzw. AppKit.
//

import SwiftUI

#if os(iOS)
import UIKit

/// Eingabefeld für Quelltext (iOS).
struct CodeTextEditor: UIViewRepresentable {
    /// Bearbeiteter Text.
    @Binding var text: String

    /// Legt den Coordinator (Rückmeldung von Eingaben) an.
    ///
    /// - Returns: Coordinator mit Bindung an den Text.
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Legt die Textansicht einmalig an.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Textansicht ohne automatische Ersetzungen.
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardType = .asciiCapable
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.text = text
        textView.delegate = context.coordinator
        return textView
    }

    /// Übernimmt einen von außen geänderten Text.
    ///
    /// - Parameters:
    ///   - textView: Angezeigte Textansicht.
    ///   - context: Kontext.
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text { textView.text = text }
    }

    /// Meldet Eingaben an die Bindung.
    final class Coordinator: NSObject, UITextViewDelegate {
        /// Bindung an den Text.
        @Binding private var text: String

        /// Legt den Coordinator an.
        ///
        /// - Parameter text: Bindung an den Text.
        init(text: Binding<String>) { _text = text }

        /// Getippter Text: Bindung nachziehen.
        ///
        /// - Parameter textView: Geänderte Textansicht.
        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
#else
import AppKit

/// Eingabefeld für Quelltext (macOS).
struct CodeTextEditor: NSViewRepresentable {
    /// Bearbeiteter Text.
    @Binding var text: String

    /// Legt den Coordinator (Rückmeldung von Eingaben) an.
    ///
    /// - Returns: Coordinator mit Bindung an den Text.
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Legt Textansicht samt Scroll-Ansicht einmalig an.
    ///
    /// - Parameter context: Kontext mit dem Coordinator.
    /// - Returns: Scroll-Ansicht mit der Textansicht ohne automatische Ersetzungen.
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.string = text
        textView.delegate = context.coordinator
        return scrollView
    }

    /// Übernimmt einen von außen geänderten Text.
    ///
    /// - Parameters:
    ///   - scrollView: Angezeigte Scroll-Ansicht.
    ///   - context: Kontext.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
    }

    /// Meldet Eingaben an die Bindung.
    final class Coordinator: NSObject, NSTextViewDelegate {
        /// Bindung an den Text.
        @Binding private var text: String

        /// Legt den Coordinator an.
        ///
        /// - Parameter text: Bindung an den Text.
        init(text: Binding<String>) { _text = text }

        /// Getippter Text: Bindung nachziehen.
        ///
        /// - Parameter notification: Änderungsmeldung der Textansicht.
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
#endif
