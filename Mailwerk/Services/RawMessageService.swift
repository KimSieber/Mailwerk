//
//  RawMessageService.swift
//  Mailwerk
//
//  Zweck: Holt die Originalquelle einer Mail vom Server – genau so, wie
//  sie übertragen wurde – und bereitet sie zur Anzeige auf.
//
//  Die Quelle wird bei jedem Öffnen neu geholt und nicht gespeichert: Sie
//  ist ein seltener Analysefall, der Cache enthält nur ausgewählte
//  Kopfzeilen, und eine Kopie würde ihn bei großen Mails verdoppeln.
//
//  Der Ordner wird nur zum Lesen geöffnet (EXAMINE), und die Mail wird mit
//  `BODY.PEEK[]` geholt – beides verändert nichts am Server, auch nicht
//  den Gelesen-Status.
//
//  Grenzen: Ohne Netz gibt es keine Quelle. Mails über der Schwelle für das
//  automatische Laden von Anhängen (5 MB) werden nicht geholt: SwiftMail
//  bricht das Holen der ganzen Mail nach festen 10 Sekunden ab.
//
//  Abgrenzung: Aufbereitung des Texts → RawMessageFormatter; Anzeige →
//  RawSourceView; Verbindung und Zugangsdaten → MailSession.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailSession, AccountStore,
//  MailFetchService (Schwelle), RawMessageFormatter, Log.
//

import Foundation
import SwiftMail
import os

/// Abruf der Originalquelle einer Mail.
enum RawMessageService {

    /// Ob die Quelle geholt werden kann.
    enum Availability: Equatable {
        /// Holen möglich.
        case available
        /// Mail größer als die Schwelle.
        case tooLarge
        /// Keine Netzverbindung.
        case offline
    }

    /// Prüft, ob die Quelle einer Mail geholt werden kann.
    ///
    /// Verarbeitung: Ohne Netz gilt „offline“ vor allem anderen; sonst
    /// entscheidet die Größe der Mail.
    ///
    /// - Parameters:
    ///   - sizeBytes: Gesamtgröße der Mail (RFC822.SIZE).
    ///   - isOnline: `true`, wenn eine Netzverbindung besteht.
    ///   - limit: Größte Mail in Bytes, die geholt wird.
    /// - Returns: Ergebnis der Prüfung.
    static func availability(
        sizeBytes: Int,
        isOnline: Bool,
        limit: Int = MailFetchService.autoDownloadThreshold
    ) -> Availability {
        if !isOnline { return .offline }
        return sizeBytes > limit ? .tooLarge : .available
    }

    /// Holt die Originalquelle einer Mail und bereitet sie auf.
    ///
    /// Verarbeitung: Meldet sich am Postfach der Mail an, öffnet ihren
    /// Ordner nur zum Lesen und holt die ganze Mail über ihre UID. Das
    /// Aufbereiten läuft neben der Oberfläche, weil große Mails dafür
    /// spürbar Zeit brauchen.
    ///
    /// - Parameters:
    ///   - message: Mail (liefert Postfach, Ordner und UID).
    ///   - accountStore: Quelle für Postfach und Passwort.
    /// - Returns: Aufbereiteter Text der Quelle.
    /// - Throws: `MailCredentialError` sowie Verbindungs- und IMAP-Fehler.
    static func fetchSource(
        of message: CachedMessage,
        accountStore: AccountStore
    ) async throws -> String {
        let credentials = try accountStore.credentials(for: message.accountID)
        let folder = message.folder
        let uid = SwiftMail.UID(message.uid)
        let data = try await MailSession.withIMAP(credentials) { server -> Data in
            _ = try await server.examineMailbox(folder)
            return try await server.fetchRawMessage(identifier: uid)
        }
        Log.view.info("📄 Originalquelle geholt: \(data.count / 1024) KB, Ordner \(folder, privacy: .public)")
        return await Task.detached(priority: .userInitiated) {
            RawMessageFormatter.format(data)
        }.value
    }
}
