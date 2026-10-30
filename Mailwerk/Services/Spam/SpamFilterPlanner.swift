//
//  SpamFilterPlanner.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 24.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Fasst die Einzelentscheidungen eines Filterlaufs zu einem
//  Arbeitsplan zusammen: welche Nachrichten bekommen welches Keyword,
//  welche wandern in den Spam-Ordner.
//
//  Der Plan bündelt gleichartige Schritte, damit der Server pro Lauf nur
//  wenige Befehle sieht statt einen je Nachricht. Reine Logik ohne IMAP,
//  deshalb `nonisolated` und vollständig per Unit-Test abgedeckt.
//
//  Dazu die Auswahl der zu prüfenden Mails (`uncheckedUIDs`) – auch das
//  reine Logik, damit der Filterlauf im Dienst nur noch ausführt.
//
//  Abgrenzung: Einzelentscheidung → SpamClassifier; Ausführen →
//  SpamFilterService.
//
//  Abhängigkeiten: Foundation, SpamClassifier, FilterAddress, SpamHeaderVerdict.
//

import Foundation

/// Eine zu prüfende Nachricht, reduziert auf das, was die Entscheidung braucht.
nonisolated struct SpamCandidate: Equatable {
    /// UID im Posteingang.
    let uid: UInt32
    /// Absender laut `From`-Header; nil, wenn er unbrauchbar ist.
    let sender: FilterAddress?
    /// Einstufung des Servers.
    let verdict: SpamHeaderVerdict
}

/// Arbeitsplan eines Laufs. Alle Listen sind aufsteigend nach UID sortiert
/// und frei von Doppelten.
nonisolated struct SpamFilterPlan: Equatable {
    /// Alle verarbeiteten Nachrichten – bekommen `$MailwerkChecked`,
    /// damit kein Gerät sie ein zweites Mal prüft.
    var checked: [UInt32] = []
    /// Zusätzlich `$MailwerkBlacklisted`: als Spam erkannt wegen Blacklist.
    var blacklisted: [UInt32] = []
    /// Wandern in den Spam-Ordner des Postfachs.
    var moveToSpam: [UInt32] = []
    /// Bleiben im Posteingang.
    var keep: [UInt32] = []

    /// Leerer Plan.
    static let empty = SpamFilterPlan()

    /// `true`, wenn nichts zu tun ist.
    var isEmpty: Bool { checked.isEmpty }
}

/// Erstellt den Arbeitsplan eines Filterlaufs.
nonisolated enum SpamFilterPlanner {

    /// Wendet den Classifier auf alle Kandidaten an und bündelt das Ergebnis.
    ///
    /// Verarbeitung: Kommt dieselbe UID mehrfach vor, zählt sie nur einmal;
    /// alle Listen werden aufsteigend sortiert.
    ///
    /// - Parameters:
    ///   - candidates: Zu prüfende Nachrichten.
    ///   - lists: Black- und Whitelist.
    ///   - scoreLimit: Score-Obergrenze für Whitelist-Treffer.
    /// - Returns: Arbeitsplan.
    static func plan(
        for candidates: [SpamCandidate],
        lists: FilterLists,
        scoreLimit: Double = SpamClassifier.defaultScoreLimit
    ) -> SpamFilterPlan {
        var plan = SpamFilterPlan()
        var seen = Set<UInt32>()

        for candidate in candidates where seen.insert(candidate.uid).inserted {
            plan.checked.append(candidate.uid)

            switch SpamClassifier.classify(
                sender: candidate.sender,
                verdict: candidate.verdict,
                lists: lists,
                scoreLimit: scoreLimit
            ) {
            case .keep:
                plan.keep.append(candidate.uid)
            case .junkServer:
                plan.moveToSpam.append(candidate.uid)
            case .junkBlacklist:
                plan.moveToSpam.append(candidate.uid)
                plan.blacklisted.append(candidate.uid)
            }
        }

        // Aufsteigend sortiert, damit die IMAP-Befehle unabhängig von der
        // Reihenfolge der Serverantwort immer gleich aussehen.
        plan.checked.sort()
        plan.blacklisted.sort()
        plan.moveToSpam.sort()
        plan.keep.sort()
        return plan
    }

    /// Bestimmt, welche gefundenen Mails ein Filterlauf prüfen muss.
    ///
    /// Verarbeitung: Speichert der Server eigene Schlüsselwörter, hat die
    /// Suche schon nur Mails ohne `$MailwerkChecked` geliefert – alle zählen.
    /// Sonst gilt als „schon geprüft“, was bereits im Cache des
    /// Posteingangs liegt: Der Filter läuft vor jedem Abruf des
    /// Posteingangs, neue Mails sind also genau die noch nicht gecachten.
    ///
    /// - Parameters:
    ///   - found: UIDs aus der Suche des Filterlaufs.
    ///   - usesKeywords: `true`, wenn der Server eigene Schlüsselwörter speichert.
    ///   - cached: UIDs des Posteingangs im Cache.
    /// - Returns: Zu prüfende UIDs in der Reihenfolge der Suche.
    static func uncheckedUIDs(found: [UInt32], usesKeywords: Bool, cached: Set<UInt32>) -> [UInt32] {
        usesKeywords ? found : found.filter { !cached.contains($0) }
    }
}
