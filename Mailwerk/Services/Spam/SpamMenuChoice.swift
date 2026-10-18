//
//  SpamMenuChoice.swift
//  Mailwerk
//
//  Zweck: Die Spam-Aktionen einer Mail ohne Oberfläche – welche Abschnitte
//  das Untermenü „Spam / Vertrauen“ zeigt (Adresse, Domain und – nur bei
//  einer Subdomain – Hauptdomain), die gewählte Aktion (Blockieren oder
//  Vertrauen) und die Texte der Rückfrage und der Meldungen dazu.
//
//  Bewusst ohne SwiftUI: iPhone, iPad, Mac und Apple Watch zeigen dieselben
//  Einträge mit denselben Texten; nur die Darstellung unterscheidet sich.
//
//  Abgrenzung: Menü → MessageMenu; Rückfragen und Meldungen als Dialog →
//  MessageActionDialogs; Eintragen und Verschieben → SpamFilterService;
//  Apple Watch → WatchSpamActionsView.
//
//  Abhängigkeiten: Foundation, FilterAddress, FilterDomain, FilterEntryKind,
//  FilterList.
//

import Foundation

/// Eine Spam-Aktion aus dem Menü: blockieren oder vertrauen, für Adresse
/// oder Domain.
nonisolated struct SpamMenuRequest: Equatable, Sendable {
    /// Blockieren oder Vertrauen.
    nonisolated enum Kind: String, Equatable, Codable, Sendable {
        case block, trust
    }

    /// Blockieren oder Vertrauen.
    let kind: Kind
    /// Adresse oder Domain.
    let entryKind: FilterEntryKind
    /// Einzutragende Adresse bzw. Domain.
    let value: String

    /// Wert in der Schreibweise der Listen (Domains als `*domain`).
    var displayValue: String {
        FilterDomain.display(value, kind: entryKind)
    }

    /// Liste, auf die der Wert kommt.
    var list: FilterList {
        kind == .block ? .black : .white
    }
}

/// Ein Abschnitt im Spam-Untermenü: Überschrift und einzutragender Wert.
nonisolated struct SpamMenuSection: Equatable, Identifiable, Sendable {
    /// Adresse oder Domain.
    let entryKind: FilterEntryKind
    /// Einzutragender Wert.
    let value: String

    /// Kennung für SwiftUI.
    var id: String { "\(entryKind.rawValue):\(value)" }
    /// Überschrift in der Schreibweise der Listen.
    var title: String { FilterDomain.display(value, kind: entryKind) }

    /// Abschnitte für einen Absender.
    ///
    /// Verarbeitung: Adresse und Domain immer; die Hauptdomain nur, wenn
    /// der Absender auf einer Subdomain sitzt.
    ///
    /// - Parameter sender: Absender der Mail.
    /// - Returns: Abschnitte in Menüreihenfolge.
    static func sections(for sender: FilterAddress) -> [SpamMenuSection] {
        var sections = [
            SpamMenuSection(entryKind: .address, value: sender.address),
            SpamMenuSection(entryKind: .domain, value: sender.domain)
        ]
        if let main = FilterDomain.mainDomainIfDifferent(from: sender.domain) {
            sections.append(SpamMenuSection(entryKind: .domain, value: main))
        }
        return sections
    }

    /// Die Aktion dieses Abschnitts.
    ///
    /// - Parameter kind: Blockieren oder Vertrauen.
    /// - Returns: Spam-Aktion für den Wert des Abschnitts.
    func request(_ kind: SpamMenuRequest.Kind) -> SpamMenuRequest {
        SpamMenuRequest(kind: kind, entryKind: entryKind, value: value)
    }
}

/// Texte der Rückfrage und der Meldungen zu einer Spam-Aktion.
nonisolated enum SpamMenuTexts {

    /// Überschrift der Rückfrage, z. B. „*firma.de blockieren?“.
    ///
    /// - Parameter request: Spam-Aktion.
    /// - Returns: Überschrift.
    static func confirmationTitle(_ request: SpamMenuRequest) -> String {
        let shown = request.displayValue
        return request.kind == .block ? "\(shown) blockieren?" : "\(shown) vertrauen?"
    }

    /// Erklärung der Rückfrage: was mit künftigen Mails und dieser Mail geschieht.
    ///
    /// - Parameter request: Spam-Aktion.
    /// - Returns: Erklärung.
    static func confirmationMessage(_ request: SpamMenuRequest) -> String {
        let scope = request.entryKind == .domain
            ? "Alle künftigen Mails dieser Domain und ihrer Subdomains"
            : "Alle künftigen Mails dieses Absenders"
        return request.kind == .block
            ? "\(scope) wandern in den Spam-Ordner. Diese Mail wird mitverschoben."
            : "\(scope) bleiben im Posteingang. Liegt diese Mail im Spam-Ordner, wird sie zurückgeholt."
    }

    /// Beschriftung des Knopfs, der die Aktion bestätigt.
    ///
    /// - Parameter request: Spam-Aktion.
    /// - Returns: „Blockieren“ bzw. „Vertrauen“.
    static func confirmLabel(_ request: SpamMenuRequest) -> String {
        request.kind == .block ? "Blockieren" : "Vertrauen"
    }

    /// SF-Symbol des Menüeintrags.
    ///
    /// - Parameter request: Spam-Aktion.
    /// - Returns: Symbol je nach Aktion und Art des Eintrags.
    static func systemImage(_ request: SpamMenuRequest) -> String {
        switch (request.kind, request.entryKind) {
        case (.block, .address): return "person.crop.circle.badge.xmark"
        case (.block, .domain):  return "globe.badge.chevron.backward"
        case (.trust, .address): return "person.crop.circle.badge.checkmark"
        case (.trust, .domain):  return "globe"
        }
    }

    /// Bestätigung des Listeneintrags, z. B. „a@firma.de steht jetzt auf der Blacklist.“
    ///
    /// - Parameter request: Ausgeführte Spam-Aktion.
    /// - Returns: Meldungstext.
    static func resultMessage(_ request: SpamMenuRequest) -> String {
        "\(request.displayValue) steht jetzt auf der \(listName(request.list))."
    }

    /// Hinweis, wenn der Wert schon auf der anderen Liste steht.
    ///
    /// - Parameters:
    ///   - request: Spam-Aktion.
    ///   - list: Liste, auf der der Wert bereits steht.
    /// - Returns: Meldungstext mit dem, was zu tun ist.
    static func otherListMessage(_ request: SpamMenuRequest, list: FilterList) -> String {
        "\(request.displayValue) steht bereits auf der \(listName(list)). Entferne den Eintrag dort zuerst."
    }

    /// Name einer Liste in Meldungen.
    ///
    /// - Parameter list: Liste.
    /// - Returns: „Whitelist“ bzw. „Blacklist“.
    static func listName(_ list: FilterList) -> String {
        list == .white ? "Whitelist" : "Blacklist"
    }
}
