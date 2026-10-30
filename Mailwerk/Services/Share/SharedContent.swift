//
//  SharedContent.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 14.10.2026
//  Geändert: 14.10.2026
//
//  Zweck: Inhalte, die eine andere App über „Teilen“ an Mailwerk übergibt,
//  und die Regeln, wie daraus eine neue Mail wird:
//  - Dateien, Fotos, Videos und Kontakte (vCard) → Anhänge,
//  - Links → antippbare Links im Text; die Seitenüberschrift wird Betreff,
//  - markierter Text → Text der Mail.
//
//  Reine Logik ohne Oberfläche und ohne Systemdienste, deshalb ohne Gerät
//  testbar. Das Einlesen aus den Systemdaten erledigt SharedItemLoader in
//  der Erweiterung.
//
//  Abgrenzung: Einlesen → SharedItemLoader (Erweiterung); Vorbelegung des
//  Verfassen-Fensters → ComposeViewModel.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Ein geteilter Anhang.
nonisolated struct SharedAttachment: Equatable, Sendable {
    /// Dateiname, wie er beim Empfänger erscheint.
    var filename: String
    /// MIME-Typ, z. B. „image/jpeg“.
    var mimeType: String
    /// Inhalt.
    var data: Data
}

/// Alles, was mit einem Teilen-Vorgang übergeben wurde.
nonisolated struct SharedContent: Equatable, Sendable {
    /// Anhänge in der übergebenen Reihenfolge.
    var attachments: [SharedAttachment] = []
    /// Geteilte Texte (z. B. markierter Text).
    var texts: [String] = []
    /// Geteilte Links (Web-Adressen).
    var links: [URL] = []
    /// Überschrift, die die teilende App mitliefert (z. B. Safari: Seitentitel).
    var title: String?

    /// `true`, wenn nichts Verwertbares übergeben wurde.
    var isEmpty: Bool {
        attachments.isEmpty && texts.isEmpty && links.isEmpty
    }

    /// Betreff der neuen Mail.
    ///
    /// Verarbeitung: Nur wenn ein Link geteilt wurde, wird die mitgelieferte
    /// Überschrift zum Betreff – bei Texten wäre sie meist der Text selbst.
    /// Mehrzeilige oder sehr lange Überschriften (über 200 Zeichen) gelten
    /// nicht als Seitentitel. Sonst bleibt der Betreff leer.
    var subject: String? {
        guard !links.isEmpty,
              let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              title.count <= 200,
              !title.contains(where: \.isNewline) else { return nil }
        return title
    }

    /// Bestandteile des Mailtexts in ihrer Reihenfolge: erst die Texte, dann
    /// die Links (jeweils als eigener Absatz).
    ///
    /// Verarbeitung: Leere Texte entfallen. Ein Text, der nur aus einem der
    /// geteilten Links besteht (manche Apps liefern den Link zusätzlich als
    /// Text), entfällt ebenfalls, damit der Link nicht doppelt erscheint.
    var bodyParts: [SharedBodyPart] {
        let linkStrings = Set(links.map(\.absoluteString))
        let textParts = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !linkStrings.contains($0) }
            .map(SharedBodyPart.text)
        return textParts + links.map(SharedBodyPart.link)
    }
}

/// Ein Absatz im Text einer geteilten Mail.
nonisolated enum SharedBodyPart: Equatable, Sendable {
    /// Gewöhnlicher Text.
    case text(String)
    /// Antippbarer Link.
    case link(URL)
}

/// Regeln für Dateinamen geteilter Anhänge.
nonisolated enum SharedContentRules {

    /// Dateiname eines geteilten Anhangs.
    ///
    /// Verarbeitung: Nimmt den von der teilenden App vorgeschlagenen Namen
    /// (sonst den Ersatznamen) und hängt die Endung des Typs an, falls der
    /// Name noch keine Endung hat. Schrägstriche und Doppelpunkte werden
    /// ersetzt, damit kein Pfad entsteht.
    ///
    /// - Parameters:
    ///   - suggested: Vorgeschlagener Name; `nil` oder leer = Ersatzname.
    ///   - fileExtension: Übliche Endung des Typs (ohne Punkt), z. B. „jpeg“.
    ///   - fallback: Ersatzname, z. B. „Foto“.
    /// - Returns: Dateiname.
    static func filename(suggested: String?, fileExtension: String?, fallback: String) -> String {
        let trimmed = suggested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = (trimmed.isEmpty ? fallback : trimmed)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard let fileExtension, !fileExtension.isEmpty,
              (base as NSString).pathExtension.isEmpty else { return base }
        return "\(base).\(fileExtension)"
    }

    /// Macht gleiche Dateinamen eindeutig.
    ///
    /// Verarbeitung: Der erste Name bleibt; jede Wiederholung bekommt vor
    /// der Endung eine laufende Nummer („Foto.jpeg“, „Foto 2.jpeg“, …).
    /// Groß-/Kleinschreibung zählt nicht als Unterschied.
    ///
    /// - Parameter names: Dateinamen in ihrer Reihenfolge.
    /// - Returns: Eindeutige Dateinamen in derselben Reihenfolge.
    static func uniqueFilenames(_ names: [String]) -> [String] {
        var used: Set<String> = []
        return names.map { name in
            guard used.contains(name.lowercased()) else {
                used.insert(name.lowercased())
                return name
            }
            let ext = (name as NSString).pathExtension
            let stem = (name as NSString).deletingPathExtension
            var number = 2
            var candidate = name
            repeat {
                candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
                number += 1
            } while used.contains(candidate.lowercased())
            used.insert(candidate.lowercased())
            return candidate
        }
    }
}
