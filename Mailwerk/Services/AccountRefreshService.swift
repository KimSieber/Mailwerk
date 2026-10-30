//
//  AccountRefreshService.swift
//  Mailwerk
//
//  Zweck: Ruft ein Postfach über *eine* IMAP-Verbindung ab – Spamfilter
//  (bzw. Suche nach dem Spam-Ordner), Posteingang und Spam-Ordner
//  nacheinander auf derselben Anmeldung (Prüfbericht P-13).
//
//  Bisher öffnete der Spamfilter eine eigene Verbindung und der Abruf
//  danach eine zweite: je Postfach zwei TLS-Aufbauten und zwei
//  Anmeldungen (bei OAuth zusätzlich die Token-Prüfung). Manche Anbieter
//  bremsen dichte Anmeldefolgen aus; mit dem parallelen Abruf (P-21)
//  würde sich das verschärfen.
//
//  Fehlerregeln (unverändert gegenüber dem bisherigen Ablauf):
//  - Ein Fehler des Spamfilters verhindert den Abruf nicht. War es ein
//    Verbindungsfehler, ist die gemeinsame Verbindung meist unbrauchbar –
//    der Abruf läuft dann über eine neue Verbindung (`SpamStepFailure`).
//  - Scheitert die Anmeldung an der Verbindung (Gmail bremst dichte
//    Anmeldefolgen, LOGIN läuft dann in die Zeitüberschreitung), folgt
//    nach kurzer Pause genau ein zweiter Versuch – sofern das Gerät online
//    ist (`shouldRetryLogin`). Früher fing das die zweite Verbindung des
//    Abrufs zufällig ab; mit nur einer Verbindung ist er ausdrücklich.
//  - Andere Anmeldefehler (z. B. OAuth abgelaufen): Filter und Abruf
//    entfallen; der Fehler kommt als Abruffehler zurück.
//  - Vermerken des Sync-Zustands, Abbruch je Ordner und Abmelden regelt
//    `MailFetchService.refreshAndCache(_:prepare:)` wie bisher.
//
//  Abgrenzung: Die Auswertung (Rückfragen zum Spam-Ordner, Erreichbarkeit,
//  Meldungen, zweiter Versuch beim Spam-Ordner) bleibt im InboxViewModel.
//  Der Filterlauf selbst steht in `SpamFilterService.filterInbox(on:…)`,
//  der Ordnerabruf in `MailFetchService`.
//
//  Nebenläufigkeit: `nonisolated`; der Einstieg `refresh` ist
//  `@concurrent` und läuft abseits des Hauptthreads. Nur das Merken des
//  Spam-Ordners springt über `rememberSpamFolder` auf den Main-Actor.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailFetchService, SpamFilterService,
//  MailFolder, FilterLists, Log.
//

import Foundation
import SwiftMail
import os

/// Abruf eines Postfachs über eine gemeinsame Verbindung.
nonisolated enum AccountRefreshService {

    // MARK: - Eingaben und Ergebnis

    /// Was vor dem Abruf auf der Verbindung mit dem Spam-Ordner geschieht.
    enum SpamStep: Sendable {
        /// Nichts – Filter aus und Spam-Ordner bekannt.
        case none
        /// Spamfilter laufen lassen (findet und merkt dabei den Spam-Ordner).
        case filter(lists: FilterLists, scoreLimit: Double)
        /// Filter aus, Spam-Ordner unbekannt: nur suchen und merken.
        case locateFolder
    }

    /// Ergebnis eines Postfach-Abrufs.
    struct RefreshResult: Sendable {
        /// Ergebnis des Filterlaufs; `nil`, wenn keiner lief oder er scheiterte.
        var spamOutcome: SpamFilterService.Outcome?
        /// Fehler des Spam-Schritts (Filter oder Ordnersuche); `nil` = ohne Fehler.
        var spamError: (any Error)?
        /// Mit abgerufener Spam-Ordner; `nil` = keiner bekannt.
        var spamFolder: String?
        /// Fehler des Abrufs (meist `MailFetchService.FolderRefreshError`);
        /// `nil` = Posteingang und Spam-Ordner vollständig abgerufen.
        var fetchError: (any Error)?
    }

    /// Wie es nach einem Fehler des Spam-Schritts weitergeht.
    enum SpamStepFailure: Equatable, Sendable {
        /// Verbindung ist noch brauchbar – Abruf auf ihr fortsetzen.
        case continueOnConnection
        /// Verbindung ist verloren – Abruf über eine neue Verbindung.
        case reconnect
    }

    /// Interner Marker: Der Spam-Schritt hat die Verbindung verloren.
    private struct SpamStepConnectionLost: Error {
        /// Eigentlicher Fehler des Spam-Schritts.
        let underlying: any Error
    }

    // MARK: - Abruf

    /// Pause vor dem zweiten Anmeldeversuch.
    static let loginRetryDelay: Duration = .seconds(2)

    /// Ruft ein Postfach über eine Verbindung ab: Spam-Schritt, dann
    /// Posteingang und Spam-Ordner.
    ///
    /// Verarbeitung:
    /// 1. Ein Durchgang (`attempt`): anmelden, Spam-Schritt, Ordner abrufen.
    /// 2. Scheiterte er an der Verbindung, noch bevor auf ihr gearbeitet
    ///    wurde (Verbindungsaufbau oder Anmeldung), und ist das Gerät
    ///    online: nach `loginRetryDelay` genau ein zweiter Durchgang.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Zugang.
    ///   - spamStep: Spam-Schritt vor dem Abruf.
    ///   - knownSpamFolder: Bereits gemerkter Spam-Ordner (`nil` = keiner).
    ///   - rememberSpamFolder: Merkt einen gefundenen Spam-Ordner beim Postfach.
    ///   - isOnline: Meldet, ob das Gerät Netz hat (vor dem zweiten Versuch).
    /// - Returns: Ergebnis mit Filterausgang, Spam-Ordner und Fehlern.
    @concurrent
    static func refresh(
        _ credentials: MailCredentials,
        spamStep: SpamStep,
        knownSpamFolder: String?,
        rememberSpamFolder: @escaping @MainActor @Sendable (String) -> Void,
        isOnline: @escaping @MainActor @Sendable () -> Bool
    ) async -> RefreshResult {
        let first = await attempt(
            credentials, spamStep: spamStep, knownSpamFolder: knownSpamFolder,
            rememberSpamFolder: rememberSpamFolder
        )
        guard shouldRetryLogin(after: first.result.fetchError, workStarted: first.workStarted) else {
            return first.result
        }
        let account = credentials.account
        Log.fetch.info("🔁 [\(account.displayName, privacy: .private)] Anmeldung gescheitert – zweiter Versuch in \(loginRetryDelay.components.seconds) s")
        // Abgebrochen (z. B. App im Hintergrund, neuer Abruf): keinen
        // zweiten Anmeldeversuch mehr starten.
        do {
            try await Task.sleep(for: loginRetryDelay)
        } catch {
            return first.result
        }
        guard await isOnline() else { return first.result }
        let second = await attempt(
            credentials, spamStep: spamStep, knownSpamFolder: knownSpamFolder,
            rememberSpamFolder: rememberSpamFolder
        )
        if second.result.fetchError == nil {
            Log.fetch.info("🔁 [\(account.displayName, privacy: .private)] Zweiter Anmeldeversuch erfolgreich")
        }
        return second.result
    }

    /// Entscheidet, ob nach einem gescheiterten Durchgang ein zweiter folgt.
    ///
    /// Verarbeitung: Nur bei einem reinen Verbindungsfehler und nur, wenn
    /// auf der Verbindung noch nichts geschehen ist (Verbindungsaufbau oder
    /// Anmeldung gescheitert). Ist schon gearbeitet worden, gelten die
    /// übrigen Regeln (Spam-Ordner einzeln wiederholen, nächster Abruf).
    ///
    /// - Parameters:
    ///   - error: Abruffehler des Durchgangs (`nil` = erfolgreich).
    ///   - workStarted: Ob der Spam-Schritt bzw. Abruf schon begonnen hatte.
    /// - Returns: `true`, wenn ein zweiter Durchgang folgen soll.
    static func shouldRetryLogin(after error: (any Error)?, workStarted: Bool) -> Bool {
        guard let error, !workStarted else { return false }
        let underlying = (error as? MailFetchService.FolderRefreshError)?.underlying ?? error
        return MailFetchService.isConnectionError(underlying)
    }

    /// Ein Durchgang: anmelden, Spam-Schritt, Posteingang und Spam-Ordner.
    ///
    /// Verarbeitung:
    /// 1. Anmelden (in `MailFetchService.refreshAndCache(_:prepare:)`).
    /// 2. Spam-Schritt auf der Verbindung (`runSpamStep`). Ein gefundener
    ///    Spam-Ordner wird sofort über `rememberSpamFolder` gemerkt.
    /// 3. Posteingang und – falls bekannt – Spam-Ordner abrufen.
    /// 4. Hat der Spam-Schritt die Verbindung verloren, Schritt 3 über eine
    ///    neue Verbindung wiederholen.
    ///
    /// - Parameters:
    ///   - credentials: Postfach und Zugang.
    ///   - spamStep: Spam-Schritt vor dem Abruf.
    ///   - knownSpamFolder: Bereits gemerkter Spam-Ordner (`nil` = keiner).
    ///   - rememberSpamFolder: Merkt einen gefundenen Spam-Ordner beim Postfach.
    /// - Returns: Ergebnis und ob auf der Verbindung schon gearbeitet wurde
    ///   (`false` = Verbindungsaufbau oder Anmeldung gescheitert).
    private static func attempt(
        _ credentials: MailCredentials,
        spamStep: SpamStep,
        knownSpamFolder: String?,
        rememberSpamFolder: @escaping @MainActor @Sendable (String) -> Void
    ) async -> (result: RefreshResult, workStarted: Bool) {
        let account = credentials.account
        var result = RefreshResult(spamFolder: knownSpamFolder)
        var workStarted = false

        do {
            try await MailFetchService.refreshAndCache(credentials) { server in
                workStarted = true
                do {
                    let step = try await runSpamStep(
                        spamStep, on: server, account: account, rememberSpamFolder: rememberSpamFolder
                    )
                    result.spamOutcome = step.outcome
                    if let found = step.spamFolder { result.spamFolder = found }
                } catch {
                    result.spamError = error
                    if failureHandling(forSpamStepError: error) == .reconnect {
                        throw SpamStepConnectionLost(underlying: error)
                    }
                    Log.spam.error("⚠️ [\(account.displayName, privacy: .private)] Spam-Schritt fehlgeschlagen, Abruf auf derselben Verbindung: \(error.localizedDescription, privacy: .public)")
                }
                return folders(spamFolder: result.spamFolder)
            }
        } catch let failure as MailFetchService.FolderRefreshError
                    where failure.underlying is SpamStepConnectionLost {
            // Spam-Schritt hat die Verbindung verloren: Abruf neu verbinden.
            Log.spam.error("⚠️ [\(account.displayName, privacy: .private)] Verbindung im Spam-Schritt verloren – Abruf über neue Verbindung")
            do {
                try await MailFetchService.refreshAndCache(
                    credentials, folders: folders(spamFolder: result.spamFolder)
                )
            } catch {
                result.fetchError = error
            }
        } catch {
            result.fetchError = error
        }
        return (result, workStarted)
    }

    /// Entscheidet, wie es nach einem Fehler des Spam-Schritts weitergeht.
    ///
    /// Verarbeitung: Ein reiner Verbindungsfehler (`MailFetchService.isConnectionError`)
    /// macht die gemeinsame Verbindung unbrauchbar → neu verbinden. Jeder
    /// andere Fehler (z. B. ein abgelehntes MOVE) lässt sie intakt → auf
    /// ihr weiter abrufen.
    ///
    /// - Parameter error: Fehler des Spam-Schritts.
    /// - Returns: Weiteres Vorgehen.
    static func failureHandling(forSpamStepError error: any Error) -> SpamStepFailure {
        MailFetchService.isConnectionError(error) ? .reconnect : .continueOnConnection
    }

    /// Abzurufende Ordner: Posteingang, dann – falls bekannt – Spam-Ordner.
    ///
    /// - Parameter spamFolder: Spam-Ordner des Postfachs (`nil`/leer = keiner).
    /// - Returns: IMAP-Pfade in Abrufreihenfolge.
    static func folders(spamFolder: String?) -> [String] {
        guard let spamFolder, !spamFolder.isEmpty, spamFolder != MailFolder.inboxPath else {
            return [MailFolder.inboxPath]
        }
        return [MailFolder.inboxPath, spamFolder]
    }

    // MARK: - Spam-Schritt

    /// Führt den Spam-Schritt auf einer angemeldeten Verbindung aus.
    ///
    /// Verarbeitung: `.filter` → Filterlauf (`SpamFilterService.filterInbox`);
    /// `.locateFolder` → nur den Spam-Ordner suchen und merken, nichts
    /// anlegen und nicht nachfragen; `.none` → nichts.
    ///
    /// - Parameters:
    ///   - step: Auszuführender Schritt.
    ///   - server: Angemeldete Verbindung.
    ///   - account: Postfach.
    ///   - rememberSpamFolder: Merkt einen gefundenen Spam-Ordner.
    /// - Returns: Filterausgang (nur bei `.filter`) und gefundener Spam-Ordner.
    /// - Throws: IMAP- oder Verbindungsfehler.
    private static func runSpamStep(
        _ step: SpamStep,
        on server: SwiftMail.IMAPServer,
        account: MailAccount,
        rememberSpamFolder: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> (outcome: SpamFilterService.Outcome?, spamFolder: String?) {
        switch step {
        case .none:
            return (nil, nil)

        case .filter(let lists, let scoreLimit):
            var found: String?
            let outcome = try await SpamFilterService.filterInbox(
                on: server,
                account: account,
                lists: lists,
                scoreLimit: scoreLimit,
                rememberSpamFolder: { folder in
                    found = folder
                    await rememberSpamFolder(folder)
                }
            )
            return (outcome, found)

        case .locateFolder:
            guard case .found(let folder) = try await SpamFilterService.resolveSpamFolder(for: account, on: server) else {
                Log.spam.info("🚧 [\(account.displayName, privacy: .private)] Kein Spam-Ordner gefunden (Filter aus, nichts angelegt)")
                return (nil, nil)
            }
            await rememberSpamFolder(folder)
            Log.spam.info("📁 [\(account.displayName, privacy: .private)] Spam-Ordner \(folder, privacy: .public) ermittelt (Filter aus)")
            return (nil, folder)
        }
    }
}
