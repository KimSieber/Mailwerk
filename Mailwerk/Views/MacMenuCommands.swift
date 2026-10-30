//
//  MacMenuCommands.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 27.10.2026
//  Geändert: 29.10.2026
//
//  Zweck: Zusätzliche Menübefehle des Mac, die über die Befehle der
//  Mailliste (InboxCommands) hinausgehen:
//  - Menü „Darstellung“: „Sidebar einblenden/ausblenden“ (⌥⌘S) – ersetzt
//    den gleichartigen Systembefehl, damit nur ein Eintrag erscheint. Er
//    wirkt wie der Ordner-Knopf über der Liste: in breiten Fenstern
//    schaltet er die feste Ordnerleiste, in schmaleren öffnet er die
//    einblendbare (MacColumnLayout);
//  - Menü „Bearbeiten“: „Alle E-Mails auswählen“ (⌥⌘A) – beginnt die
//    Mehrfachauswahl und wählt alle Mails der Liste;
//  - Menü „Ablage“: „Postfächer …“ (⌘,) – öffnet die Postfachverwaltung;
//  - Menü „Mailwerk“: „Über Mailwerk“ – ersetzt den Info-Dialog des
//    Systems und öffnet das eigene Fenster (AboutWindowView), das auch
//    Kontakt, Webseite und Open-Source-Lizenzen zeigt.
//
//  Wie bei InboxCommands wissen die Befehle nichts von der Liste: Die
//  Mailliste stellt ihre Aktionen als `MacMenuActions` bereit
//  (`focusedSceneValue`); eine fehlende Aktion graut den Befehl samt
//  Kürzel aus.
//
//  Bewusst ohne ⌘A: Dieses Kürzel gehört dem Systembefehl „Alles
//  auswählen“, der im Suchfeld und im Editor den Text auswählt. Ein
//  eigener Befehl mit ⌘A nähme es ihnen weg.
//
//  „Über Mailwerk“ braucht keine Aktion der Liste: Das Fenster öffnet
//  sich über `openWindow` und ist deshalb immer verfügbar.
//
//  Abgrenzung: Aktionen selbst und ihre Bereitstellung → InboxView;
//  Befehle für iPhone, iPad und Mac gemeinsam → InboxCommands.
//
//  Abhängigkeiten: SwiftUI, AboutWindow (Fensterkennung).
//

#if os(macOS)
import SwiftUI

/// Aktionen der Mailliste für die zusätzlichen Menübefehle des Mac. `nil`
/// = gerade nicht möglich; der Befehl ist dann ausgegraut.
struct MacMenuActions {
    /// Ordnerleiste ein- bzw. ausblenden.
    var toggleSidebar: (() -> Void)?
    /// `true`, wenn die Ordnerleiste gerade sichtbar ist (bestimmt die
    /// Beschriftung des Befehls).
    var isSidebarVisible = true
    /// Alle Mails der Liste auswählen.
    var selectAll: (() -> Void)?
    /// Postfachverwaltung öffnen.
    var showAccounts: (() -> Void)?
}

extension FocusedValues {
    /// Zusätzliche Aktionen der Mailliste der aktiven Szene; `nil` = keine Liste.
    @Entry var macMenuActions: MacMenuActions?
}

/// Zusätzliche Menübefehle des Mac.
struct MacMenuCommands: Commands {
    /// Aktionen der Mailliste der aktiven Szene.
    @FocusedValue(\.macMenuActions) private var actions
    /// Öffnet Fenster der App (hier: „Über Mailwerk“).
    @Environment(\.openWindow) private var openWindow

    /// Beschriftung des Befehls für die Ordnerleiste, passend zu ihrem
    /// Zustand.
    private var sidebarTitle: String {
        actions?.isSidebarVisible == false ? "Sidebar einblenden" : "Sidebar ausblenden"
    }

    /// Befehle in „Mailwerk“, „Darstellung“, „Bearbeiten“ und „Ablage“.
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Über Mailwerk") { openWindow(id: AboutWindow.id) }
        }
        CommandGroup(replacing: .sidebar) {
            Button(sidebarTitle) { actions?.toggleSidebar?() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(actions?.toggleSidebar == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Alle E-Mails auswählen") { actions?.selectAll?() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(actions?.selectAll == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Postfächer …") { actions?.showAccounts?() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(actions?.showAccounts == nil)
        }
    }
}
#endif
