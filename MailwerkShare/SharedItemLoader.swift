//
//  SharedItemLoader.swift
//  MailwerkShare
//
//  Zweck: Liest die Inhalte, die eine andere App über „Teilen“ übergibt,
//  aus den Anbietern des Systems (NSItemProvider) und fasst sie zu einem
//  SharedContent zusammen.
//
//  Je Anbieter genau ein Inhalt, in dieser Rangfolge:
//  1. Web-Link (http/https) → Link im Text,
//  2. Datei als Verweis (z. B. Finder, Dateien-App) → immer Anhang mit
//     dem Dateinamen und dem Inhalt der Datei – auch Text- und CSV-Dateien,
//  3. reiner Text ohne Dateinamen (z. B. markierter Text) → Text,
//  4. alles andere als Daten → Anhang. Bei Fotos wird JPEG genommen, wenn
//     die teilende App es anbietet (für Empfänger ohne HEIC), sonst das
//     Originalformat; Kontakte kommen als vCard (.vcf).
//
//  Was sich nicht lesen lässt, wird gezählt und übersprungen; der Rest
//  wird trotzdem übernommen.
//
//  Die Rückrufe des Systems kommen auf beliebigen Threads; deshalb ist
//  der Typ `nonisolated` und gibt nur fertige Werte zurück.
//
//  Abgrenzung: Regeln für Betreff, Text und Dateinamen → SharedContent /
//  SharedContentRules; Anzeige → ShareRootView.
//
//  Abhängigkeiten: Foundation, UniformTypeIdentifiers, SharedContent, Log.
//

import Foundation
import UniformTypeIdentifiers
import os

/// Ein geteiltes Element: seine Anbieter und die mitgelieferte Überschrift.
///
/// `@unchecked Sendable`: Die Anbieter werden nur gelesen; das System
/// erlaubt ihr Laden von beliebigen Threads.
nonisolated struct SharedInput: @unchecked Sendable {
    /// Anbieter der Inhalte (je Datei, Link oder Text einer).
    let providers: [NSItemProvider]
    /// Überschrift des Elements (z. B. Seitentitel aus Safari); `nil` = keine.
    let title: String?
}

/// Liest geteilte Inhalte aus den Anbietern des Systems.
nonisolated enum SharedItemLoader {

    /// Ergebnis des Einlesens.
    struct Result: Sendable {
        /// Übernommene Inhalte.
        var content: SharedContent
        /// Anzahl der Inhalte, die sich nicht lesen ließen.
        var failedCount: Int
    }

    /// Ein einzelner gelesener Inhalt.
    private enum Item {
        /// Datei als Anhang.
        case attachment(SharedAttachment)
        /// Text.
        case text(String)
        /// Web-Link.
        case link(URL)
    }

    /// Fehler beim Lesen eines Anbieters.
    private enum LoadError: Error {
        /// Der Anbieter lieferte keine Daten.
        case noData
    }

    /// Liest alle geteilten Elemente.
    ///
    /// Verarbeitung: Die Anbieter werden nacheinander gelesen (Fotos und
    /// Videos können groß sein; gleichzeitiges Laden erhöht den
    /// Speicherbedarf der Erweiterung). Die erste Überschrift gilt.
    /// Gleiche Dateinamen werden am Ende eindeutig gemacht.
    ///
    /// - Parameter inputs: Geteilte Elemente.
    /// - Returns: Inhalte und Zahl der nicht lesbaren Teile.
    static func load(_ inputs: [SharedInput]) async -> Result {
        var content = SharedContent()
        var failedCount = 0
        for input in inputs {
            if content.title == nil { content.title = input.title }
            for provider in input.providers {
                do {
                    switch try await item(from: provider) {
                    case .attachment(let attachment)?: content.attachments.append(attachment)
                    case .text(let text)?: content.texts.append(text)
                    case .link(let url)?: content.links.append(url)
                    case nil: break
                    }
                } catch {
                    failedCount += 1
                    Log.view.error("⚠️ Geteilter Inhalt nicht lesbar: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        let names = SharedContentRules.uniqueFilenames(content.attachments.map(\.filename))
        for index in content.attachments.indices {
            content.attachments[index].filename = names[index]
        }
        Log.view.info("📥 Geteilt: \(content.attachments.count) Anhänge, \(content.texts.count) Texte, \(content.links.count) Links, \(failedCount) nicht lesbar")
        return Result(content: content, failedCount: failedCount)
    }

    /// Liest den Inhalt eines Anbieters.
    ///
    /// Verarbeitung: Rangfolge Web-Link → Dateiverweis → reiner Text →
    /// Daten (siehe Datei-Kopf). Eine geteilte Datei wird so immer angehängt,
    /// auch wenn sie Text enthält; ein Text mit vorgeschlagenem Dateinamen
    /// gilt ebenfalls als Datei.
    ///
    /// - Parameter provider: Anbieter.
    /// - Returns: Inhalt; `nil`, wenn der Anbieter nichts Verwertbares hat.
    /// - Throws: Fehler beim Laden.
    private static func item(from provider: NSItemProvider) async throws -> Item? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = try await loadURL(provider),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return .link(url)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let file = try await loadFile(provider) {
            return .attachment(file)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           provider.suggestedName == nil,
           let text = try await loadText(provider) {
            return .text(text)
        }

        let types = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
        guard let type = fileType(among: types) else { return nil }
        let data = try await loadData(provider, type: type)
        return .attachment(SharedAttachment(
            filename: filename(suggested: provider.suggestedName, type: type),
            mimeType: type.preferredMIMEType ?? "application/octet-stream",
            data: data
        ))
    }

    /// Wählt den Dateityp, in dem ein Anhang übernommen wird.
    ///
    /// Verarbeitung: Bei Bildern JPEG, wenn angeboten, sonst das erste
    /// angebotene Bildformat; sonst der erste Typ mit Dateidaten, zuletzt
    /// der erste Typ überhaupt. Die Reihenfolge der Anbieter gilt als
    /// Vorrang (höchste Qualität zuerst).
    ///
    /// - Parameter types: Angebotene Typen in ihrer Reihenfolge.
    /// - Returns: Gewählter Typ; `nil` bei leerer Liste.
    private static func fileType(among types: [UTType]) -> UTType? {
        if types.contains(where: { $0.conforms(to: .image) }) {
            return types.first { $0 == .jpeg } ?? types.first { $0.conforms(to: .image) }
        }
        return types.first { $0.conforms(to: .data) } ?? types.first
    }

    /// Dateiname eines Anhangs.
    ///
    /// Verarbeitung: Passt die Endung des vorgeschlagenen Namens nicht zum
    /// gewählten Typ (z. B. „IMG_1.HEIC“, übernommen als JPEG), wird sie
    /// entfernt und die passende angehängt. Ohne Vorschlag gilt ein
    /// Ersatzname nach Art des Inhalts.
    ///
    /// - Parameters:
    ///   - suggested: Vorgeschlagener Name der teilenden App.
    ///   - type: Gewählter Typ.
    /// - Returns: Dateiname.
    private static func filename(suggested: String?, type: UTType) -> String {
        var name = suggested
        if let current = suggested {
            let ext = (current as NSString).pathExtension
            if !ext.isEmpty, UTType(filenameExtension: ext)?.conforms(to: type) != true {
                name = (current as NSString).deletingPathExtension
            }
        }
        return SharedContentRules.filename(
            suggested: name,
            fileExtension: type.preferredFilenameExtension,
            fallback: fallbackName(for: type)
        )
    }

    /// Ersatzname nach Art des Inhalts.
    ///
    /// - Parameter type: Typ des Inhalts.
    /// - Returns: z. B. „Foto“, „Video“, „Kontakt“.
    private static func fallbackName(for type: UTType) -> String {
        if type.conforms(to: .image) { return "Foto" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "Video" }
        if type.conforms(to: .vCard) { return "Kontakt" }
        if type.conforms(to: .pdf) { return "Dokument" }
        return "Anhang"
    }

    // MARK: - Laden

    /// Lädt die Daten eines Anbieters im gewählten Typ.
    ///
    /// - Parameters:
    ///   - provider: Anbieter.
    ///   - type: Gewählter Typ.
    /// - Returns: Daten.
    /// - Throws: Fehler des Anbieters oder `LoadError.noData`.
    private static func loadData(_ provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? LoadError.noData)
                }
            }
        }
    }

    /// Lädt eine Datei, die als Verweis übergeben wurde.
    ///
    /// Verarbeitung: Der Verweis gilt nur innerhalb des Rückrufs; die Datei
    /// wird deshalb dort gelesen (mit Zugriffsrecht für Dateien außerhalb
    /// der Erweiterung). Dateiname und Typ kommen aus dem Verweis.
    ///
    /// - Parameter provider: Anbieter mit einem Dateiverweis.
    /// - Returns: Anhang; `nil`, wenn der Wert kein Dateiverweis ist.
    /// - Throws: Fehler des Anbieters oder beim Lesen der Datei.
    private static func loadFile(_ provider: NSItemProvider) async throws -> SharedAttachment? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let url: URL?
                switch item {
                case let value as URL: url = value
                case let data as Data: url = URL(dataRepresentation: data, relativeTo: nil)
                default: url = nil
                }
                guard let url, url.isFileURL else {
                    continuation.resume(returning: nil)
                    return
                }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let type = UTType(filenameExtension: url.pathExtension)
                    continuation.resume(returning: SharedAttachment(
                        filename: SharedContentRules.filename(
                            suggested: url.lastPathComponent, fileExtension: nil, fallback: "Anhang"
                        ),
                        mimeType: type?.preferredMIMEType ?? "application/octet-stream",
                        data: data
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Lädt einen Link.
    ///
    /// - Parameter provider: Anbieter mit einem Link.
    /// - Returns: Link; `nil`, wenn der Wert keiner ist.
    /// - Throws: Fehler des Anbieters.
    private static func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                switch item {
                case let url as URL:
                    continuation.resume(returning: url)
                case let data as Data:
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                case let string as String:
                    continuation.resume(returning: URL(string: string))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Lädt einen Text.
    ///
    /// - Parameter provider: Anbieter mit Text.
    /// - Returns: Text; `nil`, wenn der Wert keiner ist.
    /// - Throws: Fehler des Anbieters.
    private static func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                switch item {
                case let string as String:
                    continuation.resume(returning: string)
                case let attributed as NSAttributedString:
                    continuation.resume(returning: attributed.string)
                case let data as Data:
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
