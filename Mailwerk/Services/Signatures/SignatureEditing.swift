//
//  SignatureEditing.swift
//  Mailwerk
//
//  Zweck: Umwandlungen zwischen gespeicherter Signatur (HTML mit
//  Logo-Platzhalter) und formatiertem Text im Editor:
//  - HTML → Editor: der Platzhalter `<img src="logo">` wird zum Logo-Bild
//    (`MailImageAttachment` mit Platzhalter „logo“), Breite aus dem HTML
//    oder 150 pt.
//  - Editor → HTML: das Logo wird wieder zum Platzhalter; andere Bilder
//    entfallen (eine Signatur kennt nur das eine Logo).
//  - Logo tauschen oder entfernen, während der Text im Editor steht.
//  - Beim Verfassen: die einfache Signatur in den Mailtext einsetzen bzw.
//    austauschen. Der eingesetzte Text trägt das Attribut
//    `.mailwerkSignature`; so lässt er sich beim Wechsel des Postfachs
//    wiederfinden – auch wenn der Nutzer darin etwas geändert hat.
//
//  Abgrenzung: Einlesen → RichTextImport; HTML erzeugen → RichTextHTML;
//  Regeln und Platzhalter → SignatureRules; Pflege-Seite →
//  SignatureEditorView. Einsetzen beim Verfassen → ComposeViewModel.
//
//  Abhängigkeiten: Foundation, UIKit bzw. AppKit, RichTextImport,
//  RichTextHTML, MailImageAttachment, SignatureRules.
//

import Foundation

#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension NSAttributedString.Key {
    /// Markiert eine eingesetzte Signatur im Mailtext (Wert: `true`).
    static let mailwerkSignature = NSAttributedString.Key("de.sieber-bw.mailwerk.signature")
}

/// Umwandlungen für die Bearbeitung einer Signatur im Editor.
enum SignatureEditing {

    // MARK: - Einsetzen beim Verfassen

    /// Ergebnis beim Austauschen der Signatur im Mailtext.
    struct Replacement {
        /// Neuer Mailtext.
        let text: NSAttributedString
        /// `true`, wenn im alten Text eine eingesetzte Signatur stand.
        let hadSignature: Bool
    }

    /// Eingesetzte Signatur für den Mailtext: Text der Signatur, ganz mit
    /// `.mailwerkSignature` markiert.
    ///
    /// - Parameters:
    ///   - html: HTML der (einfachen) Signatur.
    ///   - logoData: Bilddaten des Logos.
    /// - Returns: Markierter Text.
    static func markedSignature(html: String, logoData: Data?) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: editorText(html: html, logoData: logoData).text)
        result.addAttribute(.mailwerkSignature, value: true, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Setzt eine Signatur in den Mailtext ein bzw. tauscht sie aus.
    ///
    /// Verarbeitung:
    /// - Steht schon eine markierte Signatur im Text, wird ihr ganzer
    ///   Bereich (vom ersten bis zum letzten markierten Zeichen) durch die
    ///   neue ersetzt bzw. ohne neue Signatur gelöscht.
    /// - Sonst wird die neue Signatur am Ende angefügt, getrennt durch eine
    ///   Leerzeile; ein leerer Text erhält davor zwei leere Zeilen (oben
    ///   schreiben, eine Leerzeile, dann die Signatur).
    ///
    /// - Parameters:
    ///   - signature: Markierte Signatur oder `nil` (nur entfernen).
    ///   - body: Bisheriger Mailtext.
    /// - Returns: Neuer Text und ob eine Signatur vorhanden war.
    static func replacingSignature(_ signature: NSAttributedString?, in body: NSAttributedString) -> Replacement {
        let result = NSMutableAttributedString(attributedString: body)
        var first: Int?
        var last = 0
        result.enumerateAttribute(.mailwerkSignature, in: NSRange(location: 0, length: result.length), options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            if first == nil { first = range.location }
            last = NSMaxRange(range)
        }

        if let first {
            let range = NSRange(location: first, length: last - first)
            result.replaceCharacters(in: range, with: signature ?? NSAttributedString())
            return Replacement(text: result, hadSignature: true)
        }

        if let signature, signature.length > 0 {
            let separator: String
            if result.length == 0 {
                separator = "\n\n"
            } else if result.string.hasSuffix("\n") {
                separator = "\n"
            } else {
                separator = "\n\n"
            }
            result.append(NSAttributedString(string: separator, attributes: RichTextController.defaultAttributes))
            result.append(signature)
        }
        return Replacement(text: result, hadSignature: false)
    }

    /// Teile des Mailtexts rund um die eingesetzte Signatur.
    struct Split {
        /// Text vor der Signatur.
        let before: NSAttributedString
        /// Die Signatur; `nil`, wenn keine markiert ist.
        let signature: NSAttributedString?
        /// Text nach der Signatur.
        let after: NSAttributedString
    }

    /// Zerlegt den Mailtext an der markierten Signatur (für Entwürfe).
    ///
    /// Verarbeitung: Der Bereich vom ersten bis zum letzten markierten
    /// Zeichen ist die Signatur; ohne Markierung ist alles „vorher“.
    ///
    /// - Parameter body: Mailtext.
    /// - Returns: Text vorher, Signatur, Text nachher.
    static func split(_ body: NSAttributedString) -> Split {
        var first: Int?
        var last = 0
        body.enumerateAttribute(.mailwerkSignature, in: NSRange(location: 0, length: body.length), options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            if first == nil { first = range.location }
            last = NSMaxRange(range)
        }
        guard let first else {
            return Split(before: body, signature: nil, after: NSAttributedString())
        }
        return Split(
            before: body.attributedSubstring(from: NSRange(location: 0, length: first)),
            signature: body.attributedSubstring(from: NSRange(location: first, length: last - first)),
            after: body.attributedSubstring(from: NSRange(location: last, length: body.length - last))
        )
    }

    // MARK: - Pflege-Seite

    /// Logo als Bild für den Editor.
    ///
    /// - Parameters:
    ///   - data: Bilddaten des Logos.
    ///   - width: Breite in Punkt; `nil` = 150 pt.
    ///   - contentID: Content-ID; `nil` = neu vergeben.
    /// - Returns: Bild mit Platzhalter „logo“ oder `nil` bei unlesbaren Daten.
    static func logoAttachment(data: Data, width: Int? = nil, contentID: String? = nil) -> MailImageAttachment? {
        MailImageAttachment.make(
            from: data,
            displayWidth: CGFloat(width ?? SignatureRules.defaultLogoWidth),
            contentID: contentID,
            placeholder: SignatureRules.logoPlaceholder
        )
    }

    /// Formatierter Text einer Signatur.
    ///
    /// Verarbeitung: Das HTML wird eingelesen; der Logo-Platzhalter wird
    /// durch das Logo ersetzt. Alle Logos eines Texts teilen dieselbe
    /// Content-ID, damit beim Versand nur ein Inline-Teil entsteht.
    ///
    /// - Parameters:
    ///   - html: HTML der Signatur.
    ///   - logoData: Bilddaten des Logos; `nil` = Platzhalter entfallen.
    /// - Returns: Text samt Angabe, ob beim Einlesen etwas wegfiel.
    static func editorText(html: String, logoData: Data?) -> RichTextImport.Result {
        let contentID = MailImageAttachment.newContentID()
        return RichTextImport.attributedString(fromHTML: html) { source, width in
            guard source.lowercased() == SignatureRules.logoPlaceholder, let logoData else { return nil }
            return logoAttachment(data: logoData, width: width, contentID: contentID)
        }
    }

    /// HTML aus dem Editor mit Logo-Platzhalter.
    ///
    /// - Parameter text: Formatierter Text der Signatur.
    /// - Returns: Lesbar umbrochenes HTML; Bilder ohne Platzhalter entfallen.
    static func html(from text: NSAttributedString) -> String {
        SignatureRules.readableHTML(RichTextHTML.html(from: text) { $0.placeholder })
    }

    /// Anzahl der Bilder im Text, die nicht das Logo sind.
    ///
    /// - Parameter text: Formatierter Text der Signatur.
    /// - Returns: Anzahl (wird beim Sichern nicht übernommen).
    static func foreignImageCount(in text: NSAttributedString) -> Int {
        var count = 0
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length), options: []) { value, _, _ in
            if let value, (value as? MailImageAttachment)?.placeholder == nil { count += 1 }
        }
        return count
    }

    /// Tauscht das Logo im Text aus oder entfernt es.
    ///
    /// Verarbeitung: Jedes Logo-Bild wird durch das neue Logo in derselben
    /// Breite ersetzt; ohne neues Logo wird es aus dem Text gelöscht.
    /// Andere Bilder bleiben unberührt.
    ///
    /// - Parameters:
    ///   - text: Formatierter Text der Signatur.
    ///   - logoData: Neue Bilddaten; `nil` = Logo entfernen.
    /// - Returns: Geänderter Text.
    static func replacingLogo(in text: NSAttributedString, with logoData: Data?) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        var ranges: [(NSRange, MailImageAttachment)] = []
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length), options: []) { value, range, _ in
            if let image = value as? MailImageAttachment, image.placeholder != nil {
                ranges.append((range, image))
            }
        }
        let contentID = MailImageAttachment.newContentID()
        for (range, old) in ranges.reversed() {
            if let logoData,
               let replacement = logoAttachment(data: logoData, width: Int(old.displayWidth), contentID: contentID) {
                result.addAttribute(.attachment, value: replacement, range: range)
            } else {
                result.deleteCharacters(in: range)
            }
        }
        return result
    }
}
