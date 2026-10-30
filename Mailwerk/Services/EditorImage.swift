//
//  EditorImage.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 12.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Bilder im formatierten Editor (z. B. Logo einer Signatur oder
//  ein eingefügtes Foto).
//
//  - `MailImageAttachment`: Bild im Text samt den Daten zum Versenden,
//    MIME-Typ, Content-ID und Anzeigebreite. Beim Senden wird daraus ein
//    Inline-Teil, das HTML spricht es per `cid:` an (RichTextHTML).
//  - `EditorImageData`: bereitet Bilddaten auf – verkleinert große Bilder
//    und wandelt Formate wie HEIC in JPEG bzw. PNG (mit Transparenz).
//  - `EditorImages.normalize`: Bilder, die das System beim Einfügen oder
//    Ziehen anlegt, werden durch `MailImageAttachment` ersetzt, damit
//    jedes Bild im Text auch versendet wird.
//
//  Beim Kopieren innerhalb des Editors wird ein Bild als gewöhnlicher
//  Anhang des Systems weitergereicht (samt Daten) und danach wieder
//  aufbereitet; es erhält dabei eine neue Content-ID.
//
//  Abgrenzung: Umwandlung nach HTML und Liste der Inline-Teile →
//  RichTextHTML; Einlesen aus HTML → RichTextImport; Editor →
//  RichTextEditor.
//
//  Abhängigkeiten: Foundation, ImageIO, UniformTypeIdentifiers, UIKit bzw.
//  AppKit.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Bild im Text

/// Bild im Editor mit allem, was zum Versenden nötig ist.
nonisolated final class MailImageAttachment: NSTextAttachment {
    /// Bilddaten, wie sie versendet werden.
    let imageData: Data
    /// MIME-Typ der Bilddaten, z. B. „image/png“.
    let mimeType: String
    /// Content-ID ohne spitze Klammern, unter der das HTML das Bild anspricht.
    let contentID: String
    /// Anzeigebreite in Punkt (im Editor und im versendeten HTML).
    let displayWidth: CGFloat
    /// Platzhalter im HTML einer Signatur (z. B. „logo“); `nil` = keiner.
    let placeholder: String?

    /// Größte Kantenlänge eingefügter Bilder in Pixeln.
    static let maxPixelSize = 1600
    /// Größte Anzeigebreite in Punkt.
    static let maxDisplayWidth: CGFloat = 600

    /// Legt ein Bild aus aufbereiteten Daten an.
    ///
    /// Verarbeitung: Die Daten werden auch als Inhalt des Systemanhangs
    /// hinterlegt – so überstehen sie Kopieren und Einfügen. Die Höhe
    /// ergibt sich aus der Breite und dem Seitenverhältnis.
    ///
    /// - Parameters:
    ///   - prepared: Aufbereitete Bilddaten (`EditorImageData.prepare`).
    ///   - displayWidth: Anzeigebreite in Punkt; `nil` = aus der Pixelbreite.
    ///   - contentID: Content-ID; `nil` = neu vergeben.
    ///   - placeholder: Platzhalter im Signatur-HTML.
    init(
        prepared: EditorImageData.Prepared,
        displayWidth: CGFloat? = nil,
        contentID: String? = nil,
        placeholder: String? = nil
    ) {
        imageData = prepared.data
        mimeType = prepared.mimeType
        self.contentID = contentID ?? Self.newContentID()
        self.placeholder = placeholder
        let width = min(displayWidth ?? Self.defaultDisplayWidth(pixelWidth: prepared.pixelWidth), Self.maxDisplayWidth)
        self.displayWidth = max(width, 1)
        let uti = UTType(mimeType: prepared.mimeType)?.identifier ?? UTType.image.identifier
        super.init(data: prepared.data, ofType: uti)

        #if os(iOS)
        image = UIImage(data: prepared.data)
        #else
        image = NSImage(data: prepared.data)
        #endif
        let ratio = prepared.pixelWidth > 0 ? CGFloat(prepared.pixelHeight) / CGFloat(prepared.pixelWidth) : 1
        bounds = CGRect(x: 0, y: 0, width: self.displayWidth, height: (self.displayWidth * ratio).rounded())
    }

    /// Wird nicht unterstützt – beim Archivieren gilt das Bild als
    /// gewöhnlicher Systemanhang (siehe `classForCoder`).
    ///
    /// - Parameter coder: Archiv.
    required init?(coder: NSCoder) {
        return nil
    }

    /// Archiviert als gewöhnlicher Systemanhang (Kopieren, Einfügen,
    /// Rückgängig); `EditorImages.normalize` bereitet ihn danach wieder auf.
    override var classForCoder: AnyClass { NSTextAttachment.self }

    /// Legt ein Bild aus beliebigen Bilddaten an.
    ///
    /// - Parameters:
    ///   - data: Bilddaten (PNG, JPEG, GIF, HEIC, TIFF …).
    ///   - displayWidth: Anzeigebreite in Punkt; `nil` = aus der Pixelbreite.
    ///   - contentID: Content-ID; `nil` = neu vergeben.
    ///   - placeholder: Platzhalter im Signatur-HTML.
    /// - Returns: Bild oder `nil`, wenn die Daten kein lesbares Bild sind.
    static func make(
        from data: Data,
        displayWidth: CGFloat? = nil,
        contentID: String? = nil,
        placeholder: String? = nil
    ) -> MailImageAttachment? {
        guard let prepared = EditorImageData.prepare(data, maxPixelSize: maxPixelSize) else { return nil }
        return MailImageAttachment(
            prepared: prepared, displayWidth: displayWidth, contentID: contentID, placeholder: placeholder
        )
    }

    /// Anzeigebreite ohne Vorgabe: halbe Pixelbreite (scharf auf
    /// Retina-Bildschirmen), höchstens 300 pt.
    ///
    /// - Parameter pixelWidth: Breite des Bildes in Pixeln.
    /// - Returns: Breite in Punkt.
    static func defaultDisplayWidth(pixelWidth: Int) -> CGFloat {
        min(CGFloat(pixelWidth) / 2, 300)
    }

    /// Neue, weltweit eindeutige Content-ID.
    ///
    /// - Returns: z. B. „bild-1f0c…@mailwerk“.
    static func newContentID() -> String {
        "bild-\(UUID().uuidString.lowercased())@mailwerk"
    }

    /// Dateiname des Inline-Teils, z. B. „bild-1.png“.
    ///
    /// - Parameter number: Laufende Nummer in der Mail.
    /// - Returns: Dateiname mit passender Endung.
    func filename(number: Int) -> String {
        let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "png"
        return "bild-\(number).\(ext)"
    }
}

// MARK: - Bilddaten aufbereiten

/// Aufbereitung von Bilddaten für Editor und Versand.
nonisolated enum EditorImageData {
    /// JPEG-Qualität beim Verkleinern (0…1) – kaum sichtbare Verluste bei
    /// deutlich kleineren Dateien.
    static let jpegQuality = 0.85

    /// Aufbereitete Bilddaten.
    struct Prepared: Equatable {
        /// Bilddaten.
        let data: Data
        /// MIME-Typ: „image/png“, „image/jpeg“ oder „image/gif“.
        let mimeType: String
        /// Breite in Pixeln.
        let pixelWidth: Int
        /// Höhe in Pixeln.
        let pixelHeight: Int
    }

    /// MIME-Typen, die unverändert übernommen werden.
    private static let keptTypes: [String: String] = [
        UTType.png.identifier: "image/png",
        UTType.jpeg.identifier: "image/jpeg",
        UTType.gif.identifier: "image/gif"
    ]

    /// Bereitet Bilddaten auf.
    ///
    /// Verarbeitung: PNG, JPEG und GIF, die klein genug und richtig
    /// gedreht sind, bleiben unverändert (keine erneute Kompression, GIF
    /// behält seine Animation). Alles andere wird über ImageIO verkleinert,
    /// gedreht und als PNG (mit Transparenz) bzw. JPEG (Qualität 0,85)
    /// neu geschrieben.
    ///
    /// - Parameters:
    ///   - data: Beliebige Bilddaten.
    ///   - maxPixelSize: Größte Kantenlänge in Pixeln.
    /// - Returns: Aufbereitete Daten oder `nil`, wenn es kein lesbares Bild ist.
    static func prepare(_ data: Data, maxPixelSize: Int) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }

        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let type = CGImageSourceGetType(source) as String?
        if max(width, height) <= maxPixelSize, orientation == 1,
           let type, let mimeType = keptTypes[type] {
            return Prepared(data: data, mimeType: mimeType, pixelWidth: width, pixelHeight: height)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, max(width, height))
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
        let hasAlpha = !opaque.contains(image.alphaInfo)
        let outputType = hasAlpha ? UTType.png : UTType.jpeg

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, outputType.identifier as CFString, 1, nil
        ) else { return nil }
        let quality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, hasAlpha ? nil : quality as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return Prepared(
            data: output as Data,
            mimeType: hasAlpha ? "image/png" : "image/jpeg",
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }
}

// MARK: - Bilder im Text vereinheitlichen

/// Pflege der Bilder im Textspeicher des Editors.
enum EditorImages {

    /// Ersetzt Bilder, die das System angelegt hat (Einfügen, Ziehen,
    /// Kopieren), durch `MailImageAttachment`.
    ///
    /// Verarbeitung: Jedes Bild wird an seiner Stelle ausgetauscht; die
    /// Textlänge bleibt gleich, Markierung und Rückgängig-Schritte bleiben
    /// gültig. Übrige Attribute (z. B. ein Link) bleiben erhalten. Ein
    /// Anhang ohne lesbare Bilddaten bleibt stehen und wird nicht versendet.
    ///
    /// - Parameter storage: Textspeicher des Editors.
    /// - Returns: `true`, wenn etwas ersetzt wurde.
    @discardableResult
    static func normalize(_ storage: NSTextStorage) -> Bool {
        var replacements: [(NSRange, MailImageAttachment)] = []
        storage.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: storage.length), options: []
        ) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  !(attachment is MailImageAttachment),
                  let data = imageData(of: attachment),
                  let image = MailImageAttachment.make(from: data) else { return }
            replacements.append((range, image))
        }
        guard !replacements.isEmpty else { return false }

        storage.beginEditing()
        for (range, image) in replacements {
            storage.addAttribute(.attachment, value: image, range: range)
        }
        storage.endEditing()
        return true
    }

    /// Bilddaten eines Systemanhangs.
    ///
    /// - Parameter attachment: Anhang im Text.
    /// - Returns: Daten aus Inhalt, Dateihülle oder Bild; `nil`, wenn keine vorliegen.
    static func imageData(of attachment: NSTextAttachment) -> Data? {
        if let data = attachment.contents, !data.isEmpty { return data }
        if let data = attachment.fileWrapper?.regularFileContents, !data.isEmpty { return data }
        #if os(iOS)
        return attachment.image?.pngData()
        #else
        return attachment.image?.tiffRepresentation
        #endif
    }
}
