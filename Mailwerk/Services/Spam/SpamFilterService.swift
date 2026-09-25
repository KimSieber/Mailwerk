//
//  SpamFilterService.swift
//  Mailwerk
//
//  Führt den Filterlauf eines Postfachs aus: ungeprüfte Mails der letzten
//  30 Tage suchen, Spam-Header lesen, entscheiden, Keywords setzen und
//  erkannten Spam in den Spam-Ordner desselben Postfachs verschieben.
//
//  Reihenfolge ist Absicht: erst die Keywords, dann das Verschieben. So
//  trägt die Nachricht ihre Kennzeichnung mit in den Zielordner, auch wenn
//  die Verbindung mittendrin abbricht.
//
//  Die Entscheidung selbst steckt in `SpamFilterPlanner` und ist dort
//  getestet – hier geht es nur um das Ausführen.
//

import Foundation
import SwiftMail

@MainActor
final class SpamFilterService {

    // MARK: - Ergebnistypen

    struct RunSummary: Equatable {
        let folder: String
        let checked: Int
        let movedToSpam: Int
        let keptInInbox: Int
    }

    enum Outcome: Equatable {
        /// Lauf abgeschlossen.
        case completed(RunSummary)
        /// Das Postfach hat keinen Spam-Ordner. Der Vorschlag muss dem
        /// Nutzer vorgelegt werden – angelegt wird nur nach Bestätigung.
        case needsSpamFolder(proposal: String)
    }

    enum FilterError: LocalizedError {
        case noPassword
        case accountNotFound
        case unusableSender
        case noSpamFolder(proposal: String)

        var errorDescription: String? {
            switch self {
            case .noPassword:
                return "Kein Passwort im Keychain"
            case .accountNotFound:
                return "Postfach nicht gefunden"
            case .unusableSender:
                return "Der Absender dieser Mail lässt sich nicht auswerten"
            case .noSpamFolder(let proposal):
                return "Dieses Postfach hat keinen Spam-Ordner. Vorgeschlagen wird „\(proposal)“."
            }
        }
    }

    // MARK: - Abhängigkeiten

    private let accountStore: AccountStore
    private let filterLists: any FilterListRepository

    /// Ab diesem Score rettet auch ein Whitelist-Eintrag eine Mail nicht mehr.
    var scoreLimit: Double

    init(
        accountStore: AccountStore,
        filterLists: any FilterListRepository,
        scoreLimit: Double = SpamClassifier.defaultScoreLimit
    ) {
        self.accountStore = accountStore
        self.filterLists = filterLists
        self.scoreLimit = scoreLimit
    }

    // MARK: - Filterlauf

    /// Prüft die ungeprüften Mails der INBOX eines Postfachs.
    @discardableResult
    func run(for account: MailAccount) async throws -> Outcome {
        guard let password = try accountStore.password(for: account) else {
            throw FilterError.noPassword
        }
        let lists = try await filterLists.lists()

        let server = MailServerFactory.imapServer(for: account)
        do {
            try await server.connect()
            try await server.login(username: account.username, password: password)

            // 1. Spam-Ordner des Postfachs bestimmen
            let resolution = try await resolveSpamFolder(for: account, on: server)
            guard case .found(let spamFolder) = resolution else {
                try await server.logout()
                guard case .missing(let proposal) = resolution else {
                    return .needsSpamFolder(proposal: SpamFolderResolver.proposedName)
                }
                print("🚧 [\(account.displayName)] Kein Spam-Ordner gefunden, Vorschlag: \(proposal)")
                return .needsSpamFolder(proposal: proposal)
            }
            accountStore.setSpamFolder(spamFolder, for: account.id)

            // 2. Ungeprüfte Mails der letzten 30 Tage suchen
            _ = try await server.selectMailbox(MailFetchService.inboxFolder)
            let sinceDate = Calendar.current.date(
                byAdding: .day, value: -MailFetchService.syncDays, to: Date()
            )!
            // Ohne Sortierung: Die Reihenfolge spielt keine Rolle, der Plan
            // sortiert ohnehin. Das spart die SORT-Erweiterung des Servers.
            let searchResult: ExtendedSearchResult<SwiftMail.UID> = try await server.extendedSearch(
                criteria: [.unkeyword(SpamKeyword.checked), .since(sinceDate)]
            )
            // `all` liefert ESEARCH, `ordered` eine einfache SEARCH-Antwort.
            let matches = searchResult.all ?? UIDSet(searchResult.ordered ?? [])
            let uids = matches.toArray()
            print("🛡️ [\(account.displayName)] \(uids.count) ungeprüfte Mails seit \(sinceDate)")

            guard !uids.isEmpty else {
                try await server.logout()
                return .completed(
                    RunSummary(folder: spamFolder, checked: 0, movedToSpam: 0, keptInInbox: 0)
                )
            }

            // 3. Absender und Spam-Header holen – PEEK, die Mails bleiben ungelesen
            let infos = try await server.fetchMessageInfosBulk(
                using: matches,
                options: .slim,
                headerFields: SpamHeaderParser.fieldNames
            )
            let candidates = infos.compactMap(candidate(from:))

            // 4. Entscheiden
            let plan = SpamFilterPlanner.plan(
                for: candidates, lists: lists, scoreLimit: scoreLimit
            )

            // 5. Ausführen – Keywords zuerst, dann verschieben
            try await apply(plan, on: server, account: account, spamFolder: spamFolder)

            try await server.logout()

            let summary = RunSummary(
                folder: spamFolder,
                checked: plan.checked.count,
                movedToSpam: plan.moveToSpam.count,
                keptInInbox: plan.keep.count
            )
            print("🛡️ [\(account.displayName)] Fertig: \(summary.checked) geprüft, \(summary.movedToSpam) nach \(spamFolder), \(summary.keptInInbox) behalten")
            return .completed(summary)

        } catch {
            try? await server.disconnect()
            throw error
        }
    }

    /// Legt den Spam-Ordner an, nachdem der Nutzer den Vorschlag bestätigt hat,
    /// und merkt ihn beim Postfach.
    @discardableResult
    func createSpamFolder(_ proposal: String, for account: MailAccount) async throws -> String {
        let created = try await MailActionService.createFolder(
            proposal, accountID: account.id, accountStore: accountStore
        )
        accountStore.setSpamFolder(created, for: account.id)
        return created
    }

    // MARK: - Aktionen an einer einzelnen Mail

    /// Trägt Absender oder Domain auf die Blacklist ein und verschiebt die
    /// Mail in den Spam-Ordner, falls sie noch nicht dort liegt.
    /// - Returns: true, wenn die Mail verschoben wurde.
    @discardableResult
    func block(_ message: CachedMessage, kind: FilterEntryKind) async throws -> Bool {
        let (account, value) = try context(for: message, kind: kind)
        try await filterLists.add(value, kind: kind, to: .black)

        return try await withConnection(for: account) { server in
            let spamFolder = try await requireSpamFolder(for: account, on: server)

            _ = try await server.selectMailbox(message.folder)
            try await server.store(
                flags: [
                    SwiftMail.Flag.custom(SpamKeyword.checked),
                    SwiftMail.Flag.custom(SpamKeyword.blacklisted)
                ],
                on: uidSet([message.uid]),
                operation: .add
            )

            guard message.folder != spamFolder else { return false }
            return try await move(
                message, to: spamFolder, on: server, account: account
            )
        }
    }

    /// Trägt Absender oder Domain auf die Whitelist ein und holt die Mail
    /// zurück in die INBOX, falls sie im Spam-Ordner liegt.
    /// - Returns: true, wenn die Mail verschoben wurde.
    @discardableResult
    func trust(_ message: CachedMessage, kind: FilterEntryKind) async throws -> Bool {
        let (account, value) = try context(for: message, kind: kind)
        try await filterLists.add(value, kind: kind, to: .white)

        return try await withConnection(for: account) { server in
            let resolution = try await resolveSpamFolder(for: account, on: server)
            let spamFolder: String? = {
                if case .found(let folder) = resolution { return folder }
                return nil
            }()

            _ = try await server.selectMailbox(message.folder)

            // `$MailwerkChecked` bleibt: Die Mail ist geprüft, und ohne das
            // Keyword liefe sie nach dem Verschieben erneut durch den Filter.
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

            guard message.folder == spamFolder else { return false }
            return try await move(
                message, to: MailFetchService.inboxFolder, on: server, account: account
            )
        }
    }

    // MARK: - Intern

    /// Überführt eine Server-Antwort in einen Kandidaten.
    /// Ohne UID ist die Nachricht nicht adressierbar und wird übersprungen.
    private func candidate(from info: MessageInfo) -> SpamCandidate? {
        guard let uid = info.uid else { return nil }

        // `additionalHeaderFields` behält Reihenfolge und Wiederholungen.
        // Das Wörterbuch `additionalFields` wäre hier falsch: Bei mehreren
        // X-Spam-Status-Zeilen gewinnt dort die letzte – ein Absender könnte
        // die Einstufung des Servers so überschreiben.
        let lines = (info.additionalHeaderFields ?? []).map {
            SpamHeaderLine(name: $0.name, value: $0.value)
        }
        return SpamCandidate(
            uid: uid.value,
            sender: info.from.flatMap { FilterAddress.sender(fromHeader: $0) },
            verdict: SpamHeaderParser.parse(lines)
        )
    }

    private func apply(
        _ plan: SpamFilterPlan,
        on server: SwiftMail.IMAPServer,
        account: MailAccount,
        spamFolder: String
    ) async throws {
        guard !plan.isEmpty else { return }

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

    /// Zieht die verschobenen Mails im lokalen Cache nach.
    /// Meldet der Server keine Ziel-UIDs (kein UIDPLUS), bleibt nur das
    /// Entfernen – sonst zeigte der Cache eine Mail, die dort nicht mehr liegt.
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
                accountID: account.id, folder: MailFetchService.inboxFolder, uid: uid
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

    private func uidSet(_ uids: [UInt32]) -> UIDSet {
        UIDSet(uids.map { SwiftMail.UID($0) })
    }

    /// Postfach und normalisierter Listenwert zu einer Mail.
    private func context(
        for message: CachedMessage,
        kind: FilterEntryKind
    ) throws -> (account: MailAccount, value: String) {
        guard let account = accountStore.accounts.first(where: { $0.id == message.accountID }) else {
            throw FilterError.accountNotFound
        }
        guard let sender = FilterAddress.sender(fromHeader: message.from) else {
            throw FilterError.unusableSender
        }
        return (account, kind == .address ? sender.address : sender.domain)
    }

    /// Verschiebt eine einzelne Mail und zieht den Cache nach.
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
        print("🛡️ [\(account.displayName)] Mail UID \(message.uid) nach \(folder) verschoben")
        return true
    }

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

    /// Baut eine Verbindung auf, führt die Operation aus und meldet sich ab.
    private func withConnection<T>(
        for account: MailAccount,
        _ body: (SwiftMail.IMAPServer) async throws -> T
    ) async throws -> T {
        guard let password = try accountStore.password(for: account) else {
            throw FilterError.noPassword
        }
        let server = MailServerFactory.imapServer(for: account)
        do {
            try await server.connect()
            try await server.login(username: account.username, password: password)
            let result = try await body(server)
            try await server.logout()
            return result
        } catch {
            try? await server.disconnect()
            throw error
        }
    }
}
