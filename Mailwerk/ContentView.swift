//
//  ContentView.swift
//  Mailwerk
//
//  Zweck: Wurzelansicht der App. Reicht die beim Start angelegten,
//  langlebigen Objekte an die Hauptansicht weiter.
//
//  Die Objekte selbst entstehen genau einmal in `MailwerkApp`. Würden sie
//  hier als Startwerte von `@State` oder im `init` erzeugt, liefe diese
//  Erzeugung bei jedem Neuaufbau der Ansicht durch SwiftUI erneut – die
//  Kopien würden zwar verworfen, kosteten aber jedes Mal Arbeit (z. B.
//  Laden der Liste aus dem Cache).
//
//  Abgrenzung: Aufbau der Objekte → MailwerkApp; Nachrichtenliste →
//  InboxView.
//
//  Abhängigkeiten: InboxView, AppObjects.
//

import SwiftUI

/// Wurzelansicht: zeigt die Nachrichtenliste.
struct ContentView: View {
    /// Beim App-Start einmal angelegte Objekte.
    let objects: AppObjects

    /// Hauptansicht mit den gemeinsamen Objekten.
    var body: some View {
        InboxView(
            accountStore: objects.accountStore,
            filterLists: objects.filterLists,
            spamSettings: objects.spamSettings,
            viewModel: objects.inbox,
            folderCatalog: objects.folderCatalog
        )
    }
}

/// Die langlebigen Objekte der App, einmal beim Start angelegt.
///
/// Gebündelt, damit sie gemeinsam an einer Stelle entstehen und als ein
/// Wert durch die Ansichten gereicht werden.
@MainActor
final class AppObjects {
    /// Quelle für Postfächer und Passwörter.
    let accountStore: AccountStore
    /// Black-/Whitelist für den Spamfilter.
    let filterLists: any FilterListRepository
    /// Einstellungen des Spamfilters.
    let spamSettings: SpamSettings
    /// Zustand der Nachrichtenliste.
    let inbox: InboxViewModel
    /// Ordnerbäume der Postfächer für die Ordnerleiste.
    let folderCatalog: FolderCatalog

    /// Legt alle Objekte in der nötigen Reihenfolge an.
    ///
    /// Verarbeitung: Erst Postfächer und Spam-Einstellungen, dann das
    /// ViewModel (zeigt sofort den Cache) und der Ordnerkatalog, die beide
    /// darauf aufbauen.
    ///
    /// - Parameter filterLists: Speicher der Filterlisten.
    init(filterLists: any FilterListRepository) {
        let accountStore = AccountStore()
        let spamSettings = SpamSettings()
        self.accountStore = accountStore
        self.filterLists = filterLists
        self.spamSettings = spamSettings
        self.inbox = InboxViewModel(
            accountStore: accountStore,
            filterLists: filterLists,
            spamSettings: spamSettings
        )
        self.folderCatalog = InboxView.makeFolderCatalog(accountStore: accountStore)
    }
}

#Preview {
    ContentView(objects: AppObjects(filterLists: InMemoryFilterListRepository()))
}
