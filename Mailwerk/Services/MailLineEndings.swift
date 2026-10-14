//
//  MailLineEndings.swift
//  Mailwerk
//
//  Zweck: Bringt Text- und HTML-Teil einer ausgehenden Nachricht auf
//  einheitliche Zeilenenden CRLF ("\r\n"), wie SMTP und IMAP sie verlangen.
//
//  Hintergrund: Meldet der Server 8BITMIME, übergibt SwiftMail Text und HTML
//  unverändert als `8bit`. Ein einzelnes LF ("\n") aus Editor oder Signatur
//  käme dann als „nacktes LF“ beim Server an. Strenge Server (z. B. Posteo,
//  Schutz gegen SMTP Smuggling) lehnen das ab: „521 5.5.2 bare <LF> received“.
//
//  Abgrenzung: Aufbau der Nachricht → MailSendService.makeEmail; Kodierung
//  und Versand → SwiftMail.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Vereinheitlicht Zeilenenden für den Versand.
nonisolated enum MailLineEndings {

    /// Wandelt alle Zeilenenden eines Textes in CRLF um.
    ///
    /// Verarbeitung: Zuerst werden CRLF und einzelne CR zu LF
    /// zusammengeführt, danach wird jedes LF zu CRLF. So entsteht weder ein
    /// doppeltes CR noch bleibt ein einzelnes CR oder LF übrig – egal, in
    /// welcher Mischung der Text ankommt.
    ///
    /// - Parameter text: Text mit beliebigen Zeilenenden.
    /// - Returns: Derselbe Text, jedes Zeilenende als CRLF.
    static func crlf(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
    }
}
