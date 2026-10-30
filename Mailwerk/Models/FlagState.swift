//
//  FlagState.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 10.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Wertet die IMAP-Flags einer Mail in einem Durchlauf aus –
//  ungelesen, gekennzeichnet, beantwortet, weitergeleitet.
//
//  „Weitergeleitet“ ist kein Systemflag, sondern das Keyword `$Forwarded`
//  (Apple Mail, Thunderbird u. a.); verglichen wird ohne Groß-/Kleinschreibung.
//
//  Vergleich mit dem Cache: `matches(_:)` sagt, ob der gespeicherte Stand
//  einer Mail schon den Server-Flags entspricht – dann muss beim Abruf
//  nichts geschrieben werden.
//
//  Abgrenzung: Abruf und Abgleich → MailFetchService; Markieren beim
//  Versand → MailSendService.
//
//  Abhängigkeiten: SwiftMail (Flag), CachedFlagState (Vergleich).
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

    /// Flags aus gespeicherten Einzelwerten (z. B. aus dem Cache).
    ///
    /// - Parameters:
    ///   - isUnread: Ohne `\Seen`.
    ///   - isFlagged: Mit `\Flagged`.
    ///   - isAnswered: Mit `\Answered`.
    ///   - isForwarded: Mit `$Forwarded`.
    init(isUnread: Bool, isFlagged: Bool, isAnswered: Bool, isForwarded: Bool) {
        self.isUnread = isUnread
        self.isFlagged = isFlagged
        self.isAnswered = isAnswered
        self.isForwarded = isForwarded
    }

    /// Prüft, ob der gespeicherte Stand einer Mail diesen Flags entspricht.
    ///
    /// Verarbeitung: Vergleich in `CachedFlagState.matches` (dort getestet).
    ///
    /// - Parameter cached: Flags der Mail im Cache.
    /// - Returns: `true`, wenn alle vier Flags übereinstimmen.
    func matches(_ cached: CachedFlagState) -> Bool {
        cached.matches(
            isUnread: isUnread, isFlagged: isFlagged,
            isAnswered: isAnswered, isForwarded: isForwarded
        )
    }
}
