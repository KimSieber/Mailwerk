//
//  AttachmentTransferable.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 27.10.2026
//  Geändert: 27.10.2026
//
//  Zweck: Stellt einen Anhang als Datei zum Herausziehen (Drag & Drop)
//  bereit – aus der Mailansicht in den Finder, auf den Schreibtisch oder
//  in andere Apps. Nur Mac.
//
//  Beim Start des Ziehens wird die Datei über
//  `AttachmentManager.writeTempFile` ins Temp-Verzeichnis der App
//  geschrieben – mit bereinigtem Namen (ein Pfadtrenner im MIME-Dateinamen
//  kann nicht aus dem Verzeichnis ausbrechen) und passender Endung – und
//  beim nächsten Start mit den übrigen Anhang-Dateien aufgeräumt. Gezogen
//  wird die Datei selbst (Datei-URL); das Ziel übernimmt so Namen und
//  Endung des Anhangs.
//
//  Hinweis: Die frühere Fassung bot den Anhang als
//  `FileRepresentation` mit dem Typ „Daten“ an. Der Finder legte ihn dann
//  unter dem Namen „Daten“ ohne Endung ab, weil diese Darstellung keinen
//  Dateinamen je Anhang mitgibt.
//
//  Abgrenzung: Die Zeile, die das Ziehen anbietet → AttachmentRow;
//  Schreiben und Bereinigen der Dateien → AttachmentManager.
//
//  Abhängigkeiten: Foundation, AttachmentManager, CachedAttachment, Log.
//

#if os(macOS)
import Foundation
import os

/// Anhang als ziehbare Datei (Mac).
enum AttachmentTransferable {

    /// Liefert den Anbieter für das Herausziehen eines Anhangs.
    ///
    /// Verarbeitung: Schreibt die Datei ins Temp-Verzeichnis und bietet sie
    /// als Datei-URL an; der Dateiname wird zusätzlich als Vorschlag
    /// gesetzt. Lässt sich die Datei nicht schreiben (z. B. Daten nicht
    /// geladen), wird ein leerer Anbieter geliefert – das Ziel erhält
    /// nichts, der Fehler wird protokolliert.
    ///
    /// - Parameter attachment: Anhang mit geladenen Daten.
    /// - Returns: Anbieter für das Ziehen.
    static func itemProvider(for attachment: CachedAttachment) -> NSItemProvider {
        do {
            let url = try AttachmentManager.writeTempFile(for: attachment)
            guard let provider = NSItemProvider(contentsOf: url) else {
                return NSItemProvider()
            }
            provider.suggestedName = url.lastPathComponent
            return provider
        } catch {
            Log.view.error("⚠️ Anhang nicht zum Ziehen bereitgestellt: \(error.localizedDescription, privacy: .public)")
            return NSItemProvider()
        }
    }
}
#endif
