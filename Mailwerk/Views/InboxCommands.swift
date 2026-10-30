//
//  InboxCommands.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 22.10.2026
//  Geändert: 27.10.2026
//
//  Zweck: Menübefehle und Tastaturkürzel der Mailliste auf iPhone (mit
//  Tastatur), iPad und Mac. Sie stehen in der Menüleiste –
//  „Neue E-Mail“ im Menü „Ablage“, die übrigen im eigenen Menü „Postfach“ –
//  und wirken mit Tastatur:
//  - ⌘N neue E-Mail, ⌘R aktualisieren, ⌘F suchen
//  - im Spaltenlayout: ⌘⌫ geöffnete E-Mail löschen (mit Rückfrage), Esc
//    beendet das Vollbild (nur iPad – der Mac hat kein Vollbild der
//    Mailansicht, Esc bleibt dort Suchfeld und Sheets); „Nächste/Vorige
//    E-Mail“ ohne Kürzel – die Pfeiltasten bewegen die Auswahl der Liste
//    selbst (InboxView)
//
//  Szenenbefehle sind der Weg, den iPadOS für Tastaturkürzel vorsieht;
//  Kürzel an unsichtbaren Knöpfen in einer Ansicht kommen dort nicht an.
//  Die Befehle wissen nichts von der Liste: Die Mailliste stellt ihre
//  Aktionen als `InboxCommandActions` bereit (`focusedSceneValue`); eine
//  fehlende Aktion graut den Befehl samt Kürzel aus.
//
//  „Neue E-Mail“ ersetzt den Systembefehl „Neues Fenster“ (⌘N), wie in
//  Apple Mail. Mailwerk ist auf ein Fenster ausgelegt – Liste und Zustand
//  gibt es je App nur einmal.
//
//  Abgrenzung: Aktionen selbst → InboxView; zusätzliche Menübefehle nur
//  des Mac (Darstellung, Bearbeiten, Postfächer) → MacMenuCommands. Auf dem
//  Mac tragen die Kürzel allein die Menübefehle – Knöpfe der Kopfleisten
//  setzen keine eigenen, sonst kollidierten sie.
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

/// Aktionen der Mailliste für Menübefehle und Tastaturkürzel. `nil` =
/// gerade nicht möglich; der Befehl ist dann ausgegraut.
struct InboxCommandActions {
    /// Neue E-Mail verfassen.
    var newMail: (() -> Void)?
    /// Gezeigte Ansicht abrufen.
    var refresh: (() -> Void)?
    /// Suchfeld öffnen.
    var search: (() -> Void)?
    /// Nächste E-Mail der Liste öffnen (Spaltenlayout).
    var nextMail: (() -> Void)?
    /// Vorige E-Mail der Liste öffnen (Spaltenlayout).
    var previousMail: (() -> Void)?
    /// Geöffnete E-Mail löschen, mit Rückfrage (Spaltenlayout).
    var deleteMail: (() -> Void)?
    /// Vollbild der Mailansicht beenden.
    var exitFullscreen: (() -> Void)?

    /// Liefert die Aktion nur, wenn sie gerade möglich ist.
    ///
    /// - Parameters:
    ///   - isEnabled: `true`, wenn die Aktion möglich ist.
    ///   - action: Auszuführende Aktion.
    /// - Returns: `action` oder `nil`.
    static func enabled(_ isEnabled: Bool, _ action: @escaping () -> Void) -> (() -> Void)? {
        isEnabled ? action : nil
    }
}

extension FocusedValues {
    /// Aktionen der Mailliste der aktiven Szene; `nil` = keine Liste.
    @Entry var inboxCommands: InboxCommandActions?
}

/// Menübefehle der Mailliste.
struct InboxCommands: Commands {
    /// Aktionen der Mailliste der aktiven Szene.
    @FocusedValue(\.inboxCommands) private var actions

    /// „Neue E-Mail“ im Menü „Ablage“, die übrigen Befehle im Menü „Postfach“.
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            command("Neue E-Mail", actions?.newMail)
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Postfach") {
            command("Aktualisieren", actions?.refresh)
                .keyboardShortcut("r", modifiers: .command)
            command("Suchen", actions?.search)
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            // Ohne Kürzel: ↓/↑ bewegt die Auswahl der Liste selbst
            // (Tastaturnavigation des Systems, siehe InboxView).
            command("Nächste E-Mail", actions?.nextMail)
            command("Vorige E-Mail", actions?.previousMail)
            command("E-Mail löschen", actions?.deleteMail)
                .keyboardShortcut(.delete, modifiers: .command)
            #if !os(macOS)
            Divider()
            command("Vollbild beenden", actions?.exitFullscreen)
                .keyboardShortcut(.escape, modifiers: [])
            #endif
        }
    }

    /// Menübefehl, ausgegraut ohne Aktion.
    ///
    /// - Parameters:
    ///   - title: Beschriftung.
    ///   - action: Aktion; `nil` = ausgegraut.
    /// - Returns: Der Befehl.
    private func command(_ title: String, _ action: (() -> Void)?) -> some View {
        Button(title) { action?() }
            .disabled(action == nil)
    }
}
