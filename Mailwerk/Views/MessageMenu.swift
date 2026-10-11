//
//  MessageMenu.swift
//  Mailwerk
//
//  Zweck: Gemeinsames Aktionsmenü einer Mail. Dasselbe Menü erscheint in
//  der Mailansicht (Drei-Punkte-Menü) und in der Liste (Kontextmenü per
//  langem Drücken), damit beide gleich aussehen und sich gleich bedienen.
//
//  Aufbau (jeder Eintrag einzeilig):
//  - nur im Kontextmenü der Liste: „Auswählen“ (Mehrfachauswahl)
//  - Antworten, Allen antworten, Weiterleiten
//  - Kennzeichnung (Symbol zeigt, was der Tipp bewirkt), Gelesen bzw.
//    Ungelesen, Verschieben
//  - Untermenü „Spam / Vertrauen“: je ein Abschnitt für Adresse und
//    Domain mit der Überschrift des Werts, darunter „Blockieren“ und
//    „Vertrauen“
//  - zusätzliche Einträge des Aufrufers (in der Mailansicht Teilen,
//    Drucken, Anlagen lokal löschen), zuletzt „Mail löschen“
//
//  Das Menü löst nur aus; was geschieht, entscheidet der Aufrufer über
//  `MessageMenuAction`. Beschriftungen und Symbole kommen aus
//  `MessageMenuLabels`, damit sie an einer Stelle stehen und testbar sind.
//
//  Abgrenzung: Rückfragen und Meldungen → MessageActionDialogs; Ausführung
//  → MessageDetailView bzw. InboxView/InboxViewModel.
//
//  Abhängigkeiten: SwiftUI, FilterAddress, FilterEntryKind, ComposeKind.
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

/// Eine Spam-Aktion aus dem Menü: blockieren oder vertrauen, für Adresse
/// oder Domain.
struct SpamMenuRequest: Equatable {
    /// Blockieren oder Vertrauen.
    enum Kind: Equatable {
        case block, trust
    }

    /// Blockieren oder Vertrauen.
    let kind: Kind
    /// Adresse oder Domain.
    let entryKind: FilterEntryKind
    /// Einzutragende Adresse bzw. Domain.
    let value: String
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

    /// Eintrag „Mail löschen“.
    static let delete = Entry(title: "Mail löschen", systemImage: "trash.fill", accessibility: "Mail löschen")

    /// Eintrag im Spam-Untermenü. Der Wert steht als Abschnittsüberschrift
    /// darüber; der Eintrag selbst bleibt kurz.
    ///
    /// - Parameter request: Spam-Aktion.
    /// - Returns: Eintrag.
    static func spam(_ request: SpamMenuRequest) -> Entry {
        switch (request.kind, request.entryKind) {
        case (.block, .address):
            return Entry(title: "Blockieren", systemImage: "person.crop.circle.badge.xmark",
                         accessibility: "\(request.value) blockieren")
        case (.block, .domain):
            return Entry(title: "Blockieren", systemImage: "globe.badge.chevron.backward",
                         accessibility: "\(request.value) blockieren")
        case (.trust, .address):
            return Entry(title: "Vertrauen", systemImage: "person.crop.circle.badge.checkmark",
                         accessibility: "\(request.value) vertrauen")
        case (.trust, .domain):
            return Entry(title: "Vertrauen", systemImage: "globe",
                         accessibility: "\(request.value) vertrauen")
        }
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

    /// Untermenü „Spam / Vertrauen“ mit je einem Abschnitt für Adresse und
    /// Domain.
    ///
    /// - Parameter sender: Absender der Mail.
    /// - Returns: Untermenü.
    private func spamMenu(for sender: FilterAddress) -> some View {
        Menu {
            Section(sender.address) {
                spamButton(SpamMenuRequest(kind: .block, entryKind: .address, value: sender.address))
                spamButton(SpamMenuRequest(kind: .trust, entryKind: .address, value: sender.address))
            }
            Section(sender.domain) {
                spamButton(SpamMenuRequest(kind: .block, entryKind: .domain, value: sender.domain))
                spamButton(SpamMenuRequest(kind: .trust, entryKind: .domain, value: sender.domain))
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
        Button(role: role) {
            onAction(action)
        } label: {
            Label(entry.title, systemImage: entry.systemImage)
        }
        .accessibilityLabel(entry.accessibility)
    }
}
