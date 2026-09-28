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

    /// Aktive Ansicht. Ändert sich durch die Seitenleiste.
    var selection: MailboxSelection = .allInboxes {
        didSet { loadFromCache() }
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
        switch selection {
        case .allInboxes:
            messages = MessageStore.shared.allMessages(
                accountIDs: accountIDs, folder: MailFetchService.inboxFolder
            )
        case .flagged:
            messages = MessageStore.shared.flaggedInboxMessages(
                accountIDs: accountIDs
            )
        }
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

    @MainActor
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

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
                        errors.append("\(account.displayName): Spamfilter – \(error.localizedDescription)")
                        print("⚠️ \(account.displayName): Spamfilter fehlgeschlagen: \(error.localizedDescription)")
                    }
                }

                try await MailFetchService.refreshAndCache(
                    account: account, password: password
                )
                print("✅ \(account.displayName): Abruf abgeschlossen")
            } catch {
                errors.append("\(account.displayName): \(error.localizedDescription)")
                print("❌ \(account.displayName): \(error.localizedDescription)")
            }

            // Nach jedem Konto Liste aktualisieren → schrittweiser Aufbau
            loadFromCache()
        }

        loadFromCache()
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
        print("🔄 Refresh fertig. Fehler: \(errors.count), Nachrichten gesamt: \(messages.count)")
    }
}
