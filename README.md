# Mailwerk

Mailwerk ist ein alternativer E-Mail-Client für iPhone, iPad und Mac, geschrieben in Swift/SwiftUI.

Schwerpunkte:

- gemeinsamer Posteingang für mehrere IMAP-Postfächer („Alle Eingänge“)
- eigener, clientseitiger Spamfilter mit Black- und Whitelist (Abgleich über iCloud)
- offline nutzbar dank lokalem Cache
- Signaturen, Entwürfe, Suche, Teilen-Erweiterung

## Voraussetzungen

- Xcode (aktuelle Version) und ein Apple-Developer-Konto zum Signieren
- Swift-Package-Abhängigkeit: [SwiftMail](https://github.com/Cocoanetics/SwiftMail) (wird von Xcode automatisch geladen)

## Lizenz

Der Quellcode von Mailwerk steht unter der [MIT-Lizenz](LICENSE).

**Ausgenommen** sind der Name „Mailwerk“ und das App-Icon (der Ordner `AppIcons/`, `Mailwerk/AppIcon.icon` sowie die App-Icon-Grafiken in den Asset-Katalogen). Alle Rechte daran bleiben vorbehalten. Wer den Code für ein eigenes Projekt nutzt, muss einen anderen Namen und ein anderes Icon verwenden – insbesondere bei einer Veröffentlichung in einem App Store.

### Verwendete Open-Source-Komponenten

| Komponente | Lizenz |
|---|---|
| [SwiftMail](https://github.com/Cocoanetics/SwiftMail) (Oliver Drobnik) | BSD 2-Clause |
| [SwiftNIO](https://github.com/apple/swift-nio), [swift-nio-imap](https://github.com/apple/swift-nio-imap), [swift-nio-ssl](https://github.com/apple/swift-nio-ssl) und weitere Apple-Pakete (über SwiftMail) | Apache 2.0 |

Die Lizenztexte liegen in den jeweiligen Repositories.

---

© 2026 Kim Sieber
