//
//  SpamClassifier.swift
//  Mailwerk
//
//  Zweck: Entscheidet für eine Mail anhand der Black- und Whitelist und der
//  Spam-Einstufung des Servers:
//  - beim Filterlauf: behalten oder nach Spam (`classify`);
//  - in der Anzeige: ist der Absender vertrauenswürdig genug, um externe
//    Inhalte sofort zu laden (`trustsSender`);
//  - in der Mailliste: darf die Zeile ein Absenderbild zeigen
//    (`allowsSenderImage`) – nur, wenn der Filter die Mail behalten würde.
//
//  Alle Entscheidungen nutzen denselben Listenabgleich (`listMatch`): der
//  genaueste Eintrag gewinnt – exakte Adresse vor Domain, eine Subdomain
//  vor ihrer übergeordneten Domain (`news.firma.de` vor `firma.de`), auf
//  jeder Stufe Whitelist vor Blacklist. Ein Domain-Eintrag gilt samt
//  Subdomains (FilterDomain). Ein Whitelist-Treffer behält die Mail
//  unabhängig von der Einstufung des Servers – Server liegen oft falsch.
//  Einzige Ausnahme: ein gelieferter Score bei oder über der Obergrenze –
//  Schutz gegen gefälschte `From`-Adressen. So gilt für Spamfilter und
//  Anzeige dieselbe Regel, und sie steht nur an einer Stelle.
//
//  Reine Logik ohne IMAP und ohne Speicherort der Listen, vollständig per
//  Unit-Test abgedeckt. `nonisolated`, weil der Filterlauf außerhalb des
//  Main-Actors arbeitet.
//
//  Abgrenzung: Auswertung der Server-Header → SpamHeaderParser; Plan für
//  viele Mails → SpamFilterPlanner; Ausführen → SpamFilterService.
//
//  Abhängigkeiten: Foundation, FilterAddress, FilterDomain, SpamHeaderVerdict.
//

import Foundation

/// Entscheidung des Filters für eine Mail.
nonisolated enum SpamDecision: Equatable {
    /// Mail bleibt in der INBOX.
    case keep
    /// Server-Einstufung (rspamd) → Spam-Ordner.
    case junkServer
    /// Blacklist-Treffer → Spam-Ordner, zusätzlich Keyword `$MailwerkBlacklisted`.
    case junkBlacklist
}

/// Momentaufnahme der Whitelist und der Blacklist, bereits normalisiert.
///
/// Zwei Listen, je nach Art des Eintrags in zwei Mengen zerlegt. Die Trennung
/// dient allein dem Nachschlagen: Ein Absender wird zuerst als ganze Adresse
/// gesucht, erst danach über seine Domain und deren übergeordnete Domains.
/// In der Oberfläche und im Speicher
/// bleiben es zwei Listen.
nonisolated struct FilterLists: Equatable {
    /// Exakte Adressen auf der Whitelist.
    var whiteAddresses: Set<String> = []
    /// Domains auf der Whitelist.
    var whiteDomains: Set<String> = []
    /// Exakte Adressen auf der Blacklist.
    var blackAddresses: Set<String> = []
    /// Domains auf der Blacklist.
    var blackDomains: Set<String> = []

    /// Leere Listen.
    static let empty = FilterLists()
}

/// Entscheidungsregeln aus Listen und Server-Einstufung.
nonisolated enum SpamClassifier {

    /// Standardwert der Score-Obergrenze für Whitelist-Treffer.
    static let defaultScoreLimit: Double = 15

    /// Spezifischster Treffer eines Absenders in den Listen.
    private nonisolated enum ListMatch {
        /// Treffer auf der Whitelist.
        case white
        /// Treffer auf der Blacklist.
        case black
    }

    /// Entscheidet, ob eine Mail behalten oder nach Spam verschoben wird.
    ///
    /// Verarbeitung (der spezifischste Treffer entscheidet):
    /// 1. exakte Adresse: Whitelist → behalten*, Blacklist → Spam
    /// 2. Domain, von der genauesten zur allgemeinsten (`news.firma.de`, dann
    ///    `firma.de`): Whitelist → behalten*, Blacklist → Spam
    /// 3. Server-Einstufung Spam → Spam
    /// 4. sonst behalten
    ///
    /// \* Ein Whitelist-Treffer behält die Mail unabhängig von der
    /// Einstufung des Servers, auch bei „Yes“ ohne Score. Nur ein
    /// gelieferter Score **bei oder über** `scoreLimit` übersteuert ihn –
    /// Schutz gegen gefälschte `From`-Adressen.
    ///
    /// - Parameters:
    ///   - sender: Absender; `nil`, wenn er sich nicht auswerten lässt.
    ///   - verdict: Einstufung des Servers.
    ///   - lists: Black- und Whitelist.
    ///   - scoreLimit: Score-Obergrenze für Whitelist-Treffer.
    /// - Returns: Entscheidung für die Mail.
    static func classify(
        sender: FilterAddress?,
        verdict: SpamHeaderVerdict,
        lists: FilterLists,
        scoreLimit: Double = defaultScoreLimit
    ) -> SpamDecision {
        if let sender, let match = listMatch(for: sender, in: lists) {
            switch match {
            case .white: return whitelisted(verdict, scoreLimit)
            case .black: return .junkBlacklist
            }
        }
        return verdict.isSpam ? .junkServer : .keep
    }

    /// Entscheidet, ob ein Absender vertrauenswürdig genug ist, um externe
    /// Inhalte seiner Mail sofort zu laden.
    ///
    /// Verarbeitung: Vertrauenswürdig ist ein Absender nur, wenn sein
    /// spezifischster Listentreffer die Whitelist ist (Adresse vor Domain,
    /// eine Blacklist-Adresse schlägt also eine Whitelist-Domain) und kein
    /// gelieferter Score die Obergrenze erreicht – dieselbe Regel wie im
    /// Spamfilter. Ist der Befund des Servers unbekannt (nicht gespeichert),
    /// wird nicht vertraut.
    ///
    /// - Parameters:
    ///   - sender: Absender; `nil`, wenn er sich nicht auswerten lässt.
    ///   - verdict: Einstufung des Servers; `nil` = unbekannt.
    ///   - lists: Black- und Whitelist.
    ///   - scoreLimit: Score-Obergrenze für Whitelist-Treffer.
    /// - Returns: `true`, wenn externe Inhalte sofort geladen werden dürfen.
    static func trustsSender(
        sender: FilterAddress?,
        verdict: SpamHeaderVerdict?,
        lists: FilterLists,
        scoreLimit: Double = defaultScoreLimit
    ) -> Bool {
        guard let sender, let verdict,
              listMatch(for: sender, in: lists) == .white else { return false }
        return whitelisted(verdict, scoreLimit) == .keep
    }

    /// Entscheidet, ob die Mailliste zu einer Mail ein Absenderbild
    /// (Kontaktbild oder Logo) zeigen darf.
    ///
    /// Verarbeitung: Erlaubt nur, wenn der Spamfilter die Mail behalten
    /// würde (`classify` liefert `.keep`). Damit bekommt eine Mail auf der
    /// Blacklist oder mit Spam-Einstufung des Servers kein vertraut
    /// wirkendes Bild – außer ein Whitelist-Treffer rettet sie unterhalb der
    /// Score-Obergrenze. Ist die Einstufung des Servers unbekannt, wird
    /// vorsichtshalber kein Bild gezeigt.
    ///
    /// - Parameters:
    ///   - sender: Absender; `nil`, wenn er sich nicht auswerten lässt.
    ///   - verdict: Einstufung des Servers; `nil` = unbekannt.
    ///   - lists: Black- und Whitelist.
    ///   - scoreLimit: Score-Obergrenze für Whitelist-Treffer.
    /// - Returns: `true`, wenn ein Absenderbild gezeigt werden darf.
    static func allowsSenderImage(
        sender: FilterAddress?,
        verdict: SpamHeaderVerdict?,
        lists: FilterLists,
        scoreLimit: Double = defaultScoreLimit
    ) -> Bool {
        guard let verdict else { return false }
        return classify(sender: sender, verdict: verdict, lists: lists, scoreLimit: scoreLimit) == .keep
    }

    /// Prüft, ob der spezifischste Listentreffer eines Absenders die
    /// Whitelist ist.
    ///
    /// Verarbeitung: Derselbe Abgleich wie bei allen Entscheidungen
    /// (`listMatch`) – eine Blacklist-Adresse schlägt also eine
    /// Whitelist-Domain. Die Score-Obergrenze spielt hier keine Rolle.
    ///
    /// - Parameters:
    ///   - sender: Absender.
    ///   - lists: Black- und Whitelist.
    /// - Returns: `true` bei einem Whitelist-Treffer.
    static func isWhitelisted(_ sender: FilterAddress, in lists: FilterLists) -> Bool {
        listMatch(for: sender, in: lists) == .white
    }

    /// Sucht den spezifischsten Listentreffer eines Absenders.
    ///
    /// Verarbeitung: Zuerst die exakte Adresse (Whitelist, dann Blacklist),
    /// danach die Domain und ihre übergeordneten Domains bis zur
    /// Hauptdomain, vom genauesten zum allgemeinsten Eintrag, je Stufe in
    /// derselben Reihenfolge. Der erste Treffer gewinnt.
    ///
    /// - Parameters:
    ///   - sender: Absender.
    ///   - lists: Black- und Whitelist.
    /// - Returns: Treffer oder `nil`, wenn der Absender auf keiner Liste steht.
    private static func listMatch(for sender: FilterAddress, in lists: FilterLists) -> ListMatch? {
        if lists.whiteAddresses.contains(sender.address) { return .white }
        if lists.blackAddresses.contains(sender.address) { return .black }
        for domain in FilterDomain.matchCandidates(for: sender.domain) {
            if lists.whiteDomains.contains(domain) { return .white }
            if lists.blackDomains.contains(domain) { return .black }
        }
        return nil
    }

    /// Ein Whitelist-Treffer schützt, solange kein gelieferter Score die
    /// Obergrenze erreicht. Die Einstufung „Yes“/„No“ des Servers spielt
    /// keine Rolle; ohne Score schützt der Treffer immer.
    ///
    /// - Parameters:
    ///   - verdict: Einstufung des Servers.
    ///   - scoreLimit: Score-Obergrenze.
    /// - Returns: `.keep`, wenn der Treffer schützt, sonst `.junkServer`.
    private static func whitelisted(_ verdict: SpamHeaderVerdict, _ scoreLimit: Double) -> SpamDecision {
        guard let score = verdict.score else { return .keep }
        return score < scoreLimit ? .keep : .junkServer
    }
}
