//
//  FetchCoordinator.swift
//  Mailwerk
//
//  Zweck: Stimmt die Abrufe vom Server aufeinander ab. Abrufe laufen
//  nacheinander, nie gleichzeitig. Zwei gleichzeitige Abrufe würden
//  denselben Ordner über zwei Verbindungen bearbeiten und sich dabei den
//  Sync-Zustand (UIDNEXT, Fensterbeginn) gegenseitig überschreiben.
//
//  Regeln:
//  - Läuft dieselbe Anforderung schon oder wartet sie bereits, schließt
//    sich der Aufrufer ihr an. Es wird nichts doppelt abgerufen.
//  - Eine andere Anforderung wartet, bis alle vorherigen fertig sind.
//  - Eine neue Anforderung kann wartende verdrängen (`supersedes`). So
//    zählt bei schnell nacheinander angetippten Ordnern nur der letzte.
//    Eine bereits laufende Anforderung wird nie verdrängt.
//
//  Der Baustein kennt keine Mails und kein Netz; was abgerufen wird,
//  übergibt der Aufrufer als Operation. Dadurch ist er ohne Server testbar.
//
//  Abgrenzung: Welche Abrufe es gibt und was sie tun → InboxViewModel;
//  Abruf selbst → MailFetchService.
//
//  Abhängigkeiten: keine (nur Swift Concurrency).
//

import Foundation

/// Art eines Abrufs der Nachrichtenliste.
enum FetchRequest: Hashable {
    /// Alle Posteingänge samt Spam-Ordnern (Start, Herunterziehen).
    case inboxes
    /// Ein einzelner Ordner (Antippen in der Leiste, Herunterziehen dort).
    case folder(accountID: UUID, path: String)
    /// „Ältere laden“ für die genannten Ordner (Schlüssel Postfach|Ordner).
    case older(targets: [String])

    /// Verdrängungsregel: Ein neuer Ordnerabruf verdrängt einen noch
    /// wartenden Ordnerabruf – angezeigt wird ohnehin nur der zuletzt
    /// gewählte Ordner. Alle anderen Abrufe bleiben bestehen.
    ///
    /// - Parameters:
    ///   - new: Neu eintreffende Anforderung.
    ///   - waiting: Bereits wartende Anforderung.
    /// - Returns: `true`, wenn `waiting` entfallen soll.
    ///
    /// `nonisolated`, weil die Regel als Startwert einer Eigenschaft
    /// (`InboxViewModel.fetches`) übergeben wird – solche Ausdrücke wertet
    /// Swift außerhalb des Main-Actors aus. Die Regel ist eine reine
    /// Funktion ohne Zustand.
    nonisolated static func supersedes(_ new: FetchRequest, _ waiting: FetchRequest) -> Bool {
        if case .folder = new, case .folder = waiting { return true }
        return false
    }
}

/// Führt Abrufe nacheinander und ohne Doppelungen aus.
@MainActor
final class FetchCoordinator<Request: Hashable> {

    /// Ergebnis eines Aufrufs von `run`.
    enum Outcome: Equatable {
        /// Die Operation dieses Aufrufs wurde ausgeführt.
        case performed
        /// Dieselbe Anforderung lief schon oder wartete; der Aufrufer hat
        /// sich ihr angeschlossen und auf ihr Ende gewartet.
        case joined
        /// Die Anforderung wurde vor ihrem Start von einer neueren verdrängt.
        case superseded
    }

    /// Ein eingeplanter Abruf.
    private struct Entry {
        /// Kennung dieses Eintrags (unterscheidet Wiederholungen derselben Anforderung).
        let id: UUID
        /// Ablauf des Abrufs; liefert `true`, wenn die Operation ausgeführt wurde.
        let task: Task<Bool, Never>
    }

    /// Verdrängungsregel (neu, wartend) → wartende entfällt.
    private let supersedes: (Request, Request) -> Bool
    /// Eingeplante Abrufe (laufend oder wartend) je Anforderung.
    private var scheduled: [Request: Entry] = [:]
    /// Kennungen der Abrufe, die bereits gestartet sind.
    private var started: Set<UUID> = []
    /// Kennungen der Abrufe, die vor ihrem Start verdrängt wurden.
    private var superseded: Set<UUID> = []
    /// Zuletzt eingeplanter Abruf; der nächste wartet auf ihn.
    private var tail: Task<Bool, Never>?

    /// Legt den Koordinator an.
    ///
    /// - Parameter supersedes: Regel `(neu, wartend) → Bool`; `true` = die
    ///   wartende Anforderung entfällt. Standard: nichts wird verdrängt.
    init(supersedes: @escaping (Request, Request) -> Bool = { _, _ in false }) {
        self.supersedes = supersedes
    }

    /// `true`, solange ein Abruf läuft oder wartet.
    var isBusy: Bool { !scheduled.isEmpty }

    /// `true`, wenn diese Anforderung gerade läuft oder wartet.
    ///
    /// - Parameter request: Anforderung.
    /// - Returns: `true` bei laufender oder wartender Anforderung.
    func isScheduled(_ request: Request) -> Bool {
        scheduled[request] != nil
    }

    /// Führt eine Anforderung aus – nach allen vorher eingeplanten.
    ///
    /// Verarbeitung:
    /// 1. Läuft oder wartet dieselbe Anforderung schon, wird auf sie
    ///    gewartet (`joined`), die eigene Operation entfällt.
    /// 2. Sonst werden wartende Anforderungen geprüft, die die neue
    ///    verdrängt. Sie werden aus der Planung genommen und übersprungen,
    ///    wenn sie an der Reihe wären. Eine erneute Anforderung desselben
    ///    Ordners plant daher neu ein, statt sich dem verdrängten
    ///    anzuschließen.
    /// 3. Die neue Anforderung wird hinten angestellt und ausgeführt,
    ///    sobald alle vorherigen fertig sind.
    ///
    /// Der Abruf läuft in einer eigenen Aufgabe. Bricht der Aufrufer ab
    /// (z. B. Herunterziehen vorzeitig beendet), läuft der Abruf trotzdem
    /// zu Ende – ein halber Abruf wäre schlechter als ein verspäteter.
    ///
    /// - Parameters:
    ///   - request: Anforderung.
    ///   - operation: Auszuführender Abruf.
    /// - Returns: Was mit der Anforderung geschehen ist.
    @discardableResult
    func run(
        _ request: Request,
        operation: @escaping @MainActor () async -> Void
    ) async -> Outcome {
        if let existing = scheduled[request] {
            _ = await existing.task.value
            return .joined
        }

        for (waiting, entry) in scheduled
        where !started.contains(entry.id) && supersedes(request, waiting) {
            superseded.insert(entry.id)
            scheduled[waiting] = nil
        }

        let id = UUID()
        let previous = tail
        let task = Task { @MainActor () -> Bool in
            _ = await previous?.value
            defer { self.finish(request, id: id) }
            guard !self.superseded.contains(id) else { return false }
            self.started.insert(id)
            await operation()
            return true
        }
        scheduled[request] = Entry(id: id, task: task)
        tail = task

        return await task.value ? .performed : .superseded
    }

    /// Räumt nach einem Abruf auf.
    ///
    /// Verarbeitung: Der Planungseintrag wird nur entfernt, wenn er noch
    /// zu diesem Abruf gehört – nach einer Verdrängung kann dieselbe
    /// Anforderung schon neu eingeplant sein.
    ///
    /// - Parameters:
    ///   - request: Anforderung.
    ///   - id: Kennung des beendeten Abrufs.
    private func finish(_ request: Request, id: UUID) {
        if scheduled[request]?.id == id {
            scheduled[request] = nil
        }
        started.remove(id)
        superseded.remove(id)
    }
}
