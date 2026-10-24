//
//  MessageDetailHeader.swift
//  Mailwerk
//
//  Zweck: Kopfbereich der Mailansicht – Betreff mit Kennzeichen, Absender,
//  Empfänger, Kopie, „Antwort an“ und Datum (rechts daneben die
//  Spam-Einschätzung, z. B. `[SPAM score=7.2]` oder `[NoSpam]`) – sowie die
//  schmalen Hinweise „Externe Inhalte blockiert“ (Knopf „Laden“) und zur
//  Übersetzung fremdsprachiger Mails (`TranslationNotice`).
//
//  Ist ein Betreff übersetzt, zeigt der Kopf ihn statt des Originals
//  (`translatedSubject`); die Mail selbst entscheidet, wann das gilt.
//
//  Links neben Personen und Datum steht wie in Apple Mail derselbe Kreis
//  wie in der Mailliste (SenderAvatarView): Kontaktbild, Logo oder
//  Initialen des Absenders, in Gesendet/Entwürfen des ersten Empfängers;
//  leer, wenn kein Bild gezeigt werden darf.
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
//  Zwischenablage, CachedMessage, HeaderPerson, FlowLayout,
//  SenderAvatarView (Inhalt des Kreises und Text der Spam-Einschätzung
//  kommen fertig von MessageDetailView).
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
    /// Text zur Spam-Einschätzung; `nil` = keiner.
    var spamMark: String? = nil
    /// Kreis wie in der Mailliste (Kontaktbild, Logo, Initialen oder leer);
    /// `nil` = kein Kreis.
    var avatar: SenderAvatar? = nil
    /// Übersetzter Betreff; `nil` = das Original wird gezeigt.
    var translatedSubject: String? = nil

    /// Betreff, Kennzeichnung, Personen und Datum.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(translatedSubject ?? message.subject)
                    .font(.title2)
                    .bold()
                    .textSelection(.enabled)
                if isFlagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                }
            }
            // Wie in Apple Mail: der Kreis links neben Personen und Datum.
            HStack(alignment: .top, spacing: 10) {
                if let avatar {
                    SenderAvatarView(avatar: avatar)
                }
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        peopleRow("Von", HeaderPerson.list([message.from]))
                        peopleRow("An", HeaderPerson.list(toAddresses))
                        peopleRow("Kopie", HeaderPerson.list(message.headers.ccList))
                        peopleRow("Antwort an", HeaderPerson.replyTo(message.headers.replyToList, sender: message.from))
                    }
                    dateLine
                }
            }
        }
    }

    /// Datum links, Spam-Einschätzung rechtsbündig; entfällt ohne beides.
    @ViewBuilder
    private var dateLine: some View {
        if message.date != nil || spamMark != nil {
            HStack {
                if let date = message.date {
                    Text(date, format: .dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits).year().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
                }
                Spacer(minLength: 8)
                if let spamMark {
                    Text(spamMark)
                        .lineLimit(1)
                        .accessibilityLabel("Spam-Einschätzung \(spamMark)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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

// MARK: - Hinweis Übersetzung

/// Zustand des Übersetzungs-Hinweises einer Mail.
enum TranslationNoticeState {
    /// Fremde Sprache erkannt, noch nicht übersetzt; Knopf trägt den
    /// Sprachnamen (z. B. „Schwedisch übersetzen“).
    case offer(languageName: String)
    /// Übersetzung läuft (ggf. inkl. Herunterladen des Sprachmodells).
    case translating
    /// Übersetzung wird angezeigt; Rückweg zum Original.
    case translated
    /// Übersetzung fehlgeschlagen; Knopf zum erneuten Versuch.
    case failed(String)
}

/// Schmaler Hinweis zur Übersetzung einer fremdsprachigen Mail – analog
/// `RemoteContentNotice`, aber mit vier Zuständen in einem Baustein, damit
/// an derselben Stelle steht, was gerade gilt.
struct TranslationNotice: View {
    /// Aktueller Zustand.
    let state: TranslationNoticeState
    /// Startet die Übersetzung (auch „Erneut versuchen“).
    let onTranslate: () -> Void
    /// Rückweg: zeigt wieder das Original.
    let onShowOriginal: () -> Void

    /// Symbol, Hinweis und ein Knopf je Zustand, in einer Zeile.
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble")
                .foregroundStyle(.secondary)
            switch state {
            case .offer(let languageName):
                Spacer(minLength: 8)
                Button("\(languageName) übersetzen") {
                    onTranslate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .translating:
                Text("Wird übersetzt …")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                ProgressView()
                    .controlSize(.small)
            case .translated:
                Text("Übersetzt")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Original anzeigen") {
                    onShowOriginal()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Erneut versuchen") {
                    onTranslate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .font(.footnote)
    }
}
