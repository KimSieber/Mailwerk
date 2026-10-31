//
//  MessageMenu.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 12.10.2026
//  Geändert: 31.10.2026
//
//  Zweck: Gemeinsames Aktionsmenü einer Mail. Dasselbe Menü erscheint in
//  der Mailansicht (Drei-Punkte-Menü) und in der Liste (Kontextmenü per
//  langem Drücken), damit beide gleich aussehen und sich gleich bedienen.
//
//  Aufbau (jeder Eintrag einzeilig):
//  - nur im Kontextmenü der Liste auf iPhone/iPad: „Auswählen“
//    (Mehrfachauswahl; auf dem Mac wählt ⌘- bzw. ⇧-Klick)
//  - Antworten, Allen antworten, Weiterleiten
//  - Kennzeichnung (Symbol zeigt, was der Tipp bewirkt), Gelesen bzw.
//    Ungelesen, Verschieben
//  - Untermenü „Spam / Vertrauen“: je ein Abschnitt für Adresse, Domain
//    und – nur bei einer Subdomain – Hauptdomain, mit der Überschrift des
//    Werts in der Schreibweise der Listen (`a@mail.firma.de`,
//    `*mail.firma.de`, `*firma.de`), darunter „Blockieren“ und „Vertrauen“
//  - zusätzliche Einträge des Aufrufers (in der Mailansicht Teilen,
//    Drucken, Anlagen lokal löschen), zuletzt „Mail löschen“
//
//  Für mehrere ausgewählte Mails (Kontextmenü der Liste auf dem Mac) gibt
//  es ein verkürztes Menü (`MessageSelectionMenuItems`): Kennzeichnung,
//  Gelesen bzw. Ungelesen, Verschieben, Löschen – dieselben Sammelaktionen
//  wie die Befehlsleiste im Auswahlmodus von iPhone und iPad.
//
//  Die Mailansicht hängt darunter noch einen eigenen Abschnitt
//  „Originalquelle“ an (Beschriftung hier in `MessageMenuLabels.source`);
//  im Kontextmenü der Liste fehlt er bewusst.
//
//  Das Menü löst nur aus; was geschieht, entscheidet der Aufrufer über
//  `MessageMenuAction`. Beschriftungen und Symbole kommen aus
//  `MessageMenuLabels`, damit sie an einer Stelle stehen und testbar sind.
//
//  Abgrenzung: Rückfragen und Meldungen → MessageActionDialogs; Ausführung
//  → MessageDetailView bzw. InboxView/InboxViewModel; Spam-Aktion und
//  Abschnitte des Untermenüs → SpamMenuChoice.
//
//  Abhängigkeiten: SwiftUI, FilterAddress, SpamMenuRequest, SpamMenuSection,
//  ComposeKind, MessageSelection, MessageListItem.
//

import SwiftUI

/// Was das Menü über die Mail wissen muss.
struct MessageMenuContext: Equatable {
    /// `true` = Mail ist ungelesen.
    let isUnread: Bool
    /// `true` = Mail ist gekennzeichnet.
    let isFlagged: Bool
    /// Absender für die Spam-Einträge; `nil` = nicht auswertbar, das
    /// Untermenü entfällt dann.
    let sender: FilterAddress?
}

extension MessageMenuContext {
    /// Zustand aus einem Listeneintrag.
    ///
    /// - Parameter item: Listeneintrag.
    init(_ item: MessageListItem) {
        self.init(
            isUnread: item.isUnread,
            isFlagged: item.isFlagged,
            sender: FilterAddress.sender(fromHeader: item.from)
        )
    }
}

/// Im Menü gewählte Aktion.
enum MessageMenuAction: Equatable {
    /// Mehrfachauswahl beginnen, diese Mail ist ausgewählt.
    case select
    /// Antworten, Allen antworten oder Weiterleiten.
    case reply(ComposeKind)
    /// Kennzeichnung umschalten.
    case toggleFlag
    /// Gelesen/ungelesen umschalten.
    case toggleRead
    /// Ordnerwahl zum Verschieben öffnen.
    case move
    /// Spam-Aktion (mit Rückfrage).
    case spam(SpamMenuRequest)
    /// Mail löschen (mit Rückfrage).
    case delete
}

/// Beschriftungen und Symbole der Menüeinträge.
enum MessageMenuLabels {
    /// Ein Eintrag: sichtbarer Text, Symbol und ausführliche Bezeichnung
    /// für VoiceOver und Sprachsteuerung.
    struct Entry: Equatable {
        /// Sichtbarer, kurzer Text.
        let title: String
        /// SF-Symbol.
        let systemImage: String
        /// Ausführliche Bezeichnung für Bedienungshilfen.
        let accessibility: String
    }

    /// Eintrag „Kennzeichnung“: Der Text bleibt gleich, das Symbol zeigt,
    /// was der Tipp bewirkt.
    ///
    /// - Parameter isFlagged: Aktueller Zustand.
    /// - Returns: Eintrag.
    static func flag(isFlagged: Bool) -> Entry {
        isFlagged
            ? Entry(title: "Kennzeichnung", systemImage: "flag.slash", accessibility: "Kennzeichnung entfernen")
            : Entry(title: "Kennzeichnung", systemImage: "flag", accessibility: "Kennzeichnen")
    }

    /// Eintrag „Gelesen“ bzw. „Ungelesen“ – benannt nach dem Zustand, den
    /// der Tipp herstellt.
    ///
    /// - Parameter isUnread: Aktueller Zustand.
    /// - Returns: Eintrag.
    static func read(isUnread: Bool) -> Entry {
        isUnread
            ? Entry(title: "Gelesen", systemImage: "envelope.open", accessibility: "Als gelesen markieren")
            : Entry(title: "Ungelesen", systemImage: "envelope.badge", accessibility: "Als ungelesen markieren")
    }

    /// Eintrag „Auswählen“ (nur im Kontextmenü der Liste).
    static let select = Entry(title: "Auswählen", systemImage: "checkmark.circle", accessibility: "Mehrere Mails auswählen")

    /// Eintrag „Verschieben“.
    static let move = Entry(title: "Verschieben", systemImage: "folder", accessibility: "In Ordner verschieben")

    /// Eintrag „Mails löschen“ für mehrere ausgewählte Mails.
    static let deleteSelection = Entry(title: "Mails löschen", systemImage: "trash.fill", accessibility: "Ausgewählte Mails löschen")

    /// Eintrag „Mail löschen“.
    static let delete = Entry(title: "Mail löschen", systemImage: "trash.fill", accessibility: "Mail löschen")

    /// Eintrag „Originalquelle“ (nur in der Mailansicht, ganz unten).
    static let source = Entry(title: "Originalquelle", systemImage: "doc.plaintext", accessibility: "Originalquelle der Mail anzeigen")

    /// Eintrag im Spam-Untermenü. Der Wert steht als Abschnittsüberschrift
    /// darüber; der Eintrag selbst bleibt kurz.
    ///
    /// - Parameter request: Spam-Aktion.
    /// - Returns: Eintrag.
    static func spam(_ request: SpamMenuRequest) -> Entry {
        Entry(
            title: SpamMenuTexts.confirmLabel(request),
            systemImage: SpamMenuTexts.systemImage(request),
            accessibility: "\(request.displayValue) \(request.kind == .block ? "blockieren" : "vertrauen")"
        )
    }
}

/// Antworten, Allen antworten und Weiterleiten – im Menü und im
/// Antworten-Knopf der Mailansicht.
struct ReplyMenuButtons: View {
    /// Empfängt die gewählte Aktion.
    let onAction: (MessageMenuAction) -> Void

    /// Die drei Einträge.
    var body: some View {
        Button {
            onAction(.reply(.reply))
        } label: {
            Label("Antworten", systemImage: "arrowshape.turn.up.left")
        }
        Button {
            onAction(.reply(.replyAll))
        } label: {
            Label("Allen antworten", systemImage: "arrowshape.turn.up.left.2")
        }
        Button {
            onAction(.reply(.forward))
        } label: {
            Label("Weiterleiten", systemImage: "arrowshape.turn.up.right")
        }
    }
}

/// Einträge des Aktionsmenüs; einsetzbar in `Menu` und `contextMenu`.
struct MessageMenuItems<Extra: View>: View {
    /// Zustand der Mail.
    let context: MessageMenuContext
    /// `true` = „Auswählen“ als erster Eintrag (Kontextmenü der Liste).
    var showsSelect = false
    /// Empfängt die gewählte Aktion.
    let onAction: (MessageMenuAction) -> Void
    /// Zusätzliche Einträge vor „Mail löschen“ (z. B. Teilen, Drucken).
    @ViewBuilder let extra: () -> Extra

    /// Abschnitte des Menüs.
    var body: some View {
        if showsSelect {
            Section {
                entryButton(MessageMenuLabels.select, action: .select)
            }
        }

        Section {
            ReplyMenuButtons(onAction: onAction)
        }

        Section {
            entryButton(MessageMenuLabels.flag(isFlagged: context.isFlagged), action: .toggleFlag)
            entryButton(MessageMenuLabels.read(isUnread: context.isUnread), action: .toggleRead)
            entryButton(MessageMenuLabels.move, action: .move)
        }

        if let sender = context.sender {
            Section {
                spamMenu(for: sender)
            }
        }

        Section {
            extra()
            entryButton(MessageMenuLabels.delete, action: .delete, role: .destructive)
        }
    }

    /// Untermenü „Spam / Vertrauen“ mit je einem Abschnitt für Adresse,
    /// Domain und gegebenenfalls Hauptdomain (SpamMenuSection).
    ///
    /// - Parameter sender: Absender der Mail.
    /// - Returns: Untermenü.
    private func spamMenu(for sender: FilterAddress) -> some View {
        Menu {
            ForEach(SpamMenuSection.sections(for: sender)) { section in
                Section(section.title) {
                    spamButton(SpamMenuRequest(kind: .block, entryKind: section.entryKind, value: section.value))
                    spamButton(SpamMenuRequest(kind: .trust, entryKind: section.entryKind, value: section.value))
                }
            }
        } label: {
            Label("Spam / Vertrauen", systemImage: "shield")
        }
    }

    /// Eintrag im Spam-Untermenü.
    ///
    /// - Parameter request: Spam-Aktion.
    /// - Returns: Knopf.
    private func spamButton(_ request: SpamMenuRequest) -> some View {
        entryButton(MessageMenuLabels.spam(request), action: .spam(request))
    }

    /// Knopf aus Beschriftung und Aktion.
    ///
    /// - Parameters:
    ///   - entry: Text, Symbol und Bezeichnung für Bedienungshilfen.
    ///   - action: Ausgelöste Aktion.
    ///   - role: Rolle des Knopfs (z. B. rot für Löschen).
    /// - Returns: Knopf.
    private func entryButton(
        _ entry: MessageMenuLabels.Entry,
        action: MessageMenuAction,
        role: ButtonRole? = nil
    ) -> some View {
        MenuEntryButton(entry: entry, role: role) { onAction(action) }
    }
}

/// Einträge des Kontextmenüs für mehrere ausgewählte Mails (Mac).
///
/// Die Symbole von Kennzeichnung und Gelesen zeigen wie in der
/// Befehlsleiste, was der Klick bei dieser Auswahl bewirkt (Regeln in
/// MessageSelection). Verschieben ist gesperrt, wenn die Mails aus
/// mehreren Postfächern stammen.
struct MessageSelectionMenuItems: View {
    /// Ausgewählte Mails (mindestens zwei).
    let items: [MessageListItem]
    /// Empfängt die gewählte Aktion: `.toggleFlag`, `.toggleRead`, `.move`
    /// oder `.delete`.
    let onAction: (MessageMenuAction) -> Void

    /// Abschnitte des Menüs.
    var body: some View {
        Section {
            entryButton(
                MessageMenuLabels.flag(isFlagged: MessageSelection.flagChange(for: items) == .flagged(false)),
                action: .toggleFlag
            )
            entryButton(
                MessageMenuLabels.read(isUnread: MessageSelection.readChange(for: items) == .read(true)),
                action: .toggleRead
            )
            entryButton(MessageMenuLabels.move, action: .move)
                .disabled(!MessageSelection.canMove(items))
        }
        Section {
            entryButton(MessageMenuLabels.deleteSelection, action: .delete, role: .destructive)
        }
    }

    /// Ein Eintrag des Menüs.
    ///
    /// - Parameters:
    ///   - entry: Beschriftung und Symbol.
    ///   - action: Auszulösende Aktion.
    ///   - role: Rolle des Knopfs (z. B. destruktiv).
    /// - Returns: Knopf.
    private func entryButton(
        _ entry: MessageMenuLabels.Entry,
        action: MessageMenuAction,
        role: ButtonRole? = nil
    ) -> some View {
        MenuEntryButton(entry: entry, role: role) { onAction(action) }
    }
}

/// Knopf eines Menüeintrags: Text und Symbol, dazu die ausführliche
/// Bezeichnung für Bedienungshilfen – für beide Menüs gleich.
private struct MenuEntryButton: View {
    /// Beschriftung und Symbol.
    let entry: MessageMenuLabels.Entry
    /// Rolle des Knopfs (z. B. destruktiv); `nil` = gewöhnlich.
    var role: ButtonRole?
    /// Auszuführende Aktion.
    let action: () -> Void

    /// Der Knopf.
    var body: some View {
        Button(role: role, action: action) {
            Label(entry.title, systemImage: entry.systemImage)
        }
        .accessibilityLabel(entry.accessibility)
    }
}
