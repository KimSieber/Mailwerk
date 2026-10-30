//
//  OpenSourceLicenses.swift
//  Mailwerk
//  Autor: Kim Sieber
//  Erstellt: 29.10.2026
//  Geändert: 29.10.2026
//
//  Zweck: Verzeichnis der Open-Source-Komponenten, die in Mailwerk
//  stecken, samt ihrer Lizenztexte – für „Über Mailwerk“ →
//  „Open-Source-Lizenzen“.
//
//  Die Lizenzen von SwiftMail (BSD 2-Clause), SwiftCross (MIT) und den
//  Apple-Paketen (Apache 2.0) verlangen, dass Urheberhinweis, Lizenztext
//  und – bei Apache 2.0 – die NOTICE-Datei mit der fertigen App
//  ausgeliefert werden. Die Texte liegen deshalb unverändert als
//  Textdateien in `Resources/Licenses/` und werden aus dem Bundle gelesen
//  (offline verfügbar, kein Abruf aus dem Netz).
//
//  Pflege: Kommt eine Abhängigkeit hinzu oder fällt eine weg, hier den
//  Eintrag ergänzen bzw. entfernen und die Textdatei aus dem Repository
//  der Komponente in `Resources/Licenses/` ablegen bzw. löschen.
//  Swift Collections, Swift Atomics und Swift System stehen unter
//  Apache 2.0 mit „Runtime Library Exception“ (keine Pflicht zur Nennung);
//  sie sind der Vollständigkeit halber trotzdem aufgeführt.
//
//  Abgrenzung: Anzeige → LicenseListView; Lizenz von Mailwerk selbst →
//  LICENSE im Repository (Kopie in License-Mailwerk.txt).
//
//  Abhängigkeiten: Foundation.
//

import Foundation

/// Eine Komponente mit ihrer Lizenz.
nonisolated struct OpenSourceComponent: Identifiable, Hashable, Sendable {
    /// Name der Komponente; zugleich Kennung.
    let name: String
    /// Bezeichnung der Lizenz, z. B. „MIT“.
    let licenseName: String
    /// Herkunft, z. B. „über SwiftMail“; `nil` = direkt verwendet.
    let origin: String?
    /// Webseite bzw. Repository der Komponente.
    let websiteURL: URL
    /// Name der Lizenzdatei im Bundle (ohne Endung „.txt“).
    let licenseFile: String
    /// Name der NOTICE-Datei im Bundle (ohne Endung); `nil` = keine.
    let noticeFile: String?

    /// Kennung für Listen.
    var id: String { name }
}

/// Verzeichnis der Komponenten und Zugriff auf ihre Lizenztexte.
nonisolated enum OpenSourceLicenses {

    /// Mailwerk selbst.
    static let mailwerk = OpenSourceComponent(
        name: "Mailwerk",
        licenseName: "MIT",
        origin: nil,
        websiteURL: URL(string: "https://github.com/KimSieber/Mailwerk")!,
        licenseFile: "License-Mailwerk",
        noticeFile: nil
    )

    /// Verwendete Komponenten, in der Reihenfolge der Anzeige.
    static let components: [OpenSourceComponent] = [
        OpenSourceComponent(
            name: "SwiftMail",
            licenseName: "BSD 2-Clause",
            origin: nil,
            websiteURL: URL(string: "https://github.com/Cocoanetics/SwiftMail")!,
            licenseFile: "License-SwiftMail",
            noticeFile: nil
        ),
        OpenSourceComponent(
            name: "SwiftCross",
            licenseName: "MIT",
            origin: "über SwiftMail",
            websiteURL: URL(string: "https://github.com/Cocoanetics/SwiftCross")!,
            licenseFile: "License-SwiftCross",
            noticeFile: nil
        ),
        OpenSourceComponent(
            name: "SwiftNIO",
            licenseName: "Apache 2.0",
            origin: "über SwiftMail",
            websiteURL: URL(string: "https://github.com/apple/swift-nio")!,
            licenseFile: "License-Apache-2.0",
            noticeFile: "Notice-swift-nio"
        ),
        OpenSourceComponent(
            name: "SwiftNIO SSL (mit BoringSSL)",
            licenseName: "Apache 2.0",
            origin: "über SwiftMail",
            websiteURL: URL(string: "https://github.com/apple/swift-nio-ssl")!,
            licenseFile: "License-Apache-2.0",
            noticeFile: "Notice-swift-nio-ssl"
        ),
        OpenSourceComponent(
            name: "SwiftNIO IMAP",
            licenseName: "Apache 2.0",
            origin: "über SwiftMail",
            websiteURL: URL(string: "https://github.com/apple/swift-nio-imap")!,
            licenseFile: "License-Apache-2.0",
            noticeFile: "Notice-swift-nio-imap"
        ),
        OpenSourceComponent(
            name: "Swift Logging API",
            licenseName: "Apache 2.0",
            origin: "über SwiftMail",
            websiteURL: URL(string: "https://github.com/apple/swift-log")!,
            licenseFile: "License-Apache-2.0",
            noticeFile: "Notice-swift-log"
        ),
        OpenSourceComponent(
            name: "Swift Collections",
            licenseName: "Apache 2.0",
            origin: "über SwiftMail",
            websiteURL: URL(string: "https://github.com/apple/swift-collections")!,
            licenseFile: "License-Apache-2.0-RuntimeException",
            noticeFile: nil
        ),
        OpenSourceComponent(
            name: "Swift Atomics",
            licenseName: "Apache 2.0",
            origin: "über SwiftNIO",
            websiteURL: URL(string: "https://github.com/apple/swift-atomics")!,
            licenseFile: "License-Apache-2.0-RuntimeException",
            noticeFile: nil
        ),
        OpenSourceComponent(
            name: "Swift System",
            licenseName: "Apache 2.0",
            origin: "über SwiftNIO",
            websiteURL: URL(string: "https://github.com/apple/swift-system")!,
            licenseFile: "License-Apache-2.0-RuntimeException",
            noticeFile: nil
        )
    ]

    /// Vollständiger Text zu einer Komponente: Lizenz, ggf. gefolgt von
    /// ihrer NOTICE-Datei.
    ///
    /// Verarbeitung: Liest die Textdateien aus dem Bundle. Fehlt eine
    /// Datei (z. B. versehentlich nicht im Ziel), steht statt des Texts
    /// ein Hinweis mit der Webseite der Komponente – die Ansicht bleibt
    /// benutzbar.
    ///
    /// - Parameter component: Komponente.
    /// - Returns: Anzuzeigender Text.
    static func fullText(for component: OpenSourceComponent) -> String {
        guard let license = text(named: component.licenseFile) else {
            return "Lizenztext nicht gefunden. Er ist unter \(component.websiteURL.absoluteString) einsehbar."
        }
        guard let noticeFile = component.noticeFile, let notice = text(named: noticeFile) else {
            return license
        }
        return license + "\n\n――――――――――  NOTICE  ――――――――――\n\n" + notice
    }

    /// Liest eine Textdatei aus dem Bundle.
    ///
    /// - Parameter name: Dateiname ohne Endung „.txt“.
    /// - Returns: Inhalt, oder `nil`, wenn die Datei fehlt oder nicht lesbar ist.
    private static func text(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
