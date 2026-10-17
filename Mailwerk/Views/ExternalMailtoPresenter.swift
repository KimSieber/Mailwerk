//
//  ExternalMailtoPresenter.swift
//  Mailwerk
//
//  Zweck: Öffnet für einen mailto:-Link von außen das Verfassen-Fenster
//  bzw. zeigt den Hinweis „Bitte zuerst ein Postfach einrichten“, und
//  stellt den Modifier bereit, mit dem sich Fenster (Blätter) als offen
//  melden.
//
//  Absender ist immer das Standard-Postfach – ein Link von außen hat
//  keinen Bezug zur gerade gezeigten Ansicht. Ohne Standard-Postfach
//  bleibt der Absender leer (wie bei einer neuen Mail in „Alle
//  Eingänge“).
//
//  Zeitpunkt: Erst wenn kein Fenster mehr offen ist, und mit kurzer
//  Verzögerung. Das Schließen eines Blatts ist noch nicht abgeschlossen,
//  wenn es sich abmeldet; ein sofort angefordertes neues Blatt würde von
//  SwiftUI übergangen. Ist nach der Wartezeit wieder ein Fenster offen,
//  wartet der Link weiter.
//
//  Abgrenzung: Regeln (wartender Link, Zähler) → ExternalMailtoRouter;
//  Verfassen-Fenster → ComposeView.
//
//  Abhängigkeiten: SwiftUI, ExternalMailtoRouter, AccountStore,
//  ComposeView, Dialogs (AlertItem).
//

import SwiftUI

extension View {
    /// Meldet diese Ansicht als offenes Fenster, solange sie sichtbar ist.
    ///
    /// Gehört an den Inhalt jedes Blatts (`sheet`), und zwar außen um die
    /// ganze Ansicht, damit Navigation innerhalb des Blatts nicht als
    /// Schließen zählt.
    ///
    /// - Returns: Ansicht mit An- und Abmeldung beim Router.
    func countsAsOpenWindow() -> some View {
        modifier(OpenWindowTracker())
    }

    /// Öffnet für mailto:-Links von außen das Verfassen-Fenster.
    ///
    /// - Parameters:
    ///   - accountStore: Quelle für Postfächer und Passwörter.
    ///   - onSent: Rückruf nach erfolgreichem Versand.
    /// - Returns: Ansicht mit Verfassen-Fenster und Hinweis.
    func externalMailtoPresenter(
        accountStore: AccountStore,
        onSent: @escaping () -> Void
    ) -> some View {
        modifier(ExternalMailtoPresenter(accountStore: accountStore, onSent: onSent))
    }
}

/// Meldet ein Fenster beim Router an und ab.
private struct OpenWindowTracker: ViewModifier {
    /// Ansicht ist gerade angemeldet – verhindert doppeltes Zählen.
    @State private var isCounted = false

    /// Meldet beim Erscheinen an und beim Verschwinden ab.
    ///
    /// - Parameter content: Inhalt des Blatts.
    /// - Returns: Unveränderte Ansicht.
    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isCounted else { return }
                isCounted = true
                ExternalMailtoRouter.shared.windowDidAppear()
            }
            .onDisappear {
                guard isCounted else { return }
                isCounted = false
                ExternalMailtoRouter.shared.windowDidDisappear()
            }
    }
}

/// Zeigt Verfassen-Fenster bzw. Hinweis für Links von außen.
private struct ExternalMailtoPresenter: ViewModifier {
    /// Quelle für Postfächer und Passwörter.
    let accountStore: AccountStore
    /// Rückruf nach erfolgreichem Versand.
    let onSent: () -> Void

    /// Vermittler der Links.
    private let router = ExternalMailtoRouter.shared
    /// Offenes Verfassen-Fenster für einen Link; `nil` = keins.
    @State private var request: ExternalComposeRequest?
    /// Hinweis „kein Postfach“; `nil` = keiner.
    @State private var notice: AlertItem?

    /// Wartezeit, bis ein gerade geschlossenes Blatt ganz verschwunden ist.
    private static let presentationDelay: Duration = .milliseconds(500)

    /// Hängt Verfassen-Fenster und Hinweis an die Ansicht.
    ///
    /// Verarbeitung: Sobald ein Link wartet und kein Fenster offen ist,
    /// wird nach kurzer Wartezeit erneut geprüft und der Link abgeholt.
    ///
    /// - Parameter content: Wurzelansicht.
    /// - Returns: Ansicht mit Blatt und Hinweis.
    func body(content: Content) -> some View {
        content
            .onChange(of: router.isReadyToPresent, initial: true) { _, isReady in
                guard isReady else { return }
                Task { await presentWhenSettled() }
            }
            .sheet(item: $request) { request in
                // Absender: immer das Standard-Postfach (senderAccountID nil).
                ComposeView(
                    accountStore: accountStore,
                    kind: .new,
                    mailto: request.link,
                    onSent: onSent
                )
                .countsAsOpenWindow()
            }
            .alertItem($notice)
    }

    /// Holt den wartenden Link nach der Wartezeit ab und zeigt ihn an.
    ///
    /// Verarbeitung: Ist nach der Wartezeit wieder ein Fenster offen,
    /// geschieht nichts; der Link wartet auf das nächste Schließen.
    private func presentWhenSettled() async {
        try? await Task.sleep(for: Self.presentationDelay)
        switch router.takePending(hasAccounts: !accountStore.accounts.isEmpty) {
        case .compose(let next):
            request = next
        case .noAccount:
            notice = AlertItem(
                title: "Kein Postfach eingerichtet",
                message: "Bitte zuerst ein Postfach einrichten, um eine E-Mail zu schreiben."
            )
        case nil:
            break
        }
    }
}
