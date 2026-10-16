//
//  MessageDetailHeader.swift
//  Mailwerk
//
//  Zweck: Kopfbereich der Mailansicht – Betreff mit Kennzeichen, Absender,
//  Empfänger, Kopie, „Antwort an“ und Datum – sowie der schmale Hinweis
//  „Externe Inhalte blockiert“ mit dem Knopf „Laden“.
//
//  Betreff: lässt sich markieren (Mac) bzw. per langem Drücken kopieren
//  (iPhone/iPad).
//
//  Personen: wie in Apple Mail jede als eigenes antippbares Element – der
//  Name (ohne Namen die Adresse) in der Akzentfarbe mit „›“. Ein Tipp
//  öffnet ein Menü mit der Adresse als Überschrift und „Adresse kopieren“,
//  „Suchen nach …“, „Kontaktkarte anzeigen“ und „Neue E-Mail an …“. Die
//  Bezeichnungen „Von/An/Kopie/Antwort an“ gehören nicht dazu. „Antwort
//  an“ erscheint nur, wenn es vom Absender abweicht.
//
//  „Suchen nach …“ übergibt die Person an die Mailansicht (`onSearch`), die
//  sich schließt und in der Liste die Suche mit der Person als Marke
//  startet. Ohne Liste (`onSearch` = `nil`) entfällt der Eintrag.
//
//  Abgrenzung: Inhalt, Menü und Aktionen der Mail, Kontaktkarte und neue
//  Mail → MessageDetailView; Anhänge → MessageAttachmentList; Zerlegen der
//  Adressen → HeaderPerson.
//
//  Abhängigkeiten: SwiftUI, UIKit (iOS) bzw. AppKit (macOS) für die
//  Zwischenablage, CachedMessage, HeaderPerson, FlowLayout.
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Kopfbereich

/// Kopfbereich einer Mail.
struct MessageDetailHeader: View {
    /// Angezeigte Mail.
    let message: CachedMessage
    /// Kennzeichnung (von der Ansicht nachgeführt).
    let isFlagged: Bool
    /// „Neue E-Mail an …“ aus dem Menü einer Person.
    var onNewMail: (HeaderPerson) -> Void = { _ in }
    /// „Kontaktkarte anzeigen“ aus dem Menü einer Person.
    var onContactCard: (HeaderPerson) -> Void = { _ in }
    /// „Suchen nach …“ aus dem Menü einer Person; `nil` = Eintrag entfällt.
    var onSearch: ((HeaderPerson) -> Void)?

    /// Betreff, Kennzeichnung, Personen und Datum.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(message.subject)
                    .font(.title2)
                    .bold()
                    .textSelection(.enabled)
                if isFlagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                peopleRow("Von", HeaderPerson.list([message.from]))
                peopleRow("An", HeaderPerson.list(toAddresses))
                peopleRow("Kopie", HeaderPerson.list(message.headers.ccList))
                peopleRow("Antwort an", HeaderPerson.replyTo(message.headers.replyToList, sender: message.from))
            }
            if let date = message.date {
                Text(date, format: .dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits).year().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Empfänger: aus den gespeicherten Kopfzeilen, bei älteren Mails ohne
    /// diese Liste ersatzweise das Feld „An“.
    private var toAddresses: [String] {
        message.headers.toList.isEmpty ? [message.to] : message.headers.toList
    }

    /// Zeile mit Bezeichnung und den Personen; entfällt ohne Personen.
    ///
    /// - Parameters:
    ///   - label: Bezeichnung, z. B. „Von“.
    ///   - people: Personen der Zeile.
    /// - Returns: Die Zeile oder nichts.
    @ViewBuilder
    private func peopleRow(_ label: String, _ people: [HeaderPerson]) -> some View {
        if !people.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(label):")
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    ForEach(people) { person in
                        HeaderPersonMenu(
                            person: person,
                            onNewMail: onNewMail,
                            onContactCard: onContactCard,
                            onSearch: onSearch
                        )
                    }
                }
            }
            .font(.subheadline)
        }
    }
}

// MARK: - Person mit Menü

/// Eine Person im Mailkopf: Name mit „›“, ein Tipp öffnet das Menü.
struct HeaderPersonMenu: View {
    /// Gezeigte Person.
    let person: HeaderPerson
    /// „Neue E-Mail an …“.
    let onNewMail: (HeaderPerson) -> Void
    /// „Kontaktkarte anzeigen“.
    let onContactCard: (HeaderPerson) -> Void
    /// „Suchen nach …“; `nil` = Eintrag entfällt.
    let onSearch: ((HeaderPerson) -> Void)?

    /// Name als Menüknopf.
    var body: some View {
        Menu {
            Section {
                Button {
                    copyAddress()
                } label: {
                    Label("Adresse kopieren", systemImage: "doc.on.doc")
                }
                if let onSearch {
                    Button {
                        onSearch(person)
                    } label: {
                        Label("Suchen nach „\(person.address)“", systemImage: "magnifyingglass")
                    }
                }
                Button {
                    onContactCard(person)
                } label: {
                    Label("Kontaktkarte anzeigen", systemImage: "person.crop.circle")
                }
                Button {
                    onNewMail(person)
                } label: {
                    Label("Neue E-Mail an „\(person.title)“", systemImage: "square.and.pencil")
                }
            } header: {
                Text(verbatim: person.address)
            }
        } label: {
            HStack(spacing: 2) {
                Text(verbatim: person.title)
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("\(person.title), \(person.address)")
    }

    /// Legt die reine Adresse (ohne Namen) in die Zwischenablage.
    private func copyAddress() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(person.address, forType: .string)
        #else
        UIPasteboard.general.string = person.address
        #endif
    }
}

// MARK: - Hinweis externe Inhalte

/// Schmaler Hinweis „Externe Inhalte blockiert“ mit kleinem Knopf zum
/// Laden – bewusst zurückhaltend, damit er die Mail nicht verdrängt.
struct RemoteContentNotice: View {
    /// Gibt externe Inhalte für diese Anzeige frei.
    let onLoad: () -> Void

    /// Symbol, Hinweis und Knopf in einer Zeile.
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            Text("Externe Inhalte blockiert")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Laden") {
                onLoad()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Externe Inhalte laden")
        }
        .font(.footnote)
    }
}
