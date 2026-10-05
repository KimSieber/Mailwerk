//
//  ServerReconciliation.swift
//  Mailwerk
//
//  Zweck: Vergleicht den Cache eines Ordners mit dem Stand auf dem Server
//  und sagt, was zu tun ist.
//
//  Grundsatz: Der Server ist führend, Mailwerk folgt ihm. Das gilt für
//  das Webmail ebenso wie für weitere Mailwerk-Installationen auf iPad
//  oder Mac – für den Abgleich sind beide dasselbe.
//
//  Grundlage ist der Stand des ganzen Ordners, den der Aufrufer mit
//  einer einzigen Flag-Abfrage holt. Daraus ergibt sich:
//  - welche Flags sich geändert haben,
//  - welche Mails es auf dem Server nicht mehr gibt,
//  - welche Mails auf dem Server liegen, aber im Cache fehlen (z. B.
//    eine im Webmail verschobene oder kopierte Mail mit altem Datum,
//    die der zeitfensterbasierte SEARCH nicht findet).
//
//  Verschwundene UIDs werden nur aus dem Cache dieses Ordners entfernt.
//  Wohin eine Mail gegangen ist, sagt IMAP nicht – sie kann gelöscht oder
//  verschoben worden sein, und im Zielordner hat sie eine neue UID. Im
//  Papierkorb erscheint sie also erst, wenn er geöffnet wird. Das ist
//  dasselbe Verhalten wie beim Verschieben in Mailwerk.
//
//  Reine Logik ohne IMAP- und Datenbankzugriff, deshalb `nonisolated`.
//
//  Abhängigkeiten: keine (reine Datentypen).
//

import Foundation

/// Stand eines Ordners auf dem Server, als UID-Mengen.
nonisolated struct ServerFolderState: Equatable {
    /// Alle UIDs im Ordner.
    var all: Set<UInt32>
    /// UIDs ohne `\Seen` (ungelesen).
    var unseen: Set<UInt32>
    /// UIDs mit `\Flagged` (gekennzeichnet).
    var flagged: Set<UInt32>
    /// UIDs mit `\Answered` (beantwortet).
    var answered: Set<UInt32>
    /// UIDs mit `$Forwarded`. `nil`, wenn das Kennzeichen nicht ermittelt
    /// werden konnte – dann bleibt es im Cache unangetastet. manitu meldet
    /// es.
    var forwarded: Set<UInt32>?
}

/// Flags einer gecachten Mail, wie der Abgleich sie braucht.
nonisolated struct CachedFlagState: Equatable {
    /// Cache-ID der Nachricht (`CachedMessage.id`).
    let id: String
    /// IMAP-UID der Nachricht im Ordner.
    let uid: UInt32
    /// true = ungelesen (kein `\Seen`).
    var isUnread: Bool
    /// true = gekennzeichnet (`\Flagged`).
    var isFlagged: Bool
    /// true = beantwortet (`\Answered`).
    var isAnswered: Bool
    /// true = weitergeleitet (`$Forwarded`).
    var isForwarded: Bool
}

nonisolated enum ServerReconciliation {

    /// Was am Cache eines Ordners zu ändern ist.
    struct Plan: Equatable {
        /// IDs von Mails, die es auf dem Server nicht mehr gibt.
        var removedIDs: [String] = []
        /// Mails mit geänderten Flags, mit ihrem neuen Stand.
        var flagUpdates: [CachedFlagState] = []
        /// UIDs, die auf dem Server liegen, aber im Cache fehlen. Der
        /// Aufrufer lädt sie nach. Sortiert aufsteigend, damit ältere
        /// Mails zuerst gespeichert werden.
        var missingUIDs: [UInt32] = []

        /// true, wenn es nichts zu tun gibt.
        var isEmpty: Bool {
            removedIDs.isEmpty && flagUpdates.isEmpty && missingUIDs.isEmpty
        }
    }

    /// Vergleicht Cache und Server und liefert den Änderungsplan.
    ///
    /// Verarbeitung: Iteriert über die gecachten Mails und prüft jede gegen
    /// den Server-Stand. Mails, die es auf dem Server nicht mehr gibt (und
    /// deren UID ≤ `keepUIDsAbove` liegt), werden als entfernt gemeldet.
    /// Mails mit geänderten Flags werden als Update gemeldet. Anschließend
    /// wird die Differenz Server minus Cache berechnet: UIDs, die auf dem
    /// Server liegen, aber im Cache fehlen, werden als `missingUIDs`
    /// gemeldet – das schließt Mails ein, die im Webmail verschoben oder
    /// kopiert wurden und deren altes Eingangsdatum außerhalb des
    /// Zeitfensters liegt.
    ///
    /// - Parameters:
    ///   - cached: Alle gecachten Mails dieses Ordners.
    ///   - server: Die UID-Mengen des Servers.
    ///   - keepUIDsAbove: UIDs oberhalb dieser Grenze bleiben unangetastet.
    ///     Gedacht für Mails, die nach der Server-Abfrage eingetroffen und
    ///     schon gecacht sind – sie stünden sonst fälschlich als „gelöscht"
    ///     da. Die Grenze ist die höchste UID der Server-Abfrage.
    /// - Returns: Änderungsplan mit Entfernungen, Flag-Updates und
    ///   fehlenden UIDs.
    static func plan(
        cached: [CachedFlagState],
        server: ServerFolderState,
        keepUIDsAbove: UInt32
    ) -> Plan {
        var plan = Plan()
        var cachedUIDs = Set<UInt32>()

        for message in cached {
            cachedUIDs.insert(message.uid)

            guard server.all.contains(message.uid) else {
                if message.uid <= keepUIDsAbove { plan.removedIDs.append(message.id) }
                continue
            }
            var updated = message
            updated.isUnread = server.unseen.contains(message.uid)
            updated.isFlagged = server.flagged.contains(message.uid)
            updated.isAnswered = server.answered.contains(message.uid)
            if let forwarded = server.forwarded {
                updated.isForwarded = forwarded.contains(message.uid)
            }
            if updated != message { plan.flagUpdates.append(updated) }
        }

        // UIDs, die auf dem Server liegen, aber im Cache fehlen.
        // Nur UIDs ≤ keepUIDsAbove: höhere wurden möglicherweise gerade
        // erst vom regulären Abruf gecacht und erscheinen nicht in der
        // Server-Antwort, die vor dem Abruf geholt wurde.
        let missing = server.all.subtracting(cachedUIDs)
            .filter { $0 <= keepUIDsAbove }
            .sorted()
        plan.missingUIDs = missing

        return plan
    }

    /// Obergrenze für `keepUIDsAbove`: die höchste UID, die der Server
    /// gemeldet hat. Bei leerem Ordner gilt `.max`, damit ein geleerter
    /// Ordner auch im Cache geleert wird.
    ///
    /// - Parameter server: Server-Stand des Ordners.
    /// - Returns: Höchste UID oder `.max`.
    static func highestUID(in server: ServerFolderState) -> UInt32 {
        server.all.max() ?? .max
    }
}
