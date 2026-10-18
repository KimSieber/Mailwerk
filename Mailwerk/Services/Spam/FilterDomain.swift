//
//  FilterDomain.swift
//  Mailwerk
//
//  Zweck: Domain-Regeln der Filterlisten an einer Stelle:
//  - Ein Domain-Eintrag gilt für die Domain selbst und alle Subdomains:
//    `apple.com` trifft `xyz@apple.com` und `xyz@mail.apple.com`, aber
//    nicht `xyz@badapple.com` (Vergleich an der Punkt-Grenze).
//  - Schreibweise in Liste, Menü und Export: `*apple.com`. Das `*` steht
//    für „ein Punkt oder das @-Zeichen davor“ – wie im manitu-Portal und
//    bei anderen Blacklists.
//  - Länderendungen (`com`, `de`, `co.uk`, `com.au` …) sind keine Domain
//    und lassen sich nie eintragen.
//  - Hauptdomain einer Adresse für das Spam-Menü: dieselbe Kürzung wie bei
//    den Absenderbildern (`SenderDomain`), damit es nur eine Liste
//    zweiteiliger Länderendungen gibt.
//
//  Reine Logik, deshalb `nonisolated`; vollständig per Unit-Test abgedeckt.
//
//  Abgrenzung: Normalisieren der Eingabe → FilterAddress; Vorrang der
//  Treffer → SpamClassifier.
//
//  Abhängigkeiten: Foundation, FilterAddress, FilterEntryKind, SenderDomain.
//

import Foundation

/// Domain-Regeln der Filterlisten.
nonisolated enum FilterDomain {

    /// Schreibweise einer Domain in Liste, Menü und Export.
    ///
    /// - Parameter domain: Normalisierte Domain, z. B. `apple.com`.
    /// - Returns: Anzeige, z. B. `*apple.com`.
    static func display(_ domain: String) -> String {
        "*\(domain)"
    }

    /// Schreibweise eines Listeneintrags: Adressen unverändert, Domains als
    /// `*domain`.
    ///
    /// - Parameters:
    ///   - value: Gespeicherter Wert.
    ///   - kind: Adresse oder Domain.
    /// - Returns: Anzeige.
    static func display(_ value: String, kind: FilterEntryKind) -> String {
        switch kind {
        case .address: value
        case .domain: display(value)
        }
    }

    /// Prüft, ob ein Wert nur eine Länderendung ist (`de`, `com`, `co.uk` …).
    ///
    /// - Parameter domain: Normalisierte Domain.
    /// - Returns: `true`, wenn der Wert keine eintragbare Domain ist.
    static func isSuffixOnly(_ domain: String) -> Bool {
        let labels = domain.split(separator: ".")
        return labels.count < 2 || SenderDomain.twoPartSuffixes.contains(domain)
    }

    /// Normalisiert eine Domain-Eingabe für die Filterlisten.
    ///
    /// Verarbeitung: Erkennt die Schreibweisen `apple.com`, `*apple.com`,
    /// `*.apple.com`, `*@apple.com` und `@apple.com`, prüft die Form wie
    /// `FilterAddress.normalizedDomain` und lehnt reine Länderendungen ab.
    /// Die Platzhalter gelten nur hier, nie für die Domain eines Absenders.
    ///
    /// - Parameter raw: Eingabe.
    /// - Returns: Domain oder `nil` bei unbrauchbarer Eingabe.
    static func listable(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("*.") {
            value.removeFirst(2)
        } else if value.hasPrefix("*"), !value.hasPrefix("*@") {
            value.removeFirst()
        }
        guard let domain = FilterAddress.normalizedDomain(value),
              !isSuffixOnly(domain) else { return nil }
        return domain
    }

    /// Alle Domain-Einträge, die einen Absender treffen können, vom
    /// genauesten zum allgemeinsten.
    ///
    /// Verarbeitung: Entfernt von vorn Abschnitt für Abschnitt bis zur
    /// Hauptdomain; Länderendungen gehören nie dazu.
    /// `a.mail.apple.com` → `a.mail.apple.com`, `mail.apple.com`, `apple.com`.
    ///
    /// - Parameter domain: Domain des Absenders.
    /// - Returns: Kandidaten in absteigender Genauigkeit.
    static func matchCandidates(for domain: String) -> [String] {
        let main = SenderDomain.mainDomain(of: domain)
        guard !isSuffixOnly(main) else { return [] }

        var candidates: [String] = []
        var labels = domain.split(separator: ".").map(String.init)
        while !labels.isEmpty {
            let candidate = labels.joined(separator: ".")
            candidates.append(candidate)
            if candidate == main { break }
            labels.removeFirst()
        }
        return candidates
    }

    /// Listenwert für einen Absender aus dem Spam-Menü.
    ///
    /// Verarbeitung: Ohne gewünschten Wert die Adresse bzw. die Domain des
    /// Absenders. Ein gewünschter Wert wird nur übernommen, wenn er zum
    /// Absender passt – die eigene Adresse bzw. die Domain oder eine ihrer
    /// übergeordneten Domains bis zur Hauptdomain. So lässt sich über eine
    /// Mail nie ein fremder Wert oder eine Länderendung eintragen.
    ///
    /// - Parameters:
    ///   - sender: Absender der Mail.
    ///   - kind: Adresse oder Domain.
    ///   - requested: Gewünschter Wert; `nil` = Adresse bzw. Domain des Absenders.
    /// - Returns: Einzutragender Wert oder `nil`, wenn er nicht zum Absender passt.
    static func entryValue(for sender: FilterAddress, kind: FilterEntryKind, requested: String?) -> String? {
        switch kind {
        case .address:
            guard let requested else { return sender.address }
            return requested.lowercased() == sender.address ? sender.address : nil
        case .domain:
            let candidates = matchCandidates(for: sender.domain)
            guard let requested else { return candidates.first }
            let value = requested.lowercased()
            return candidates.contains(value) ? value : nil
        }
    }

    /// Hauptdomain einer Absender-Domain für das Spam-Menü.
    ///
    /// - Parameter domain: Domain des Absenders, z. B. `mail.apple.com`.
    /// - Returns: Hauptdomain (z. B. `apple.com`) oder `nil`, wenn sie mit
    ///   der Domain übereinstimmt – dann gibt es keine Subdomain und keinen
    ///   eigenen Menüabschnitt.
    static func mainDomainIfDifferent(from domain: String) -> String? {
        let main = SenderDomain.mainDomain(of: domain)
        guard main != domain, !isSuffixOnly(main) else { return nil }
        return main
    }
}
