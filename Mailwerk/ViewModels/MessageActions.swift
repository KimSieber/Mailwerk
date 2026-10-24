//
//  MessageActions.swift
//  Mailwerk
//
//  Zweck: Aktionen an einer einzelnen Mail – gelesen/ungelesen,
//  kennzeichnen, löschen, verschieben – jeweils auf dem Server UND im
//  lokalen Cache, an einer Stelle.
//
//  Liste (Wischaktionen, Kontextmenü) und Mailansicht (Menü) nutzen
//  dieselben Funktionen und laden danach nur ihre Liste neu bzw.
//  schließen sich. Kennzeichnung und Gelesen-Status sind zusätzlich als
//  umkehrbare `StateChange` beschrieben – Grundlage für „Rückgängig“.
//
//  Für mehrere Mails werden die Ziele je Postfach und Ordner gruppiert;
//  jede Gruppe ist ein Serverbefehl. Scheitert eine Gruppe, laufen die
//  übrigen weiter, und das Ergebnis (`BatchOutcome`) nennt, was gelang
//  und was nicht.
//
//  Ändert sich auf dem Server nichts (Fehler), bleibt auch der Cache
//  unverändert; der Fehler geht an den Aufrufer, der ihn anzeigt.
//
//  Abgrenzung: Die IMAP-Befehle selbst → MailActionService; Spam-Aktionen
//  → SpamFilterService; Anzeige und Rückfragen → InboxViewModel bzw.
//  MessageDetailView.
//
//  Messung: Jede Aktion (einzeln und gesammelt) ist ein Messpunkt für
//  Instruments („Mail-Aktion“, v0.2.3c) – Grundlage für die Entscheidung,
//  ob die Aktionen ebenfalls vom Hauptthread gelöst werden müssen.
//
//  Abhängigkeiten: MailActionService, MessageStore, AccountStore, FolderKey, Log.
//

import Foundation

/// Aktionen an einer einzelnen Mail auf Server und Cache.
enum MessageActions {

    /// Was eine Aktion von einer Mail braucht: Cache-ID, Postfach, Ordner, UID.
    struct Target: Equatable {
        /// Cache-ID der Mail.
        let id: String
        /// Postfach der Mail.
        let accountID: UUID
        /// Ordner der Mail (UIDs gelten nur je Ordner).
        let folder: String
        /// UID der Mail im Ordner.
        let uid: UInt32
    }

    /// Umkehrbare Zustandsänderung: Kennzeichnung oder Gelesen-Status,
    /// jeweils mit dem neu gesetzten Wert.
    enum StateChange: Equatable {
        /// Kennzeichnung gesetzt (`true`) bzw. entfernt (`false`).
        case flagged(Bool)
        /// Als gelesen (`true`) bzw. ungelesen (`false`) markiert.
        case read(Bool)

        /// Die Änderung, die diese zurücknimmt.
        var reversed: StateChange {
            switch self {
            case .flagged(let value): return .flagged(!value)
            case .read(let value): return .read(!value)
            }
        }
    }

    /// Führt eine Zustandsänderung an einer Mail aus.
    ///
    /// - Parameters:
    ///   - change: Kennzeichnung oder Gelesen-Status mit neuem Wert.
    ///   - target: Betroffene Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Throws: `MailCredentialError` oder `MailActionService.ActionError`.
    static func apply(_ change: StateChange, to target: Target, accountStore: AccountStore) async throws {
        let interval = Log.beginInterval(Log.Interval.mailAction)
        defer { Log.endInterval(interval) }
        switch change {
        case .flagged(let value):
            try await setFlagged(value, for: target, accountStore: accountStore)
        case .read(let value):
            try await setRead(value, for: target, accountStore: accountStore)
        }
    }

    /// Markiert eine Mail als gelesen oder ungelesen.
    ///
    /// - Parameters:
    ///   - isRead: `true` = gelesen, `false` = ungelesen.
    ///   - target: Betroffene Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Throws: `MailCredentialError` oder `MailActionService.ActionError`.
    static func setRead(_ isRead: Bool, for target: Target, accountStore: AccountStore) async throws {
        try await MailActionService.setRead(
            uid: target.uid,
            isRead: isRead,
            accountID: target.accountID,
            accountStore: accountStore,
            folder: target.folder
        )
        MessageStore.shared.updateUnread(messageID: target.id, isUnread: !isRead)
    }

    /// Setzt oder entfernt die Kennzeichnung einer Mail.
    ///
    /// - Parameters:
    ///   - isFlagged: `true` = kennzeichnen, `false` = Kennzeichnung entfernen.
    ///   - target: Betroffene Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Throws: `MailCredentialError` oder `MailActionService.ActionError`.
    static func setFlagged(_ isFlagged: Bool, for target: Target, accountStore: AccountStore) async throws {
        try await MailActionService.setFlagged(
            uid: target.uid,
            isFlagged: isFlagged,
            accountID: target.accountID,
            accountStore: accountStore,
            folder: target.folder
        )
        MessageStore.shared.updateFlagged(messageID: target.id, isFlagged: isFlagged)
    }

    /// Löscht eine Mail (Papierkorb oder endgültig) und entfernt sie aus
    /// dem Cache ihres Ordners.
    ///
    /// Verarbeitung: Im Papierkorb erscheint die Mail beim nächsten Abruf
    /// dieses Ordners.
    ///
    /// - Parameters:
    ///   - target: Betroffene Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Throws: `MailCredentialError` oder `MailActionService.ActionError`.
    static func delete(_ target: Target, accountStore: AccountStore) async throws {
        let interval = Log.beginInterval(Log.Interval.mailAction)
        defer { Log.endInterval(interval) }
        try await MailActionService.deleteMessage(
            uid: target.uid,
            accountID: target.accountID,
            accountStore: accountStore,
            folder: target.folder
        )
        MessageStore.shared.deleteMessage(id: target.id)
    }

    /// Verschiebt eine Mail in einen anderen Ordner desselben Postfachs und
    /// entfernt sie aus dem Cache des bisherigen Ordners.
    ///
    /// Verarbeitung: Im Zielordner erscheint die Mail beim nächsten Abruf
    /// dieses Ordners.
    ///
    /// - Parameters:
    ///   - target: Betroffene Mail.
    ///   - path: Server-Pfad des Zielordners.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Throws: `MailCredentialError` oder `MailActionService.ActionError`.
    static func move(_ target: Target, to path: String, accountStore: AccountStore) async throws {
        let interval = Log.beginInterval(Log.Interval.mailAction)
        defer { Log.endInterval(interval) }
        try await MailActionService.moveMessage(
            uid: target.uid,
            toFolder: path,
            accountID: target.accountID,
            accountStore: accountStore,
            folder: target.folder
        )
        MessageStore.shared.deleteMessage(id: target.id)
    }
}

extension MessageActions {

    // MARK: - Mehrere Mails

    /// Ergebnis einer Aktion an mehreren Mails.
    struct BatchOutcome {
        /// Eine gescheiterte Gruppe (ein Ordner eines Postfachs).
        struct Failure {
            /// Postfach der Gruppe.
            let accountID: UUID
            /// Anzahl der Mails der Gruppe.
            let count: Int
            /// Aufgetretener Fehler.
            let error: Error
        }

        /// Mails, an denen die Aktion gelang.
        var succeeded: [Target] = []
        /// Gescheiterte Gruppen.
        var failures: [Failure] = []

        /// Anzahl der Mails, an denen die Aktion scheiterte.
        var failedCount: Int { failures.reduce(0) { $0 + $1.count } }
    }

    /// Gruppiert Ziele nach Postfach und Ordner, in der Reihenfolge ihres
    /// ersten Auftretens.
    ///
    /// - Parameter targets: Ziele der Aktion.
    /// - Returns: Nicht leere Gruppen; jede gehört zu genau einem Ordner.
    static func groups(_ targets: [Target]) -> [[Target]] {
        var order: [FolderKey] = []
        var grouped: [FolderKey: [Target]] = [:]
        for target in targets {
            let key = FolderKey(accountID: target.accountID, folder: target.folder)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(target)
        }
        return order.compactMap { grouped[$0] }
    }

    /// Führt eine Zustandsänderung an mehreren Mails aus – je Ordner ein
    /// Serverbefehl – und trägt sie bei Erfolg in den Cache ein.
    ///
    /// - Parameters:
    ///   - change: Kennzeichnung oder Gelesen-Status mit neuem Wert.
    ///   - targets: Betroffene Mails.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: Gelungene Mails und gescheiterte Gruppen.
    static func apply(_ change: StateChange, to targets: [Target], accountStore: AccountStore) async -> BatchOutcome {
        let interval = Log.beginInterval(Log.Interval.mailAction)
        defer { Log.endInterval(interval) }
        return await runGrouped(targets) { group, accountID, folder in
            let uids = group.map(\.uid)
            switch change {
            case .flagged(let value):
                try await MailActionService.setFlagged(
                    uids: uids, isFlagged: value, accountID: accountID,
                    accountStore: accountStore, folder: folder
                )
                for target in group {
                    MessageStore.shared.updateFlagged(messageID: target.id, isFlagged: value)
                }
            case .read(let value):
                try await MailActionService.setRead(
                    uids: uids, isRead: value, accountID: accountID,
                    accountStore: accountStore, folder: folder
                )
                for target in group {
                    MessageStore.shared.updateUnread(messageID: target.id, isUnread: !value)
                }
            }
        }
    }

    /// Löscht mehrere Mails (Papierkorb oder endgültig) und entfernt sie
    /// aus dem Cache ihres Ordners.
    ///
    /// - Parameters:
    ///   - targets: Betroffene Mails.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: Gelungene Mails und gescheiterte Gruppen.
    static func delete(_ targets: [Target], accountStore: AccountStore) async -> BatchOutcome {
        let interval = Log.beginInterval(Log.Interval.mailAction)
        defer { Log.endInterval(interval) }
        return await runGrouped(targets) { group, accountID, folder in
            try await MailActionService.deleteMessages(
                uids: group.map(\.uid), accountID: accountID,
                accountStore: accountStore, folder: folder
            )
            for target in group {
                MessageStore.shared.deleteMessage(id: target.id)
            }
        }
    }

    /// Verschiebt mehrere Mails in einen Ordner desselben Postfachs und
    /// entfernt sie aus dem Cache des bisherigen Ordners.
    ///
    /// - Parameters:
    ///   - targets: Betroffene Mails (alle aus einem Postfach).
    ///   - path: Server-Pfad des Zielordners.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Returns: Gelungene Mails und gescheiterte Gruppen.
    static func move(_ targets: [Target], to path: String, accountStore: AccountStore) async -> BatchOutcome {
        let interval = Log.beginInterval(Log.Interval.mailAction)
        defer { Log.endInterval(interval) }
        return await runGrouped(targets) { group, accountID, folder in
            try await MailActionService.moveMessages(
                uids: group.map(\.uid), toFolder: path, accountID: accountID,
                accountStore: accountStore, folder: folder
            )
            for target in group {
                MessageStore.shared.deleteMessage(id: target.id)
            }
        }
    }

    /// Führt eine Operation je Ordnergruppe aus und sammelt das Ergebnis.
    ///
    /// Verarbeitung: Gruppen laufen nacheinander; ein Fehler betrifft nur
    /// seine Gruppe.
    ///
    /// - Parameters:
    ///   - targets: Betroffene Mails.
    ///   - operation: Aktion an einer Gruppe (Mails, Postfach, Ordner).
    /// - Returns: Gelungene Mails und gescheiterte Gruppen.
    private static func runGrouped(
        _ targets: [Target],
        operation: ([Target], UUID, String) async throws -> Void
    ) async -> BatchOutcome {
        var outcome = BatchOutcome()
        for group in groups(targets) {
            guard let first = group.first else { continue }
            do {
                try await operation(group, first.accountID, first.folder)
                outcome.succeeded += group
            } catch {
                outcome.failures.append(
                    BatchOutcome.Failure(accountID: first.accountID, count: group.count, error: error)
                )
            }
        }
        return outcome
    }
}

extension MessageActions.Target {
    /// Ziel aus einem Listeneintrag.
    ///
    /// - Parameter item: Listeneintrag.
    init(_ item: MessageListItem) {
        self.init(id: item.id, accountID: item.accountID, folder: item.folder, uid: item.uid)
    }

    /// Ziel aus einer vollständigen Mail.
    ///
    /// - Parameter message: Mail aus dem Cache.
    init(_ message: CachedMessage) {
        self.init(id: message.id, accountID: message.accountID, folder: message.folder, uid: message.uid)
    }
}
