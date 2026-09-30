//
//  ServerReconciliation.swift
//  Mailwerk
//
//  Vergleicht den Cache eines Ordners mit dem Stand auf dem Server und
//  sagt, was zu tun ist (v0.1.8d).
//
//  Grundsatz: Der Server ist führend, Mailwerk folgt ihm. Das gilt für
//  das Webmail ebenso wie für weitere Mailwerk-Installationen auf iPad
//  oder Mac – für den Abgleich sind beide dasselbe.
//
//  Grundlage ist der Stand des ganzen Ordners, den der Aufrufer mit
//  einer einzigen Flag-Abfrage holt (v0.1.8e). Daraus ergibt sich, was im
//  Cache fehlt und welche Flags sich geändert haben.
//
//  Verschwundene UIDs werden nur aus dem Cache dieses Ordners entfernt.
//  Wohin eine Mail gegangen ist, sagt IMAP nicht – sie kann gelöscht oder
//  verschoben worden sein, und im Zielordner hat sie eine neue UID. Im
//  Papierkorb erscheint sie also erst, wenn er geöffnet wird. Das ist
//  dasselbe Verhalten wie beim Verschieben in Mailwerk.
//
//  Reine Logik ohne IMAP- und Datenbankzugriff, deshalb `nonisolated`.
//

import Foundation

/// Stand eines Ordners auf dem Server, als UID-Mengen.
nonisolated struct ServerFolderState: Equatable {
    var all: Set<UInt32>
    var unseen: Set<UInt32>
    var flagged: Set<UInt32>
    var answered: Set<UInt32>
    /// UIDs mit `$Forwarded`. `nil`, wenn das Kennzeichen nicht ermittelt
    /// werden konnte – dann bleibt es im Cache unangetastet. manitu meldet
    /// es (v0.1.8e).
    var forwarded: Set<UInt32>?
}

/// Flags einer gecachten Mail, wie der Abgleich sie braucht.
nonisolated struct CachedFlagState: Equatable {
    let id: String
    let uid: UInt32
    var isUnread: Bool
    var isFlagged: Bool
    var isAnswered: Bool
    var isForwarded: Bool
}

nonisolated enum ServerReconciliation {

    /// Was am Cache eines Ordners zu ändern ist.
    struct Plan: Equatable {
        /// IDs von Mails, die es auf dem Server nicht mehr gibt.
        var removedIDs: [String] = []
        /// Mails mit geänderten Flags, mit ihrem neuen Stand.
        var flagUpdates: [CachedFlagState] = []

        var isEmpty: Bool { removedIDs.isEmpty && flagUpdates.isEmpty }
    }

    /// Vergleicht Cache und Server.
    /// - Parameters:
    ///   - cached: alle gecachten Mails dieses Ordners.
    ///   - server: die vier UID-Mengen des Servers.
    ///   - keepUIDsAbove: UIDs oberhalb dieser Grenze bleiben unangetastet.
    ///     Gedacht für Mails, die nach der Server-Abfrage eingetroffen und
    ///     schon gecacht sind – sie stünden sonst fälschlich als „gelöscht“
    ///     da. Die Grenze ist die höchste UID der Server-Abfrage.
    static func plan(
        cached: [CachedFlagState],
        server: ServerFolderState,
        keepUIDsAbove: UInt32
    ) -> Plan {
        var plan = Plan()
        for message in cached {
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
        return plan
    }

    /// Obergrenze für `keepUIDsAbove`: die höchste UID, die der Server
    /// gemeldet hat. Bei leerem Ordner gilt `.max`, damit ein geleerter
    /// Ordner auch im Cache geleert wird.
    static func highestUID(in server: ServerFolderState) -> UInt32 {
        server.all.max() ?? .max
    }
}
