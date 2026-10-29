//
//  SenderIconFetcherTests.swift
//  MailwerkTests
//
//  Zweck: Tests für den Logo-Abruf ohne Netz (SenderIconFetcher) – Icon-
//  Angaben im HTML, Größenangaben, Einstufung von Netzfehlern und das
//  Aufbereiten der Bilder.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Mailwerk

@MainActor
struct SenderIconFetcherTests {

    /// Testhilfe: Adresse der Startseite.
    private let base = URL(string: "https://www.firma.de/start/")!

    /// Testhilfe: einfarbiges PNG mit wählbarer Kantenlänge.
    private func png(size: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// Testhilfe: Kantenlänge eines Bildes.
    private func width(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return properties[kCGImagePropertyPixelWidth] as? Int
    }

    // MARK: - HTML

    /// Größere Icons zuerst; apple-touch-icon ohne Größe zählt als 180 px; relative Adressen werden aufgelöst.
    @Test func iconLinksAreSortedAndResolved() {
        let html = """
            <head>
            <link rel="icon" href="/favicon-32.png" sizes="32x32">
            <LINK REL="apple-touch-icon" HREF="touch.png">
            <link rel='shortcut icon' href='https://cdn.firma.de/big.png' sizes='16x16 256x256'>
            </head>
            """
        let links = SenderIconFetcher.iconLinks(inHTML: html, baseURL: base).map(\.absoluteString)
        #expect(links == [
            "https://cdn.firma.de/big.png",
            "https://www.firma.de/start/touch.png",
            "https://www.firma.de/favicon-32.png"
        ])
    }

    /// SVG, mask-icon, data:-Adressen, HTTP und fremde rel-Werte entfallen.
    @Test func unusableLinksAreSkipped() {
        let html = """
            <link rel="icon" type="image/svg+xml" href="/icon.svg">
            <link rel="mask-icon" href="/mask.svg">
            <link rel="icon" href="/logo.svg">
            <link rel="icon" href="data:image/png;base64,AAAA">
            <link rel="icon" href="http://www.firma.de/plain.png">
            <link rel="stylesheet" href="/style.css">
            """
        #expect(SenderIconFetcher.iconLinks(inHTML: html, baseURL: base).isEmpty)
    }

    /// Protokoll-relative Adressen und &amp; in der Adresse werden richtig gelesen.
    @Test func protocolRelativeAndEntities() {
        let html = #"<link rel="icon" href="//static.firma.de/i.png?v=1&amp;s=2">"#
        let links = SenderIconFetcher.iconLinks(inHTML: html, baseURL: base).map(\.absoluteString)
        #expect(links == ["https://static.firma.de/i.png?v=1&s=2"])
    }

    /// Größenangaben: größte Kante, „any“ und Unlesbares ergeben nil.
    @Test func largestSizeIsParsed() {
        #expect(SenderIconFetcher.largestSize(in: "16x16 32x32 180x180") == 180)
        #expect(SenderIconFetcher.largestSize(in: "any") == nil)
        #expect(SenderIconFetcher.largestSize(in: nil) == nil)
    }

    // MARK: - Netzfehler

    /// Fehlendes Netz und Zeitüberschreitung sind vorübergehend, unbekannte Domain nicht.
    @Test func transientErrorsAreRecognized() {
        #expect(SenderIconFetcher.isTransient(URLError(.notConnectedToInternet)))
        #expect(SenderIconFetcher.isTransient(URLError(.timedOut)))
        #expect(!SenderIconFetcher.isTransient(URLError(.cannotFindHost)))
        #expect(!SenderIconFetcher.isTransient(URLError(.serverCertificateUntrusted)))
    }

    // MARK: - Bild

    /// Große Bilder werden auf höchstens 120 px verkleinert und als PNG gespeichert.
    @Test func largeImageIsScaledDown() throws {
        let result = try #require(SenderIconFetcher.normalizedPNG(from: try png(size: 512)))
        #expect(width(of: result) == SenderIconFetcher.iconPixelSize)
    }

    /// Kleine Icons werden genommen (lieber unscharf als gar nicht), winzige verworfen.
    @Test func smallImageIsKeptTinyIsRejected() throws {
        let small = try #require(SenderIconFetcher.normalizedPNG(from: try png(size: 16)))
        #expect(width(of: small) == 16)
        #expect(SenderIconFetcher.normalizedPNG(from: try png(size: 1)) == nil)
    }

    /// Keine Bilddaten (z. B. HTML-Fehlerseite) ergeben kein Logo.
    @Test func nonImageDataIsRejected() {
        #expect(SenderIconFetcher.normalizedPNG(from: Data("<html>404</html>".utf8)) == nil)
    }
}
