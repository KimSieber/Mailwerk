//
//  SpamFilterPlanner.swift
//  Mailwerk
//
//  Fasst die Einzelentscheidungen eines Filterlaufs zu einem Arbeitsplan
//  zusammen: welche Nachrichten bekommen welches Keyword, welche wandern
//  in den Spam-Ordner.
//
//  Der Plan bündelt gleichartige Schritte, damit der Server pro Lauf nur
//  wenige Befehle sieht statt einen je Nachricht. Reine Logik ohne IMAP,
//  deshalb `nonisolated` und vollständig per Unit-Test abgedeckt.
//

import Foundation

/// Eine zu prüfende Nachricht, reduziert auf das, was die Entscheidung braucht.
nonisolated struct SpamCandidate: Equatable {
    let uid: UInt32
    /// Absender laut `From`-Header; nil, wenn er unbrauchbar ist.
    let sender: FilterAddress?
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

    static let empty = SpamFilterPlan()

    var isEmpty: Bool { checked.isEmpty }
}

nonisolated enum SpamFilterPlanner {

    /// Wendet den Classifier auf alle Kandidaten an und bündelt das Ergebnis.
    /// Kommt dieselbe UID mehrfach vor, zählt sie nur einmal.
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
}
