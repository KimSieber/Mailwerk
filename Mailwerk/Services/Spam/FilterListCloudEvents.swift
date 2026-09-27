//
//  FilterListCloudEvents.swift
//  Mailwerk
//
//  Meldet, wenn der iCloud-Abgleich Änderungen an den Filterlisten von
//  einem anderen Gerät übernommen hat.
//
//  SwiftData gleicht intern über Core Data mit CloudKit ab und sendet
//  dabei `NSPersistentCloudKitContainer.eventChangedNotification`. Jede
//  Einrichtung, jedes Hochladen und jedes Herunterladen erzeugt zwei
//  Meldungen: eine zum Start und eine zum Ende. Durchgelassen wird nur
//  das erfolgreich beendete Herunterladen – erst dann stehen die neuen
//  Einträge im Speicher und ein erneutes Lesen lohnt sich.
//
//  Kapselt Core Data an einer Stelle, damit die Oberfläche davon
//  nichts wissen muss. Ohne iCloud (lokaler Speicher) kommt nie eine
//  Meldung; das ist gewollt.
//

import Combine
import CoreData
import Foundation

nonisolated enum FilterListCloudEvents {

    /// Feuert auf dem Main-Thread, nachdem Änderungen aus iCloud
    /// erfolgreich übernommen wurden.
    static var remoteChangesImported: AnyPublisher<Void, Never> {
        NotificationCenter.default
            .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .filter(isFinishedImport)
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Nur ein abgeschlossenes, erfolgreiches Herunterladen zählt.
    private static func isFinishedImport(_ notification: Notification) -> Bool {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else {
            return false
        }
        return event.type == .import && event.endDate != nil && event.succeeded
    }
}
