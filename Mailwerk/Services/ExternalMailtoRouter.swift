//
//  ExternalMailtoRouter.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 18.10.2026
//  Geändert: 18.10.2026
//
//  Zweck: Nimmt mailto:-Links an, die das System von außen an Mailwerk
//  übergibt (Safari, Kontakte, andere Apps), und entscheidet, wann daraus
//  ein Verfassen-Fenster wird.
//
//  Regeln:
//  - Gemerkt wird immer nur der zuletzt eingegangene Link; ein neuer Link
//    ersetzt einen noch wartenden.
//  - Ist gerade ein Fenster (Blatt) offen, wartet der Link, bis alle
//    Fenster geschlossen sind. So geht keine angefangene Mail verloren.
//  - Ohne eingerichtetes Postfach wird kein Verfassen-Fenster geöffnet,
//    sondern ein Hinweis angezeigt; der Link wird dabei verworfen.
//  - Ein Link ohne Inhalt („mailto:“) öffnet eine leere neue Mail.
//
//  Offene Fenster melden sich über `windowDidAppear`/`windowDidDisappear`
//  an und ab (Modifier `countsAsOpenWindow`, ExternalMailtoPresenter.swift).
//  Ein Zähler statt eines Schalters, weil Fenster verschachtelt sein
//  können (z. B. „Postfach hinzufügen“ über der Postfachliste).
//
//  Abgrenzung: Zerlegen des Links → MailtoLink; Anzeige des Fensters und
//  des Hinweises → ExternalMailtoPresenter; Annahme vom System →
//  MailwerkApp (`onOpenURL`).
//
//  Abhängigkeiten: Foundation, Observation, MailtoLink.
//

import Foundation
import Observation

/// Auftrag, aus einem Link von außen ein Verfassen-Fenster zu öffnen.
struct ExternalComposeRequest: Identifiable, Equatable {
    /// Kennung für das Blatt; je Auftrag neu.
    let id = UUID()
    /// Inhalt des Links; `nil` = Link ohne Inhalt, leere neue Mail.
    let link: MailtoLink?
}

/// Was beim Abholen eines wartenden Links zu tun ist.
enum ExternalMailtoOutcome: Equatable {
    /// Verfassen-Fenster mit dem Auftrag öffnen.
    case compose(ExternalComposeRequest)
    /// Kein Postfach eingerichtet – Hinweis zeigen.
    case noAccount
}

/// Vermittelt mailto:-Links von außen an das Verfassen-Fenster.
@Observable
final class ExternalMailtoRouter {
    /// Gemeinsame Instanz der App.
    static let shared = ExternalMailtoRouter()

    /// Wartender Auftrag; `nil` = keiner.
    private(set) var pending: ExternalComposeRequest?
    /// Anzahl der gerade offenen Fenster (Blätter).
    private(set) var openWindowCount = 0

    /// Ein Auftrag wartet und kein Fenster ist offen.
    var isReadyToPresent: Bool {
        pending != nil && openWindowCount == 0
    }

    /// Nimmt einen Link vom System an.
    ///
    /// Verarbeitung: Nur Links mit Schema mailto werden angenommen. Ein
    /// angenommener Link ersetzt einen noch wartenden.
    ///
    /// - Parameter url: Vom System übergebener Link.
    /// - Returns: `true`, wenn der Link angenommen wurde.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "mailto" else { return false }
        pending = ExternalComposeRequest(link: MailtoLink(url: url))
        return true
    }

    /// Meldet, dass ein Fenster erschienen ist.
    func windowDidAppear() {
        openWindowCount += 1
    }

    /// Meldet, dass ein Fenster geschlossen wurde.
    ///
    /// Verarbeitung: Der Zähler fällt nie unter null, auch wenn eine
    /// Abmeldung doppelt käme.
    func windowDidDisappear() {
        openWindowCount = max(0, openWindowCount - 1)
    }

    /// Holt den wartenden Auftrag ab, sofern er jetzt dran ist.
    ///
    /// Verarbeitung: Nur wenn kein Fenster offen ist. Der Auftrag wird
    /// dabei entfernt – auch im Fall „kein Postfach“.
    ///
    /// - Parameter hasAccounts: Mindestens ein Postfach ist eingerichtet.
    /// - Returns: Was zu tun ist, oder `nil`, wenn nichts ansteht.
    func takePending(hasAccounts: Bool) -> ExternalMailtoOutcome? {
        guard isReadyToPresent, let request = pending else { return nil }
        pending = nil
        return hasAccounts ? .compose(request) : .noAccount
    }
}
