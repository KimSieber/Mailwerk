//
//  SenderDomain.swift
//  Mailwerk
//
//  Zweck: Ermittelt zu einer E-Mail-Adresse die Domain, deren Logo
//  (Favicon) die Mailliste zeigt, und schließt Freemail-Anbieter aus.
//
//  Gekürzt wird auf die Hauptdomain: `noreply@mailing.beispiel-shop.de` →
//  `beispiel-shop.de`. Versandadressen liegen oft auf Subdomains ohne eigene
//  Webseite; das Logo der Marke hängt an der Hauptdomain. Länderendungen
//  aus zwei Teilen (`co.uk`, `com.au` …) kennt eine kleine feste Liste.
//
//  Freemail: Bei Adressen allgemeiner Anbieter (gmail.com, gmx.de, …)
//  gibt es kein Logo – sonst stünde bei jeder Privatperson das Logo ihres
//  Anbieters. Eine Fehlanzeige bei unbekannten Anbietern ist akzeptiert.
//
//  Domains mit Umlauten werden nicht umgewandelt (kein Punycode) und
//  bleiben ohne Logo.
//
//  Reine Logik ohne Netz, vollständig per Unit-Test abgedeckt.
//
//  Abgrenzung: Laden der Logos → SenderIconFetcher; Ablage → MessageStore
//  (Tabelle `sender_icon`); Ablaufregeln → SenderIconRecord.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Domain-Regeln für Absenderlogos.
nonisolated enum SenderDomain {

    /// Domains allgemeiner Mail-Anbieter, für die kein Logo geladen wird.
    static let freemailDomains: Set<String> = [
        "gmail.com", "googlemail.com",
        "gmx.de", "gmx.net", "gmx.at", "gmx.ch", "gmx.com",
        "web.de", "t-online.de", "freenet.de", "mail.de", "arcor.de",
        "posteo.de", "posteo.net", "mailbox.org",
        "icloud.com", "me.com", "mac.com",
        "outlook.com", "outlook.de", "hotmail.com", "hotmail.de",
        "live.com", "live.de", "msn.com",
        "yahoo.com", "yahoo.de", "aol.com", "aol.de",
        "proton.me", "protonmail.com"
    ]

    /// Länderendungen aus zwei Teilen; die Hauptdomain hat dort drei Teile.
    static let twoPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk",
        "co.at", "or.at",
        "com.au", "net.au", "org.au",
        "co.nz", "co.jp", "co.za", "co.in",
        "com.br", "com.tr", "com.cn", "com.mx"
    ]

    /// Domain eines Logos zu einer Adresse.
    ///
    /// Verarbeitung: Nimmt den Teil nach dem letzten `@`, kürzt ihn auf die
    /// Hauptdomain und schließt Freemail-Anbieter aus.
    ///
    /// - Parameter address: E-Mail-Adresse (ohne Anzeigename).
    /// - Returns: Hauptdomain oder `nil` bei Freemail oder unbrauchbarer Adresse.
    static func iconDomain(forAddress address: String) -> String? {
        guard let domain = domain(ofAddress: address) else { return nil }
        let main = mainDomain(of: domain)
        return freemailDomains.contains(main) ? nil : main
    }

    /// Domain-Teil einer Adresse, bereinigt.
    ///
    /// Verarbeitung: Kleinschreibung, ohne Leerraum und abschließenden
    /// Punkt. Verlangt mindestens zwei Teile und nur Zeichen, die in einem
    /// Hostnamen vorkommen dürfen – der Wert wird später Teil einer URL.
    ///
    /// - Parameter address: E-Mail-Adresse.
    /// - Returns: Domain oder `nil`, wenn keine brauchbare vorliegt.
    static func domain(ofAddress address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        var domain = address[address.index(after: at)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while domain.hasSuffix(".") { domain.removeLast() }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) })
        else { return nil }
        return domain
    }

    /// Hauptdomain: die letzten zwei Teile, bei zweiteiligen Länderendungen
    /// die letzten drei.
    ///
    /// - Parameter domain: Bereinigte Domain.
    /// - Returns: Hauptdomain.
    static func mainDomain(of domain: String) -> String {
        let labels = domain.split(separator: ".")
        guard labels.count > 2 else { return domain }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let keep = twoPartSuffixes.contains(lastTwo) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}
