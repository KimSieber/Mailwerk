//
//  SpamClassifier.swift
//  Mailwerk
//
//  Entscheidet für eine Mail: behalten oder nach Spam. Reine Logik ohne IMAP
//  und ohne Speicherort der Listen, vollständig per Unit-Test abgedeckt.
//
//  `nonisolated`, weil der Filterlauf außerhalb des Main-Actors arbeitet.
//

import Foundation

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
/// gesucht, erst danach über seine Domain. In der Oberfläche und im Speicher
/// bleiben es zwei Listen.
nonisolated struct FilterLists: Equatable {
    var whiteAddresses: Set<String> = []
    var whiteDomains: Set<String> = []
    var blackAddresses: Set<String> = []
    var blackDomains: Set<String> = []

    static let empty = FilterLists()
}

nonisolated enum SpamClassifier {

    /// Standardwert der Score-Obergrenze für Whitelist-Treffer.
    static let defaultScoreLimit: Double = 15

    /// Vorrang (der spezifischste Treffer entscheidet):
    /// 1. exakte Adresse: Whitelist → behalten*, Blacklist → Spam
    /// 2. Domain: Whitelist → behalten*, Blacklist → Spam
    /// 3. Server-Einstufung Spam → Spam
    /// 4. sonst behalten
    ///
    /// \* Eine vom Server als Spam markierte Mail wird trotz Whitelist-Treffer
    /// nur behalten, wenn ihr Score **unter** `scoreLimit` liegt. Ohne lesbaren
    /// Score gilt er als unendlich. Schutz gegen gefälschte `From`-Adressen.
    static func classify(
        sender: FilterAddress?,
        verdict: SpamHeaderVerdict,
        lists: FilterLists,
        scoreLimit: Double = defaultScoreLimit
    ) -> SpamDecision {
        if let sender {
            if lists.whiteAddresses.contains(sender.address) {
                return whitelisted(verdict, scoreLimit)
            }
            if lists.blackAddresses.contains(sender.address) {
                return .junkBlacklist
            }
            if lists.whiteDomains.contains(sender.domain) {
                return whitelisted(verdict, scoreLimit)
            }
            if lists.blackDomains.contains(sender.domain) {
                return .junkBlacklist
            }
        }
        return verdict.isSpam ? .junkServer : .keep
    }

    /// Ein Whitelist-Treffer schützt nur unterhalb der Score-Obergrenze.
    /// Ohne lesbaren Score gilt die Mail als hoch bewertet (konservativ).
    private static func whitelisted(_ verdict: SpamHeaderVerdict, _ scoreLimit: Double) -> SpamDecision {
        guard verdict.isSpam else { return .keep }
        let score = verdict.score ?? .infinity
        return score < scoreLimit ? .keep : .junkServer
    }
}
