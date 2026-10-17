//
//  Log.swift
//  Mailwerk
//
//  Zweck: Protokoll der App über `os.Logger` – eine Kategorie je Bereich,
//  filterbar in der Xcode-Konsole und in der App „Konsole“ (Subsystem =
//  Bundle-ID der App).
//
//  Kategorien:
//  - Abruf     – Abruf vom Server, Abgleich, Netzzustand
//  - Aktionen  – Aktionen an Mails und Ordnern
//  - Spam      – Spamfilter und Filterlisten
//  - Versand   – Versand und Gesendet-Kopie
//  - Cache     – lokale Ablage und Postfach-Konfiguration
//  - Ansicht   – Ansichten (Ordnerleiste, Mail, Drucken, Messungen)
//  - Anmeldung – Anmeldung per OAuth 2 (nie Tokens, nur Abläufe)
//
//  Stufen: `.error` für Fehler, `.info` für Abläufe und Ergebnisse,
//  `.debug` für Messwerte und Diagnose.
//
//  Datenschutz: Zahlen, Ordnernamen und Fehlertexte sind öffentlich
//  (`privacy: .public`). Mailadressen, Betreffs, Message-IDs und Namen der
//  Postfächer sind privat (`privacy: .private`) – sie erscheinen nur, wenn
//  ein Debugger angehängt ist, sonst als „<private>“. Jede Zeichenkette
//  wird ausdrücklich eingestuft, damit die Regel im Code sichtbar ist.
//
//  Abgrenzung: Meldungen an den Nutzer → Dialogs (`AlertItem`).
//
//  Abhängigkeiten: os.
//

import Foundation
import os

/// Logger der App, je Bereich eine Kategorie.
nonisolated enum Log {
    /// Subsystem aller Logger: die Bundle-ID der App.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Mailwerk"

    /// Abruf vom Server, Abgleich, Netzzustand.
    static let fetch = Logger(subsystem: subsystem, category: "Abruf")
    /// Aktionen an Mails und Ordnern.
    static let actions = Logger(subsystem: subsystem, category: "Aktionen")
    /// Spamfilter und Filterlisten.
    static let spam = Logger(subsystem: subsystem, category: "Spam")
    /// Versand und Gesendet-Kopie.
    static let send = Logger(subsystem: subsystem, category: "Versand")
    /// Lokale Ablage und Postfach-Konfiguration.
    static let store = Logger(subsystem: subsystem, category: "Cache")
    /// Ansichten.
    static let view = Logger(subsystem: subsystem, category: "Ansicht")
    /// Anmeldung per OAuth 2 (Abläufe, nie Tokens).
    static let auth = Logger(subsystem: subsystem, category: "Anmeldung")
}
