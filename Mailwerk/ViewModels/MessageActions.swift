//
//  MessageActions.swift
//  Mailwerk
//
//  Zweck: Aktionen an einer einzelnen Mail – gelesen/ungelesen,
//  kennzeichnen, löschen, verschieben – jeweils auf dem Server UND im
//  lokalen Cache, an einer Stelle.
//
//  Vorher stand dieselbe Folge (Server-Aktion → Cache ändern) doppelt in
//  der Liste (Wischaktionen) und in der Mailansicht (Menü). Die Ansichten
//  laden danach nur noch ihre Liste neu bzw. schließen sich.
//
//  Ändert sich auf dem Server nichts (Fehler), bleibt auch der Cache
//  unverändert; der Fehler geht an den Aufrufer, der ihn anzeigt.
//
//  Abgrenzung: Die IMAP-Befehle selbst → MailActionService; Spam-Aktionen
//  → SpamFilterService; Anzeige und Rückfragen → InboxViewModel bzw.
//  MessageDetailView.
//
//  Abhängigkeiten: MailActionService, MessageStore, AccountStore.
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

    /// Markiert eine Mail als gelesen oder ungelesen.
    ///
    /// - Parameters:
    ///   - isRead: `true` = gelesen, `false` = ungelesen.
    ///   - target: Betroffene Mail.
    ///   - accountStore: Quelle für die Zugangsdaten.
    /// - Throws: `MailCredentialError` oder `MailActionService.ActionError`.
    static func setRead(_ isRead: Bool, for target: Target, accountStore: AccountStore) async throws {
        try await MailActionService.setRead(
            uid: Int(target.uid),
            isRead: isRead,
            accountID: target.accountID,
            accountStore: accountStore,
            folder: target.folder
        )
        MessageStore.shared.updateFlags(messageID: target.id, isUnread: !isRead)
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
            uid: Int(target.uid),
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
        try await MailActionService.deleteMessage(
            uid: Int(target.uid),
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
        try await MailActionService.moveMessage(
            uid: Int(target.uid),
            toFolder: path,
            accountID: target.accountID,
            accountStore: accountStore,
            folder: target.folder
        )
        MessageStore.shared.deleteMessage(id: target.id)
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
