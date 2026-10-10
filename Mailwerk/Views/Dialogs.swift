//
//  Dialogs.swift
//  Mailwerk
//
//  Zweck: Einheitliche Meldungen und Rückfragen für alle Ansichten.
//
//  - `AlertItem`: Hinweis oder Fehlermeldung mit „OK“.
//  - `ConfirmationRequest`: Rückfrage vor einer Aktion mit Bestätigen und
//    Abbrechen.
//
//  Beide erscheinen als `alert` – mittig, mit beiden Knöpfen sichtbar,
//  auf iPhone, iPad und Mac gleich. Ein `confirmationDialog` erschiene auf
//  iPad und Mac als Sprechblase an der auslösenden Stelle und blendete
//  „Abbrechen“ aus; für Rückfragen vor nicht umkehrbaren Aktionen ist das
//  zu wenig deutlich.
//
//  Jede Ansicht hält höchstens einen Zustand je Art und hängt je einen
//  Modifier an (`alertItem`, `confirmationRequest`). Mehrere Dialoge an
//  derselben Ansicht, aus einem Menü heraus geöffnet, gelten in SwiftUI als
//  unzuverlässig – so ist auch klar, welcher Dialog gerade offen ist.
//
//  Abgrenzung: Eingabedialoge (z. B. „Neuer Ordner“ mit Textfeld) und
//  Sheets bleiben in ihren Ansichten.
//
//  Abhängigkeiten: SwiftUI.
//

import SwiftUI

/// Hinweis oder Fehlermeldung mit „OK“.
struct AlertItem: Identifiable {
    /// Kennung für SwiftUI.
    let id = UUID()
    /// Überschrift.
    let title: String
    /// Meldungstext.
    let message: String
    /// Wird nach „OK“ ausgeführt (z. B. Fenster schließen); sonst `nil`.
    var onDismiss: (() -> Void)?

    /// Legt eine Meldung an.
    ///
    /// - Parameters:
    ///   - title: Überschrift.
    ///   - message: Meldungstext.
    ///   - onDismiss: Aktion nach „OK“.
    init(title: String, message: String, onDismiss: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.onDismiss = onDismiss
    }

    /// Meldung zu einem Fehler.
    ///
    /// - Parameters:
    ///   - title: Überschrift, z. B. „Löschen fehlgeschlagen“.
    ///   - error: Aufgetretener Fehler; sein Text wird angezeigt.
    /// - Returns: Fertige Meldung.
    static func failure(_ title: String, _ error: Error) -> AlertItem {
        AlertItem(title: title, message: error.localizedDescription)
    }
}

/// Rückfrage vor einer Aktion.
struct ConfirmationRequest: Identifiable {
    /// Kennung für SwiftUI. Bleibt für dieselbe Rückfrage gleich, auch wenn
    /// sie neu gebildet wird (z. B. aus einer Warteschlange).
    let id: String
    /// Frage, z. B. „Mail löschen?“.
    let title: String
    /// Erklärung der Folgen.
    let message: String
    /// Beschriftung des bestätigenden Knopfs, z. B. „Löschen“.
    let confirmLabel: String
    /// `true` = bestätigender Knopf rot (nicht umkehrbare Aktion).
    let isDestructive: Bool
    /// Beschriftung des abbrechenden Knopfs.
    let cancelLabel: String
    /// Wird nach dem Bestätigen ausgeführt.
    let onConfirm: () -> Void
    /// Wird nach dem Abbrechen ausgeführt; sonst `nil`.
    let onCancel: (() -> Void)?

    /// Legt eine Rückfrage an.
    ///
    /// - Parameters:
    ///   - id: Feste Kennung; ohne Angabe eine neue.
    ///   - title: Frage.
    ///   - message: Erklärung der Folgen.
    ///   - confirmLabel: Beschriftung des bestätigenden Knopfs.
    ///   - isDestructive: Bestätigung rot darstellen.
    ///   - cancelLabel: Beschriftung des abbrechenden Knopfs.
    ///   - onCancel: Aktion nach dem Abbrechen.
    ///   - onConfirm: Aktion nach dem Bestätigen.
    init(
        id: String = UUID().uuidString,
        title: String,
        message: String,
        confirmLabel: String,
        isDestructive: Bool = true,
        cancelLabel: String = "Abbrechen",
        onCancel: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.isDestructive = isDestructive
        self.cancelLabel = cancelLabel
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }
}

extension View {
    /// Zeigt eine Meldung, solange `item` gesetzt ist.
    ///
    /// Verarbeitung: „OK“ schließt die Meldung (setzt `item` zurück) und
    /// führt danach `onDismiss` aus.
    ///
    /// - Parameter item: Bindung an die Meldung der Ansicht.
    /// - Returns: Ansicht mit Meldung.
    func alertItem(_ item: Binding<AlertItem?>) -> some View {
        alert(
            item.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { current in
            Button("OK") { current.onDismiss?() }
        } message: { current in
            Text(current.message)
        }
    }

    /// Zeigt eine Rückfrage, solange `request` gesetzt ist.
    ///
    /// Verarbeitung: Beide Knöpfe schließen die Rückfrage (setzt `request`
    /// zurück) und führen danach ihre Aktion aus.
    ///
    /// - Parameter request: Bindung an die Rückfrage der Ansicht.
    /// - Returns: Ansicht mit Rückfrage.
    func confirmationRequest(_ request: Binding<ConfirmationRequest?>) -> some View {
        alert(
            request.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { request.wrappedValue != nil },
                set: { if !$0 { request.wrappedValue = nil } }
            ),
            presenting: request.wrappedValue
        ) { current in
            Button(current.cancelLabel, role: .cancel) { current.onCancel?() }
            Button(current.confirmLabel, role: current.isDestructive ? .destructive : nil) {
                current.onConfirm()
            }
        } message: { current in
            Text(current.message)
        }
    }
}
