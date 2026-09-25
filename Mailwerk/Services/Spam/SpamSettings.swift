//
//  SpamSettings.swift
//  Mailwerk
//
//  Einstellungen des Spamfilters. Liegen wie die Postfächer im
//  iCloud-Key-Value-Store und gelten damit für alle Geräte – genau wie
//  die Listen selbst.
//

import Foundation
import Observation

@Observable
final class SpamSettings {

    private static let enabledKey = "mailwerk.spam.enabled"
    private static let scoreLimitKey = "mailwerk.spam.scoreLimit"

    /// Der Filter ist standardmäßig aus. Er verschiebt Mails selbsttätig,
    /// deshalb wird er bewusst eingeschaltet und nicht stillschweigend aktiv.
    static let defaultEnabled = false

    private let store = NSUbiquitousKeyValueStore.default

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

    /// Änderungen von einem anderen Gerät übernehmen. Die Notification kommt
    /// auf einem Hintergrund-Thread an, der Zustand wird auf dem Main-Thread
    /// geändert.
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
