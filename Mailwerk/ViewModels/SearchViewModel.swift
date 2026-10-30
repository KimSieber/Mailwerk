//
//  SearchViewModel.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 15.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Zustand und Abläufe der Suche in der Nachrichtenliste.
//  - Lokale Suche im Cache: Teilzeichenfolge ab drei Zeichen (Leerzeichen
//    zählen mit), ohne Groß-/Kleinschreibung, über Betreff, Personen, Text
//    und Anhangnamen. Läuft nach jeder Eingabe neu, auch offline – entprellt
//    (150 ms nach dem letzten Tastendruck) und im Hintergrund; ein älteres
//    Ergebnis wird verworfen (v0.2.3d, Prüfbericht P-17).
//  - Namensvorschläge ab dem ersten Zeichen aus den Adressen des
//    Suchbereichs; eine gewählte Person wird zur Marke (Mails von und an
//    diese Adresse) und hebt die Mindestlänge auf.
//  - Serversuche auf Knopfdruck: im gezeigten Ordner bzw. nacheinander in
//    den Ordnern der Sammelansicht (Posteingänge, Spam-Ordner); höchstens
//    100 Treffer je Ordner, nur Treffer, die nicht im Cache liegen. Eine
//    geänderte Eingabe verwirft das Ergebnis. Die Sichten „Ungelesen“ und
//    „Mit Kennzeichnung“ suchen nur im Cache – ihre Mails liegen dort
//    vollständig.
//
//  Gesucht wird immer in der gezeigten Ansicht (`SearchScope`). Die
//  lokale Suche liefert nur Cache-IDs; die Liste filtert damit ihre
//  eigenen Einträge (`InboxViewModel.searchFilter`) – so gelten
//  Sortierung, Aktionen und Auswahl unverändert auch für Treffer.
//
//  Abgrenzung: Darstellung in InboxView; Suchindex im MessageStore;
//  Serversuche im MailFetchService.
//
//  Abhängigkeiten: AccountStore (Zugangsdaten), MessageStore, SearchText,
//  SearchScope, SearchPerson, MailFetchService, MailboxSelection, FolderKey,
//  Log.
//

import Foundation
import Observation
import os

/// Zustand und Abläufe der Suche.
@Observable
final class SearchViewModel {

    /// Stand der Serversuche.
    enum ServerState: Equatable {
        /// Noch nicht gesucht (oder Eingabe seither geändert).
        case idle
        /// Suche läuft.
        case searching
        /// Fertig. `hasMore`: Es gab mehr Treffer als gezeigt;
        /// `unreachable`: Anzahl der Postfächer ohne Verbindung.
        case done(hasMore: Bool, unreachable: Int)
    }

    /// Quelle für Zugangsdaten.
    private let accountStore: AccountStore

    /// Suchfeld ist geöffnet.
    var isPresented = false {
        didSet {
            guard isPresented != oldValue else { return }
            if isPresented {
                loadPeople()
            } else {
                clear()
            }
        }
    }
    /// Eingabe im Suchfeld.
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            queryChanged()
        }
    }
    /// Gewählte Person als Marke im Suchfeld (höchstens eine).
    var tokens: [SearchPerson] = [] {
        didSet {
            guard tokens != oldValue else { return }
            // Eine zweite Marke ersetzt die erste.
            if tokens.count > 1, let last = tokens.last {
                tokens = [last]
                return
            }
            if !tokens.isEmpty, !text.isEmpty {
                // Der getippte Name ist mit der Marke erledigt.
                text = ""
            }
            queryChanged()
        }
    }

    /// Suchbereich (gezeigte Ansicht).
    private(set) var scope: SearchScope?
    /// Personen des Suchbereichs für die Vorschläge.
    private(set) var people: [SearchPerson] = []
    /// Cache-IDs der lokalen Treffer; `nil` = keine Suche aktiv (Liste
    /// ungefiltert).
    private(set) var matchingIDs: Set<String>?
    /// Stand der Serversuche.
    private(set) var serverState = ServerState.idle
    /// Treffer vom Server, die nicht im Cache liegen, neueste zuerst.
    private(set) var serverHits: [MessageListItem] = []

    /// Laufende Serversuche; wird bei geänderter Eingabe abgebrochen.
    @ObservationIgnored private var serverTask: Task<Void, Never>?
    /// Laufende lokale Suche; eine neue Eingabe bricht sie ab.
    @ObservationIgnored private var localTask: Task<Void, Never>?
    /// Laufendes Lesen der Personen für die Vorschläge.
    @ObservationIgnored private var peopleTask: Task<Void, Never>?

    /// Wartezeit nach dem letzten Tastendruck, bevor lokal gesucht wird.
    static let typingDebounce: Duration = .milliseconds(150)

    /// Legt die Suche an.
    ///
    /// - Parameter accountStore: Quelle für Zugangsdaten.
    init(accountStore: AccountStore) {
        self.accountStore = accountStore
    }

    // MARK: - Abgeleitete Werte

    /// Adresse der gewählten Person; `nil` = keine.
    var address: String? { tokens.first?.address }

    /// Suchausdruck für den Index; `nil`, solange die Eingabe zu kurz und
    /// keine Person gewählt ist.
    var matchExpression: String? {
        SearchText.matchExpression(query: text, address: address)
    }

    /// `true`, wenn die Liste gerade Treffer statt aller Mails zeigt.
    var isFiltering: Bool { matchingIDs != nil }

    /// Namensvorschläge zur Eingabe; leer, sobald eine Person gewählt ist.
    var suggestions: [SearchPerson] {
        guard tokens.isEmpty else { return [] }
        return SearchPerson.suggestions(from: people, matching: text)
    }

    /// `true`, wenn „Auf dem Server weitersuchen“ angeboten wird.
    var offersServerSearch: Bool {
        isFiltering && (scope?.allowsServerSearch ?? false)
    }

    // MARK: - Ablauf

    /// Setzt den Suchbereich passend zur gezeigten Ansicht.
    ///
    /// Verarbeitung: Ein anderer Bereich beendet eine laufende Suche – die
    /// Suche gilt immer nur für die Ansicht, in der sie begonnen wurde.
    ///
    /// - Parameters:
    ///   - selection: Gezeigte Ansicht.
    ///   - fetchingAccountIDs: Postfächer mit eingeschaltetem Abruf.
    ///   - spamFolders: Spam-Ordner dieser Postfächer (Sicht „Spam“).
    func updateScope(for selection: MailboxSelection, fetchingAccountIDs: [UUID], spamFolders: [FolderKey]) {
        let newScope = SearchScope.make(
            for: selection, fetchingAccountIDs: fetchingAccountIDs, spamFolders: spamFolders
        )
        guard newScope != scope else { return }
        let hadScope = scope != nil
        scope = newScope
        if hadScope && isPresented {
            isPresented = false
        }
    }

    /// Startet die Suche nach einer Person (Marke im Suchfeld), z. B. aus
    /// dem Menü einer Person im Mailkopf.
    ///
    /// Verarbeitung: Öffnet das Suchfeld, leert die Eingabe und setzt die
    /// Person als Marke – die Liste zeigt dann die Mails von und an sie in
    /// der gezeigten Ansicht.
    ///
    /// - Parameter person: Gesuchte Person.
    func startSearch(for person: SearchPerson) {
        if !isPresented {
            isPresented = true
        }
        text = ""
        tokens = [person]
    }

    /// Führt die lokale Suche erneut aus, z. B. nachdem sich der Cache
    /// geändert hat (Abruf, Löschen, geladener Servertreffer).
    ///
    /// Verarbeitung: Eine laufende lokale Suche wird abgebrochen. Ist keine
    /// Suche aktiv (Eingabe zu kurz, keine Person), wird der Filter sofort
    /// aufgehoben. Sonst wird nach `debounce` im Hintergrund gesucht
    /// (`searchIDs`); ein inzwischen überholtes Ergebnis wird verworfen.
    ///
    /// - Parameter debounce: Wartezeit vor der Suche (beim Tippen
    ///   `typingDebounce`, sonst keine).
    func refreshLocal(debounce: Duration = .zero) {
        localTask?.cancel()
        guard let scope, let expression = matchExpression else {
            localTask = nil
            matchingIDs = nil
            return
        }
        localTask = Task {
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            let ids = await Self.searchIDs(in: scope, match: expression)
            guard !Task.isCancelled, expression == matchExpression else { return }
            matchingIDs = ids
        }
    }

    /// Sucht im Suchindex – abseits des Hauptthreads.
    ///
    /// - Parameters:
    ///   - scope: Suchbereich.
    ///   - expression: Suchausdruck für den Index.
    /// - Returns: Cache-IDs der Treffer.
    @concurrent
    nonisolated private static func searchIDs(in scope: SearchScope, match expression: String) async -> Set<String> {
        MessageStore.shared.searchMessageIDs(in: scope, match: expression)
    }

    /// Liest die Adressen des Suchbereichs – abseits des Hauptthreads.
    ///
    /// - Parameter scope: Suchbereich.
    /// - Returns: Rohe Adressen (für `SearchPerson.collect`).
    @concurrent
    nonisolated private static func addresses(in scope: SearchScope) async -> [String] {
        MessageStore.shared.participantAddresses(in: scope)
    }

    /// Nimmt einen Servertreffer aus der Liste, nachdem er geladen wurde
    /// (er ist jetzt ein lokaler Treffer).
    ///
    /// - Parameter id: Cache-ID des Treffers.
    func removeServerHit(_ id: String) {
        serverHits.removeAll { $0.id == id }
    }

    /// Sucht auf dem Server.
    ///
    /// Verarbeitung: Nacheinander je Ordner des Bereichs (eine Verbindung
    /// nach der anderen). Ein nicht erreichbares Postfach wird gezählt, die
    /// übrigen werden trotzdem durchsucht. Die Treffer aller Postfächer
    /// stehen gemeinsam nach Datum (neueste zuerst). Ändert sich die
    /// Eingabe währenddessen, wird das Ergebnis verworfen.
    func searchServer() {
        guard let scope, scope.allowsServerSearch, matchExpression != nil else { return }
        let query = text
        let address = address
        let expression = matchExpression
        serverTask?.cancel()
        serverState = .searching
        serverHits = []
        serverTask = Task {
            var outcomes: [Result<MailFetchService.ServerSearchResult, any Error>] = []
            for key in scope.folders {
                if Task.isCancelled { return }
                do {
                    let credentials = try accountStore.credentials(for: key.accountID)
                    outcomes.append(.success(try await MailFetchService.searchOnServer(
                        credentials, folder: key.folder, query: query, address: address
                    )))
                } catch {
                    outcomes.append(.failure(error))
                    Log.fetch.error("🔎 Serversuche fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                }
            }
            guard !Task.isCancelled, expression == matchExpression else { return }
            let combined = Self.combine(outcomes)
            serverHits = combined.hits
            serverState = combined.state
        }
    }

    /// Führt die Ergebnisse der Ordner einer Serversuche zusammen.
    ///
    /// Verarbeitung: Treffer aller Postfächer stehen gemeinsam nach Datum
    /// (neueste zuerst, ohne Datum zuletzt). `hasMore` gilt, sobald ein
    /// Ordner mehr Treffer hatte als gezeigt; jeder Fehler zählt als nicht
    /// erreichbares Postfach.
    ///
    /// - Parameter outcomes: Ergebnis bzw. Fehler je durchsuchtem Ordner.
    /// - Returns: Treffer und Stand „fertig“.
    static func combine(
        _ outcomes: [Result<MailFetchService.ServerSearchResult, any Error>]
    ) -> (hits: [MessageListItem], state: ServerState) {
        var hits: [MessageListItem] = []
        var hasMore = false
        var unreachable = 0
        for outcome in outcomes {
            switch outcome {
            case .success(let result):
                hits += result.hits
                hasMore = hasMore || result.hasMore
            case .failure:
                unreachable += 1
            }
        }
        let sorted = hits.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return (sorted, .done(hasMore: hasMore, unreachable: unreachable))
    }

    // MARK: - Intern

    /// Reagiert auf eine geänderte Eingabe oder Marke: lokale Suche neu,
    /// Serverergebnis verwerfen.
    private func queryChanged() {
        serverTask?.cancel()
        serverTask = nil
        serverState = .idle
        serverHits = []
        refreshLocal(debounce: Self.typingDebounce)
    }

    /// Liest die Personen des Suchbereichs für die Vorschläge.
    ///
    /// Verarbeitung: Die Adressen werden im Hintergrund gelesen; schließt
    /// sich das Suchfeld vorher, wird das Ergebnis verworfen.
    private func loadPeople() {
        peopleTask?.cancel()
        guard let scope else {
            people = []
            return
        }
        peopleTask = Task {
            let addresses = await Self.addresses(in: scope)
            guard !Task.isCancelled, isPresented, scope == self.scope else { return }
            people = SearchPerson.collect(from: addresses)
        }
    }

    /// Setzt die Suche zurück (Suchfeld geschlossen).
    private func clear() {
        serverTask?.cancel()
        serverTask = nil
        localTask?.cancel()
        localTask = nil
        peopleTask?.cancel()
        peopleTask = nil
        text = ""
        tokens = []
        people = []
        matchingIDs = nil
        serverState = .idle
        serverHits = []
    }
}
