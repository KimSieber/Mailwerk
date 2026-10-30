//
//  MailServerFactory.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 23.09.2026
//  Geändert: 30.10.2026
//
//  Zweck: Zentrale und einzige Stelle, an der IMAP- und SMTP-Verbindungen
//  erzeugt werden. Erzwingt verschlüsselte Verbindungen:
//
//  - Port 993 (IMAP) und 465 (SMTP): TLS ab dem ersten Byte (implicit TLS)
//  - jeder andere Port: STARTTLS ist Pflicht – bietet der Server es nicht
//    an, bricht die Verbindung ab, bevor Zugangsdaten gesendet werden
//  - Zertifikate werden vollständig geprüft, Mindestversion TLS 1.2
//
//  Unverschlüsselte Verbindungen sind bewusst nicht möglich.
//
//  Nebenläufigkeit (v0.2.3b): `nonisolated` – reine Werte bzw. Logik ohne
//  Bezug zur Oberfläche, damit der Abruf sie abseits des Hauptthreads
//  nutzen kann.
//
//  Abgrenzung: Anmeldung und Ablauf einer Verbindung → MailSession.
//
//  Abhängigkeiten: Foundation, SwiftMail, MailAccount.
//

import Foundation
import SwiftMail

/// Erzeugt verschlüsselte IMAP- und SMTP-Verbindungen.
nonisolated enum MailServerFactory {

    /// Ports, auf denen TLS von Beginn an gesprochen wird.
    private static let implicitTLSPorts: Set<Int> = [MailPorts.imaps, MailPorts.smtps]

    /// Mindestversion für alle TLS-Verbindungen.
    private static let minimumTLSVersion: MailTLSMinimumVersion = .tlsv12

    /// Zeitbudgets für den SMTP-Versand. Die SwiftMail-Vorgaben (RFC 5321:
    /// bis zu 10 Minuten je Schritt) sind für eine interaktive App zu lang –
    /// der Nutzer soll nach spätestens rund zwei Minuten eine klare Meldung
    /// bekommen, statt dass der Versand scheinbar hängt.
    private static let smtpSubmissionTimeouts = SMTPSubmissionTimeouts(
        mailFromResponse: smtpCommandTimeoutSeconds,
        recipientResponse: smtpCommandTimeoutSeconds,
        dataResponse: smtpCommandTimeoutSeconds,
        contentUpload: smtpContentTimeoutSeconds,
        contentResponse: smtpContentTimeoutSeconds
    )
    /// Zeitbudget je SMTP-Befehl (MAIL FROM, RCPT TO, DATA) in Sekunden.
    private static let smtpCommandTimeoutSeconds: TimeInterval = 60
    /// Zeitbudget für Übertragung und Bestätigung des Inhalts in Sekunden.
    private static let smtpContentTimeoutSeconds: TimeInterval = 120

    /// Transportsicherheit für einen Port – niemals `.plainText` oder `.automatic`.
    ///
    /// - Parameter port: Server-Port.
    /// - Returns: Implicit TLS für 993/465, sonst STARTTLS.
    static func transportSecurity(forPort port: Int) -> MailTransportSecurity {
        implicitTLSPorts.contains(port) ? .implicitTLS : .startTLS
    }

    // MARK: - IMAP

    /// IMAP-Server mit erzwungener Verschlüsselung.
    ///
    /// - Parameters:
    ///   - host: Servername.
    ///   - port: Port.
    /// - Returns: Noch nicht verbundener Server.
    static func imapServer(host: String, port: Int) -> IMAPServer {
        IMAPServer(
            host: host,
            port: port,
            transportSecurity: transportSecurity(forPort: port),
            certificateVerificationPolicy: .fullVerification,
            minimumTLSVersion: minimumTLSVersion
        )
    }

    /// IMAP-Server eines Postfachs.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Noch nicht verbundener Server.
    static func imapServer(for account: MailAccount) -> IMAPServer {
        imapServer(host: account.imapHost, port: account.imapPort)
    }

    // MARK: - SMTP

    /// SMTP-Server mit erzwungener Verschlüsselung und kurzen Zeitbudgets.
    ///
    /// - Parameters:
    ///   - host: Servername.
    ///   - port: Port.
    /// - Returns: Noch nicht verbundener Server.
    static func smtpServer(host: String, port: Int) -> SMTPServer {
        SMTPServer(
            host: host,
            port: port,
            transportSecurity: transportSecurity(forPort: port),
            certificateVerificationPolicy: .fullVerification,
            minimumTLSVersion: minimumTLSVersion,
            submissionTimeouts: smtpSubmissionTimeouts
        )
    }

    /// SMTP-Server eines Postfachs.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Noch nicht verbundener Server.
    static func smtpServer(for account: MailAccount) -> SMTPServer {
        smtpServer(host: account.smtpHost, port: account.smtpPort)
    }
}
