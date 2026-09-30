//
//  InboxViewModel.swift
//  Mailwerk
//

import Foundation
import Observation

@Observable
final class InboxViewModel {
    private let accountStore: AccountStore
    private let spamSettings: SpamSettings
    /// Wird auch von der Detailansicht für Blockieren und Vertrauen genutzt.
    let spamFilter: SpamFilterService

    var messages: [CachedMessage] = []
    var isLoading = false
    var errorMessage: String?
    /// Stand der aktuellen Ansicht laut Datenbank (Tabelle folder_sync).
    /// Überlebt Neustarts und ist auch offline bekannt. `nil` nur, wenn
    /// kein Postfach eingerichtet ist.
    var syncState: SyncState?
    /// `true`, wenn der letzte Abrufversuch dieser Ansicht an der
    /// Verbindung scheiterte. Wird still im Titel angezeigt, nicht als Alert.
    var connectionFailed = false

    /// Läuft gerade „Ältere Nachrichten laden"?
    var isLoadingOlder = false
    /// Letzter Nachladeversuch scheiterte an der Verbindung – die Zeile
    /// zeigt das selbst an, bis zum nächsten Versuch oder Ansichtswechsel.
    var olderConnectionFailed = false
    /// Ordner, für die der Server nichts Älteres mehr hat. Nur für diese
    /// Sitzung – nach dem Neustart gilt ohnehin wieder das Standardfenster.
    private var exhaustedFolders: Set<String> = []

    private let network = NetworkMonitor.shared

    /// Aktive Ansicht. Ändert sich durch die Seitenleiste.
    var selection: MailboxSelection = .allInboxes {
        didSet {
            // Der Verbindungsstatus gilt für die bisherige Ansicht; die neue
            // ermittelt ihn bei ihrem eigenen Abruf.
            connectionFailed = false
            olderConnectionFailed = false
            loadFromCache()
        }
    }

    /// Nachricht, deren Kennzeichen gerade entfernt wurde – zeigt den
    /// „Rückgängig"-Hinweis in der Kennzeichen-Sicht.
    var undoUnflag: UndoUnflag?

    struct UndoUnflag: Identifiable {
        var id: String { messageID }
        let messageID: String
        let messageUID: UInt32
        let accountID: UUID
        let folder: String
    }

    /// Ein Postfach ohne Spam-Ordner samt Vorschlag. Angelegt wird nur nach
    /// Bestätigung durch den Nutzer.
    struct PendingSpamFolder: Identifiable {
        var id: UUID { account.id }
        let account: MailAccount
        let proposal: String
    }

    /// Offene Rückfragen aus dem letzten Abruf.
    var pendingSpamFolders: [PendingSpamFolder] = []

    /// Postfächer, für die in dieser Sitzung abgelehnt wurde. Verhindert,
    /// dass bei jedem Abruf erneut gefragt wird.
    private var declinedSpamFolders: Set<UUID> = []

    init(
        accountStore: AccountStore,
        filterLists: any FilterListRepository,
        spamSettings: SpamSettings
    ) {
        self.accountStore = accountStore
        self.spamSettings = spamSettings
        self.spamFilter = SpamFilterService(
            accountStore: accountStore,
            filterLists: filterLists,
            scoreLimit: spamSettings.scoreLimit
        )
        loadFromCache()
    }

    func loadFromCache() {
        let accountIDs = accountStore.accounts.map(\.id)
        syncState = currentSyncState()
        switch selection {
        case .allInboxes:
            messages = MessageStore.shared.allMessages(
                accountIDs: accountIDs, folder: MailFetchService.inboxFolder
            )
        case .flagged:
            messages = MessageStore.shared.flaggedInboxMessages(
                accountIDs: accountIDs
            )
        case .folder(let accountID, let path, _):
            messages = MessageStore.shared.folderMessages(
                accountID: accountID, folder: path
            )
        }
    }

    /// Stand der gewählten Ansicht. Sammelansichten sind so aktuell wie
    /// der älteste beteiligte Posteingang.
    private func currentSyncState() -> SyncState? {
        let accounts = accountStore.accounts
        guard !accounts.isEmpty else { return nil }
        switch selection {
        case .allInboxes, .flagged:
            return .oldest(accounts.map {
                MessageStore.shared.lastSync(accountID: $0.id, folder: MailFetchService.inboxFolder)
            })
        case .folder(let accountID, let path, _):
            return .oldest([MessageStore.shared.lastSync(accountID: accountID, folder: path)])
        }
    }

    // MARK: - Ältere Nachrichten

    /// Ordner, deren Fenster die aktuelle Ansicht bilden: bei einem Ordner
    /// dieser allein, bei „Alle Eingänge" die Posteingänge aller Postfächer.
    /// Die Kennzeichen-Sicht lädt nicht nach.
    private var olderTargets: [(account: MailAccount, folder: String)] {
        switch selection {
        case .allInboxes:
            return accountStore.accounts.map { ($0, MailFetchService.inboxFolder) }
        case .flagged:
            return []
        case .folder(let accountID, let path, _):
            guard let account = accountStore.accounts.first(where: { $0.id == accountID }) else { return [] }
            return [(account, path)]
        }
    }

    private func exhaustedKey(_ accountID: UUID, _ folder: String) -> String {
        "\(accountID.uuidString)|\(folder)"
    }

    /// Ordner der Ansicht, für die es noch Älteres geben kann.
    private var openOlderTargets: [(account: MailAccount, folder: String)] {
        olderTargets.filter { !exhaustedFolders.contains(exhaustedKey($0.account.id, $0.folder)) }
    }

    /// Zeile „Ältere Nachrichten laden" anzeigen? Nicht in der
    /// Kennzeichen-Sicht und nicht ohne Postfächer.
    var showsOlderRow: Bool { !olderTargets.isEmpty }

    /// `true`, wenn der Server für alle Ordner der Ansicht nichts Älteres hat.
    var olderExhausted: Bool { showsOlderRow && openOlderTargets.isEmpty }

    /// Bis zu welchem Tag ein Tipp mindestens lädt – für die Beschriftung.
    /// Bei mehreren Postfächern der späteste der nächsten Zeiträume.
    var nextOlderDate: Date? {
        let standard = SyncWindow.standardStart(now: Date(), days: MailFetchService.syncDays)
        return openOlderTargets
            .map { target -> Date in
                let start = MessageStore.shared.windowStart(accountID: target.account.id, folder: target.folder)
                    ?? standard
                return SyncWindow.nextBlock(before: start, days: MailFetchService.syncDays).since
            }
            .max()
    }

    /// Lädt für die aktuelle Ansicht den nächsten älteren Zeitraum nach.
    @MainActor
    func loadOlder() async {
        guard !isLoadingOlder else { return }
        guard network.isOnline else {
            connectionFailed = true
            olderConnectionFailed = true
            return
        }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        olderConnectionFailed = false

        var errors: [String] = []
        for target in openOlderTargets {
            let key = exhaustedKey(target.account.id, target.folder)
            do {
                let password = try readPassword(for: target.account)
                let result = try await MailFetchService.fetchOlder(
                    account: target.account, password: password, folder: target.folder
                )
                switch result {
                case .noOlder:
                    exhaustedFolders.insert(key)
                case .loaded(let count, _, let hasMore):
                    print("📬 [\(target.account.displayName)/\(target.folder)] \(count) ältere Nachrichten geladen")
                    if !hasMore { exhaustedFolders.insert(key) }
                }
            } catch {
                if let message = classify(error, context: target.account.displayName) {
                    errors.append(message)
                } else {
                    olderConnectionFailed = true
                }
                if !network.isOnline { break }
            }
            loadFromCache()
        }
        loadFromCache()
        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
        }
    }

    /// Fehlendes Passwort im Schlüsselbund.
    private struct MissingPasswordError: LocalizedError {
        var errorDescription: String? { "kein Passwort gefunden" }
    }

    /// Liest das Passwort eines Postfachs. Keychain-Fehler und ein
    /// fehlendes Passwort werden geworfen statt still verschluckt.
    private func readPassword(for account: MailAccount) throws -> String {
        guard let password = try accountStore.password(for: account) else {
            throw MissingPasswordError()
        }
        return password
    }

    /// Ordnet einen Abruffehler ein: Verbindungsfehler werden still
    /// vermerkt, alle anderen als Meldungstext zurückgegeben.
    private func classify(_ error: Error, context: String) -> String? {
        if MailFetchService.isConnectionError(error) || !network.isOnline {
            connectionFailed = true
            print("📴 \(context): keine Verbindung (\(error.localizedDescription))")
            return nil
        }
        return "\(context): \(error.localizedDescription)"
    }

    /// Anzahl gekennzeichneter Mails in den Posteingängen (für die Leiste).
    var flaggedCount: Int {
        MessageStore.shared.flaggedInboxCount(
            accountIDs: accountStore.accounts.map(\.id)
        )
    }

    /// Legt den vorgeschlagenen Spam-Ordner an. Beim nächsten Abruf wird
    /// das Postfach dann mitgefiltert.
    @MainActor
    func createSpamFolder(for pending: PendingSpamFolder) async {
        do {
            let created = try await spamFilter.createSpamFolder(
                pending.proposal, for: pending.account
            )
            print("📁 [\(pending.account.displayName)] Spam-Ordner \(created) angelegt")
        } catch {
            errorMessage = "\(pending.account.displayName): Ordner konnte nicht angelegt werden – \(error.localizedDescription)"
        }
        dismissSpamFolderRequest(pending, declineForSession: false)
    }

    /// Entfernt eine Rückfrage aus der Warteschlange.
    func dismissSpamFolderRequest(_ pending: PendingSpamFolder, declineForSession: Bool) {
        if declineForSession {
            declinedSpamFolders.insert(pending.account.id)
        }
        pendingSpamFolders.removeAll { $0.id == pending.id }
    }

    /// Abruf eines einzelnen Ordners (beim Antippen in der Leiste).
    /// Zeigt sofort den Cache und lädt im Hintergrund nach.
    @MainActor
    func refreshFolder(accountID: UUID, path: String) async {
        guard let account = accountStore.accounts.first(where: { $0.id == accountID }) else { return }
        let password: String
        do {
            password = try readPassword(for: account)
        } catch {
            errorMessage = "\(account.displayName): \(error.localizedDescription)"
            return
        }

        // Ohne Netz gar nicht erst versuchen: Cache zeigen, still vermerken.
        guard network.isOnline else {
            connectionFailed = true
            loadFromCache()
            return
        }

        isLoading = true
        defer { isLoading = false }

        connectionFailed = false
        do {
            try await MailFetchService.refreshAndCache(
                account: account, password: password, folder: path
            )
        } catch {
            if let message = classify(error, context: account.displayName) {
                errorMessage = message
            }
        }
        loadFromCache()
    }

    @MainActor
    func refresh() async {
        // Ohne Netz gar nicht erst versuchen: Cache zeigen, still vermerken.
        guard network.isOnline else {
            connectionFailed = true
            loadFromCache()
            print("📴 Refresh übersprungen: kein Netz")
            return
        }

        isLoading = true
        defer { isLoading = false }
        connectionFailed = false

        print("🔄 Refresh gestartet für \(accountStore.accounts.count) Konten")

        var errors: [String] = []
        pendingSpamFolders = []

        for account in accountStore.accounts {
            print("🔄 Starte Abruf: \(account.displayName) (ID: \(account.id.uuidString))")
            do {
                guard let password = try accountStore.password(for: account) else {
                    errors.append("\(account.displayName): kein Passwort gefunden")
                    print("❌ \(account.displayName): kein Passwort im Keychain")
                    continue
                }

                // Erst filtern, dann abrufen: So landet erkannter Spam gar
                // nicht erst im Posteingang. Ein Fehler im Filter darf den
                // Abruf nicht verhindern.
                if spamSettings.isEnabled {
                    spamFilter.scoreLimit = spamSettings.scoreLimit
                    do {
                        if case .needsSpamFolder(let proposal) = try await spamFilter.run(for: account),
                           !declinedSpamFolders.contains(account.id) {
                            pendingSpamFolders.append(
                                PendingSpamFolder(account: account, proposal: proposal)
                            )
                        }
                    } catch {
                        if let message = classify(error, context: "\(account.displayName): Spamfilter") {
                            errors.append(message)
                        }
                        print("⚠️ \(account.displayName): Spamfilter fehlgeschlagen: \(error.localizedDescription)")
                    }
                }

                // Posteingang abrufen
                try await MailFetchService.refreshAndCache(
                    account: account, password: password
                )

                // Spam-Ordner mit abrufen – dort wird am meisten gearbeitet
                if let spamFolder = account.spamFolder, !spamFolder.isEmpty {
                    do {
                        try await MailFetchService.refreshAndCache(
                            account: account, password: password, folder: spamFolder
                        )
                        print("📬 [\(account.displayName)] Spam-Ordner \(spamFolder) abgerufen")
                    } catch {
                        print("⚠️ [\(account.displayName)] Spam-Abruf fehlgeschlagen: \(error.localizedDescription)")
                    }
                }
                print("✅ \(account.displayName): Abruf abgeschlossen")
            } catch {
                if let message = classify(error, context: account.displayName) {
                    errors.append(message)
                }
                print("❌ \(account.displayName): \(error.localizedDescription)")
            }

            // Nach jedem Konto Liste aktualisieren → schrittweiser Aufbau
            loadFromCache()

            // Netz während des Abrufs verloren: die übrigen Postfächer
            // nicht einzeln in Zeitüberschreitungen laufen lassen.
            if !network.isOnline {
                connectionFailed = true
                print("📴 Refresh abgebrochen: Netz verloren")
                break
            }
        }

        // Wird ein einzelner Ordner angezeigt, diesen ebenfalls abrufen
        if case .folder(let accountID, let path, _) = selection {
            if let account = accountStore.accounts.first(where: { $0.id == accountID }) {
                do {
                    let password = try readPassword(for: account)
                    try await MailFetchService.refreshAndCache(
                        account: account, password: password, folder: path
                    )
                } catch {
                    if let message = classify(error, context: "\(account.displayName)/\(path)") {
                        errors.append(message)
                    }
                }
            }
        }

        loadFromCache()
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
        print("🔄 Refresh fertig. Fehler: \(errors.count), Nachrichten gesamt: \(messages.count)")
    }
}
