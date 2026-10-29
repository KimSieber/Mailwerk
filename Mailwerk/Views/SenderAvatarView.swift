//
//  SenderAvatarView.swift
//  Mailwerk
//
//  Zweck: Runder Kreis links in der Listenzeile – Kontaktbild, sonst Logo
//  der Absenderdomain auf weißem Grund, sonst Initialen auf einer festen
//  Farbe je Absender, oder ein leerer Kreis, wenn kein Bild gezeigt werden
//  darf (Spam, Spamverdacht, unbekannte Einstufung).
//
//  Logos stehen immer auf Weiß mit feinem Rand: Viele sind dunkel auf
//  transparentem Grund und wären im Dunkelmodus sonst unsichtbar.
//
//  Der leere Kreis hält den Platz, damit alle Zeilen gleich ausgerichtet
//  bleiben.
//
//  Abgrenzung: Welche Person und welche Initialen → MessageRowParty; ob
//  ein Bild erlaubt ist → SpamClassifier.allowsSenderImage; Kontaktbilder
//  → ContactImageDirectory; Logos → SenderIconCache.
//
//  Abhängigkeiten: SwiftUI, AccountColor (Farbpalette).
//

import SwiftUI

/// Inhalt des Kreises.
enum SenderAvatar {
    /// Leerer Kreis (kein Bild erlaubt).
    case empty
    /// Bild (Kontaktbild), rund zugeschnitten.
    case image(Image)
    /// Logo der Absenderdomain, eingepasst auf weißem Kreis.
    case logo(Image)
    /// Initialen auf der Farbe mit dem Index in `AccountColor.allCases`.
    case initials(String, colorIndex: Int)
}

/// Runder Kreis mit Initialen oder leer.
struct SenderAvatarView: View {
    /// Darzustellender Inhalt.
    let avatar: SenderAvatar

    /// Durchmesser in Punkten.
    static let size: CGFloat = 40
    /// Abstand des Logos zum Kreisrand, damit eckige Logos nicht beschnitten werden.
    static let logoInset: CGFloat = 6

    /// Aufbau des Kreises.
    var body: some View {
        ZStack {
            switch avatar {
            case .empty:
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            case .image(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            case .logo(let image):
                Circle()
                    .fill(Color.white)
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(Self.logoInset)
                    .clipShape(Circle())
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
            case .initials(let text, colorIndex: let colorIndex):
                Circle()
                    .fill(color(at: colorIndex))
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }

    /// Farbe aus der Palette; ein ungültiger Index fällt auf die erste Farbe.
    ///
    /// - Parameter index: Index in `AccountColor.allCases`.
    /// - Returns: Farbe des Kreises.
    private func color(at index: Int) -> Color {
        let palette = AccountColor.allCases
        return palette.indices.contains(index) ? palette[index].color : palette[0].color
    }
}
