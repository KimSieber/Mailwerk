//
//  DecodedImage.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 11.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Erzeugt aus Bilddaten (JPEG, PNG …) ein SwiftUI-Bild – auf iOS
//  über UIKit, auf dem Mac über AppKit. Gemeinsam genutzt von
//  Kontaktbildern und Absenderlogos.
//
//  Verkleinert (v0.2.3c, Prüfbericht P-09): `thumbnail(from:maxPixelSize:)`
//  dekodiert über ImageIO direkt auf die gewünschte Kantenlänge und
//  abseits des Hauptthreads. Für die Kreise der Mailliste reichen 120
//  Pixel; bisher wurde jedes Bild in voller Auflösung beim ersten
//  Zeichnen auf dem Hauptthread dekodiert.
//
//  Abgrenzung: Kontaktbilder → ContactImageDirectory; Logos →
//  SenderIconCache.
//
//  Abhängigkeiten: SwiftUI, ImageIO, UIKit bzw. AppKit.
//

import SwiftUI
import ImageIO
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

    /// Erzeugt ein verkleinertes Bild abseits des Hauptthreads.
    ///
    /// Verarbeitung: ImageIO erzeugt ein Vorschaubild mit höchstens
    /// `maxPixelSize` Pixeln an der längeren Kante, beachtet die
    /// Ausrichtung und dekodiert sofort (`ShouldCacheImmediately`) – das
    /// Zeichnen muss danach nichts mehr dekodieren. Die Anzeige skaliert
    /// das Bild ohnehin (`resizable`), der Maßstab spielt daher keine Rolle.
    ///
    /// - Parameters:
    ///   - data: Bilddaten (JPEG, PNG …).
    ///   - maxPixelSize: Größte Kantenlänge in Pixeln.
    /// - Returns: Bild oder `nil`, wenn die Daten kein lesbares Bild sind.
    @concurrent
    nonisolated static func thumbnail(from data: Data, maxPixelSize: Int) async -> Image? {
        guard let cgImage = thumbnailImage(from: data, maxPixelSize: maxPixelSize) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }

    /// Verkleinertes, sofort dekodiertes Bild als `CGImage` (Kern von
    /// `thumbnail`, einzeln prüfbar).
    ///
    /// - Parameters:
    ///   - data: Bilddaten.
    ///   - maxPixelSize: Größte Kantenlänge in Pixeln.
    /// - Returns: Bild oder `nil`, wenn die Daten kein lesbares Bild sind.
    nonisolated static func thumbnailImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
