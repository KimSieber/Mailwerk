# Mailwerk – Entwicklungsdokumentation v0.1.0

2026-09-18 · Commit-Stand vor Übergang auf 0.1.1

---

## Zusammenfassung

Version 0.1.0 umfasst die Grundstruktur des Mailwerk-Clients: Xcode-Projekt, Package-Integration, Postfach-Einrichtung mit Verbindungstest, Unified Inbox mit Pull-to-Refresh, lokaler Nachrichten-Cache (SQLite) mit Body- und Anhänge-Download sowie HTML-Rendering der Detailansicht über WKWebView.

Die App ist auf iPhone, iPad und Mac lauffähig (SwiftUI Multiplatform).

---

## Projektstruktur

```
Mailwerk/
├── Models/
│   ├── MailAccount.swift           # IMAP/SMTP-Konto (ohne Passwort)
│   └── CachedMessage.swift         # Lokal gecachte Nachricht + Anhang-Modell
├── ViewModels/
│   ├── AddAccountViewModel.swift   # Logik für Postfach-Einrichtung
│   └── InboxViewModel.swift        # Unified-Inbox-Logik, Cache-Zugriff
├── Views/
│   ├── AccountListView.swift       # Kontoverwaltung
│   ├── AddAccountView.swift        # Formular: neues Postfach anlegen
│   ├── InboxView.swift             # Unified Inbox mit Pull-to-Refresh
│   ├── MessageDetailView.swift     # Nachricht-Detailansicht
│   └── HTMLMailView.swift          # WKWebView-Wrapper für HTML-Mails
├── Services/
│   ├── KeychainService.swift       # Keychain-Wrapper (iCloud-Sync)
│   ├── AccountStore.swift          # Account-Persistenz (NSUbiquitousKeyValueStore)
│   ├── MailConnectionTester.swift  # IMAP/SMTP-Verbindungstest
│   ├── MailFetchService.swift      # IMAP-Abruf mit Cache-Logik
│   └── MessageStore.swift          # SQLite-Wrapper für lokalen Cache
├── MailwerkApp.swift
└── ContentView.swift
```

---

## Erledigte Schritte (v0.1.0)

### Schritt 1: Projektstruktur & Package-Dependency

- Xcode-Projekt als Multiplatform-App (SwiftUI) angelegt
- GitHub-Repo: `KimSieber/Mailwerk` (public)
- Bundle Identifier: `de.sieber-bw.Mailwerk`
- **SwiftMail** (Cocoanetics) als SPM-Dependency hinzugefügt – deckt IMAP und SMTP ab
- Ordnerstruktur Models/ViewModels/Views/Services angelegt

### Schritt 2: Datenmodell & sichere Speicherung

- `MailAccount`-Struct: Host, Port, Username, Displayname für IMAP und SMTP
- Passwort separat im Keychain, referenziert über Account-UUID
- **iCloud-Keychain-Sync** aktiviert (`kSecAttrSynchronizable = true`) – Passwörter synchronisieren automatisch zwischen eigenen Geräten
- **NSUbiquitousKeyValueStore** für Account-Metadaten – synchronisiert ebenfalls über iCloud, inkl. `didChangeExternallyNotification`-Handler für Live-Updates
- Xcode-Capabilities: iCloud (Key-value storage) + Keychain Sharing

### Schritt 3: Postfach-Einrichtung (UI)

- Formular mit Feldern: Anzeigename, Benutzername, Passwort, IMAP-Host/Port, SMTP-Host/Port
- **Verbindungstest-Button**: testet IMAP (connect → login → selectMailbox INBOX → logout) und SMTP (connect → login → disconnect) nacheinander
- Erfolgreich getestet mit 2 realen Postfächern (manitu)
- Account-Liste mit Swipe-to-Delete

### Schritt 4: IMAP-Abruf & Unified Inbox

- **IMAP SEARCH SINCE** für serverseitige 30-Tage-Filterung (kein Download alter Mails)
- Header-Abruf mit `.slim`-Optionen (Envelope, Datum, Flags, Größe)
- Für neue Mails: vollständiger Body-Download via `fetchMessage(from:)`
- Für bereits gecachte Mails: nur Gelesen-Status aktualisieren (kein erneuter Download)
- **Anhänge**: automatischer Download bei Mails ≤ 5 MB Gesamtgröße, darüber nur Metadaten (Nachladen bei Tap, noch nicht implementiert)
- Alte Cache-Einträge jenseits des 30-Tage-Fensters werden beim Refresh bereinigt
- Unified Inbox: Nachrichten aller Konten gemischt, sortiert nach Datum (neueste zuerst)
- Pull-to-Refresh und automatischer Abruf beim App-Start

### Schritt 4b: Lokaler Cache (SQLite)

- System-SQLite (`import SQLite3`), kein externes Package
- Tabelle `message`: id, accountID, uid, subject, from, to, date, isUnread, totalSizeBytes, textBody, htmlBody, fetchedAt
- Tabelle `attachment`: id, messageID, filename, contentType, sizeBytes, data (BLOB, nullable)
- Foreign Key mit ON DELETE CASCADE
- Detailansicht liest ausschließlich aus dem Cache – kein Netzwerkzugriff beim Öffnen einer Mail

### Schritt 4c: HTML-Rendering

- `HTMLMailView`: WKWebView-Wrapper mit plattformspezifischer Implementierung (UIViewRepresentable / NSViewRepresentable)
- Dynamische Höhenmessung über JavaScript (`document.body.scrollHeight`) nach Laden des HTML
- Dark-Mode-Support über CSS `prefers-color-scheme`
- HTML-Body wird bevorzugt vor Plain-Text angezeigt

---

## Getroffene Architektur- & Design-Entscheidungen

| Entscheidung | Begründung |
|---|---|
| **SwiftMail** (Cocoanetics) als IMAP/SMTP-Framework | Moderne async/actor-API auf Swift NIO, aktiv gepflegt, deckt alle benötigten IMAP-Operationen ab |
| **IMAP + SMTP**, kein POP3 | IMAP für serverseitigen Zustand (Flags, Ordner), SMTP für Versand |
| **iCloud Keychain-Sync** für Passwörter | Ende-zu-Ende-verschlüsselt, keine eigene Serverinfrastruktur nötig, Zugangsdaten verlassen nie einen verarbeitenden Dienst |
| **NSUbiquitousKeyValueStore** für Account-Metadaten | Einfachste iCloud-Sync-Lösung, für wenige Accounts (< 1 MB) ausreichend |
| **System-SQLite** statt GRDB.swift | GRDB verursachte Package-Resolution-Konflikt mit SwiftMail; System-SQLite hat null externe Abhängigkeiten und reicht für den Cache |
| **Spam-Blacklist/Whitelist serverseitig** (ManageSieve) | Greift geräteübergreifend, keine Cloud-Sync der Liste nötig; Klärung mit manitu-Support läuft |
| **30-Tage-Sync-Fenster** (fest, später konfigurierbar) | Marktüblich (Apple Mail iOS), begrenzt Speicher- und Datenverbrauch |
| **Anhänge automatisch ≤ 5 MB**, darüber on-demand | Schutz vor Mobilfunkvolumen-Verbrauch durch einzelne große Mails |
| **CloudKit (2b) verworfen** zugunsten von NSUbiquitousKeyValueStore (2a) | Kein Bedarf für strukturierte DB-Sync, da Blacklist serverseitig gepflegt wird |

---

## Bekannte Technical Debts / Offene Nacharbeiten

Diese Liste wird fortlaufend gepflegt und in den nächsten Versionen abgearbeitet:

| # | Bereich | Beschreibung | Priorität |
|---|---|---|---|
| TD-1 | Postfach-UI | `try?` beim Speichern/Löschen von Accounts schluckt Keychain-Fehler stillschweigend – sauberes Fehlerhandling nachholen | Mittel |
| TD-2 | IMAP-Verbindung | Für jeden Refresh wird eine neue IMAP-Verbindung auf-/abgebaut, kein Connection-Pooling/IDLE – bewusste MVP1-Vereinfachung, wird mit Push-Ausbaustufe (0.4.x) ersetzt | Niedrig (geplant) |
| TD-3 | Cache-Sync | Kein Abgleich, wenn eine Mail serverseitig gelöscht/verschoben wurde – bleibt aktuell dauerhaft im lokalen Cache | Mittel |
| TD-4 | Cache-Flags | Beim Refresh wird nur der Gelesen-Status (isUnread) aktualisiert, andere Flags (beantwortet, geflaggt) werden nicht nachgezogen | Mittel |
| TD-5 | Anhänge > 5 MB | On-demand-Nachladen bei Tap ist noch nicht implementiert (nur Metadaten werden gespeichert) | Hoch |
| TD-6 | Anhänge-Anzeige | Gecachte Anhänge werden in der Detailansicht noch nicht angezeigt (kein UI dafür) | Hoch |

---

## Noch nicht implementiert (geplant für 0.1.x)

Laut ursprünglicher MVP1-Roadmap stehen noch aus:

- [ ] **SMTP-Versand**: Senden / Antworten / Weiterleiten (SwiftMail SMTPServer-API steht bereit)
- [ ] **Basis-Aktionen**: Löschen, Verschieben, Gelesen/Ungelesen markieren, Flag setzen (IMAP STORE/MOVE)
- [ ] **Anhänge in der Detailansicht anzeigen** (gecachte + on-demand für > 5 MB)
- [ ] **Weitere Ordner**: aktuell wird nur INBOX synchronisiert – Sent, Drafts, Trash etc. fehlen
- [ ] **Account bearbeiten**: angelegte Konten können nur gelöscht, nicht editiert werden
- [ ] **Fehlerhandling**: durchgängig saubere Fehlermeldungen statt `try?`

---

## Dateien im Projekt (Stand v0.1.0)

| Datei | Zeilen (ca.) | Beschreibung |
|---|---|---|
| `MailAccount.swift` | 45 | Konto-Datenmodell |
| `CachedMessage.swift` | 35 | Cache-Datenmodell (Message + Attachment) |
| `KeychainService.swift` | 75 | Keychain CRUD mit iCloud-Sync |
| `AccountStore.swift` | 55 | Account-Persistenz (iCloud KVS) |
| `MailConnectionTester.swift` | 45 | IMAP/SMTP-Verbindungstest |
| `MailFetchService.swift` | 110 | IMAP-Abruf mit 30-Tage-Filter und Cache-Logik |
| `MessageStore.swift` | 220 | SQLite-Wrapper (Messages + Attachments) |
| `AddAccountViewModel.swift` | 60 | ViewModel für Konto-Einrichtung |
| `InboxViewModel.swift` | 45 | ViewModel für Unified Inbox |
| `AccountListView.swift` | 50 | Kontoverwaltungs-View |
| `AddAccountView.swift` | 80 | Konto-Einrichtungs-Formular |
| `InboxView.swift` | 85 | Unified Inbox + InboxRow |
| `MessageDetailView.swift` | 45 | Mail-Detailansicht |
| `HTMLMailView.swift` | 95 | WKWebView-Wrapper (iOS + macOS) |
| `ContentView.swift` | 15 | Root-View |
| `MailwerkApp.swift` | 12 | App-Einstiegspunkt |

---

## Abhängigkeiten

| Package | Version | Zweck |
|---|---|---|
| [SwiftMail](https://github.com/Cocoanetics/SwiftMail) | Up to Next Major | IMAP- und SMTP-Client (baut auf Swift NIO) |
| System-SQLite (`import SQLite3`) | – | Lokaler Nachrichten-Cache |

Verworfene Abhängigkeit: **GRDB.swift** – Package-Resolution-Konflikt mit SwiftMail (`swift-tools-version: 6.1` / `swiftLanguageModes: [.v6]`).

---

## Xcode-Konfiguration

- **Xcode**: 26.6
- **Swift**: 5.0
- **Deployment Targets**: iOS 26.5, macOS 26.5, visionOS 26.5
- **Bundle Identifier**: `de.sieber-bw.Mailwerk`
- **Development Team**: 62QD57DH52
- **Capabilities**: iCloud (Key-value storage), Keychain Sharing
- **Supported Platforms**: iphoneos, iphonesimulator, macosx, xros, xrsimulator
