//
//  SMTPLoginFailureTests.swift
//  MailwerkTests
//
//  Zweck: Tests für `SMTPLoginFailure.message` – verständliche Meldung bei
//  abgelehnter SMTP-Anmeldung, mit und ohne Antwort des Servers.
//

import Foundation
import Testing
@testable import Mailwerk

struct SMTPLoginFailureTests {

    /// Mit Antwort des Servers wird sie genannt.
    @Test func namesServerReply() {
        let text = SMTPLoginFailure.message(serverReply: "535 5.7.8 Username and Password not accepted")
        #expect(text.contains("abgelehnt"))
        #expect(text.contains("535 5.7.8 Username and Password not accepted"))
        #expect(text.contains("Benutzername und Passwort"))
    }

    /// Ohne Antwort (Verbindung beendet) nennt die Meldung den Abbruch.
    @Test func explainsClosedConnection() {
        let text = SMTPLoginFailure.message(serverReply: nil)
        #expect(text.contains("Verbindung beendet"))
        #expect(text.contains("Benutzername oder Passwort"))
    }

    /// Leere Antwort zählt wie keine Antwort.
    @Test func treatsBlankReplyAsMissing() {
        #expect(SMTPLoginFailure.message(serverReply: "  \n") == SMTPLoginFailure.message(serverReply: nil))
    }
}
