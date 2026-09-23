//
//  MailServerFactory.swift
//  Mailwerk
//
//  Zentrale und einzige Stelle, an der IMAP- und SMTP-Verbindungen erzeugt
//  werden. Erzwingt verschlüsselte Verbindungen:
//
//  - Port 993 (IMAP) und 465 (SMTP): TLS ab dem ersten Byte (implicit TLS)
//  - jeder andere Port: STARTTLS ist Pflicht – bietet der Server es nicht an,
//    bricht die Verbindung ab, bevor Zugangsdaten gesendet werden
//  - Zertifikate werden vollständig geprüft, Mindestversion TLS 1.2
//
//  Unverschlüsselte Verbindungen sind bewusst nicht möglich.
//

import Foundation
import SwiftMail

enum MailServerFactory {

    /// Ports, auf denen TLS von Beginn an gesprochen wird.
    private static let implicitTLSPorts: Set<Int> = [993, 465]

    /// Mindestversion für alle TLS-Verbindungen.
    private static let minimumTLSVersion: MailTLSMinimumVersion = .tlsv12

    /// Zeitbudgets für den SMTP-Versand. Die SwiftMail-Vorgaben (RFC 5321:
    /// bis zu 10 Minuten je Schritt) sind für eine interaktive App zu lang –
    /// der Nutzer soll nach spätestens rund zwei Minuten eine klare Meldung
    /// bekommen, statt dass der Versand scheinbar hängt.
    private static let smtpSubmissionTimeouts = SMTPSubmissionTimeouts(
        mailFromResponse: 60,
        recipientResponse: 60,
        dataResponse: 60,
        contentUpload: 120,
        contentResponse: 120
    )

    /// Transportsicherheit für einen Port – niemals `.plainText` oder `.automatic`.
    static func transportSecurity(forPort port: Int) -> MailTransportSecurity {
        implicitTLSPorts.contains(port) ? .implicitTLS : .startTLS
    }

    // MARK: - IMAP

    static func imapServer(host: String, port: Int) -> IMAPServer {
        IMAPServer(
            host: host,
            port: port,
            transportSecurity: transportSecurity(forPort: port),
            certificateVerificationPolicy: .fullVerification,
            minimumTLSVersion: minimumTLSVersion
        )
    }

    static func imapServer(for account: MailAccount) -> IMAPServer {
        imapServer(host: account.imapHost, port: account.imapPort)
    }

    // MARK: - SMTP

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

    static func smtpServer(for account: MailAccount) -> SMTPServer {
        smtpServer(host: account.smtpHost, port: account.smtpPort)
    }
}
