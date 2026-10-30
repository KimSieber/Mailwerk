//
//  MessageActionDialogs.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 12.10.2026
//  Geändert: 24.10.2026
//
//  Zweck: Rückfragen und Meldungen zu den Aktionen des Mail-Menüs –
//  einheitlich für Mailansicht und Liste: Löschen (mit Anzahl), Spam-
//  Aktionen (Blockieren, Vertrauen) samt Ergebnis- und Fehlermeldung.
//  Dazu die Ausführung einer Spam-Aktion an einer Mail.
//
//  Abgrenzung: Darstellung der Dialoge → Dialogs.swift; Texte der
//  Spam-Aktionen → SpamMenuTexts; Eintragen und Verschieben selbst →
//  SpamFilterService; Menü → MessageMenu.
//
//  Abhängigkeiten: Dialogs (AlertItem, ConfirmationRequest),
//  SpamFilterService, FilterListError, SpamMenuChoice (SpamMenuRequest,
//  SpamMenuTexts).
//

import Foundation

/// Rückfragen und Meldungen zu den Aktionen an Mails.
enum MessageActionDialogs {

    /// Rückfrage vor dem Löschen von Mails, mit Anzahl ab zwei Mails.
    ///
    /// - Parameters:
    ///   - count: Anzahl der zu löschenden Mails (mindestens 1).
    ///   - onConfirm: Wird nach „Löschen“ ausgeführt.
    /// - Returns: Rückfrage.
    static func deleteConfirmation(count: Int, onConfirm: @escaping () -> Void) -> ConfirmationRequest {
        let isSingle = count <= 1
        return ConfirmationRequest(
            title: isSingle ? "Mail löschen?" : "\(count) Mails löschen?",
            message: isSingle
                ? "Die Mail wird auf dem Server gelöscht bzw. in den Papierkorb verschoben."
                : "Die \(count) Mails werden auf dem Server gelöscht bzw. in den Papierkorb verschoben.",
            confirmLabel: "Löschen",
            onConfirm: onConfirm
        )
    }

    /// Rückfrage vor dem Blockieren bzw. Vertrauen.
    ///
    /// - Parameters:
    ///   - request: Spam-Aktion.
    ///   - onConfirm: Wird nach dem Bestätigen ausgeführt.
    /// - Returns: Rückfrage; Blockieren mit rotem Knopf.
    static func spamConfirmation(_ request: SpamMenuRequest, onConfirm: @escaping () -> Void) -> ConfirmationRequest {
        ConfirmationRequest(
            title: SpamMenuTexts.confirmationTitle(request),
            message: SpamMenuTexts.confirmationMessage(request),
            confirmLabel: SpamMenuTexts.confirmLabel(request),
            isDestructive: request.kind == .block,
            onConfirm: onConfirm
        )
    }

    /// Bestätigung eines Listeneintrags, wenn die Mail nicht verschoben wurde.
    ///
    /// - Parameter request: Ausgeführte Spam-Aktion.
    /// - Returns: Meldung.
    static func spamResultAlert(_ request: SpamMenuRequest) -> AlertItem {
        AlertItem(title: "Listeneintrag", message: SpamMenuTexts.resultMessage(request))
    }

    /// Meldung zu einer gescheiterten Spam-Aktion.
    ///
    /// Verarbeitung: Steht der Wert schon auf der anderen Liste, erklärt die
    /// Meldung, was zu tun ist; sonst erscheint der Fehlertext.
    ///
    /// - Parameters:
    ///   - request: Spam-Aktion.
    ///   - error: Aufgetretener Fehler.
    /// - Returns: Meldung.
    static func spamFailureAlert(_ request: SpamMenuRequest, _ error: Error) -> AlertItem {
        if case FilterListError.alreadyOnOtherList(let list) = error {
            return AlertItem(
                title: "Listeneintrag",
                message: SpamMenuTexts.otherListMessage(request, list: list)
            )
        }
        return .failure("Listeneintrag fehlgeschlagen", error)
    }
}

extension SpamMenuRequest {
    /// Trägt Adresse bzw. Domain in die Liste ein und verschiebt die Mail
    /// bei Bedarf (Blockieren → Spam-Ordner, Vertrauen → aus dem
    /// Spam-Ordner in den Posteingang).
    ///
    /// - Parameters:
    ///   - message: Betroffene Mail.
    ///   - spamFilter: Spamfilter mit Listen und Serverzugang.
    /// - Returns: `true`, wenn die Mail verschoben wurde.
    /// - Throws: Fehler der Filterlisten (z. B. `FilterListError`) oder
    ///   Verbindungs- und Serverfehler.
    func perform(on message: CachedMessage, using spamFilter: SpamFilterService) async throws -> Bool {
        switch kind {
        case .block: return try await spamFilter.block(message, kind: entryKind, value: value)
        case .trust: return try await spamFilter.trust(message, kind: entryKind, value: value)
        }
    }
}
