//
//  AccountStore.swift
//  Mailwerk
//
//  Zweck: Verwaltet die Postfach-Konfigurationen und das Standard-Postfach
//  für neue Mails. Beides liegt im iCloud Key-Value-Store und ist damit
//  auf allen Geräten gleich; Passwörter liegen im Schlüsselbund.
//
//  Der gemerkte Spam-Ordner gehört bewusst zu den synchronisierten
//  Kontodaten: Er bezeichnet einen Ordner auf dem Server und ist auf allen
//  Geräten derselbe. Geschrieben wird nur, wenn er sich ändert.
//
//  Ob ein Postfach abgerufen wird („Abruf“ ein/aus), gilt dagegen nur für
//  dieses Gerät: Die ausgeschalteten Postfächer liegen in den lokalen
//  Einstellungen (UserDefaults), nicht in iCloud. So lässt sich ein
//  Postfach etwa nur am Mac abrufen. Regeln → FetchSelection.
//
//  Fehler beim Lesen oder Schreiben der Kontoliste werden protokolliert.
//  Lässt sich die gespeicherte Liste nicht lesen (etwa weil ein anderes
//  Gerät mit neuerer App-Version sie geschrieben hat), bleiben die
//  geladenen Postfächer unverändert, und die unlesbaren Daten werden
//  sofort unter einem eigenen Schlüssel gesichert. Überschreibt das Gerät
//  die Liste später, gehen die Postfächer des anderen Geräts so nicht
//  verloren.
//
//  Teilen-Erweiterung: Dort gibt es keinen Zugriff auf den iCloud-Key-
//  Value-Speicher der App. `init(shareContext:)` legt einen nur lesenden
//  Store aus der Abschrift der App an (ShareContext); Änderungen werden
//  dann nicht nach iCloud geschrieben.
//
//  Anmeldung per OAuth 2: Statt des Passworts liegt das Refresh-Token im
//  Schlüsselbund (`addAccount(_:refreshToken:)`, `updateRefreshToken`).
//  Beim Entfernen wird es mit gelöscht, ebenso der Zustand im
//  OAuthTokenService und die Anzeige „neu anmelden“.
//
//  Abgrenzung: Zugangsdaten für Verbindungen → MailSession
//  (`credentials(for:)` als Erweiterung dort); Cache je Postfach →
//  MessageStore.
//
//  Abhängigkeiten: NSUbiquitousKeyValueStore, UserDefaults, KeychainService,
//  MessageStore (Cache beim Entfernen leeren), MailAccount, FetchSelection,
//  ShareContext, OAuthTokenService, OAuthSignInState, Log.
//

import Foundation
import Observation
import os

/// Postfächer und Standard-Postfach, synchronisiert über iCloud.
@Observable
final class AccountStore {
    /// Schlüssel der Kontoliste im Key-Value-Store.
    private static let accountsKey = "mailwerk.accounts"
    /// Schlüssel für die Sicherung einer unlesbaren Kontoliste.
    private static let unreadableAccountsKey = "mailwerk.accounts.unreadable"
    /// Schlüssel des Standard-Postfachs im Key-Value-Store.
    private static let defaultAccountKey = "mailwerk.defaultAccountID"
    /// iCloud Key-Value-Store; `nil` im nur lesenden Store der
    /// Teilen-Erweiterung.
    private let store: NSUbiquitousKeyValueStore?
    /// Schlüssel der ausgeschalteten Postfächer in den lokalen Einstellungen.
    private static let pausedAccountsKey = "mailwerk.fetchPausedAccounts"
    /// Lokale Einstellungen dieses Geräts (nicht über iCloud abgeglichen).
    private let localDefaults: UserDefaults

    /// Postfächer, die auf diesem Gerät nicht über „Alle Eingänge“
    /// abgerufen werden.
    private(set) var pausedAccountIDs: Set<UUID> = []

    /// Eingerichtete Postfächer.
    private(set) var accounts: [MailAccount] = []

    /// ID des Standard-Postfachs für neue Mails. `nil` = kein Standard definiert.
    private(set) var defaultAccountID: UUID?

    /// Lädt die Postfächer und beobachtet Änderungen von anderen Geräten.
    ///
    /// Verarbeitung: Liest den lokalen Stand und die ausgeschalteten
    /// Postfächer dieses Geräts, meldet sich für
    /// `didChangeExternallyNotification` an und stößt den Abgleich mit
    /// iCloud an.
    ///
    /// - Parameter localDefaults: Lokale Einstellungen; Tests übergeben eigene.
    init(localDefaults: UserDefaults = .standard) {
        self.localDefaults = localDefaults
        let store = NSUbiquitousKeyValueStore.default
        self.store = store
        pausedAccountIDs = FetchSelection.pausedIDs(
            from: localDefaults.stringArray(forKey: Self.pausedAccountsKey)
        )
        load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    /// Legt einen nur lesenden Store aus der Abschrift der App an
    /// (Teilen-Erweiterung).
    ///
    /// Verarbeitung: Übernimmt Postfächer und Standard-Postfach der
    /// Abschrift; ein Standard-Postfach, das es nicht (mehr) gibt, entfällt.
    /// Es gibt keine Verbindung zu iCloud und keine Beobachtung.
    ///
    /// - Parameters:
    ///   - shareContext: Abschrift der App.
    ///   - localDefaults: Lokale Einstellungen; Tests übergeben eigene.
    init(shareContext: ShareContext, localDefaults: UserDefaults = .standard) {
        self.localDefaults = localDefaults
        store = nil
        accounts = shareContext.accounts
        defaultAccountID = shareContext.defaultAccountID.flatMap { id in
            shareContext.accounts.contains(where: { $0.id == id }) ? id : nil
        }
    }

    /// Meldet die Beobachtung der iCloud-Änderungen ab.
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Postfächer

    /// Richtet ein Postfach ein.
    ///
    /// - Parameters:
    ///   - account: Neues Postfach.
    ///   - password: Passwort; wird im Schlüsselbund gespeichert.
    /// - Throws: Fehler des Schlüsselbunds (dann wird nichts gespeichert).
    func addAccount(_ account: MailAccount, password: String) throws {
        try KeychainService.savePassword(password, for: account.id)
        accounts.append(account)
        saveAccounts()
    }

    /// Richtet ein Postfach mit Anmeldung per OAuth 2 ein.
    ///
    /// Verarbeitung: Erst das Refresh-Token in den Schlüsselbund, dann das
    /// Postfach in die Liste – scheitert der Schlüsselbund, entsteht kein
    /// Postfach ohne Anmeldung.
    ///
    /// - Parameters:
    ///   - account: Neues Postfach (mit `oauthProvider`).
    ///   - refreshToken: Refresh-Token der Anmeldung.
    /// - Throws: Fehler des Schlüsselbunds (dann wird nichts gespeichert).
    func addAccount(_ account: MailAccount, refreshToken: String) throws {
        try KeychainService.saveRefreshToken(refreshToken, for: account.id)
        accounts.append(account)
        saveAccounts()
    }

    /// Ersetzt das Refresh-Token eines Postfachs nach einer erneuten
    /// Anmeldung.
    ///
    /// - Parameters:
    ///   - refreshToken: Neues Refresh-Token.
    ///   - accountID: Postfach.
    /// - Throws: Fehler des Schlüsselbunds.
    func updateRefreshToken(_ refreshToken: String, for accountID: UUID) throws {
        try KeychainService.saveRefreshToken(refreshToken, for: accountID)
    }

    /// Entfernt ein Postfach samt Passwort und Cache.
    ///
    /// Verarbeitung: Ohne Postfach hat sein Cache keinen Zweck mehr – Mails,
    /// Anhänge, Stände, Zeitfenster und Ordnerliste werden entfernt. War es
    /// das Standard-Postfach, wird der Standard zurückgesetzt. Bei Anmeldung
    /// per OAuth 2 werden Refresh-Token, Tokens im Speicher und die Anzeige
    /// „neu anmelden“ mit entfernt.
    ///
    /// - Parameter account: Zu entfernendes Postfach.
    /// - Throws: Fehler des Schlüsselbunds (dann bleibt das Postfach erhalten).
    func removeAccount(_ account: MailAccount) throws {
        try KeychainService.deletePassword(for: account.id)
        try KeychainService.deleteRefreshToken(for: account.id)
        let accountID = account.id
        Task { await OAuthTokenService.shared.forget(accountID) }
        OAuthSignInState.shared.setSignInRequired(false, for: accountID)
        accounts.removeAll { $0.id == account.id }
        saveAccounts()

        let removed = MessageStore.shared.deleteAccount(accountID: account.id)
        Log.store.info("🗑️ [\(account.displayName, privacy: .private)] Postfach entfernt, \(removed) Mails aus dem Cache gelöscht")

        if defaultAccountID == account.id {
            setDefaultAccount(nil)
        }
        setFetchEnabled(true, for: account.id)
    }

    /// Ändert ein Postfach und – falls angegeben – sein Passwort.
    ///
    /// - Parameters:
    ///   - updated: Geänderte Konfiguration (gleiche ID).
    ///   - newPassword: Neues Passwort; `nil` oder leer = unverändert.
    /// - Throws: Fehler des Schlüsselbunds (dann wird nichts gespeichert).
    func updateAccount(_ updated: MailAccount, newPassword: String?) throws {
        guard let index = accounts.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        if let newPassword, !newPassword.isEmpty {
            try KeychainService.savePassword(newPassword, for: updated.id)
        }
        accounts[index] = updated
        saveAccounts()
    }

    /// Liest das Passwort eines Postfachs.
    ///
    /// - Parameter account: Postfach.
    /// - Returns: Passwort oder `nil`, wenn keins gespeichert ist.
    /// - Throws: Lesefehler des Schlüsselbunds.
    func password(for account: MailAccount) throws -> String? {
        try KeychainService.readPassword(for: account.id)
    }

    /// Merkt den gefundenen bzw. angelegten Spam-Ordner beim Postfach.
    ///
    /// Verarbeitung: Geschrieben wird nur bei einer Änderung; unbekannte
    /// Kennungen werden übergangen.
    ///
    /// - Parameters:
    ///   - folder: Server-Pfad des Spam-Ordners; `nil` = vergessen.
    ///   - accountID: Postfach.
    func setSpamFolder(_ folder: String?, for accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }),
              accounts[index].spamFolder != folder else { return }
        accounts[index].spamFolder = folder
        saveAccounts()
    }

    // MARK: - Abruf je Postfach (nur dieses Gerät)

    /// Postfächer, die über „Alle Eingänge“ abgerufen und in den
    /// Sammelsichten gezeigt werden – in ihrer Reihenfolge.
    var fetchingAccounts: [MailAccount] {
        let active = Set(FetchSelection.activeIDs(accounts.map(\.id), paused: pausedAccountIDs))
        return accounts.filter { active.contains($0.id) }
    }

    /// `true`, wenn das Postfach auf diesem Gerät abgerufen wird.
    ///
    /// - Parameter accountID: Postfach.
    /// - Returns: `false`, wenn der Abruf ausgeschaltet ist.
    func isFetchEnabled(_ accountID: UUID) -> Bool {
        !pausedAccountIDs.contains(accountID)
    }

    /// Schaltet den Abruf eines Postfachs auf diesem Gerät ein oder aus.
    ///
    /// Verarbeitung: Gespeichert wird nur in den lokalen Einstellungen;
    /// unveränderte Werte werden nicht geschrieben.
    ///
    /// - Parameters:
    ///   - enabled: `true` = abrufen (Standard), `false` = ausschalten.
    ///   - accountID: Postfach.
    func setFetchEnabled(_ enabled: Bool, for accountID: UUID) {
        var updated = pausedAccountIDs
        if enabled { updated.remove(accountID) } else { updated.insert(accountID) }
        guard updated != pausedAccountIDs else { return }
        pausedAccountIDs = updated
        localDefaults.set(FetchSelection.storedValue(updated), forKey: Self.pausedAccountsKey)
    }

    // MARK: - Standard-Postfach

    /// Setzt das Standard-Postfach.
    ///
    /// - Parameter id: Postfach; `nil` entfernt die Einstellung. Unbekannte
    ///   IDs werden ignoriert.
    func setDefaultAccount(_ id: UUID?) {
        if let id, !accounts.contains(where: { $0.id == id }) {
            return
        }
        defaultAccountID = id
        guard let store else { return }
        if let id {
            store.set(id.uuidString, forKey: Self.defaultAccountKey)
        } else {
            store.removeObject(forKey: Self.defaultAccountKey)
        }
        store.synchronize()
    }

    // MARK: - Persistenz

    /// Übernimmt Änderungen von anderen Geräten.
    ///
    /// Verarbeitung: Die Mitteilung kommt auf einem Hintergrund-Thread an;
    /// der beobachtete Zustand wird nur auf dem Main-Thread geändert.
    ///
    /// - Parameter notification: Mitteilung des Key-Value-Stores.
    @objc private func externalChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.load()
        }
    }

    /// Liest Kontoliste und Standard-Postfach aus dem Key-Value-Store.
    ///
    /// Verarbeitung: Lässt sich die Kontoliste nicht lesen, bleiben die
    /// geladenen Postfächer unverändert; die unlesbaren Daten werden
    /// gesichert (`preserveUnreadable`). Das Standard-Postfach wird nur
    /// übernommen, wenn es (schon) existiert; der gespeicherte Wert bleibt
    /// stehen – kommen die Konten per iCloud später an, greift er beim
    /// nächsten Laden.
    private func load() {
        guard let store else { return }
        if let data = store.data(forKey: Self.accountsKey) {
            do {
                accounts = try JSONDecoder().decode([MailAccount].self, from: data)
            } catch {
                Log.store.error("⚠️ Kontoliste nicht lesbar, wird gesichert: \(String(describing: error), privacy: .public)")
                preserveUnreadable(data)
            }
        }

        if let raw = store.string(forKey: Self.defaultAccountKey),
           let id = UUID(uuidString: raw),
           accounts.contains(where: { $0.id == id }) {
            defaultAccountID = id
        } else {
            defaultAccountID = nil
        }
    }

    /// Sichert eine unlesbare Kontoliste unter eigenem Schlüssel.
    ///
    /// Verarbeitung: Eine bereits vorhandene Sicherung wird nicht
    /// überschrieben – sie ist der älteste unlesbare Stand.
    ///
    /// - Parameter data: Unlesbare Daten der Kontoliste.
    private func preserveUnreadable(_ data: Data) {
        guard let store, store.data(forKey: Self.unreadableAccountsKey) == nil else { return }
        store.set(data, forKey: Self.unreadableAccountsKey)
    }

    /// Schreibt die Kontoliste in den Key-Value-Store.
    ///
    /// Verarbeitung: Ein Kodierfehler wird protokolliert; der gespeicherte
    /// Stand bleibt dann unverändert.
    private func saveAccounts() {
        guard let store else { return }
        do {
            let data = try JSONEncoder().encode(accounts)
            store.set(data, forKey: Self.accountsKey)
            store.synchronize()
        } catch {
            Log.store.error("⚠️ Kontoliste nicht gespeichert: \(String(describing: error), privacy: .public)")
        }
    }
}
