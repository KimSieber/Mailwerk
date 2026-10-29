//
//  ContentView.swift
//  Mailwerk
//
//  Zweck: Wurzelansicht der App. Reicht die beim Start angelegten,
//  langlebigen Objekte an die Hauptansicht weiter und öffnet für
//  mailto:-Links von außen das Verfassen-Fenster (ExternalMailtoPresenter).
//
//  Die Objekte selbst entstehen genau einmal in `MailwerkApp`. Würden sie
//  hier als Startwerte von `@State` oder im `init` erzeugt, liefe diese
//  Erzeugung bei jedem Neuaufbau der Ansicht durch SwiftUI erneut – die
//  Kopien würden zwar verworfen, kosteten aber jedes Mal Arbeit (z. B.
//  Laden der Liste aus dem Cache).
//
//  Mac: Die Wurzelansicht legt die Mindestgröße des Fensters fest – eine
//  Spalte breit (380 × 500 pt, MacColumnLayout) – und legt Nebelblau auch
//  unter die Zeile der Fensterknöpfe; dort steht mittig „Mailwerk“
//  (MacWindowTitle) (Standardgröße, Fensterstil und
//  Größenänderung der Szene → MailwerkApp).
//
//  Abgrenzung: Aufbau der Objekte → MailwerkApp; Nachrichtenliste →
//  InboxView.
//
//  Abhängigkeiten: InboxView, AppObjects, SignatureStore,
//  ShareContextPublisher, ExternalMailtoPresenter, MacColumnLayout,
//  AppTheme.
//

import SwiftUI

/// Wurzelansicht: zeigt die Nachrichtenliste.
struct ContentView: View {
    /// Beim App-Start einmal angelegte Objekte.
    let objects: AppObjects

    /// Hauptansicht mit den gemeinsamen Objekten.
    ///
    /// Das Verfassen-Fenster für Links von außen hängt hier an der Wurzel,
    /// nicht in der Liste: Es gehört zu keiner Ansicht und hält die
    /// ohnehin große InboxView frei davon.
    var body: some View {
        InboxView(
            accountStore: objects.accountStore,
            filterLists: objects.filterLists,
            spamSettings: objects.spamSettings,
            viewModel: objects.inbox,
            folderCatalog: objects.folderCatalog
        )
        // mailto:-Links von außen (Absender: Standard-Postfach)
        .externalMailtoPresenter(accountStore: objects.accountStore) { [inbox = objects.inbox] in
            inbox.loadFromCache()
        }
        // Signaturen für alle Ansichten (Postfach bearbeiten, Verfassen)
        .environment(objects.signatures)
        #if os(macOS)
        // Mindestgröße des Mac-Fensters: eine Spalte (380 × 500 pt).
        .frame(minWidth: MacColumnLayout.windowMinWidth, minHeight: MacColumnLayout.windowMinHeight)
        // Nebelblau auch in der Zeile der Fensterknöpfe – keine weiße Fläche.
        .background(AppTheme.background.ignoresSafeArea())
        // Name der App mittig in der Zeile der Fensterknöpfe.
        .overlay { MacWindowTitle() }
        #endif
    }
}

#if os(macOS)
/// Name der App mittig in der obersten Fensterzeile (Mac).
///
/// Verarbeitung: Das Fenster hat keine Titelleiste (`hiddenTitleBar`);
/// oben bleibt die Zeile der Fensterknöpfe frei. Die Ebene reicht bis an
/// den oberen Fensterrand (`ignoresSafeArea`) und setzt den Titel in eine
/// Zeile von der Höhe der Titelleiste des Systems (28 pt) – so steht er auf
/// Höhe der Fensterknöpfe. Der freigehaltene Rand selbst lässt sich hier
/// nicht verlässlich messen (er meldet 0), daher die feste Höhe. Die Ebene
/// nimmt keine Klicks an – das Fenster lässt sich dort weiter ziehen.
private struct MacWindowTitle: View {
    /// Höhe der Titelleiste des Systems in Punkt.
    private static let titleBarHeight: CGFloat = 28

    /// Titel „Mailwerk“ in der Zeile der Fensterknöpfe.
    var body: some View {
        VStack(spacing: 0) {
            Text("Mailwerk")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.titleBarHeight)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif

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
    /// Signaturen der Postfächer.
    let signatures: SignatureStore
    /// Hält die Abschrift für die Teilen-Erweiterung aktuell.
    let shareContext: ShareContextPublisher

    /// Legt alle Objekte in der nötigen Reihenfolge an.
    ///
    /// Verarbeitung: Erst Postfächer und Spam-Einstellungen, dann das
    /// ViewModel (zeigt sofort den Cache) und der Ordnerkatalog, die beide
    /// darauf aufbauen. Zuletzt die Abschrift für die Teilen-Erweiterung,
    /// die Postfächer und Signaturen beobachtet.
    ///
    /// - Parameters:
    ///   - filterLists: Speicher der Filterlisten.
    ///   - signatures: Speicher der Signaturen.
    init(filterLists: any FilterListRepository, signatures: SignatureStore) {
        let accountStore = AccountStore()
        let spamSettings = SpamSettings()
        self.accountStore = accountStore
        self.filterLists = filterLists
        self.signatures = signatures
        self.spamSettings = spamSettings
        self.inbox = InboxViewModel(
            accountStore: accountStore,
            filterLists: filterLists,
            spamSettings: spamSettings
        )
        self.folderCatalog = InboxView.makeFolderCatalog(accountStore: accountStore)
        self.shareContext = ShareContextPublisher(accountStore: accountStore, signatures: signatures)
    }
}

#Preview {
    ContentView(objects: AppObjects(
        filterLists: InMemoryFilterListRepository(),
        signatures: SignatureStore(storage: InMemorySignatureStorage(), observesCloud: false)
    ))
}
