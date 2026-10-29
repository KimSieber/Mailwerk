# Mailwerk – Entwicklungsdokumentation v0.1.1

2026-09-19 · Commit-Stand vor Übergang auf 0.1.2

---

## Zusammenfassung

Version 0.1.1 ergänzt die in v0.1.0 angelegte Cache-Infrastruktur um vollständiges Anhang-Handling: Anzeige gecachter Anhänge in der Detailansicht, On-demand-Download für Mails > 5 MB, QuickLook-Vorschau (PDF, Bilder, Text etc.), Teilen/Speichern über das System-Share-Sheet, lokales Löschen von Anhang-Daten zur Speicherfreigabe sowie eine Büroklammer-Kennzeichnung in der Inbox-Liste.

Zusätzlich wurden mehrere Bugfixes und UX-Verbesserungen vorgenommen, die während der Entwicklung aufgefallen sind.

---

## Projektstruktur (Änderungen gegenüber v0.1.0)

```
Mailwerk/
├── Models/
│   ├── MailAccount.swift               # unverändert
│   ├── CachedMessage.swift             # + hasAttachments-Flag
│   └── InboxMessage.swift              # unverändert (aktuell nicht aktiv genutzt)
├── ViewModels/
│   ├── AddAccountViewModel.swift       # unverändert
│   └── InboxViewModel.swift            # + inkrementeller Listenaufbau, Diagnose-Logging
├── Views/
│   ├── AccountListView.swift           # unverändert
│   ├── AddAccountView.swift            # unverändert
│   ├── InboxView.swift                 # + Büroklammer, Lade-Spinner, Toolbar-Fortschritt
│   ├── MessageDetailView.swift         # + Anhang-Sektion, QuickLook, Drei-Punkte-Menü
│   ├── AttachmentRow.swift             # NEU – Anhang-Zeile mit Vorschau/Share/Download
│   └── HTMLMailView.swift              # unverändert
├── Services/
│   ├── KeychainService.swift           # unverändert
│   ├── AccountStore.swift              # unverändert
│   ├── MailConnectionTester.swift      # unverändert
│   ├── MailFetchService.swift          # + inkrementelles Speichern, per-Message-Error-Handling
│   ├── MessageStore.swift              # + Migration, UPSERT, updateFlags, deleteAttachmentData
│   └── AttachmentManager.swift         # NEU – Temp-Dateien, On-demand-IMAP-Download
├── MailwerkApp.swift
└── ContentView.swift
```

---

## Erledigte Schritte (v0.1.1)

### Anhang-Handling (Hauptfeature)

- **Büroklammer-Icon in der Inbox-Liste**: `hasAttachments`-Bool in `CachedMessage` und SQLite-Schema, wird beim IMAP-Abruf gesetzt. InboxRow zeigt SF Symbol `paperclip` zwischen Absender und Datum.
- **Anhang-Liste in der Detailansicht**: Unterhalb des Mail-Bodys, mit Überschrift „Anhänge (n)". Pro Anhang: Typ-Icon (nach MIME-Type), Dateiname, formatierte Größe.
- **QuickLook-Vorschau**: Tap auf einen Anhang schreibt die Daten als temporäre Datei und öffnet `.quickLookPreview()`. Unterstützt nativ PDF, Bilder, Text und viele weitere Formate.
- **On-demand-Download**: Anhänge von Mails > 5 MB (nur Metadaten im Cache) werden bei Tap per IMAP nachgeladen. Spinner während des Downloads, automatische Vorschau nach Abschluss.
- **Teilen / Speichern**: `ShareLink` pro Anhang (↑-Button), öffnet das System-Share-Sheet. Funktioniert auf iOS, iPadOS und macOS.
- **Lokales Löschen**: Über das Drei-Punkte-Menü → „Anlagen lokal löschen". Setzt nur die BLOBs in SQLite auf NULL, Metadaten bleiben erhalten. Anhänge zeigen danach „Tippen zum Laden" und können erneut vom Server geholt werden. Bestätigungsdialog vor dem Löschen.

### Drei-Punkte-Aktionsmenü (Gerüst)

In der Navigationsleiste der Detailansicht (`ellipsis.circle`), vier gruppierte Sektionen:

| Sektion | Menüpunkte | Status |
|---|---|---|
| Kommunikation | Antworten, Allen antworten, Weiterleiten | Platzhalter (disabled) |
| Organisation | Kennzeichnen, Gelesen/Ungelesen, In Ordner verschieben | Platzhalter (disabled) |
| Spam | Als Spam verschieben, Absender/Domain → Black-/Whitelist (4 Einträge) | Platzhalter (disabled) |
| Sonstiges | Teilen, Drucken, **Anlagen lokal löschen**, Mail löschen | Löschen aktiv, Rest Platzhalter |

### Bugfixes

- **`sqlite3_step` fehlte in `saveMessage`**: Nachrichten wurden vorbereitet aber nie in die Datenbank geschrieben. Ursache: beim Hinzufügen des `hasAttachments`-Bindings wurde der `sqlite3_step(stmt)`-Aufruf versehentlich entfernt.
- **`INSERT OR REPLACE` löste Cascade-Deletes aus**: Jedes Update einer gecachten Nachricht löschte alle zugehörigen Anhänge, da `INSERT OR REPLACE` intern als `DELETE + INSERT` implementiert ist und `ON DELETE CASCADE` auf der Attachment-Tabelle griff. Fix: Umstellung auf `INSERT ... ON CONFLICT(id) DO UPDATE SET ...` (UPSERT) für Messages und Attachments. Zusätzlich neue leichtgewichtige `updateFlags()`-Methode für den häufigsten Fall (nur Gelesen-Status).
- **Ständiger Neu-Abruf bei Navigation**: `.task { await viewModel.refresh() }` feuerte bei jedem Erscheinen der InboxView, auch beim Zurücknavigieren aus der Detailansicht. Fix: `hasLoadedOnce`-Flag, automatischer Abruf nur beim allerersten Erscheinen.
- **Migration „duplicate column"**: Bei Neuinstallation legte `CREATE TABLE` die `hasAttachments`-Spalte bereits an, `migrateIfNeeded()` versuchte sie erneut hinzuzufügen. Fix: `columnExists()`-Check per `PRAGMA table_info` vor `ALTER TABLE`.
- **Backfill für bestehende Caches**: Nach der Migration werden bestehende Nachrichten anhand der Attachment-Tabelle nachträglich mit `hasAttachments = 1` aktualisiert.

### UX-Verbesserungen

- **Lade-Spinner beim Erststart**: Großer `ProgressView` mit Text „Postfächer werden abgerufen …" statt leerem Bildschirm während des initialen Abrufs.
- **Inkrementeller Listenaufbau**: Nach jedem abgeschlossenen Konto wird `loadFromCache()` aufgerufen, die Liste füllt sich schrittweise statt erst nach allen Konten.
- **Toolbar-Spinner**: Kleiner `ProgressView` links neben „Mailwerk" in der Navigationsleiste, sichtbar solange noch Konten im Hintergrund abgerufen werden.
- **Inkrementelles Speichern**: Jede Nachricht wird sofort nach dem Abruf einzeln in den Cache geschrieben (statt Batch am Ende). Bei einem Abbruch gehen bereits abgerufene Mails nicht verloren.
- **Per-Message Error Handling**: Fehler beim Abruf einer einzelnen Mail (kaputte MIME-Struktur, Timeout) überspringen die Mail und setzen den Abruf fort, statt den ganzen Account abzubrechen.

---

## Getroffene Architektur- & Design-Entscheidungen (v0.1.1)

| Entscheidung | Begründung |
|---|---|
| **Nur lokales Löschen von Anhängen** | IMAP-Nachrichten sind serverseitig unveränderlich. Strip-and-Replace (Download → MIME umbauen → APPEND → DELETE) ist aufwendig, fehleranfällig und bei manchen Servern problematisch (UID-Wechsel, Flags/Threading). Apple Mail bietet es ebenfalls nicht an. |
| **QuickLook via `.quickLookPreview()`** | SwiftUI-native Lösung (ab iOS 15 / macOS 12), kein eigener UIViewControllerRepresentable-Wrapper nötig. Unterstützt PDF, Bilder, Text und viele weitere Formate über Apples QL-Infrastruktur. |
| **ShareLink** für Anhang-Teilen | Apple-Standard (ab iOS 16 / macOS 13), öffnet das System-Share-Sheet. Plattformübergreifend, kein eigener Code für iOS/macOS-Unterscheidung nötig. |
| **UPSERT statt INSERT OR REPLACE** | `INSERT OR REPLACE` ist intern `DELETE + INSERT`, was `ON DELETE CASCADE` auslöst und Anhänge zerstört. `INSERT ... ON CONFLICT DO UPDATE` aktualisiert in-place ohne Löschung. |
| **`updateFlags()` als eigene Methode** | Der häufigste Update-Fall (nur Gelesen-Status) braucht kein vollständiges UPSERT. Ein einfaches `UPDATE ... SET isUnread = ? WHERE id = ?` ist schneller und risikoärmer. |
| **On-demand-Download per Dateiname/ContentType-Match** | Beim Nachladen eines einzelnen Anhangs wird die Nachricht erneut vom Server geholt und der passende MIME-Part über Dateiname + Content-Type identifiziert. Einfacher als das Speichern und Parsen der MIME-Section-ID. |
| **Temporäre Dateien für Vorschau/Share** | Anhang-Daten werden als temporäre Dateien in `FileManager.temporaryDirectory` geschrieben. Werden beim nächsten App-Neustart automatisch bereinigt. |

---

## Bekannte Technical Debts / Offene Nacharbeiten

| # | Bereich | Beschreibung | Priorität | Status |
|---|---|---|---|---|
| TD-1 | Postfach-UI | `try?` beim Speichern/Löschen von Accounts schluckt Keychain-Fehler stillschweigend | Mittel | Offen (aus v0.1.0) |
| TD-2 | IMAP-Verbindung | Kein Connection-Pooling/IDLE, für jeden Refresh neue Verbindung | Niedrig | Offen (geplant für 0.4.x) |
| TD-3 | Cache-Sync | Kein Abgleich bei serverseitiger Löschung/Verschiebung – Mail bleibt dauerhaft im Cache | Mittel | Offen (aus v0.1.0) |
| TD-4 | Cache-Flags | Nur isUnread wird aktualisiert, andere Flags (beantwortet, geflaggt) nicht | Mittel | Offen (aus v0.1.0) |
| TD-5 | Anhänge > 5 MB | On-demand-Nachladen bei Tap | ~~Hoch~~ | **Erledigt (v0.1.1)** |
| TD-6 | Anhänge-Anzeige | Gecachte Anhänge in der Detailansicht anzeigen | ~~Hoch~~ | **Erledigt (v0.1.1)** |
| TD-7 | Inbox-UI | `ContentUnavailableView` ist nicht scrollbar → Pull-to-Refresh greift im leeren Zustand nicht, App muss neu gestartet werden | Mittel | Neu (v0.1.1) |
| TD-8 | Erster Abruf | Erstabruf dauert ca. 4–6 Minuten bei 300 Mails (Body-Download pro Mail). Spinner + inkrementeller Aufbau lindern das UX-Problem, aber die Laufzeit selbst ist hoch | Niedrig | Neu (v0.1.1) |
| TD-9 | Diagnose-Logging | `print()`-Diagnose-Ausgaben (📬, 📋, 🔄, 📎 etc.) sind noch aktiv – vor einer Release-Version entfernen oder hinter ein Debug-Flag setzen | Niedrig | Neu (v0.1.1) |

---

## Noch nicht implementiert (geplant für 0.1.x)

Laut ursprünglicher MVP1-Roadmap stehen noch aus:

- [ ] **SMTP-Versand**: Senden / Antworten / Weiterleiten (SwiftMail SMTPServer-API steht bereit)
- [ ] **Basis-Aktionen**: Löschen, Verschieben, Gelesen/Ungelesen markieren, Flag setzen (IMAP STORE/MOVE)
- [ ] **Weitere Ordner**: aktuell wird nur INBOX synchronisiert – Sent, Drafts, Trash etc. fehlen
- [ ] **Account bearbeiten**: angelegte Konten können nur gelöscht, nicht editiert werden
- [ ] **Fehlerhandling**: durchgängig saubere Fehlermeldungen statt `try?`

---

## Dateien im Projekt (Stand v0.1.1)

| Datei | Zeilen (ca.) | Änderung | Beschreibung |
|---|---|---|---|
| `MailAccount.swift` | 45 | — | Konto-Datenmodell |
| `CachedMessage.swift` | 43 | Geändert | + `hasAttachments`-Flag |
| `InboxMessage.swift` | 35 | — | Server-Header-Modell (aktuell nicht aktiv) |
| `KeychainService.swift` | 75 | — | Keychain CRUD mit iCloud-Sync |
| `AccountStore.swift` | 55 | — | Account-Persistenz (iCloud KVS) |
| `MailConnectionTester.swift` | 45 | — | IMAP/SMTP-Verbindungstest |
| `MailFetchService.swift` | 170 | Geändert | + inkrementelles Speichern, per-Message-Errors, Diagnose |
| `MessageStore.swift` | 338 | Geändert | + Migration, UPSERT, updateFlags, deleteAttachmentData |
| `AttachmentManager.swift` | 123 | **Neu** | Temp-Dateien für Vorschau/Share, On-demand-IMAP-Download |
| `AddAccountViewModel.swift` | 60 | — | ViewModel für Konto-Einrichtung |
| `InboxViewModel.swift` | 62 | Geändert | + inkrementeller Aufbau nach jedem Konto, Diagnose |
| `AccountListView.swift` | 50 | — | Kontoverwaltungs-View |
| `AddAccountView.swift` | 80 | — | Konto-Einrichtungs-Formular |
| `InboxView.swift` | 118 | Geändert | + Büroklammer, Lade-Spinner, Toolbar-Fortschritt |
| `MessageDetailView.swift` | 280 | Geändert | + Anhang-Sektion, QuickLook, Drei-Punkte-Menü |
| `AttachmentRow.swift` | 91 | **Neu** | Anhang-Zeile mit Typ-Icon, Share, Download-Status |
| `HTMLMailView.swift` | 95 | — | WKWebView-Wrapper (iOS + macOS) |
| `ContentView.swift` | 15 | — | Root-View |
| `MailwerkApp.swift` | 12 | — | App-Einstiegspunkt |

---

## Abhängigkeiten

Unverändert gegenüber v0.1.0:

| Package | Version | Zweck |
|---|---|---|
| [SwiftMail](https://github.com/Cocoanetics/SwiftMail) | Up to Next Major (≥ 1.11.0) | IMAP- und SMTP-Client (baut auf Swift NIO) |
| System-SQLite (`import SQLite3`) | – | Lokaler Nachrichten-Cache |
| QuickLook (`import QuickLook`) | System-Framework | Anhang-Vorschau |

---

## Xcode-Konfiguration

Unverändert gegenüber v0.1.0:

- **Xcode**: 26.6
- **Swift**: 5.0
- **Deployment Targets**: iOS 26.5, macOS 26.5, visionOS 26.5
- **Bundle Identifier**: `de.sieber-bw.Mailwerk`
- **Development Team**: 62QD57DH52
- **Capabilities**: iCloud (Key-value storage), Keychain Sharing
- **Supported Platforms**: iphoneos, iphonesimulator, macosx, xros, xrsimulator
- **MARKETING_VERSION**: 0.1.1 → ab nächstem Commit 0.1.2
