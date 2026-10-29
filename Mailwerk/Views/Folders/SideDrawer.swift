//
//  SideDrawer.swift
//  Mailwerk
//
//  Zweck: Leiste, die von links über den Inhalt fährt. Der Inhalt dahinter
//  wird abgedunkelt; ein Tipp darauf oder die Escape-Taste schließt die
//  Leiste. Die Leiste liegt auf der getönten Fläche der App (AppTheme).
//
//  Bewusst schlicht gehalten. Genutzt auf dem iPhone, auf dem iPad mit
//  zwei Spalten und im Hochformat sowie auf dem Mac in Fenstern, die für
//  die feste Ordnerleiste zu schmal sind (MacColumnLayout). Bei drei
//  Spalten im Querformat steht die Ordnerleiste stattdessen fest neben der
//  Liste (InboxView); dort entfällt der Knopf für diese Leiste.
//
//  Abgrenzung: Inhalt der Leiste → FolderSidebarView; feste Spalte →
//  InboxView.
//
//  Abhängigkeiten: SwiftUI, AppTheme.
//

import SwiftUI

extension View {
    /// Blendet `drawer` als Leiste von links ein, solange `isPresented` gilt.
    ///
    /// - Parameters:
    ///   - isPresented: Sichtbarkeit der Leiste.
    ///   - drawer: Inhalt der Leiste.
    /// - Returns: Ansicht mit Leiste.
    func sideDrawer<Drawer: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder drawer: @escaping () -> Drawer
    ) -> some View {
        modifier(SideDrawerModifier(isPresented: isPresented, drawer: drawer))
    }
}

/// Legt Hintergrund und Leiste über den Inhalt.
private struct SideDrawerModifier<Drawer: View>: ViewModifier {
    /// Sichtbarkeit der Leiste.
    /// Inhalt der Leiste.
    @Binding var isPresented: Bool
    let drawer: () -> Drawer

    /// Bewegung reduzieren (Bedienungshilfen): dann nur Überblenden.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Höchstbreite der Leiste; auf schmalen Geräten ein Anteil der Breite,
    /// damit rechts immer ein Streifen der Mail-Liste sichtbar bleibt.
    private static var maxWidth: CGFloat { 320 }
    /// Anteil der Bildschirmbreite auf schmalen Geräten.
    private static var widthRatio: CGFloat { 0.84 }
    /// Deckkraft der Abdunkelung.
    private static var dimOpacity: Double { 0.3 }

    /// Inhalt mit eingeblendeter Leiste.
    ///
    /// - Parameter content: Ursprüngliche Ansicht.
    /// - Returns: Ansicht mit Hintergrund und Leiste, animiert.
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        if isPresented {
                            backdrop
                                .transition(.opacity)

                            drawer()
                                .frame(
                                    width: min(proxy.size.width * Self.widthRatio, Self.maxWidth),
                                    alignment: .topLeading
                                )
                                .frame(maxHeight: .infinity, alignment: .top)
                                .background(AppTheme.background)
                                .accessibilityAddTraits(.isModal)
                                .transition(reduceMotion ? .opacity : .move(edge: .leading))
                        }
                    }
                    .animation(.snappy(duration: 0.28), value: isPresented)
                }
            }
    }

    /// Abgedunkelter Hintergrund. Als Button, damit er per Tipp, per
    /// VoiceOver und mit der Escape-Taste (Tastatur am iPad/Mac) schließt.
    private var backdrop: some View {
        Button {
            isPresented = false
        } label: {
            Color.black
                .opacity(Self.dimOpacity)
                .ignoresSafeArea()
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Ordnerleiste schließen")
    }
}
