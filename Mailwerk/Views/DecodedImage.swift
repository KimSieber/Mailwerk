//
//  DecodedImage.swift
//  Mailwerk
//
//  Zweck: Erzeugt aus Bilddaten (JPEG, PNG …) ein SwiftUI-Bild – auf iOS
//  über UIKit, auf dem Mac über AppKit. Gemeinsam genutzt von
//  Kontaktbildern und Absenderlogos.
//
//  Abgrenzung: Kontaktbilder → ContactImageDirectory; Logos →
//  SenderIconCache.
//
//  Abhängigkeiten: SwiftUI, UIKit bzw. AppKit.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Umwandlung von Bilddaten in ein SwiftUI-Bild.
enum DecodedImage {

    /// Erzeugt ein SwiftUI-Bild aus Bilddaten.
    ///
    /// - Parameter data: Bilddaten.
    /// - Returns: Bild oder `nil` bei unlesbaren Daten.
    static func image(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}
