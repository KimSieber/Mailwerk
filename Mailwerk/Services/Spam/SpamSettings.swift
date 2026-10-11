//
//  SpamSettings.swift
//  Mailwerk
//
//  Zweck: Einstellungen des Spamfilters – an/aus und Score-Obergrenze für
//  Whitelist-Treffer. Liegen wie die Postfächer im iCloud-Key-Value-Store
//  und gelten damit für alle Geräte – genau wie die Listen selbst.
//
//  Änderungen von anderen Geräten werden auf dem Main-Thread übernommen.
//
//  Abgrenzung: Oberfläche → SpamSettingsView; Anwendung der Obergrenze →
//  SpamClassifier.
//
//  Abhängigkeiten: Foundation, Observation, SpamClassifier (Standardwert).
//

import Foundation
import Observation

/// Einstellungen des Spamfilters, über iCloud abgeglichen.
@Observable
final class SpamSettings {

    /// Schlüssel für „Filter an“ im Key-Value-Store.
    private static let enabledKey = "mailwerk.spam.enabled"
    /// Schlüssel für die Score-Obergrenze im Key-Value-Store.
    private static let scoreLimitKey = "mailwerk.spam.scoreLimit"

    /// Der Filter ist standardmäßig aus. Er verschiebt Mails selbsttätig,
    /// deshalb wird er bewusst eingeschaltet und nicht stillschweigend aktiv.
    static let defaultEnabled = false

    /// iCloud-Key-Value-Store.
    private let store = NSUbiquitousKeyValueStore.default

    /// `true`, wenn der Filter läuft; Änderungen werden sofort gespeichert.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            store.set(isEnabled, forKey: Self.enabledKey)
            store.synchronize()
        }
    }

    /// Ab diesem Score rettet auch ein Whitelist-Eintrag eine Mail nicht mehr.
    var scoreLimit: Double {
        didSet {
            guard scoreLimit != oldValue else { return }
            store.set(scoreLimit, forKey: Self.scoreLimitKey)
            store.synchronize()
        }
    }

    /// Liest die gespeicherten Werte und meldet sich für Änderungen von
    /// anderen Geräten an.
    init() {
        isEnabled = store.object(forKey: Self.enabledKey) as? Bool ?? Self.defaultEnabled

        let storedLimit = store.double(forKey: Self.scoreLimitKey)
        scoreLimit = storedLimit > 0 ? storedLimit : SpamClassifier.defaultScoreLimit

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    /// Übernimmt Änderungen von einem anderen Gerät.
    ///
    /// Verarbeitung: Die Meldung kommt auf einem Hintergrund-Thread an; der
    /// Zustand wird auf dem Main-Thread geändert.
    ///
    /// - Parameter notification: Meldung des Key-Value-Stores.
    @objc private func externalChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let enabled = store.object(forKey: Self.enabledKey) as? Bool ?? Self.defaultEnabled
            if enabled != isEnabled { isEnabled = enabled }

            let limit = store.double(forKey: Self.scoreLimitKey)
            if limit > 0, limit != scoreLimit { scoreLimit = limit }
        }
    }
}
