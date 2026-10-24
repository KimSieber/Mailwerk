//
//  MailwerkWatchApp.swift
//  MailwerkWatch
//
//  Zweck: Einstiegspunkt der Watch-App. Startet beim Start die Verbindung
//  zum iPhone und nimmt die Hintergrundaufgaben von watchOS an (Daten des
//  iPhones, die im Hintergrund eintreffen).
//
//  Aktualisiert wird beim Öffnen und bei jeder Rückkehr in den Vordergrund
//  (WatchRootView).
//
//  Abgrenzung: Austausch mit dem iPhone → WatchConnector; Startansicht →
//  WatchRootView.
//
//  Abhängigkeiten: SwiftUI, WatchKit, WatchConnector, WatchRootView.
//

import SwiftUI
import WatchKit

@main
struct MailwerkWatchApp: App {
    /// Nimmt Start und Hintergrundaufgaben von watchOS an.
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    /// Hauptfenster.
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// Start und Hintergrundaufgaben der Watch-App.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    /// Startet die Verbindung zum iPhone, damit Daten auch nach einem Start
    /// im Hintergrund ankommen.
    func applicationDidFinishLaunching() {
        WatchConnector.shared.start()
    }

    /// Nimmt Hintergrundaufgaben an.
    ///
    /// Verarbeitung: Aufgaben für Daten des iPhones hält die Verbindung, bis
    /// alles eingetroffen ist; alle anderen sind sofort erledigt.
    ///
    /// - Parameter backgroundTasks: Aufgaben von watchOS.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchConnector.shared.hold(connectivityTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
