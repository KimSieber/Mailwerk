//
//  SyncStatePlanner.swift
//  Mailwerk
//
//  Zweck: Entscheidet anhand des gespeicherten Sync-Zustands eines
//  Ordners und der Werte des Servers, wie ein Abruf vorgeht, und
//  bestimmt, welche neu angekommenen Mails nachzuladen sind.
//
//  Grundlage (Muster aus RFC 4549):
//  - UIDVALIDITY: Solange sie gleich bleibt, sind die UIDs eines Ordners
//    stabil. Ändert sie sich, ist der lokale Stand dieses Ordners ungültig.
//  - UIDNEXT: die UID, die die nächste im Ordner ankommende Mail erhält.
//    UIDs werden in der Reihenfolge des Ankommens im Ordner vergeben,
//    nicht nach Datum. Alles, was seit dem letzten Abruf angekommen ist –
//    auch eine im Webmail hineinkopierte, alt datierte Mail –, hat eine
//    UID ≥ dem damals gespeicherten UIDNEXT.
//
//  Reine Logik ohne IMAP- und Datenbankzugriff, deshalb `nonisolated`.
//
//  Abgrenzung: Abruf und Speichern übernimmt der MailFetchService, das
//  Ablegen des Zustands der MessageStore.
//
//  Abhängigkeiten: keine (reine Datentypen).
//

import Foundation

/// Sync-Zustand eines Ordners nach dem letzten erfolgreichen Abruf.
nonisolated struct FolderSyncState: Equatable {
    /// UIDVALIDITY des Ordners beim letzten Abruf.
    let uidValidity: UInt32
    /// Ab dieser UID beginnen die noch nicht gesehenen Mails.
    let uidNext: UInt32
}

nonisolated enum SyncStatePlanner {

    /// Höchstzahl der Neuankünfte, die ein Abruf je Ordner nachlädt.
    /// Gilt nur für Mails, die die Datumssuche nicht ohnehin findet.
    /// Darüber hinausgehende folgen bei den nächsten Abrufen.
    static let arrivalLimit = 200

    /// Vorgehen für einen Abruf.
    enum Decision: Equatable {
        /// Der Server meldet UIDVALIDITY oder UIDNEXT nicht. Abruf wie
        /// bisher, es wird kein Zustand gespeichert.
        case unsupported
        /// Noch kein Zustand gespeichert (erster Abruf, neue Installation,
        /// Datenbank vor Einführung des Zustands). Abruf wie bisher,
        /// danach Zustand speichern; die Historie wird nicht nachgeladen.
        case initial
        /// UIDVALIDITY hat sich geändert: Der Cache dieses Ordners ist
        /// ungültig und wird verworfen, danach wie `initial`.
        case reset
        /// Zustand gültig: Abruf wie bisher und zusätzlich Neuankünfte
        /// ab der gespeicherten UID nachladen.
        case incremental(fromUID: UInt32)
    }

    /// Ergebnis der Planung für Neuankünfte.
    struct ArrivalPlan: Equatable {
        /// UIDs, die jetzt geladen werden, aufsteigend.
        let toLoad: [UInt32]
        /// Anzahl der Neuankünfte, die wegen der Obergrenze auf einen
        /// späteren Abruf warten.
        let deferredCount: Int
        /// Wert, der als neuer UIDNEXT gespeichert wird.
        let nextUIDNext: UInt32
    }

    /// Entscheidet, wie ein Abruf vorgeht.
    ///
    /// Verarbeitung: Meldet der Server einen der beiden Werte nicht
    /// (SwiftMail liefert dann 0), gilt `unsupported`. Ohne gespeicherten
    /// Zustand gilt `initial`. Weicht UIDVALIDITY ab, gilt `reset`.
    /// Sonst `incremental` ab dem gespeicherten UIDNEXT.
    ///
    /// - Parameters:
    ///   - stored: Gespeicherter Zustand oder `nil`.
    ///   - serverUIDValidity: UIDVALIDITY aus dem SELECT (0 = nicht gemeldet).
    ///   - serverUIDNext: UIDNEXT aus dem SELECT (0 = nicht gemeldet).
    /// - Returns: Das Vorgehen für diesen Abruf.
    static func decide(
        stored: FolderSyncState?,
        serverUIDValidity: UInt32,
        serverUIDNext: UInt32
    ) -> Decision {
        guard serverUIDValidity != 0, serverUIDNext != 0 else { return .unsupported }
        guard let stored else { return .initial }
        guard stored.uidValidity == serverUIDValidity else { return .reset }
        return .incremental(fromUID: stored.uidNext)
    }

    /// Bestimmt, welche Neuankünfte geladen werden und welcher UIDNEXT
    /// danach gespeichert wird.
    ///
    /// Verarbeitung: Neuankünfte sind Server-UIDs im Bereich
    /// `fromUID ..< serverUIDNext`. Die obere Grenze ist nötig, weil die
    /// UID-Liste nach dem SELECT geholt wird und inzwischen eingetroffene
    /// Mails enthalten kann; diese gehören zum nächsten Abruf. Bekannte
    /// UIDs (schon im Cache oder von der Datumssuche gefunden) fallen
    /// heraus. Von den übrigen werden höchstens `limit` geladen,
    /// aufsteigend. Bleibt etwas übrig, rückt der gespeicherte UIDNEXT
    /// nur bis hinter die zuletzt geladene UID vor, damit der Rest beim
    /// nächsten Abruf folgt.
    ///
    /// - Parameters:
    ///   - serverUIDs: Alle UIDs des Ordners auf dem Server.
    ///   - fromUID: Gespeicherter UIDNEXT des letzten Abrufs.
    ///   - serverUIDNext: UIDNEXT aus dem aktuellen SELECT.
    ///   - known: UIDs, die nicht mehr geladen werden müssen.
    ///   - limit: Obergrenze für diesen Abruf.
    /// - Returns: Zu ladende UIDs, Anzahl zurückgestellter und neuer UIDNEXT.
    static func arrivals(
        serverUIDs: Set<UInt32>,
        fromUID: UInt32,
        serverUIDNext: UInt32,
        known: Set<UInt32>,
        limit: Int = arrivalLimit
    ) -> ArrivalPlan {
        let candidates = serverUIDs
            .filter { $0 >= fromUID && $0 < serverUIDNext }
            .subtracting(known)
            .sorted()
        let toLoad = Array(candidates.prefix(max(limit, 0)))
        let deferred = candidates.count - toLoad.count

        let next: UInt32
        if deferred == 0 {
            next = serverUIDNext            // alles geladen
        } else if let last = toLoad.last {
            next = last + 1                 // Rest folgt beim nächsten Abruf
        } else {
            next = fromUID                  // nichts geladen (Grenze 0)
        }
        return ArrivalPlan(toLoad: toLoad, deferredCount: deferred, nextUIDNext: next)
    }

    /// Bestimmt den UIDNEXT, der nach dem Laden der Neuankünfte
    /// gespeichert wird.
    ///
    /// Verarbeitung: Nur wenn alle geplanten Neuankünfte gespeichert
    /// wurden, gilt der geplante Wert. Konnte auch nur eine nicht geladen
    /// werden, bleibt der bisherige Stand stehen, damit der nächste Abruf
    /// sie erneut versucht. Bereits gespeicherte Mails sind dann bekannt
    /// und werden nicht doppelt geladen.
    ///
    /// - Parameters:
    ///   - plan: Planung der Neuankünfte.
    ///   - fromUID: Bisher gespeicherter UIDNEXT.
    ///   - failedCount: Anzahl der Neuankünfte, die nicht gespeichert wurden.
    /// - Returns: Zu speichernder UIDNEXT.
    static func uidNextAfterLoading(
        plan: ArrivalPlan,
        fromUID: UInt32,
        failedCount: Int
    ) -> UInt32 {
        failedCount == 0 ? plan.nextUIDNext : fromUID
    }
}
