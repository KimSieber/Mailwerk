//
//  MailLink.swift
//  Mailwerk
//
//  Entscheidet, was ein getippter Link in einer HTML-Mail auslöst, und
//  zerlegt mailto:-Links (RFC 6068) für eine neue Mail in Mailwerk.
//
//  Reine Logik ohne UI, damit sie ohne Mail-Bibliothek testbar ist.
//

import Foundation

nonisolated enum MailLinkAction: Equatable, Sendable {
    /// Im Standardbrowser bzw. in der zuständigen System-App öffnen.
    case openExternally(URL)
    /// Neue Mail in Mailwerk mit Vorbelegung.
    case compose(MailtoLink)
    /// Nicht öffnen (z. B. javascript:, file:, data:).
    case ignore

    /// Nur diese Schemata werden an das System weitergegeben.
    static let externalSchemes: Set<String> = ["http", "https", "tel"]

    init(url: URL) {
        switch url.scheme?.lowercased() {
        case "mailto":
            if let link = MailtoLink(url: url) {
                self = .compose(link)
            } else {
                self = .ignore
            }
        case let scheme? where Self.externalSchemes.contains(scheme):
            self = .openExternally(url)
        default:
            self = .ignore
        }
    }
}

/// Inhalt eines mailto:-Links, z. B.
/// `mailto:a@x.de,b@x.de?cc=c@x.de&subject=Hallo&body=Text`.
nonisolated struct MailtoLink: Equatable, Identifiable, Sendable {
    /// Der ursprüngliche Link – zugleich Kennung für das Sheet.
    let id: String
    let to: [String]
    let cc: [String]
    let bcc: [String]
    let subject: String?
    let body: String?

    init?(url: URL) {
        guard url.scheme?.lowercased() == "mailto" else { return nil }
        let raw = url.absoluteString
        let rest = String(raw.dropFirst("mailto:".count))
        let parts = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)

        var to = Self.addresses(String(parts.first ?? ""))
        var cc: [String] = []
        var bcc: [String] = []
        var subject: String?
        var body: String?

        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0]).lowercased()
                let value = kv.count > 1 ? Self.decode(String(kv[1])) : ""
                switch key {
                case "to":      to += Self.addresses(value, decoded: true)
                case "cc":      cc += Self.addresses(value, decoded: true)
                case "bcc":     bcc += Self.addresses(value, decoded: true)
                case "subject": subject = value.isEmpty ? nil : value
                case "body":    body = value.isEmpty ? nil : value
                default:        break   // unbekannte Felder ignorieren
                }
            }
        }

        guard !to.isEmpty || !cc.isEmpty || !bcc.isEmpty || subject != nil || body != nil
        else { return nil }

        self.id = raw
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }

    /// Kommagetrennte Adressliste; leere Einträge fallen weg.
    private static func addresses(_ text: String, decoded: Bool = false) -> [String] {
        let source = decoded ? text : decode(text)
        return source
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Prozent-Kodierung auflösen. `+` bleibt ein Pluszeichen (RFC 6068),
    /// Leerzeichen kommen als %20.
    private static func decode(_ text: String) -> String {
        text.removingPercentEncoding ?? text
    }
}
