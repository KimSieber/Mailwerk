//
//  MacDetailHeaderBar.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 27.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Kopfleiste über der Mailansicht auf dem Mac – ein gewöhnlicher
//  View statt Einträgen der System-Symbolleiste, damit beim Mailwechsel
//  nichts flackert.
//
//  Aufbau wie auf dem iPad:
//  - links: leer; in der einspaltigen Darstellung ein Zurück-Knopf
//    (grauer Kreis mit `chevron.left`), der die Mail schließt;
//  - Mitte: Farbpunkt und Name des Postfachs der Mail, bei Platzmangel
//    gekürzt;
//  - rechts: drei Knöpfe Antworten, Allen antworten und Weiterleiten
//    (auf dem Mac ist Gedrückthalten für weitere Varianten unüblich, Platz
//    ist genug) und das Aktionsmenü – immer mit drei Punkten; während
//    einer Aktion zeigt es den Kreisel.
//
//  Die Leiste hat in allen Zuständen dieselbe Höhe. Solange die Mail noch
//  aus dem Cache lädt, steht sie schon mit ausgegrauten Knöpfen und dem
//  Postfachnamen aus dem Listeneintrag (MessageDetailLoader) – beim
//  Mailwechsel springt nichts. Vollbild-Knopf und Pfeile gibt es auf dem
//  Mac nicht (Fenster bzw. Pfeiltasten übernehmen das).
//
//  Abgrenzung: Menüinhalte und Aktionen → MessageDetailView; Kreisknöpfe
//  → SheetHeaderBar.swift.
//
//  Abhängigkeiten: SwiftUI, HeaderCircleButton, HeaderCircleLabel, AppTheme.
//

#if os(macOS)
import SwiftUI

/// Kopfleiste über der Mailansicht (Mac).
struct MacDetailHeaderBar<ActionMenu: View>: View {
    /// Name des Postfachs der Mail.
    let accountName: String
    /// Farbe des Postfachs; `nil` = keine gewählt.
    let accountColor: Color?
    /// Schließt die Mail (einspaltige Darstellung); `nil` = kein Knopf.
    let onBack: (() -> Void)?
    /// `false`, solange die Mail lädt – Knöpfe ausgegraut.
    let isEnabled: Bool
    /// Eine Aktion an der Mail läuft – Kreisel im Aktionsmenü.
    let isProcessing: Bool
    /// Antworten.
    let onReply: () -> Void
    /// Allen antworten.
    let onReplyAll: () -> Void
    /// Weiterleiten.
    let onForward: () -> Void
    /// Inhalt des Aktionsmenüs.
    @ViewBuilder let actionMenu: () -> ActionMenu

    /// Höhe der Leiste in Punkt – gleich der Kopfleiste der Sheets.
    static var height: CGFloat { 52 }

    /// Breite der Knopfgruppe rechts: vier Kreise mit Abständen.
    private static var trailingWidth: CGFloat {
        4 * HeaderCircleMetrics.diameter + 3 * 10
    }

    /// Leiste: Zurück, Postfach, Antworten/Allen antworten/Weiterleiten und
    /// Menü.
    ///
    /// Verarbeitung: Passt der Postfachname zwischen gleich breite Ränder,
    /// steht er genau in der Mitte der Leiste (wie auf dem iPad). In einer
    /// schmalen Mailansicht rückt er zwischen Zurück-Knopf und Knopfgruppe
    /// und wird bei Bedarf gekürzt – die Knöpfe überdeckt er nie.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.regular) {
                leadingButtons
                    .frame(width: Self.trailingWidth, alignment: .leading)
                Spacer(minLength: 0)
                accountLabel
                    .fixedSize()
                Spacer(minLength: 0)
                trailingButtons
                    .frame(width: Self.trailingWidth, alignment: .trailing)
            }
            HStack(spacing: AppSpacing.regular) {
                leadingButtons
                accountLabel
                    .frame(maxWidth: .infinity)
                trailingButtons
            }
        }
        .padding(.horizontal, AppSpacing.large)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(AppTheme.background)
        // Kein Divider: In der Überlagerung einer HStack würde er senkrecht.
        .overlay(alignment: .bottom) { HeaderBottomLine() }
    }

    /// Zurück-Knopf (nur in der einspaltigen Darstellung).
    @ViewBuilder
    private var leadingButtons: some View {
        if let onBack {
            HeaderCircleButton(
                title: "Zurück zur Liste",
                systemImage: "chevron.left",
                help: "Zurück zur Liste",
                action: onBack
            )
        }
    }

    /// Antworten, Allen antworten, Weiterleiten und das Aktionsmenü.
    private var trailingButtons: some View {
        HStack(spacing: AppSpacing.medium) {
            HeaderCircleButton(
                title: "Antworten",
                systemImage: "arrowshape.turn.up.left",
                isEnabled: isEnabled,
                action: onReply
            )
            HeaderCircleButton(
                title: "Allen antworten",
                systemImage: "arrowshape.turn.up.left.2",
                isEnabled: isEnabled,
                action: onReplyAll
            )
            HeaderCircleButton(
                title: "Weiterleiten",
                systemImage: "arrowshape.turn.up.right",
                isEnabled: isEnabled,
                action: onForward
            )
            Menu {
                actionMenu()
            } label: {
                HeaderCircleLabel(systemImage: "ellipsis", isBusy: isProcessing)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Weitere Aktionen")
            .accessibilityLabel("Weitere Aktionen")
            .disabled(!isEnabled || isProcessing)
            .opacity(isEnabled || isProcessing ? 1 : 0.4)
        }
        .fixedSize()
    }

    /// Farbpunkt und Name des Postfachs, mittig.
    private var accountLabel: some View {
        HStack(spacing: AppSpacing.small) {
            if let accountColor {
                Circle()
                    .fill(accountColor)
                    .frame(width: 9, height: 9)
            }
            Text(accountName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension MacDetailHeaderBar where ActionMenu == EmptyView {
    /// Leiste mit ausgegrauten Knöpfen, solange die Mail lädt.
    ///
    /// - Parameters:
    ///   - accountName: Postfachname aus dem Listeneintrag.
    ///   - accountColor: Farbe des Postfachs.
    ///   - onBack: Schließt die Mail; `nil` = kein Knopf.
    init(placeholderFor accountName: String, accountColor: Color?, onBack: (() -> Void)?) {
        self.init(
            accountName: accountName,
            accountColor: accountColor,
            onBack: onBack,
            isEnabled: false,
            isProcessing: false,
            onReply: {},
            onReplyAll: {},
            onForward: {},
            actionMenu: { EmptyView() }
        )
    }
}
#endif
