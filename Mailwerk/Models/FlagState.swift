//
//  FlagState.swift
//  Mailwerk
//
//  Zweck: Wertet die IMAP-Flags einer Mail in einem Durchlauf aus –
//  ungelesen, gekennzeichnet, beantwortet, weitergeleitet.
//
//  „Weitergeleitet“ ist kein Systemflag, sondern das Keyword `$Forwarded`
//  (Apple Mail, Thunderbird u. a.); verglichen wird ohne Groß-/Kleinschreibung.
//
//  Abgrenzung: Abruf und Abgleich → MailFetchService; Markieren beim
//  Versand → MailSendService.
//
//  Abhängigkeiten: SwiftMail (Flag).
//

import Foundation
import SwiftMail

/// Ausgewertete IMAP-Flags einer Mail.
nonisolated struct FlagState: Equatable {
    /// IMAP-Keyword für weitergeleitete Mails.
    static let forwardedKeyword = "$Forwarded"

    /// Ohne `\Seen`.
    let isUnread: Bool
    /// Mit `\Flagged`.
    let isFlagged: Bool
    /// Mit `\Answered`.
    let isAnswered: Bool
    /// Mit `$Forwarded`.
    let isForwarded: Bool

    /// Wertet die Flags einer Mail aus.
    ///
    /// Verarbeitung: Ein Durchlauf über alle Flags. `SwiftMail.Flag` ist
    /// voll qualifiziert, da NIOIMAPCore ebenfalls `Flag` definiert.
    ///
    /// - Parameter flags: IMAP-Flags der Mail.
    init(_ flags: [SwiftMail.Flag]) {
        var seen = false, flagged = false, answered = false, forwarded = false
        for flag in flags {
            switch flag {
            case .seen:     seen = true
            case .flagged:  flagged = true
            case .answered: answered = true
            case .custom(let keyword)
                where keyword.caseInsensitiveCompare(Self.forwardedKeyword) == .orderedSame:
                forwarded = true
            default:        break
            }
        }
        isUnread = !seen
        isFlagged = flagged
        isAnswered = answered
        isForwarded = forwarded
    }
}
