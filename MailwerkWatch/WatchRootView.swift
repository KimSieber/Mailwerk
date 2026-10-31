//
//  WatchRootView.swift
//  MailwerkWatch
//  Autor: Kim Sieber
//  Erstellt: 20.10.2026
//  Geändert: 30.10.2026
//
//  Zweck: Menü der Watch – die vier Sammelansichten der App (Alle
//  Eingänge, Ungelesen mit Zähler, Mit Kennzeichnung mit Zähler, Spam),
//  darunter der Stand und „Aktualisieren“. Beim Start ist „Alle Eingänge“
//  bereits geöffnet; das Menü liegt einen Schritt zurück.
//
//  Aktualisiert wird beim Öffnen, bei jeder Rückkehr in den Vordergrund,
//  per Herunterziehen (WatchPullToRefresh) und per Knopf. Ist das iPhone nicht erreichbar,
//  zeigt die Watch ihren gespeicherten Stand mit Uhrzeit des letzten
//  Abrufs. Hinweise des iPhones zum letzten Abruf stehen über dem Stand –
//  alle, z. B. je nicht erreichbarem Postfach eine Zeile.
//
//  Abgrenzung: Liste einer Sicht → WatchMailListView; Austausch →
//  WatchConnector.
//
//  Abhängigkeiten: SwiftUI, WatchStore, WatchConnector, WatchMailbox
//  (WatchView), WatchMailListView, WatchPullToRefresh.
//

import SwiftUI

/// Menü mit den Sammelansichten; startet in „Alle Eingänge“.
struct WatchRootView: View {
    /// Speicher der App.
    private let store = WatchStore.shared
    /// Vordergrund oder Hintergrund.
    @Environment(\.scenePhase) private var scenePhase
    /// Geöffnete Ansichten; beim Start „Alle Eingänge“.
    @State private var path: [WatchView] = [.allInboxes]

    /// Sammelansichten, Stand und Hinweise.
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(WatchView.allCases) { view in
                        NavigationLink(value: view) {
                            row(for: view)
                        }
                    }
                }
                Section {
                    statusRow
                    Button {
                        Task { await WatchConnector.shared.refresh() }
                    } label: {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.status == .syncing)
                }
            }
            .navigationTitle("Mailwerk")
            .navigationDestination(for: WatchView.self) { view in
                WatchMailListView(view: view)
            }
            .watchPullToRefresh {
                await WatchConnector.shared.refresh()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await WatchConnector.shared.refresh() }
        }
        .alert(
            "Aktion nicht ausgeführt",
            isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.notice ?? "")
        }
    }

    /// Zeile einer Sammelansicht mit Zähler (Ungelesen, Kennzeichnung).
    ///
    /// - Parameter view: Sicht.
    /// - Returns: Symbol, Titel und ggf. Zahl.
    private func row(for view: WatchView) -> some View {
        HStack {
            Label(view.title, systemImage: view.systemImage)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let count = count(for: view), count > 0 {
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Zähler einer Sicht; `nil` = die Sicht zeigt keinen (wie in der App).
    ///
    /// - Parameter view: Sicht.
    /// - Returns: Anzahl oder `nil`.
    private func count(for view: WatchView) -> Int? {
        switch view {
        case .unread: return store.unreadCount
        case .flagged: return store.flaggedCount
        case .allInboxes, .spam: return nil
        }
    }

    /// Stand: Aktualisierung läuft, iPhone nicht erreichbar, letzter Abruf.
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch store.status {
            case .syncing:
                HStack(spacing: 6) {
                    ProgressView()
                        .frame(width: 16, height: 16)
                    Text("Aktualisiere …")
                }
            case .unreachable:
                Text("iPhone nicht erreichbar")
            case .companionMissing:
                Text("Mailwerk fehlt auf dem iPhone")
            case .idle:
                EmptyView()
            }
            if !store.hasAccounts {
                Text("Auf dem iPhone ist kein Postfach mit eingeschaltetem Abruf eingerichtet.")
            } else {
                ForEach(store.problems, id: \.self) { problem in
                    Text(problem)
                }
            }
            Text(syncText)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }

    /// Uhrzeit des letzten Abrufs auf dem iPhone.
    private var syncText: String {
        guard let date = store.lastServerSync else {
            return store.hasSnapshot ? "Noch nicht abgerufen" : "Noch nichts vom iPhone erhalten"
        }
        return "Stand: \(ListDateFormatter.string(for: date))"
    }
}
