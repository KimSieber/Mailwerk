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
//  Ohne gespeicherten Wert (Erstinstallation, neuer Speicher) ist der
//  Filter eingeschaltet (`defaultEnabled`).
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

    /// Der Filter ist nach der Erstinstallation eingeschaltet. Von ihm hängen
    /// auch die Sammelansicht „Spam“ und der Abruf der Spam-Ordner ab (er
    /// ermittelt den Spam-Ordner je Postfach). Ein gespeicherter Wert – auch
    /// „aus“ – hat immer Vorrang.
    static let defaultEnabled = true

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
        isEnabled = Self.enabled(stored: store.object(forKey: Self.enabledKey))
        scoreLimit = Self.validScoreLimit(store.double(forKey: Self.scoreLimitKey))
            ?? SpamClassifier.defaultScoreLimit

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
            let enabled = Self.enabled(stored: store.object(forKey: Self.enabledKey))
            if enabled != isEnabled { isEnabled = enabled }

            if let limit = Self.validScoreLimit(store.double(forKey: Self.scoreLimitKey)),
               limit != scoreLimit {
                scoreLimit = limit
            }
        }
    }

    /// Gespeicherter Schalter des Filters.
    ///
    /// - Parameter stored: Wert aus iCloud; fehlt er oder ist er kein
    ///   Wahrheitswert, gilt `defaultEnabled`.
    /// - Returns: `true`, wenn der Filter läuft.
    static func enabled(stored: Any?) -> Bool {
        stored as? Bool ?? defaultEnabled
    }

    /// Gespeicherte Score-Obergrenze, sofern brauchbar.
    ///
    /// - Parameter stored: Wert aus iCloud; 0 bedeutet „nie gespeichert“.
    /// - Returns: Grenze oder `nil`, wenn keine gespeichert ist (dann gilt
    ///   beim Start der Standardwert, bei einer Änderung von außen bleibt
    ///   der bisherige Wert).
    static func validScoreLimit(_ stored: Double) -> Double? {
        stored > 0 ? stored : nil
    }
}
