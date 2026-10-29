//
//  OAuthError.swift
//  Mailwerk
//
//  Zweck: Fehler der Anmeldung per OAuth 2 mit verständlichen deutschen
//  Meldungen.
//
//  Wichtig ist die Unterscheidung „Anmeldung abgelaufen“
//  (`signInRequired`) gegenüber allem anderen: Nur dann zeigt Mailwerk
//  am Postfach das Warnzeichen und den Hinweis „Neu anmelden“. Ein
//  fehlendes Netz ist nie „abgelaufen“ – es bleibt ein Verbindungsfehler
//  (URLError) und wird wie bisher als „Offline“ behandelt.
//
//  Abgrenzung: Einordnung von Verbindungsfehlern →
//  ConnectionErrorClassifier.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Fehler der Anmeldung per OAuth 2.
nonisolated enum OAuthError: LocalizedError, Equatable, Sendable {
    /// Der Anbieter nimmt die gespeicherte Anmeldung nicht mehr an (oder es
    /// ist keine gespeichert) – der Nutzer muss sich neu anmelden.
    case signInRequired
    /// Der Nutzer hat das Anmeldefenster geschlossen.
    case cancelled
    /// Das Anmeldefenster steht hier nicht zur Verfügung (z. B. in der
    /// Teilen-Erweiterung).
    case signInUnavailable
    /// Die Rückkehr aus dem Anmeldefenster gehört nicht zu dieser
    /// Anmeldung (`state` weicht ab).
    case stateMismatch
    /// Der Anbieter hat die Anmeldung abgelehnt; Fehlercode und Text des
    /// Anbieters.
    case providerError(code: String, description: String?)
    /// Die Antwort des Anbieters ist unvollständig oder unlesbar.
    case invalidResponse(String)
    /// Der Anbieter hat keine dauerhafte Anmeldung (Refresh-Token)
    /// geliefert.
    case missingRefreshToken
    /// Das System liefert keinen Zufall für PKCE und `state`.
    case randomUnavailable

    /// Liefert die deutsche Meldung für den Nutzer.
    ///
    /// - Returns: Meldungstext für die Anzeige.
    var errorDescription: String? {
        switch self {
        case .signInRequired:
            return "Die Anmeldung ist abgelaufen. Bitte in Mailwerk neu anmelden."
        case .cancelled:
            return "Die Anmeldung wurde abgebrochen."
        case .signInUnavailable:
            return "Die Anmeldung ist hier nicht möglich. Bitte in Mailwerk anmelden."
        case .stateMismatch:
            return "Die Anmeldung konnte nicht bestätigt werden. Bitte erneut versuchen."
        case .providerError(let code, let description):
            let detail = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return detail.isEmpty
                ? "Die Anmeldung wurde abgelehnt (\(code))."
                : "Die Anmeldung wurde abgelehnt (\(code)): \(detail)"
        case .invalidResponse(let detail):
            return "Unerwartete Antwort bei der Anmeldung: \(detail)"
        case .missingRefreshToken:
            return "Der Anbieter hat keine dauerhafte Anmeldung geliefert. Bitte erneut anmelden."
        case .randomUnavailable:
            return "Die Anmeldung konnte nicht vorbereitet werden (kein Zufallswert)."
        }
    }
}
