//
//  MailwerkUnreadWidget.swift
//  MailwerkWatchComplication
//
//  Zweck: Komplikation und Smart-Stack-Widget der Watch mit der Zahl der
//  ungelesenen Mails in allen Eingängen. Ein Tipp öffnet die Watch-App.
//
//  Die Zahl schreibt die Watch-App bei jeder Änderung in den gemeinsamen
//  Speicher (WatchBadge) und lässt die Komplikation neu zeichnen; die
//  Komplikation selbst fragt nichts ab.
//
//  Formen: rund (Symbol mit Zahl), Ecke, eine Zeile, Rechteck (mit Stand).
//
//  Abgrenzung: Zahl → WatchStore; Ablage → WatchAppGroup, WatchBadge.
//
//  Abhängigkeiten: WidgetKit, SwiftUI, WatchBadge, ListDateFormatter.
//

import WidgetKit
import SwiftUI

/// Zusammenstellung der Widgets der Watch.
@main
struct MailwerkWatchWidgets: WidgetBundle {
    /// Enthaltene Widgets.
    var body: some Widget {
        MailwerkUnreadWidget()
    }
}

/// Komplikation „Ungelesen“.
struct MailwerkUnreadWidget: Widget {
    /// Kennung des Widgets (für `reloadTimelines`).
    static let kind = "MailwerkUnread"

    /// Aufbau und unterstützte Formen.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UnreadProvider()) { entry in
            UnreadWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ungelesen")
        .description("Ungelesene Mails in allen Eingängen.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

/// Ein Stand der Komplikation.
nonisolated struct UnreadEntry: TimelineEntry {
    /// Zeitpunkt des Eintrags.
    let date: Date
    /// Ungelesene Mails.
    let unread: Int
    /// Letzter Abruf auf dem iPhone; `nil` = unbekannt.
    let updatedAt: Date?
}

/// Liefert die Einträge aus dem gemeinsamen Speicher.
///
/// Ein Eintrag genügt: Die Watch-App lässt die Komplikation bei jeder
/// Änderung neu zeichnen.
nonisolated struct UnreadProvider: TimelineProvider {

    /// Platzhalter in der Auswahl der Komplikationen.
    func placeholder(in context: Context) -> UnreadEntry {
        UnreadEntry(date: Date(), unread: 3, updatedAt: nil)
    }

    /// Momentaufnahme (Vorschau).
    func getSnapshot(in context: Context, completion: @escaping (UnreadEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    /// Zeitleiste mit dem aktuellen Stand; neu erst auf Anstoß der App.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UnreadEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    /// Eintrag aus der gespeicherten Zahl.
    ///
    /// - Returns: Aktueller Eintrag.
    private func currentEntry() -> UnreadEntry {
        let badge = WatchBadge.load()
        return UnreadEntry(date: Date(), unread: badge.unread, updatedAt: badge.updatedAt)
    }
}

/// Darstellung je Form.
struct UnreadWidgetView: View {
    /// Darzustellender Stand.
    let entry: UnreadEntry
    /// Form der Komplikation.
    @Environment(\.widgetFamily) private var family

    /// Inhalt je Form.
    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "envelope.fill")
                    .font(.caption)
                Text("\(entry.unread)")
                    .font(.title3.bold())
                    .minimumScaleFactor(0.5)
            }
            .widgetAccentable()
        case .accessoryCorner:
            Image(systemName: "envelope.fill")
                .font(.title3)
                .widgetLabel("\(entry.unread) ungelesen")
                .widgetAccentable()
        case .accessoryInline:
            Label("\(entry.unread) ungelesen", systemImage: "envelope.fill")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Label("Mailwerk", systemImage: "envelope.fill")
                    .font(.headline)
                    .widgetAccentable()
                Text(entry.unread == 1 ? "1 ungelesene Mail" : "\(entry.unread) ungelesene Mails")
                if let updatedAt = entry.updatedAt {
                    Text("Stand: \(ListDateFormatter.string(for: updatedAt))")
                        .foregroundStyle(.secondary)
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
