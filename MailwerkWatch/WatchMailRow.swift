//
//  WatchMailRow.swift
//  MailwerkWatch
//
//  Zweck: Eine Zeile der Mail-Liste auf der Watch – wie in der App, nur
//  schmaler und ohne Vorschau des Inhalts:
//  1. Kennzeichen, Anhang und `[SPAM]` links, Datum rechts (Kurzform);
//  2. Absender, fett bei ungelesenen Mails;
//  3. Betreff (höchstens zwei Zeilen).
//  Links der Farbstreifen des Postfachs (gelesen schmal, ungelesen breit)
//  und der Kreis mit Kontaktbild, Logo bzw. Initialen – leer bei Spam,
//  dieselbe Regel wie in der App (`SpamClassifier.allowsSenderImage`).
//
//  Dazu der Kreis selbst (`WatchAvatarView`), auch für die Mailansicht.
//
//  Abgrenzung: Liste und Wischaktionen → WatchMailListView; Vorbild in der
//  App → MessageRow, SenderAvatarView.
//
//  Abhängigkeiten: SwiftUI, UIKit (UIImage), WatchStore, WatchTransfer,
//  SpamClassifier, SpamMark, ListDateFormatter, AccountColor.
//

import SwiftUI
import UIKit

/// Zeile der Mail-Liste.
struct WatchMailRow: View {
    /// Darzustellende Mail.
    let mail: WatchMail

    /// Speicher der App (Listen, Bilder).
    private let store = WatchStore.shared

    /// Breite des Streifens bei gelesenen Mails.
    private static let readStripeWidth: CGFloat = 2
    /// Breite des Streifens bei ungelesenen Mails (zugleich reservierter Platz).
    private static let unreadStripeWidth: CGFloat = 4

    /// Aufbau der Zeile.
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            stripe
            WatchAvatarView(mail: mail, size: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                statusLine
                Text(mail.senderTitle)
                    .font(.headline)
                    .fontWeight(mail.isUnread ? .bold : .regular)
                    .lineLimit(1)
                Text(mail.subject.isEmpty ? "(kein Betreff)" : mail.subject)
                    .font(.footnote)
                    .foregroundStyle(mail.isUnread ? .primary : .secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Farbstreifen am linken Rand in reserviertem Platz.
    private var stripe: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(stripeColor)
            .frame(width: mail.isUnread ? Self.unreadStripeWidth : Self.readStripeWidth)
            .frame(width: Self.unreadStripeWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
    }

    /// Farbe des Streifens: Postfachfarbe, ungelesen ohne Farbe grau,
    /// sonst unsichtbar.
    private var stripeColor: Color {
        if let hex = mail.accountColorHex { return Color(hex: hex) }
        return mail.isUnread ? Color.gray.opacity(0.5) : .clear
    }

    /// Zeile 1: Kennzeichen und Spam-Einschätzung links, Datum rechts.
    private var statusLine: some View {
        HStack(spacing: 4) {
            if mail.isFlagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Gekennzeichnet")
            }
            if mail.hasAttachments {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Mit Anhang")
            }
            if let spamMark {
                Text(spamMark)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let date = mail.date {
                Text(ListDateFormatter.compactString(for: date))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.caption2)
    }

    /// `[SPAM]` nach der Regel des Spamfilters; ohne Listen nichts.
    private var spamMark: String? {
        guard let lists = store.lists else { return nil }
        return SpamMark.text(
            sender: mail.sender,
            verdict: mail.verdict?.verdict,
            rules: SpamRules(lists: lists, scoreLimit: store.scoreLimit),
            style: .list
        )
    }
}

/// Runder Kreis mit Kontaktbild, Logo, Initialen oder leer.
struct WatchAvatarView: View {
    /// Mail, deren Absender gezeigt wird.
    let mail: WatchMail
    /// Durchmesser in Punkten.
    let size: CGFloat

    /// Speicher der App (Listen, Bilder).
    private let store = WatchStore.shared

    /// Aufbau des Kreises.
    var body: some View {
        ZStack {
            if !showsImage {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
            } else if let key = mail.avatarKey, let image = image(for: key) {
                if WatchAvatarKey.isLogo(key) {
                    Circle().fill(Color.white)
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(size * 0.15)
                        .clipShape(Circle())
                } else {
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                }
            } else {
                Circle().fill(color)
                Text(mail.initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// `true`, wenn ein Bild bzw. Initialen gezeigt werden dürfen – dieselbe
    /// Regel wie in der App; ohne Listen vorsichtshalber nicht.
    private var showsImage: Bool {
        guard let lists = store.lists else { return false }
        return SpamClassifier.allowsSenderImage(
            sender: mail.sender,
            verdict: mail.verdict?.verdict,
            lists: lists,
            scoreLimit: store.scoreLimit
        )
    }

    /// Farbe der Initialen aus der Palette der App.
    private var color: Color {
        let palette = AccountColor.allCases
        return palette.indices.contains(mail.colorIndex) ? palette[mail.colorIndex].color : palette[0].color
    }

    /// Gespeichertes Bild zum Schlüssel.
    ///
    /// - Parameter key: Schlüssel.
    /// - Returns: Bild oder `nil`, wenn keines vorliegt.
    private func image(for key: String) -> Image? {
        guard let data = store.imageData(key: key), let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
    }
}
