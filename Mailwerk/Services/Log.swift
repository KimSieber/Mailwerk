//
//  Log.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 10.10.2026
//  Geändert: 25.10.2026
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
//  Messpunkte (Signposts): `beginInterval`/`endInterval` markieren Abschnitte
//  für Instruments (Kategorie „Performance“), z. B. „Liste aus Cache“ oder
//  „Abruf Postfach“. Sie erscheinen benannt in den Werkzeugen „Time
//  Profiler“, „Hangs“ und „os_signpost“ und kosten ohne angeschlossenes
//  Instruments praktisch nichts. Namen der Messpunkte stehen in
//  `Log.Interval` gesammelt, damit sie an allen Stellen gleich heißen.
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
    /// Austausch zwischen iPhone und Apple Watch.
    static let watch = Logger(subsystem: subsystem, category: "Watch")

    // MARK: - Messpunkte (Signposts)

    /// Erzeuger der Messpunkte für Instruments.
    static let signposter = OSSignposter(subsystem: subsystem, category: "Performance")

    /// Namen der gemessenen Abschnitte – einheitlich an allen Stellen.
    nonisolated enum Interval {
        /// Liste der aktuellen Ansicht aus dem Cache lesen (InboxViewModel).
        static let listFromCache: StaticString = "Liste aus Cache"
        /// Abruf aller eingeschalteten Posteingänge (InboxViewModel).
        static let refreshAll: StaticString = "Abruf gesamt"
        /// Abruf eines Postfachs: Spamfilter, Posteingang, Spam-Ordner.
        static let refreshAccount: StaticString = "Abruf Postfach"
        /// Abruf eines Ordners auf einer Verbindung (MailFetchService).
        static let folderSync: StaticString = "Ordner-Sync"
        /// Vorbereitung beim Öffnen einer Mail (MessageDetailView).
        static let openMessage: StaticString = "Mail öffnen"
        /// Mail aus dem Cache lesen, bevor sie angezeigt wird.
        static let loadMessage: StaticString = "Mail aus Cache"
        /// Vom Öffnen bis der Inhalt sichtbar ist (MessageOpenTimer).
        static let messageVisible: StaticString = "Mail sichtbar"
        /// Ein Paket des nachgetragenen Suchindex (SearchIndexBuilder).
        static let searchIndexBatch: StaticString = "Suchindex-Paket"
        /// Aktion an einer oder mehreren Mails (MessageActions).
        static let mailAction: StaticString = "Mail-Aktion"
        /// Zusammenstellen des Stands für die Apple Watch (WatchBridge).
        static let watchSnapshot: StaticString = "Watch-Stand"
    }

    /// Ein begonnener Messabschnitt; mit `endInterval` abschließen.
    nonisolated struct MeasuredInterval {
        /// Name des Abschnitts (aus `Interval`).
        let name: StaticString
        /// Zustand des Signposts.
        let state: OSSignpostIntervalState
    }

    /// Beginnt einen Messabschnitt.
    ///
    /// Verarbeitung: Legt eine eigene Signpost-ID an, damit sich
    /// gleichzeitig laufende Abschnitte gleichen Namens (z. B. mehrere
    /// Ordner) in Instruments nicht vermischen.
    ///
    /// - Parameter name: Name des Abschnitts (aus `Interval`).
    /// - Returns: Abschnitt zum Abschließen mit `endInterval`.
    static func beginInterval(_ name: StaticString) -> MeasuredInterval {
        let id = signposter.makeSignpostID()
        return MeasuredInterval(name: name, state: signposter.beginInterval(name, id: id))
    }

    /// Vergangene Zeit seit einem Zeitpunkt in ganzen Millisekunden – für
    /// Konsolenzeilen wie „⏱ Abruf gesamt: … ms“.
    ///
    /// - Parameter start: Startzeitpunkt.
    /// - Returns: Millisekunden bis jetzt.
    static func milliseconds(since start: ContinuousClock.Instant) -> Int64 {
        let elapsed = ContinuousClock.now - start
        return elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
    }

    /// Schließt einen Messabschnitt ab.
    ///
    /// Verarbeitung: Üblich ist der Aufruf per `defer` direkt nach
    /// `beginInterval`, damit der Abschnitt auf jedem Weg endet.
    ///
    /// - Parameter interval: Begonnener Abschnitt.
    static func endInterval(_ interval: MeasuredInterval) {
        signposter.endInterval(interval.name, interval.state)
    }
}
