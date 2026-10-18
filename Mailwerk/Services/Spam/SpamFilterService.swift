//
//  SpamFilterService.swift
//  Mailwerk
//
//  Zweck: Führt den Spamfilter eines Postfachs aus und setzt die
//  Spam-Aktionen an einzelnen Mails um.
//
//  Filterlauf: ungeprüfte Mails des Standardfensters im Posteingang suchen,
//  Absender und Spam-Header lesen, entscheiden, Keywords setzen und
//  erkannten Spam in den Spam-Ordner desselben Postfachs verschieben.
//  Die Reihenfolge ist Absicht: erst die Keywords, dann das Verschieben.
//  So trägt die Nachricht ihre Kennzeichnung mit in den Zielordner, auch
//  wenn die Verbindung mittendrin abbricht.
//
//  Server ohne eigene Schlüsselwörter (z. B. Outlook, erkannt an
//  `PERMANENTFLAGS`, siehe KeywordSupport): Dort gibt es kein
//  `$MailwerkChecked`. Als „schon geprüft“ gilt dann eine Mail, die
//  bereits im lokalen Cache des Posteingangs liegt – der Filter läuft vor
//  jedem Abruf des Posteingangs, neue Mails sind also genau die noch nicht
//  gecachten. Gesetzt werden die Schlüsselwörter dort nicht; Blockieren,
//  Vertrauen und Verschieben laufen sonst gleich. Einschränkung: Mails,
//  die bei ausgeschaltetem Filter abgerufen wurden, prüft dieses Gerät
//  später nicht nach.
//
//  Spam-Ordner ohne Filter: `locateSpamFolder` ermittelt und merkt den
//  Ordner auch bei ausgeschaltetem Filter – für die Sammelansicht „Spam“.
//
//  Einzelaktionen: Absender oder Domain blockieren (Blacklist, Mail in den
//  Spam-Ordner) bzw. vertrauen (Whitelist, Mail zurück in den Posteingang).
//
//  Anzeige: Für die Mailliste liefert der Dienst die aktuellen Listen
//  (Entscheidung über Absenderbilder). Für die Mailansicht beantwortet er,
//  ob der Absender einer Mail vertrauenswürdig genug ist, um externe
//  Inhalte sofort zu laden. Die Regeln stehen im `SpamClassifier`; hier
//  werden nur die aktuellen Listen dazugegeben.
//
//  Abgrenzung: Die Entscheidung steckt in `SpamFilterPlanner` und ist dort
//  getestet – hier geht es nur um das Ausführen. Welcher Ordner der
//  Spam-Ordner ist, bestimmt `SpamFolderResolver`.
//
//  Abhängigkeiten: SwiftMail (IMAP), MailSession (Verbindung und
//  Zugangsdaten), AccountStore, FilterListRepository, SpamFilterPlanner,
//  SpamFolderResolver, SpamHeaderParser, SpamClassifier, FilterAddress,
//  MailActionService (Ordnerliste, Ordner anlegen), MessageStore (Cache
//  nachziehen, schon gecachte Mails), SyncWindow (Zeitraum), MailFolder
//  (Posteingang), KeywordSupport, Log.
//

import Foundation
import SwiftMail
import os

/// Spamfilter und Spam-Aktionen.
@MainActor
final class SpamFilterService {

    // MARK: - Ergebnistypen

    /// Ergebnis eines Filterlaufs. Die Zahlen des Laufs stehen nur im
    /// Protokoll; die Oberfläche zeigt das Ergebnis über die neu geladene
    /// Liste.
    enum Outcome: Equatable {
        /// Lauf abgeschlossen.
        case completed
        /// Das Postfach hat keinen Spam-Ordner. Der Vorschlag muss dem
        /// Nutzer vorgelegt werden – angelegt wird nur nach Bestätigung.
        case needsSpamFolder(proposal: String)
    }

    /// Fehler der Spam-Aktionen.
    enum FilterError: LocalizedError {
        /// Der Absender der Mail lässt sich nicht als Adresse auswerten.
        case unusableSender
        /// Das Postfach hat keinen Spam-Ordner (mit Namensvorschlag).
        case noSpamFolder(proposal: String)

        /// Liefert die deutsche Meldung für den Nutzer.
        ///
        /// - Returns: Meldungstext für die Anzeige.
        var errorDescription: String? {
            switch self {
            case .unusableSender:
                return "Der Absender dieser Mail lässt sich nicht auswerten"
            case .noSpamFolder(let proposal):
                return "Dieses Postfach hat keinen Spam-Ordner. Vorgeschlagen wird „\(proposal)“."
            }
        }
    }

    // MARK: - Abhängigkeiten

    /// Quelle für Postfächer, Zugangsdaten und den gemerkten Spam-Ordner.
    private let accountStore: AccountStore
    /// Black- und Whitelist.
    private let filterLists: any FilterListRepository

    /// Legt den Dienst an.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Zugangsdaten.
    ///   - filterLists: Black- und Whitelist.
    init(accountStore: AccountStore, filterLists: any FilterListRepository) {
        self.accountStore = accountStore
        self.filterLists = filterLists
    }

    // MARK: - Filterlauf

    /// Prüft die ungeprüften Mails im Posteingang eines Postfachs.
    ///
    /// Verarbeitung:
    /// 1. Spam-Ordner bestimmen; fehlt er, endet der Lauf mit einem Vorschlag.
    /// 2. Ungeprüfte Mails des Standardfensters (`SyncWindow`) suchen
    ///    (ohne `$MailwerkChecked`).
    /// 3. Absender und Spam-Header holen – ohne die Mails als gelesen zu markieren.
    /// 4. Mit `SpamFilterPlanner` entscheiden.
    /// 5. Keywords setzen, dann Spam verschieben und den Cache nachziehen.
    ///
    /// - Parameters:
    ///   - account: Postfach.
    ///   - scoreLimit: Ab diesem Score rettet auch ein Whitelist-Eintrag eine
    ///     Mail nicht mehr.
    /// - Returns: Abgeschlossen oder der Vorschlag für einen Spam-Ordner.
    /// - Throws: `MailCredentialError`, Fehler der Filterlisten oder IMAP-Fehler.
    @discardableResult
    func run(for account: MailAccount, scoreLimit: Double) async throws -> Outcome {
        let credentials = try accountStore.credentials(for: account)
        let lists = try await filterLists.lists()

        return try await MailSession.withIMAP(credentials) { server -> Outcome in
            // 1. Spam-Ordner des Postfachs bestimmen
            let spamFolder: String
            switch try await resolveSpamFolder(for: account, on: server) {
            case .found(let folder):
                spamFolder = folder
            case .missing(let proposal):
                Log.spam.info("🚧 [\(account.displayName, privacy: .private)] Kein Spam-Ordner gefunden, Vorschlag: \(proposal, privacy: .public)")
                return .needsSpamFolder(proposal: proposal)
            }
            accountStore.setSpamFolder(spamFolder, for: account.id)

            // 2. Ungeprüfte Mails des Standardfensters suchen – mit
            //    `$MailwerkChecked`, sofern der Server eigene Schlüsselwörter
            //    speichert, sonst alle noch nicht gecachten.
            let inbox = try await server.selectMailbox(MailFolder.inboxPath)
            let usesKeywords = Self.storesKeywords(inbox)
            if !usesKeywords {
                Log.spam.info("🛡️ [\(account.displayName, privacy: .private)] Server speichert keine eigenen Schlüsselwörter (PERMANENTFLAGS: \(Self.flagNames(inbox.permanentFlags).joined(separator: " "), privacy: .public)) – geprüft wird, was noch nicht im Cache liegt")
            }
            let sinceDate = SyncWindow.standardStart()
            let criteria: [SwiftMail.SearchCriteria] = usesKeywords
                ? [.unkeyword(SpamKeyword.checked), .since(sinceDate)]
                : [.since(sinceDate)]
            // Ohne Sortierung: Die Reihenfolge spielt keine Rolle, der Plan
            // sortiert ohnehin. Das spart die SORT-Erweiterung des Servers.
            let searchResult: ExtendedSearchResult<SwiftMail.UID> = try await server.extendedSearch(
                criteria: criteria,
                calendar: SyncWindow.calendar
            )
            // `all` liefert ESEARCH, `ordered` eine einfache SEARCH-Antwort.
            let matches = searchResult.all ?? UIDSet(searchResult.ordered ?? [])
            var uids = matches.toArray()
            if !usesKeywords {
                let known = MessageStore.shared.cachedUIDs(accountID: account.id, folder: MailFolder.inboxPath)
                uids = uids.filter { !known.contains($0.value) }
            }
            Log.spam.info("🛡️ [\(account.displayName, privacy: .private)] \(uids.count) ungeprüfte Mails seit \(sinceDate, privacy: .public)")

            guard !uids.isEmpty else { return .completed }

            // 3. Absender und Spam-Header holen – PEEK, die Mails bleiben ungelesen
            let infos = try await server.fetchMessageInfosBulk(
                using: usesKeywords ? matches : UIDSet(uids),
                options: .slim,
                headerFields: SpamHeaderParser.fieldNames
            )
            let candidates = infos.compactMap { candidate(from: $0) }

            // 4. Entscheiden
            let plan = SpamFilterPlanner.plan(
                for: candidates, lists: lists, scoreLimit: scoreLimit
            )

            // 5. Ausführen – Keywords zuerst, dann verschieben
            try await apply(
                plan, on: server, account: account, spamFolder: spamFolder, storesKeywords: usesKeywords
            )

            Log.spam.info("🛡️ [\(account.displayName, privacy: .private)] Fertig: \(plan.checked.count) geprüft, \(plan.moveToSpam.count) nach \(spamFolder, privacy: .public), \(plan.keep.count) behalten")
            return .completed
        }
    }

    /// Legt den Spam-Ordner an, nachdem der Nutzer den Vorschlag bestätigt
    /// hat, und merkt ihn beim Postfach.
    ///
    /// - Parameters:
    ///   - proposal: Vorgeschlagener Ordnername.
    ///   - account: Postfach.
    /// - Returns: Tatsächlicher Server-Pfad des neuen Ordners.
    /// - Throws: `MailCredentialError` oder `MailActionService.ActionError`.
    @discardableResult
    func createSpamFolder(_ proposal: String, for account: MailAccount) async throws -> String {
        let created = try await MailActionService.createFolder(
            proposal, accountID: account.id, accountStore: accountStore
        )
        accountStore.setSpamFolder(created, for: account.id)
        return created
    }

    /// Ermittelt den Spam-Ordner eines Postfachs ohne Filterlauf und merkt
    /// ihn beim Postfach.
    ///
    /// Verarbeitung: Für die Sammelansicht „Spam“ und den Abruf der
    /// Spam-Ordner muss der Ordner auch bekannt sein, wenn der Spamfilter
    /// ausgeschaltet ist. Gesucht wird wie beim Filterlauf
    /// (SpamFolderResolver: gemerkter Ordner, `\Junk`, gebräuchliche
    /// Namen). Fehlt ein Spam-Ordner, wird nichts angelegt und nicht
    /// nachgefragt – das bleibt dem Spamfilter vorbehalten.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Pfad des Spam-Ordners oder `nil`, wenn es keinen gibt.
    /// - Throws: `MailCredentialError`, `OAuthError` oder IMAP-Fehler.
    @discardableResult
    func locateSpamFolder(for account: MailAccount) async throws -> String? {
        let credentials = try accountStore.credentials(for: account)
        let resolution = try await MailSession.withIMAP(credentials) { server in
            try await resolveSpamFolder(for: account, on: server)
        }
        guard case .found(let folder) = resolution else {
            Log.spam.info("🚧 [\(account.displayName, privacy: .private)] Kein Spam-Ordner gefunden (Filter aus, nichts angelegt)")
            return nil
        }
        accountStore.setSpamFolder(folder, for: account.id)
        Log.spam.info("📁 [\(account.displayName, privacy: .private)] Spam-Ordner \(folder, privacy: .public) ermittelt (Filter aus)")
        return folder
    }

    // MARK: - Aktionen an einer einzelnen Mail

    /// Trägt Absender oder Domain auf die Blacklist ein und verschiebt die
    /// Mail in den Spam-Ordner, falls sie noch nicht dort liegt.
    ///
    /// Verarbeitung: Die Mail erhält `$MailwerkChecked` und
    /// `$MailwerkBlacklisted`, damit ein späterer Filterlauf sie nicht
    /// erneut prüft – sofern der Server eigene Schlüsselwörter speichert.
    /// Ohne Spam-Ordner wird nichts verschoben; angelegt wird er nur nach
    /// Bestätigung.
    ///
    /// - Parameters:
    ///   - message: Betroffene Mail.
    ///   - kind: Adresse oder Domain eintragen.
    ///   - value: Einzutragender Wert (z. B. die Hauptdomain); `nil` =
    ///     Adresse bzw. Domain des Absenders. Muss zum Absender passen.
    /// - Returns: `true`, wenn die Mail verschoben wurde.
    /// - Throws: `MailCredentialError`, `FilterError`, Fehler der Filterlisten
    ///   oder IMAP-Fehler.
    @discardableResult
    func block(_ message: CachedMessage, kind: FilterEntryKind, value: String? = nil) async throws -> Bool {
        let (credentials, value) = try context(for: message, kind: kind, requested: value)
        let account = credentials.account
        try await filterLists.add(value, kind: kind, to: .black)

        return try await MailSession.withIMAP(credentials) { server -> Bool in
            let spamFolder = try await requireSpamFolder(for: account, on: server)

            let selection = try await server.selectMailbox(message.folder)
            if Self.storesKeywords(selection) {
                try await server.store(
                    flags: [
                        SwiftMail.Flag.custom(SpamKeyword.checked),
                        SwiftMail.Flag.custom(SpamKeyword.blacklisted)
                    ],
                    on: uidSet([message.uid]),
                    operation: .add
                )
            }

            guard message.folder != spamFolder else { return false }
            return try await move(message, to: spamFolder, on: server, account: account)
        }
    }

    /// Trägt Absender oder Domain auf die Whitelist ein und holt die Mail
    /// zurück in den Posteingang, falls sie im Spam-Ordner liegt.
    ///
    /// Verarbeitung: `$MailwerkBlacklisted` wird entfernt, `$MailwerkChecked`
    /// bleibt bzw. wird gesetzt – die Mail ist geprüft, und ohne das Keyword
    /// liefe sie nach dem Verschieben erneut durch den Filter. Speichert der
    /// Server keine eigenen Schlüsselwörter, entfällt beides; die Mail liegt
    /// nach dem Verschieben im Cache und gilt damit als geprüft.
    ///
    /// - Parameters:
    ///   - message: Betroffene Mail.
    ///   - kind: Adresse oder Domain eintragen.
    ///   - value: Einzutragender Wert (z. B. die Hauptdomain); `nil` =
    ///     Adresse bzw. Domain des Absenders. Muss zum Absender passen.
    /// - Returns: `true`, wenn die Mail verschoben wurde.
    /// - Throws: `MailCredentialError`, `FilterError`, Fehler der Filterlisten
    ///   oder IMAP-Fehler.
    @discardableResult
    func trust(_ message: CachedMessage, kind: FilterEntryKind, value: String? = nil) async throws -> Bool {
        let (credentials, value) = try context(for: message, kind: kind, requested: value)
        let account = credentials.account
        try await filterLists.add(value, kind: kind, to: .white)

        return try await MailSession.withIMAP(credentials) { server -> Bool in
            let resolution = try await resolveSpamFolder(for: account, on: server)
            let spamFolder: String? = {
                if case .found(let folder) = resolution { return folder }
                return nil
            }()

            let selection = try await server.selectMailbox(message.folder)
            if Self.storesKeywords(selection) {
                try await server.store(
                    flags: [SwiftMail.Flag.custom(SpamKeyword.blacklisted)],
                    on: uidSet([message.uid]),
                    operation: .remove
                )
                try await server.store(
                    flags: [SwiftMail.Flag.custom(SpamKeyword.checked)],
                    on: uidSet([message.uid]),
                    operation: .add
                )
            }

            guard message.folder == spamFolder else { return false }
            return try await move(
                message, to: MailFolder.inboxPath, on: server, account: account
            )
        }
    }

    // MARK: - Filterlisten für die Anzeige

    /// Liest die aktuellen Black- und Whitelists für Entscheidungen in der
    /// Oberfläche (z. B. Absenderbilder in der Mailliste).
    ///
    /// Verarbeitung: Ein Lesefehler wird protokolliert und als `nil`
    /// gemeldet; die Oberfläche entscheidet dann vorsichtig.
    ///
    /// - Returns: Aktuelle Listen oder `nil`, wenn sie nicht lesbar sind.
    func currentLists() async -> FilterLists? {
        do {
            return try await filterLists.lists()
        } catch {
            Log.spam.error("⚠️ Filterlisten für die Mailliste nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Externe Inhalte

    /// Prüft, ob externe Inhalte einer Mail sofort geladen werden dürfen.
    ///
    /// Verarbeitung: Liest die aktuellen Listen und wendet
    /// `SpamClassifier.trustsSender` auf Absender und gespeicherte
    /// Spam-Angabe der Mail an. Lassen sich die Listen nicht lesen, wird
    /// nicht vertraut – der Nutzer kann die Inhalte dann per Knopf laden.
    ///
    /// - Parameters:
    ///   - message: Angezeigte Mail.
    ///   - scoreLimit: Score-Obergrenze aus den Spam-Einstellungen.
    /// - Returns: `true`, wenn der Absender vertrauenswürdig ist.
    func trustsRemoteContent(of message: CachedMessage, scoreLimit: Double) async -> Bool {
        do {
            let lists = try await filterLists.lists()
            return SpamClassifier.trustsSender(
                sender: FilterAddress.sender(fromHeader: message.from),
                verdict: message.headers.spamVerdict,
                lists: lists,
                scoreLimit: scoreLimit
            )
        } catch {
            Log.spam.error("⚠️ Filterlisten für externe Inhalte nicht lesbar: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Intern

    /// Überführt eine Server-Antwort in einen Kandidaten für den Filter.
    ///
    /// Verarbeitung: `additionalHeaderFields` behält Reihenfolge und
    /// Wiederholungen. Das Wörterbuch `additionalFields` wäre hier falsch:
    /// Bei mehreren X-Spam-Status-Zeilen gewänne dort die letzte – ein
    /// Absender könnte die Einstufung des Servers so überschreiben.
    ///
    /// - Parameter info: Kopfdaten einer Mail.
    /// - Returns: Kandidat oder `nil` ohne UID (nicht adressierbar).
    private func candidate(from info: MessageInfo) -> SpamCandidate? {
        guard let uid = info.uid else { return nil }
        let lines = (info.additionalHeaderFields ?? []).map {
            SpamHeaderLine(name: $0.name, value: $0.value)
        }
        return SpamCandidate(
            uid: uid.value,
            sender: info.from.flatMap { FilterAddress.sender(fromHeader: $0) },
            verdict: SpamHeaderParser.parse(lines)
        )
    }

    /// Setzt die Entscheidung des Filters auf dem Server um.
    ///
    /// Verarbeitung: Zuerst `$MailwerkBlacklisted` und `$MailwerkChecked`
    /// (nur wenn der Server eigene Schlüsselwörter speichert), danach das
    /// Verschieben in den Spam-Ordner samt Cache.
    ///
    /// - Parameters:
    ///   - plan: Entscheidung des Filters.
    ///   - server: Angemeldete Verbindung mit ausgewähltem Posteingang.
    ///   - account: Postfach.
    ///   - spamFolder: Spam-Ordner des Postfachs.
    ///   - storesKeywords: `true`, wenn der Server eigene Schlüsselwörter
    ///     speichert.
    /// - Throws: IMAP-Fehler.
    private func apply(
        _ plan: SpamFilterPlan,
        on server: SwiftMail.IMAPServer,
        account: MailAccount,
        spamFolder: String,
        storesKeywords: Bool
    ) async throws {
        guard !plan.isEmpty else { return }

        if storesKeywords {
            if !plan.blacklisted.isEmpty {
                try await server.store(
                    flags: [SwiftMail.Flag.custom(SpamKeyword.blacklisted)],
                    on: uidSet(plan.blacklisted),
                    operation: .add
                )
            }

            try await server.store(
                flags: [SwiftMail.Flag.custom(SpamKeyword.checked)],
                on: uidSet(plan.checked),
                operation: .add
            )
        }

        guard !plan.moveToSpam.isEmpty else { return }

        let copyUID = try await server.move(
            messages: uidSet(plan.moveToSpam), to: spamFolder
        )
        updateCache(
            movedUIDs: plan.moveToSpam,
            copyUID: copyUID,
            account: account,
            spamFolder: spamFolder
        )
    }

    /// Prüft, ob der ausgewählte Ordner die Schlüsselwörter des Filters
    /// dauerhaft speichert.
    ///
    /// - Parameter selection: Antwort auf die Auswahl des Ordners.
    /// - Returns: `true`, wenn `$MailwerkChecked` gespeichert werden kann.
    private static func storesKeywords(_ selection: SwiftMail.Mailbox.Selection) -> Bool {
        KeywordSupport.allows(SpamKeyword.checked, permanentFlags: flagNames(selection.permanentFlags))
    }

    /// Namen der Kennzeichen für Prüfung und Protokoll.
    ///
    /// - Parameter flags: Kennzeichen von SwiftMail.
    /// - Returns: Eigene Kennzeichen mit Namen, die übrigen mit ihrem
    ///   IMAP-Namen (z. B. `\Seen`).
    private static func flagNames(_ flags: [SwiftMail.Flag]) -> [String] {
        flags.map { flag in
            switch flag {
            case .seen: return "\\Seen"
            case .answered: return "\\Answered"
            case .flagged: return "\\Flagged"
            case .deleted: return "\\Deleted"
            case .draft: return "\\Draft"
            case .custom(let name): return name
            }
        }
    }

    /// Zieht die verschobenen Mails im lokalen Cache nach.
    ///
    /// Verarbeitung: Meldet der Server die Ziel-UIDs (UIDPLUS), wird die
    /// Mail umgezogen. Sonst bleibt nur das Entfernen – sonst zeigte der
    /// Cache eine Mail, die dort nicht mehr liegt.
    ///
    /// - Parameters:
    ///   - movedUIDs: UIDs im Posteingang.
    ///   - copyUID: Zuordnung alte → neue UID, sofern gemeldet.
    ///   - account: Postfach.
    ///   - spamFolder: Spam-Ordner.
    private func updateCache(
        movedUIDs: [UInt32],
        copyUID: CopyUID?,
        account: MailAccount,
        spamFolder: String
    ) {
        let destinations = Dictionary(
            (copyUID?.mapping ?? []).map { ($0.source.value, $0.destination.value) },
            uniquingKeysWith: { first, _ in first }
        )

        for uid in movedUIDs {
            let cachedID = CachedMessage.makeID(
                accountID: account.id, folder: MailFolder.inboxPath, uid: uid
            )
            if let newUID = destinations[uid] {
                MessageStore.shared.relocateMessage(
                    id: cachedID, toFolder: spamFolder, newUID: newUID
                )
            } else {
                MessageStore.shared.deleteMessage(id: cachedID)
            }
        }
    }

    /// Wandelt UIDs in eine IMAP-UID-Menge.
    ///
    /// - Parameter uids: UIDs.
    /// - Returns: UID-Menge für IMAP-Befehle.
    private func uidSet(_ uids: [UInt32]) -> UIDSet {
        UIDSet(uids.map { SwiftMail.UID($0) })
    }

    /// Zugangsdaten und normalisierter Listenwert zu einer Mail.
    ///
    /// Verarbeitung: Der Wert kommt aus `FilterDomain.entryValue` – ein
    /// gewünschter Wert, der nicht zum Absender passt, wird abgelehnt.
    ///
    /// - Parameters:
    ///   - message: Betroffene Mail.
    ///   - kind: Adresse oder Domain.
    ///   - requested: Gewünschter Wert; `nil` = Adresse bzw. Domain des Absenders.
    /// - Returns: Zugangsdaten des Postfachs und der einzutragende Wert.
    /// - Throws: `MailCredentialError` oder `FilterError.unusableSender`.
    private func context(
        for message: CachedMessage,
        kind: FilterEntryKind,
        requested: String?
    ) throws -> (credentials: MailCredentials, value: String) {
        let credentials = try accountStore.credentials(for: message.accountID)
        guard let sender = FilterAddress.sender(fromHeader: message.from),
              let value = FilterDomain.entryValue(for: sender, kind: kind, requested: requested)
        else {
            throw FilterError.unusableSender
        }
        return (credentials, value)
    }

    /// Verschiebt eine einzelne Mail und zieht den Cache nach.
    ///
    /// - Parameters:
    ///   - message: Betroffene Mail.
    ///   - folder: Zielordner.
    ///   - server: Angemeldete Verbindung mit ausgewähltem Ordner der Mail.
    ///   - account: Postfach (für die Konsole).
    /// - Returns: Immer `true` (verschoben).
    /// - Throws: IMAP-Fehler.
    private func move(
        _ message: CachedMessage,
        to folder: String,
        on server: SwiftMail.IMAPServer,
        account: MailAccount
    ) async throws -> Bool {
        let copyUID = try await server.move(
            messages: uidSet([message.uid]), to: folder
        )
        if let newUID = copyUID?.mapping.first?.destination.value {
            MessageStore.shared.relocateMessage(
                id: message.id, toFolder: folder, newUID: newUID
            )
        } else {
            MessageStore.shared.deleteMessage(id: message.id)
        }
        Log.spam.info("🛡️ [\(account.displayName, privacy: .private)] Mail UID \(message.uid) nach \(folder, privacy: .public) verschoben")
        return true
    }

    /// Bestimmt den Spam-Ordner eines Postfachs anhand der Ordnerliste.
    ///
    /// - Parameters:
    ///   - account: Postfach (mit ggf. gemerktem Spam-Ordner).
    ///   - server: Angemeldete Verbindung.
    /// - Returns: Gefundener Ordner oder Vorschlag.
    /// - Throws: IMAP-Fehler.
    private func resolveSpamFolder(
        for account: MailAccount,
        on server: SwiftMail.IMAPServer
    ) async throws -> SpamFolderResolver.Resolution {
        let folders = try await MailActionService.mailboxes(on: server)
        return SpamFolderResolver.resolve(
            folders: folders,
            delimiter: folders.compactMap(\.hierarchyDelimiter).first,
            configured: account.spamFolder
        )
    }

    /// Wie `resolveSpamFolder`, wirft aber, wenn es keinen Ordner gibt –
    /// angelegt wird nur nach ausdrücklicher Bestätigung.
    ///
    /// - Parameters:
    ///   - account: Postfach.
    ///   - server: Angemeldete Verbindung.
    /// - Returns: Pfad des Spam-Ordners (wird beim Postfach gemerkt).
    /// - Throws: `FilterError.noSpamFolder` oder IMAP-Fehler.
    private func requireSpamFolder(
        for account: MailAccount,
        on server: SwiftMail.IMAPServer
    ) async throws -> String {
        switch try await resolveSpamFolder(for: account, on: server) {
        case .found(let folder):
            accountStore.setSpamFolder(folder, for: account.id)
            return folder
        case .missing(let proposal):
            throw FilterError.noSpamFolder(proposal: proposal)
        }
    }
}
