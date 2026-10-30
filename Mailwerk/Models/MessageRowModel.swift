//
//  MessageRowModel.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 30.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Vorberechnete Anzeige einer Zeile der Mailliste – wer gezeigt
//  wird (Name, Adresse), ob ein Absenderbild erlaubt ist und der
//  Spam-Hinweis. Bisher berechnete die Liste das bei jedem Neuzeichnen je
//  Zeile neu und zerlegte dabei die Absenderadresse dreimal (Prüfbericht
//  P-08). Jetzt entsteht das Modell einmal je Liste im Hintergrund
//  (InboxViewModel), die Zeile liest nur noch Werte.
//
//  Die Spam-Einstufung für Bild und Hinweis folgt denselben Regeln wie
//  bisher (SpamClassifier, SpamMark). Ohne gelesene Filterlisten gibt es
//  vorsichtshalber weder Bild noch Hinweis.
//
//  Nebenläufigkeit: `nonisolated` und `Sendable`, damit das Modell abseits
//  des Hauptthreads entstehen kann.
//
//  Abgrenzung: Darstellung → MessageRow; Datumstext → ListDateFormatter
//  (beim Zeichnen, weil er vom aktuellen Tag abhängt).
//
//  Abhängigkeiten: MessageListItem, MessageRowParty, FilterAddress,
//  FilterLists, SpamClassifier, SpamMark.
//

import Foundation

/// Vorberechnete Anzeige einer Zeile der Mailliste.
nonisolated struct MessageRowModel: Equatable, Sendable {
    /// Gezeigte Person (Absender bzw. erster Empfänger).
    let party: MessageRowParty
    /// `true`, wenn die Zeile ein Absenderbild zeigen darf.
    let showsImage: Bool
    /// Spam-Hinweis der Liste (`[SPAM]`) oder `nil`.
    let spamMark: String?

    /// Eingaben, von denen das Modell außer der Mail selbst abhängt.
    /// Ändert sich eine davon, gelten vorberechnete Modelle nicht mehr.
    nonisolated struct Inputs: Equatable, Sendable {
        /// `true` in Gesendet und Entwürfen (Empfänger statt Absender).
        let showsRecipients: Bool
        /// Filterlisten; `nil`, solange sie nicht gelesen sind.
        let lists: FilterLists?
        /// Score-Obergrenze für Whitelist-Treffer.
        let scoreLimit: Double
    }

    /// Berechnet das Modell einer Zeile.
    ///
    /// Verarbeitung: Zerlegt die gezeigte Adresse einmal für die Namenszeile
    /// und den Absender einmal für die Spam-Einstufung; Bild und Hinweis
    /// stammen aus derselben Einstufung. Ohne Listen weder Bild noch Hinweis.
    ///
    /// - Parameters:
    ///   - item: Listeneintrag.
    ///   - inputs: Gemeinsame Eingaben der Liste.
    /// - Returns: Modell der Zeile.
    static func make(for item: MessageListItem, inputs: Inputs) -> MessageRowModel {
        let party = MessageRowParty.make(for: item, showsRecipients: inputs.showsRecipients)
        guard let lists = inputs.lists else {
            return MessageRowModel(party: party, showsImage: false, spamMark: nil)
        }
        let sender = FilterAddress.sender(fromHeader: item.from)
        return MessageRowModel(
            party: party,
            showsImage: SpamClassifier.allowsSenderImage(
                sender: sender, verdict: item.spamVerdict, lists: lists, scoreLimit: inputs.scoreLimit
            ),
            spamMark: SpamMark.text(
                sender: sender, verdict: item.spamVerdict,
                rules: SpamRules(lists: lists, scoreLimit: inputs.scoreLimit), style: .list
            )
        )
    }

    /// Berechnet die Modelle einer ganzen Liste.
    ///
    /// - Parameters:
    ///   - items: Listeneinträge.
    ///   - inputs: Gemeinsame Eingaben der Liste.
    /// - Returns: Modelle je Cache-ID.
    static func makeAll(for items: [MessageListItem], inputs: Inputs) -> [String: MessageRowModel] {
        var result: [String: MessageRowModel] = [:]
        result.reserveCapacity(items.count)
        for item in items {
            result[item.id] = make(for: item, inputs: inputs)
        }
        return result
    }
}
