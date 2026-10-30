//
//  SMTPLoginFailure.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 14.10.2026
//  Geändert: 14.10.2026
//
//  Zweck: Verständliche Meldung, wenn die Anmeldung am Versandserver
//  (SMTP) scheitert.
//
//  Hintergrund: Manche Server (z. B. Gmail) beantworten eine abgelehnte
//  Anmeldung mit „535 …“ und schließen sofort die Verbindung. SwiftMail
//  versucht danach auf derselben Verbindung das nächste Verfahren
//  (AUTH LOGIN) und meldet nur noch einen NIO-Fehler („ChannelError 5“) –
//  die Antwort des Servers geht dabei verloren. Scheitert der Schritt
//  „Anmelden“, nachdem die Verbindung stand, liegt es fast immer an
//  Benutzername oder Passwort; das sagt die Meldung.
//
//  Abgrenzung: Welcher Schritt gescheitert ist, ermitteln MailSendService
//  und MailConnectionTester; hier entsteht nur der Text.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Schritte einer SMTP-Sitzung, für Meldungen und Protokoll.
nonisolated enum SMTPStep: String {
    /// Verbindung aufbauen (inkl. TLS und EHLO).
    case connect = "Verbinden"
    /// Anmelden (AUTH).
    case login = "Anmelden"
    /// Nachricht übertragen.
    case send = "Senden"
}

/// Meldungstexte zu einer gescheiterten SMTP-Anmeldung.
nonisolated enum SMTPLoginFailure {

    /// Meldung für den Nutzer, wenn die Anmeldung am Versandserver scheitert.
    ///
    /// Verarbeitung: Liegt eine Antwort des Servers vor (z. B. „535 5.7.8
    /// Username and Password not accepted“), wird sie genannt. Fehlt sie,
    /// weil der Server die Verbindung sofort beendet hat, erklärt die Meldung
    /// das und nennt die übliche Ursache. Leere Antworten zählen als fehlend.
    ///
    /// - Parameter serverReply: Antwort des Servers auf die Anmeldung, falls
    ///   bekannt.
    /// - Returns: Deutsche Meldung mit Hinweis auf Benutzername und Passwort.
    static func message(serverReply: String?) -> String {
        let reply = serverReply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if reply.isEmpty {
            return "Anmeldung am Versandserver fehlgeschlagen – der Server hat die Verbindung beendet. Meist sind Benutzername oder Passwort falsch; bitte prüfen."
        }
        return "Anmeldung am Versandserver abgelehnt (\(reply)). Bitte Benutzername und Passwort prüfen."
    }
}
