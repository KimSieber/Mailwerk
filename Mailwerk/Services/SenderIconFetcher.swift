//
//  SenderIconFetcher.swift
//  Mailwerk
//
//  Zweck: Lädt das Logo (Favicon) einer Domain aus dem Netz und bereitet
//  es als kleines PNG auf.
//
//  Reihenfolge je Domain:
//  1. `https://domain/apple-touch-icon.png` (meist 180 px, gute Qualität);
//  2. Icon-Angaben im HTML der Startseite, das größte zuerst;
//  3. `https://domain/favicon.ico`.
//  Das erste brauchbare Bild gewinnt. Kleine Icons werden ebenfalls
//  genommen – lieber unscharf als gar kein Logo.
//
//  Sicherheit: Nur HTTPS, auch bei Weiterleitungen
//  (`SenderIconRedirectGuard`).
//  Keine Cookies, kein Cache, kein Dienst Dritter – angefragt wird nur der
//  Webserver der Domain selbst, ohne Bezug zum Nutzer. Größenobergrenzen
//  für Bild und Startseite; ein Bild zählt nur, wenn ImageIO es lesen
//  kann. Gespeichert wird nie das Original, sondern ein neu erzeugtes PNG
//  von höchstens 120 px.
//
//  Ergebnis: Ein Logo, „kein Logo“ (Server erreicht oder Domain ohne
//  Webseite) oder „nicht erreichbar“ (Netz weg, Zeitüberschreitung). Nur
//  die ersten beiden werden gespeichert; „nicht erreichbar“ wird beim
//  nächsten App-Start erneut versucht.
//
//  Reine Netz- und Bildlogik ohne Main-Actor; Zerlegen des HTML und
//  Aufbereiten der Bilder sind ohne Netz testbar.
//
//  Abgrenzung: Welche Domain → SenderDomain; Warteschlange und Anzeige →
//  SenderIconCache; Ablage → MessageStore.
//
//  Abhängigkeiten: Foundation, ImageIO, UniformTypeIdentifiers.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Laden und Aufbereiten von Absenderlogos.
nonisolated enum SenderIconFetcher {

    /// Ergebnis eines Abrufs.
    enum Outcome: Equatable, Sendable {
        /// Logo als PNG.
        case icon(Data)
        /// Kein Logo vorhanden (wird gespeichert).
        case noIcon
        /// Nicht erreichbar – später erneut versuchen (wird nicht gespeichert).
        case unreachable
    }

    /// Höchstgröße eines Bildes in Bytes.
    static let maxImageBytes = 200 * 1024
    /// Höchstgröße der Startseite in Bytes.
    static let maxPageBytes = 512 * 1024
    /// Kantenlänge des gespeicherten PNG höchstens.
    static let iconPixelSize = 120
    /// Kleinere Bilder (z. B. 1×1-Platzhalter) werden verworfen.
    static let minimumPixelSize = 8
    /// Höchstzahl der Icon-Angaben aus der Startseite, die probiert werden.
    static let maxPageCandidates = 4

    // MARK: - Sitzung

    /// Legt die URL-Sitzung für Logo-Abrufe an.
    ///
    /// Verarbeitung: Flüchtige Sitzung ohne Cookies und ohne Cache, kurze
    /// Zeitlimits; Weiterleitungen nur auf HTTPS.
    ///
    /// - Returns: Neue Sitzung.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration, delegate: SenderIconRedirectGuard(), delegateQueue: nil)
    }

    // MARK: - Abruf

    /// Lädt das Logo einer Domain.
    ///
    /// Verarbeitung: Läuft ausdrücklich neben dem Main-Actor (`@concurrent`),
    /// damit Download und Bildaufbereitung die Oberfläche nicht bremsen.
    /// Probiert die drei Quellen der Reihe nach. „Kein Logo“
    /// gilt, sobald der Server oder die Domain eine eindeutige Antwort gab;
    /// scheitern alle Versuche nur vorübergehend, ist sie „nicht erreichbar“.
    ///
    /// - Parameters:
    ///   - domain: Hauptdomain (nur Hostnamen-Zeichen, siehe SenderDomain).
    ///   - session: Sitzung aus `makeSession()`.
    /// - Returns: Ergebnis des Abrufs.
    @concurrent
    static func fetch(domain: String, session: URLSession) async -> Outcome {
        guard let base = URL(string: "https://\(domain)/"),
              let touchIcon = URL(string: "https://\(domain)/apple-touch-icon.png"),
              let favicon = URL(string: "https://\(domain)/favicon.ico")
        else { return .noIcon }

        var answered = false

        // 1. apple-touch-icon
        let touch = await download(touchIcon, limit: maxImageBytes, session: session)
        answered = answered || touch.isAnswer
        if let png = touch.data.flatMap(normalizedPNG) { return .icon(png) }

        // 2. Icon-Angaben der Startseite
        let page = await download(base, limit: maxPageBytes, session: session)
        answered = answered || page.isAnswer
        if let html = page.data {
            let links = iconLinks(inHTML: String(decoding: html, as: UTF8.self), baseURL: page.finalURL ?? base)
            for link in links.prefix(maxPageCandidates) {
                let result = await download(link, limit: maxImageBytes, session: session)
                answered = answered || result.isAnswer
                if let png = result.data.flatMap(normalizedPNG) { return .icon(png) }
            }
        }

        // 3. favicon.ico
        let ico = await download(favicon, limit: maxImageBytes, session: session)
        answered = answered || ico.isAnswer
        if let png = ico.data.flatMap(normalizedPNG) { return .icon(png) }

        return answered ? .noIcon : .unreachable
    }

    /// Ergebnis eines einzelnen Downloads.
    private struct Download {
        /// Geladene Daten; `nil` bei Fehler oder Ablehnung.
        var data: Data?
        /// Adresse nach Weiterleitungen.
        var finalURL: URL?
        /// `true`, wenn eine eindeutige Antwort kam (auch Fehlerstatus,
        /// zu groß oder Domain unbekannt) – nicht nur ein vorübergehender Fehler.
        var isAnswer: Bool
    }

    /// Lädt eine Adresse mit Größenobergrenze.
    ///
    /// Verarbeitung: Nur HTTPS und Status 200. Bricht ab, sobald die
    /// Obergrenze überschritten ist – angekündigt oder tatsächlich.
    ///
    /// - Parameters:
    ///   - url: Adresse.
    ///   - limit: Höchstgröße in Bytes.
    ///   - session: Sitzung.
    /// - Returns: Ergebnis.
    private static func download(_ url: URL, limit: Int, session: URLSession) async -> Download {
        guard url.scheme?.lowercased() == "https" else {
            return Download(data: nil, finalURL: nil, isAnswer: true)
        }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.expectedContentLength <= Int64(limit)
            else { return Download(data: nil, finalURL: nil, isAnswer: true) }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit { return Download(data: nil, finalURL: nil, isAnswer: true) }
            }
            return Download(data: data, finalURL: http.url ?? url, isAnswer: true)
        } catch let error as URLError {
            return Download(data: nil, finalURL: nil, isAnswer: !isTransient(error))
        } catch {
            return Download(data: nil, finalURL: nil, isAnswer: true)
        }
    }

    /// Vorübergehende Netzfehler – dann wird später erneut versucht.
    ///
    /// - Parameter error: Fehler der URL-Sitzung.
    /// - Returns: `true` bei fehlendem Netz, Abbruch oder Zeitüberschreitung.
    static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .dataNotAllowed, .internationalRoamingOff, .callIsActive, .cancelled:
            return true
        default:
            return false
        }
    }

    // MARK: - HTML

    /// Muster eines `<link …>`-Tags.
    private static let linkTag = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive])
    /// Muster eines Attributs mit Wert in doppelten, einfachen oder ohne Anführungszeichen.
    private static let attribute = try? NSRegularExpression(
        pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
    )

    /// Sucht Icon-Angaben im HTML einer Startseite.
    ///
    /// Verarbeitung: Wertet `<link rel="icon|shortcut icon|apple-touch-icon…">`
    /// aus. SVG-Icons (auch `mask-icon`) entfallen, weil sie sich nicht als
    /// Bild lesen lassen. Relative Adressen werden aufgelöst; nur HTTPS
    /// bleibt. Sortiert nach angegebener Größe, `apple-touch-icon` ohne
    /// Angabe zählt als 180 px, andere ohne Angabe als 32 px.
    ///
    /// - Parameters:
    ///   - html: Inhalt der Startseite.
    ///   - baseURL: Adresse der Seite (nach Weiterleitungen).
    /// - Returns: Icon-Adressen, die größten zuerst, ohne Doppelte.
    static func iconLinks(inHTML html: String, baseURL: URL) -> [URL] {
        guard let linkTag, let attribute else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var candidates: [(url: URL, size: Int)] = []

        for match in linkTag.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let attributes = parseAttributes(tag, using: attribute)

            let rels = (attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            let isTouch = rels.contains { $0.hasPrefix("apple-touch-icon") }
            guard isTouch || rels.contains("icon") else { continue }
            if (attributes["type"] ?? "").lowercased().contains("svg") { continue }

            guard let href = attributes["href"]?
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty, !href.lowercased().hasPrefix("data:"),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  url.scheme?.lowercased() == "https",
                  !url.path.lowercased().hasSuffix(".svg")
            else { continue }

            let declared = largestSize(in: attributes["sizes"])
            candidates.append((url, declared ?? (isTouch ? 180 : 32)))
        }

        var seen = Set<URL>()
        return candidates
            .sorted { $0.size > $1.size }
            .map(\.url)
            .filter { seen.insert($0).inserted }
    }

    /// Zerlegt die Attribute eines Tags.
    ///
    /// - Parameters:
    ///   - tag: Tag-Text.
    ///   - pattern: Muster eines Attributs.
    /// - Returns: Attribute mit kleingeschriebenem Namen.
    private static func parseAttributes(_ tag: String, using pattern: NSRegularExpression) -> [String: String] {
        var result: [String: String] = [:]
        for match in pattern.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let value = (2...4).lazy
                .compactMap { Range(match.range(at: $0), in: tag) }
                .first
                .map { String(tag[$0]) } ?? ""
            result[tag[nameRange].lowercased()] = value
        }
        return result
    }

    /// Größte Kantenlänge aus einer `sizes`-Angabe wie `"16x16 32x32"`.
    ///
    /// - Parameter sizes: Wert des Attributs.
    /// - Returns: Größte Kantenlänge oder `nil`, wenn keine lesbar ist.
    static func largestSize(in sizes: String?) -> Int? {
        guard let sizes else { return nil }
        return sizes.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .compactMap { entry -> Int? in
                let parts = entry.split(separator: "x")
                guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
                return max(w, h)
            }
            .max()
    }

    // MARK: - Bild

    /// Bereitet Bilddaten als PNG von höchstens `iconPixelSize` auf.
    ///
    /// Verarbeitung: Liest die Daten mit ImageIO (auch ICO mit mehreren
    /// Größen – dann zählt die größte), verkleinert bei Bedarf und
    /// schreibt ein neues PNG. Unlesbare Daten (z. B. eine HTML-Fehlerseite
    /// mit Status 200) und winzige Bilder ergeben `nil`.
    ///
    /// - Parameter data: Geladene Bilddaten.
    /// - Returns: PNG oder `nil`.
    static func normalizedPNG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var bestIndex = 0
        var bestWidth = 0
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if width > bestWidth {
                bestWidth = width
                bestIndex = index
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: iconPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, bestIndex, options as CFDictionary),
              image.width >= minimumPixelSize, image.height >= minimumPixelSize
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Lässt Weiterleitungen beim Logo-Abruf nur auf HTTPS-Adressen zu.
///
/// Bewusst in der klassischen Form mit Completion-Handler und als eigener
/// Typ auf oberster Ebene: Die `async`-Form dieser Objective-C-Methode in
/// einem `nonisolated` Typ brachte den Compiler (Swift 6.2) zum Absturz.
nonisolated final class SenderIconRedirectGuard: NSObject, URLSessionTaskDelegate {

    /// Entscheidet über eine Weiterleitung.
    ///
    /// Verarbeitung: Ein Ziel ohne HTTPS wird nicht verfolgt; der Abruf
    /// endet dann mit der Weiterleitungsantwort und gilt als erfolglos.
    ///
    /// - Parameters:
    ///   - session: Sitzung.
    ///   - task: Abruf.
    ///   - response: Weiterleitungsantwort.
    ///   - request: Neue Anfrage.
    ///   - completionHandler: Erhält die neue Anfrage oder `nil`, um nicht zu folgen.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}
