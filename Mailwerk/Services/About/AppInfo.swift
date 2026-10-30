//
//  AppInfo.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 29.10.2026
//  Geändert: 29.10.2026
//
//  Zweck: Feste Angaben zur App für „Über Mailwerk“ – Name, Version mit
//  Build-Nummer, Urheberzeile, Kontaktadresse und Webseite.
//
//  Version und Build-Nummer kommen aus dem Bundle (Projekteinstellungen
//  MARKETING_VERSION und CURRENT_PROJECT_VERSION); sie müssen hier nie
//  von Hand nachgezogen werden. Kontakt, Webseite und Urheberzeile
//  stehen nur hier, damit sie an einer Stelle gepflegt werden.
//
//  Abgrenzung: Anzeige → AboutView; Lizenzen → OpenSourceLicenses.
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Feste Angaben zur App.
nonisolated enum AppInfo {
    /// Name der App.
    static let name = "Mailwerk"

    /// Urheberzeile.
    static let copyright = "© 2026 Kim Sieber, Stuttgart"

    /// Kontaktadresse für Rückmeldungen.
    static let contactAddress = "Mailwerk@Sieber-BW.de"

    /// Kontaktadresse als mailto:-Link.
    static let contactURL = URL(string: "mailto:\(contactAddress)")!

    /// Webseite der App.
    static let websiteURL = URL(string: "https://mailwerk.sieber-bw.de")!

    /// Webseite als angezeigter Text.
    static var websiteText: String { websiteURL.absoluteString }

    /// Versionsnummer, z. B. „0.3.0“; „–“, falls nicht ermittelbar.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    /// Build-Nummer, z. B. „1“; „–“, falls nicht ermittelbar.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    /// Anzeigetext der Version, z. B. „Version 0.3.0 (1)“.
    static var versionText: String {
        "Version \(version) (\(build))"
    }
}
