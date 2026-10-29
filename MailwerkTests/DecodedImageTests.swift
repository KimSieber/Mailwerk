//
//  DecodedImageTests.swift
//  MailwerkTests
//
//  Zweck: Tests für das verkleinerte Dekodieren der Absenderbilder
//  (DecodedImage.thumbnailImage, v0.2.3c).
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Mailwerk

/// Tests für `DecodedImage.thumbnailImage`.
struct DecodedImageTests {

    /// Testhilfe: PNG-Daten einer einfarbigen Fläche.
    private func pngData(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// Ein großes Bild wird auf die gewünschte Kantenlänge verkleinert.
    @Test("Großes Bild wird verkleinert")
    func largeImageIsDownsampled() throws {
        let image = try #require(DecodedImage.thumbnailImage(from: pngData(width: 512, height: 256), maxPixelSize: 120))
        #expect(max(image.width, image.height) == 120)
        #expect(image.width == 2 * image.height)
    }

    /// Ein kleines Bild wird nicht vergrößert.
    @Test("Kleines Bild bleibt klein")
    func smallImageStaysSmall() throws {
        let image = try #require(DecodedImage.thumbnailImage(from: pngData(width: 32, height: 32), maxPixelSize: 120))
        #expect(image.width <= 32)
    }

    /// Keine Bilddaten ergeben nil.
    @Test("Ungültige Daten ergeben nil")
    func invalidDataGivesNil() {
        #expect(DecodedImage.thumbnailImage(from: Data([1, 2, 3]), maxPixelSize: 120) == nil)
    }
}
