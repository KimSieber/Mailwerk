//
//  MessageRow.swift
//  Mailwerk
//
//  Zweck: Eine Zeile der Mailliste in drei Zeilen:
//  1. Kennzeichen (beantwortet, weitergeleitet, gekennzeichnet, Anhang)
//     links, dahinter bei Spam `[SPAM]` (ohne Score, SpamMark), Datum
//     rechts – klein und grau; das Datum wird nie gekürzt;
//  2. Name fett (bei ungelesenen Mails), dahinter die Adresse klein und
//     grau; gekürzt wird zuerst die Adresse;
//  3. Betreff.
//  Links davon der Farbstreifen des Postfachs und der Kreis mit
//  Kontaktbild, Logo bzw. Initialen.
//
//  Farbstreifen: gelesen 4 pt, ungelesen 8 pt in der Postfachfarbe.
//  Postfächer ohne Farbe zeigen gelesen keinen Streifen, ungelesen einen
//  hellgrauen mit 8 pt. Der Platz von 8 pt ist immer reserviert, damit die
//  Zeile beim Lesen nicht seitlich springt.
//
//  Neuzeichnen (v0.2.3c, Prüfbericht P-08): Die Zeile bekommt nur fertige
//  Werte und ist `Equatable`; die Liste setzt sie mit `.equatable()` ein.
//  Zeichnet sich die Liste neu – etwa weil sich die Auswahl oder die
//  Sperre einer anderen Zeile ändert –, überspringt SwiftUI alle Zeilen,
//  deren Werte gleich geblieben sind.
//
//  Bilder (v0.2.3c, Prüfbericht P-09): Den Kreis füllt `RowSenderAvatar`
//  selbst. Er holt Kontaktbild bzw. Logo asynchron und verkleinert aus den
//  Caches und lädt nur neu, wenn sich der Stand genau seiner Domain bzw.
//  der Kontakte ändert. Die Liste fragt die Caches beim Neuzeichnen nicht
//  mehr je Zeile ab. Bis das Bild vorliegt, stehen die Initialen.
//
//  Abgrenzung: Wer gezeigt wird → MessageRowParty; Datum → ListDateFormatter;
//  Kreis → SenderAvatarView; Link, Wischaktionen → InboxView.
//
//  Abhängigkeiten: SwiftUI, MessageListItem, MessageRowParty,
//  ListDateFormatter, SenderAvatarView, ContactImageDirectory,
//  SenderIconCache, AccountColor (`Color(hex:)`).
//

import SwiftUI

/// Zeile der Mailliste.
struct MessageRow: View, Equatable {
    /// Darzustellender Listeneintrag.
    let message: MessageListItem
    /// Gezeigte Person (Absender bzw. Empfänger).
    let party: MessageRowParty
    /// `true`, wenn ein Bild bzw. Initialen gezeigt werden dürfen.
    let showsImage: Bool
    /// Farbe des Postfachs; `nil` = keine Farbe gewählt.
    let colorHex: String?
    /// Text zur Spam-Einschätzung (`[SPAM]`); `nil` = keiner.
    var spamMark: String? = nil

    /// Breite des Streifens bei gelesenen Mails.
    static let readStripeWidth: CGFloat = 4
    /// Breite des Streifens bei ungelesenen Mails (zugleich reservierter Platz).
    static let unreadStripeWidth: CGFloat = 8

    /// Aufbau der Zeile.
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stripe
            RowSenderAvatar(party: party, showsImage: showsImage)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                statusLine
                nameLine
                Text(message.subject)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Teile

    /// Farbstreifen am linken Rand in reserviertem Platz.
    private var stripe: some View {
        Rectangle()
            .fill(stripeColor)
            .frame(width: message.isUnread ? Self.unreadStripeWidth : Self.readStripeWidth)
            .frame(width: Self.unreadStripeWidth, alignment: .leading)
    }

    /// Farbe des Streifens: Postfachfarbe, ungelesen ohne Farbe hellgrau,
    /// sonst unsichtbar.
    private var stripeColor: Color {
        if let colorHex { return Color(hex: colorHex) }
        return message.isUnread ? Color.gray.opacity(0.35) : .clear
    }


    /// Zeile 1: Kennzeichen und Spam-Einschätzung links, Datum rechts.
    private var statusLine: some View {
        HStack(spacing: 6) {
            if message.isAnswered {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Beantwortet")
            }
            if message.isForwarded {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Weitergeleitet")
            }
            if message.isFlagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Gekennzeichnet")
            }
            if message.hasAttachments {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Mit Anhang")
            }
            // Spam-Einschätzung nach den Symbolen, damit diese an fester
            // Stelle bleiben; das Datum hat Vorrang und wird nie gekürzt.
            if let spamMark {
                Text(spamMark)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Spam-Einschätzung \(spamMark)")
            }
            Spacer(minLength: 8)
            // Ohne Datum bleibt die Stelle leer – die aktuelle Zeit
            // würde ein falsches Datum vortäuschen.
            if let date = message.date {
                Text(ListDateFormatter.string(for: date))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.caption)
    }

    /// Zeile 2: Name, dahinter klein und grau die Adresse bzw. „+n“.
    /// Der Name hat Vorrang; gekürzt wird zuerst der Zusatz.
    private var nameLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(party.title)
                .font(.body.weight(message.isUnread ? .bold : .regular))
                .lineLimit(1)
                .layoutPriority(1)
            if let subtitle = party.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Kreis einer Listenzeile mit asynchron geladenem Bild.
///
/// Reihenfolge wie bisher: leer, wenn kein Bild erlaubt ist (Spam), sonst
/// Kontaktbild, dann Logo, ersatzweise die Initialen. Schon verkleinerte
/// Bilder erscheinen sofort; sonst lädt `.task` sie im Hintergrund. Der
/// Schlüssel der Aufgabe enthält den Stand der Kontakte und den Stand der
/// Domain – nur deren Änderung lädt neu.
private struct RowSenderAvatar: View {
    /// Gezeigte Person.
    let party: MessageRowParty
    /// `true`, wenn ein Bild bzw. Initialen gezeigt werden dürfen.
    let showsImage: Bool

    /// Geladener Inhalt; `nil`, solange nichts geladen ist bzw. kein Bild vorliegt.
    @State private var loaded: SenderAvatar?

    /// Was die Ladeaufgabe neu startet.
    private struct LoadKey: Equatable {
        let address: String?
        let showsImage: Bool
        let contactsRevision: Int
        let logoRevision: Int
    }

    /// Kreis mit Bild, Logo, Initialen oder leer.
    var body: some View {
        SenderAvatarView(avatar: avatar)
            .task(id: loadKey) { await load() }
    }

    /// Schlüssel der Ladeaufgabe aus Adresse, Erlaubnis und den Ständen
    /// von Kontakten und Domain.
    private var loadKey: LoadKey {
        LoadKey(
            address: party.address,
            showsImage: showsImage,
            contactsRevision: ContactImageDirectory.shared.revision,
            logoRevision: SenderIconCache.shared.revision(forAddress: party.address)
        )
    }

    /// Aktueller Inhalt: geladen, sonst schon im Speicher, sonst Initialen.
    private var avatar: SenderAvatar {
        guard showsImage else { return .empty }
        if let loaded { return loaded }
        if let image = ContactImageDirectory.shared.cachedThumbnail(for: party.address) { return .image(image) }
        if let logo = SenderIconCache.shared.cachedThumbnail(forAddress: party.address) { return .logo(logo) }
        return .initials(party.initials, colorIndex: party.colorIndex)
    }

    /// Lädt Kontaktbild bzw. Logo verkleinert im Hintergrund.
    ///
    /// Verarbeitung: Ohne Erlaubnis nichts (Spam löst keinen Logo-Abruf
    /// aus). Ein Kontaktbild hat Vorrang vor dem Logo.
    private func load() async {
        guard showsImage else {
            loaded = nil
            return
        }
        if let image = await ContactImageDirectory.shared.thumbnail(for: party.address) {
            loaded = .image(image)
        } else if let logo = await SenderIconCache.shared.thumbnail(forAddress: party.address) {
            loaded = .logo(logo)
        } else {
            loaded = nil
        }
    }
}
