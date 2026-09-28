//
//  SideDrawer.swift
//  Mailwerk
//
//  Leiste, die von links über den Inhalt fährt. Der Inhalt dahinter wird
//  abgedunkelt; ein Tipp darauf oder die Escape-Taste schließt die Leiste.
//
//  Bewusst schlicht gehalten (v0.1.7a, Fokus iPhone). Auf dem Mac und
//  dem iPad im Querformat soll später eine feste Seitenleiste folgen.
//

import SwiftUI

extension View {
    /// Blendet `drawer` als Leiste von links ein, solange `isPresented` gilt.
    func sideDrawer<Drawer: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder drawer: @escaping () -> Drawer
    ) -> some View {
        modifier(SideDrawerModifier(isPresented: isPresented, drawer: drawer))
    }
}

private struct SideDrawerModifier<Drawer: View>: ViewModifier {
    @Binding var isPresented: Bool
    let drawer: () -> Drawer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Höchstbreite der Leiste; auf schmalen Geräten ein Anteil der Breite,
    /// damit rechts immer ein Streifen der Mail-Liste sichtbar bleibt.
    private static var maxWidth: CGFloat { 320 }
    private static var widthRatio: CGFloat { 0.84 }
    private static var dimOpacity: Double { 0.3 }

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
                                .background(.background)
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
