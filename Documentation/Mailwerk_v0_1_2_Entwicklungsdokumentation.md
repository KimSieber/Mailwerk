# Mailwerk – Entwicklungsdokumentation v0.1.2

2026-09-20 · Commit-Stand vor Übergang auf 0.1.3

---

## Zusammenfassung

Version 0.1.2 implementiert die IMAP-Basis-Aktionen aus der MVP1-Roadmap: Gelesen/Ungelesen markieren, Kennzeichnen (Flag), Löschen (in Trash verschieben oder EXPUNGE als Fallback), Verschieben in beliebige Ordner (mit On-demand-Ordnerliste vom Server). Alle Aktionen sind sowohl über das Drei-Punkte-Menü in der Detailansicht als auch (Gelesen/Flag) über Swipe-Gesten in der Inbox-Liste erreichbar. Der lokale Cache wird bei jeder Aktion sofort aktualisiert.

Zusätzlich wurde die Flaggen-Synchronisation beim IMAP-Refresh ergänzt (schließt TD-4), das Datumsformat in Liste und Detail vereinheitlicht, und die deutsche Lokalisierung im Xcode-Projekt aktiviert.

---

## Projektstruktur (Änderungen gegenüber v0.1.1)

```
Mailwerk/
├── Models/
│   ├── MailAccount.swift               # unverändert
│   ├── CachedMessage.swift             # + isFlagged-Property
│   └── InboxMessage.swift              # unverändert (aktuell nicht aktiv genutzt)
├── ViewModels/
│   ├── AddAccountViewModel.swift       # unverändert
│   └── InboxViewModel.swift            # unverändert
├── Views/
│   ├── AccountListView.swift           # unverändert
│   ├── AddAccountView.swift            # unverändert
│   ├── InboxView.swift                 # + Swipe-Aktionen, Flag-Icon, Datumsformat, Fehler-Alert
│   ├── MessageDetailView.swift         # + Menü-Aktionen live, Ordner-Picker, Auto-Gelesen, Flag-Icon
│   ├── AttachmentRow.swift             # unverändert
│   └── HTMLMailView.swift              # unverändert
├── Services/
│   ├── KeychainService.swift           # unverändert
│   ├── AccountStore.swift              # unverändert
│   ├── MailConnectionTester.swift      # unverändert
│   ├── MailFetchService.swift          # + \Flagged-Sync beim Refresh, isFlagged beim Erstcache
│   ├── MessageStore.swift              # + Migration isFlagged, updateFlagged(), deleteMessage()
│   ├── AttachmentManager.swift         # unverändert
│   └── MailActionService.swift         # NEU – IMAP STORE/MOVE/LIST, Ordnerliste, MailFolder-Modell
├── MailwerkApp.swift
└── ContentView.swift
```

---

## Erledigte Schritte (v0.1.2)

### MailActionService (neuer Service)

- **Neuer Service `MailActionService`**: Zentraler Ort für alle IMAP-Aktionen, analog zu `MailFetchService` für den Abruf. Nutzt einen internen `withIMAPConnection`-Helfer, der Connect/Login/Logout/Error-Handling kapselt und Boilerplate reduziert.
- **`setRead(uid:isRead:accountID:accountStore:)`**: Setzt oder entfernt `\Seen` per IMAP STORE.
- **`setFlagged(uid:isFlagged:accountID:accountStore:)`**: Setzt oder entfernt `\Flagged` per IMAP STORE.
- **`deleteMessage(uid:accountID:accountStore:)`**: Sucht zunächst per `listMailboxes` den Trash-Ordner (SPECIAL-USE `\Trash`). Falls vorhanden: `MOVE` dorthin. Fallback: `STORE \Deleted` + `EXPUNGE`.
- **`moveMessage(uid:toFolder:accountID:accountStore:)`**: Verschiebt eine Nachricht per IMAP `MOVE` in einen beliebigen Ordner. SwiftMail nutzt automatisch `COPY`+`STORE \Deleted`+`EXPUNGE` als Fallback, falls der Server MOVE nicht unterstützt.
- **`fetchFolders(accountID:accountStore:)`**: Holt die Ordnerliste per `listMailboxes(wildcard: "*")`, mappt SPECIAL-USE-Attribute, filtert INBOX heraus, sortiert Spezialordner vor reguläre.
- **`MailFolder`-Struct**: Modell für einen IMAP-Ordner mit `id` (voller IMAP-Pfad), `name` (Anzeigename, letztes Pfad-Segment), `specialUse` (Optional: drafts, sent, trash, junk, archive, flagged).

### Cache-Erweiterung (CachedMessage + MessageStore)

- **`isFlagged`-Property** in `CachedMessage` (`var isFlagged: Bool`).
- **SQLite-Schema**: Neue Spalte `isFlagged INTEGER NOT NULL DEFAULT 0`, ans Ende der `CREATE TABLE`-Definition angehängt (gleicher physischer Index bei Neuinstallation und Migration).
- **Migration**: `migrateIfNeeded()` prüft per `columnExists("isFlagged", in: "message")` und ergänzt die Spalte via `ALTER TABLE` bei bestehenden Datenbanken.
- **`updateFlagged(messageID:isFlagged:)`**: Leichtgewichtiges `UPDATE message SET isFlagged = ? WHERE id = ?`, analog zu `updateFlags()`.
- **`deleteMessage(id:)`**: `DELETE FROM message WHERE id = ?` — entfernt eine einzelne Nachricht aus dem Cache. Anhänge werden über `ON DELETE CASCADE` automatisch mitgelöscht.
- **`saveMessage()`**: Um `isFlagged`-Binding erweitert (15 statt 14 Parameter).
- **`readMessage()`**: Liest `isFlagged` von Spaltenindex 14 (nach `hasAttachments` auf Index 13).

### Drei-Punkte-Menü aktiviert (MessageDetailView)

Vier der bisherigen Platzhalter im Aktionsmenü sind jetzt live verdrahtet:

| Menüpunkt | Aktion | Feedback |
|---|---|---|
| Kennzeichnen / Kennzeichnung entfernen | `MailActionService.setFlagged()` + lokales Cache-Update | Icon und Label passen sich dem aktuellen Status an |
| Als gelesen/ungelesen markieren | `MailActionService.setRead()` + lokales Cache-Update | Icon und Label passen sich dem aktuellen Status an |
| In Ordner verschieben | Öffnet `FolderPickerSheet` → `MailActionService.moveMessage()` + lokales Löschen | Dismiss nach Erfolg, Fehler-Alert bei Misserfolg |
| Mail löschen | Bestätigungsdialog → `MailActionService.deleteMessage()` + lokales Löschen | Dismiss nach Erfolg, Fehler-Alert bei Misserfolg |

- **`FolderPickerSheet`**: Neue private View, zeigt die IMAP-Ordnerliste als Sheet mit Spinner, SF-Symbol-Icons nach Spezialrolle, und Cancel-Button.
- **`onChange`-Callback**: Optionaler Closure, den die aufrufende `InboxView` mit `viewModel.loadFromCache()` verdrahtet. Wird nach jeder Statusänderung aufgerufen, damit die Inbox-Liste sofort aktualisiert wird (kein Pull-to-Refresh nötig).
- **Ladezustand**: Während einer Aktion zeigt die Toolbar einen `ProgressView` statt des Menü-Icons.
- **Auto-Gelesen beim Öffnen**: Ungelesene Mails werden beim Betreten der Detailansicht automatisch per IMAP als gelesen markiert (im `.task`-Modifier).
- **Flag-Icon im Header**: Neben dem Betreff wird `flag.fill` (orange) angezeigt, wenn die Mail gekennzeichnet ist.

### Inbox-Swipe-Aktionen (InboxView)

- **Swipe von links nach rechts** (`edge: .leading`): Gelesen/Ungelesen toggle (blau). Vollständiger Swipe löst die Aktion direkt aus.
- **Swipe von rechts nach links** (`edge: .trailing`): Flag setzen/entfernen (orange). Vollständiger Swipe löst die Aktion direkt aus.
- **`processingMessageIDs`**: Set, das gerade in Bearbeitung befindliche Message-IDs tracked. Betroffene Zeilen werden per `.disabled()` gesperrt, um Doppel-Aktionen zu verhindern.
- **Eigenes Fehler-Alert**: Getrennt vom bestehenden Refresh-Fehler-Alert (`viewModel.errorMessage`), da Swipe-Fehler pro Einzelaktion auftreten.
- **Flag-Icon in `InboxRow`**: `flag.fill` (orange) zwischen Absender und Büroklammer/Datum.

### TD-4 geschlossen: Flaggen-Sync beim Refresh (MailFetchService)

- **Bereits gecachte Mails**: Beim IMAP-Refresh wird jetzt neben `\Seen` auch `\Flagged` aus den Server-Flags ausgelesen und per `updateFlagged()` im Cache aktualisiert.
- **Neue Mails**: Beim Erstcache wird `isFlagged` korrekt aus `info.flags` befüllt (statt fest `false`).
- **Noch offen**: `\Answered`-Flag wird weiterhin nicht synchronisiert (erst relevant, wenn Antworten/Weiterleiten implementiert ist).

### UX-Verbesserungen

- **Datumsformat**: In Inbox-Liste und Detailansicht einheitlich als `EE, dd.MM.yyyy HH:mm` (Wochentag, Datum, Uhrzeit) statt nur Datum ohne Uhrzeit.
- **Deutsche Lokalisierung**: German als Lokalisierung im Xcode-Projekt hinzugefügt, damit Wochentage und Formatierung der Systemsprache folgen.

---

## Getroffene Architektur- & Design-Entscheidungen (v0.1.2)

| Entscheidung | Begründung |
|---|---|
| **Eigener `MailActionService` statt Erweiterung von `MailFetchService`** | Klare Trennung: `MailFetchService` liest (SEARCH + FETCH), `MailActionService` schreibt (STORE + MOVE + LIST). Hält beide Dateien fokussiert und testbar. |
| **`withIMAPConnection`-Helfer** | Alle Aktionen brauchen das gleiche Connect/Login/Logout/Error-Pattern. Ein generischer Helfer mit Closure reduziert Boilerplate und stellt sicheres Aufräumen (disconnect bei Fehler) sicher. |
| **Löschen = MOVE nach Trash (bevorzugt)** | Analog zu Apple Mail. Der Trash-Ordner wird per SPECIAL-USE `\Trash` identifiziert. Nur als Fallback (Server ohne Trash/SPECIAL-USE): `STORE \Deleted` + `EXPUNGE`. |
| **Ordnerliste on-demand statt vollständige Ordner-Synchronisation** | Für „In Ordner verschieben" reicht ein `LIST` beim Öffnen des Pickers. Volle Ordner-Synchronisation (Inhalte aller Ordner anzeigen, Ordner anlegen/löschen) bleibt ein eigenes Feature. |
| **SwiftMail `MOVE` mit Default-Fallback** | SwiftMail v1.11.0 bietet `MoveFallbackPolicy.copyStoreExpunge` als Default — deckt Server ohne MOVE-Extension automatisch ab. Kein eigener Fallback-Code nötig. |
| **`isFlagged` ans Schema-Ende** | `ALTER TABLE ADD COLUMN` hängt neue Spalten immer ans Ende an. `CREATE TABLE` (Neuinstallation) tut es nun ebenfalls. Damit stimmen die physischen Spaltenindizes in beiden Fällen überein — kein Index-Mismatch bei `SELECT *`. |
| **Lokale State-Variablen für Gelesen/Flag in der Detailansicht** | `message` ist als `let` reingereicht und nicht mutierbar. Separate `@State`-Variablen `isUnread` und `isFlagged` ermöglichen sofortiges UI-Feedback ohne die View von außen neu aufzubauen. |
| **`onChange`-Callback statt Environment/Notification** | Einfachster Mechanismus, um die Inbox-Liste nach einer Aktion in der Detailansicht zu aktualisieren. Kein globaler Notification-Bus nötig, keine enge Kopplung. |
| **Kein Löschen per Swipe** | Löschen ist destruktiv und selten — im Drei-Punkte-Menü mit Bestätigungsdialog besser aufgehoben als in einer schnellen Wischgeste. Swipe-Slots werden für häufige Aktionen (Gelesen/Flag) genutzt. |
| **Fester DateFormatter mit `de_DE`-Locale nicht eingebaut** | Stattdessen deutsche Lokalisierung im Xcode-Projekt aktiviert. Die `.dateTime`-API von SwiftUI folgt dann automatisch der Systemsprache. |

---

## Bugfixes (v0.1.2)

- **Spaltenindex-Vertauschung `isFlagged`/`hasAttachments` in `readMessage`**: `isFlagged` wurde versehentlich von Spaltenindex 13 gelesen (das ist `hasAttachments`). Fix: `isFlagged` auf Index 14, `hasAttachments` bleibt auf 13.
- **`IMAPServer` ambiguous for type lookup**: `NIOIMAPCore`-Import erzeugte Namenskonflikt mit `SwiftMail.IMAPServer`. Fix: Explizite Qualifizierung `SwiftMail.IMAPServer` in `MailActionService`.

---

## Bekannte Technical Debts / Offene Nacharbeiten

| # | Bereich | Beschreibung | Priorität | Status |
|---|---|---|---|---|
| TD-1 | Postfach-UI | `try?` beim Speichern/Löschen von Accounts schluckt Keychain-Fehler stillschweigend | Mittel | Offen (aus v0.1.0) |
| TD-2 | IMAP-Verbindung | Kein Connection-Pooling/IDLE, für jeden Refresh und jede Aktion neue Verbindung | Niedrig | Offen (geplant für 0.4.x) |
| TD-3 | Cache-Sync | Kein Abgleich bei serverseitiger Löschung/Verschiebung – Mail bleibt dauerhaft im Cache | Mittel | Offen (aus v0.1.0) |
| TD-4 | Cache-Flags | ~~Nur isUnread wurde synchronisiert~~ | ~~Mittel~~ | **Erledigt (v0.1.2)**: `\Flagged` wird jetzt auch synchronisiert; `\Answered` bleibt offen |
| TD-7 | Inbox-UI | `ContentUnavailableView` ist nicht scrollbar → Pull-to-Refresh greift im leeren Zustand nicht, App muss neu gestartet werden | Mittel | Offen (aus v0.1.1) |
| TD-8 | Erster Abruf | Erstabruf dauert ca. 4–6 Minuten bei 300 Mails (Body-Download pro Mail). Spinner + inkrementeller Aufbau lindern das UX-Problem, aber die Laufzeit selbst ist hoch | Niedrig | Offen (aus v0.1.1) |
| TD-9 | Diagnose-Logging | `print()`-Diagnose-Ausgaben (📬, 📋, 🔄, 📎, 🗑️, 📁, 🚩 etc.) sind noch aktiv – vor einer Release-Version entfernen oder hinter ein Debug-Flag setzen | Niedrig | Offen (aus v0.1.1) |
| TD-10 | Ordnerverwaltung | Ordner anlegen und löschen (IMAP CREATE/DELETE) ist noch nicht möglich – Anforderung für das Feature „Weitere Ordner" vorgemerkt | Mittel | Neu (v0.1.2) |
| TD-11 | IMAP-Aktionen | Jede Aktion (Flag, Gelesen, Löschen, Verschieben) baut eine eigene IMAP-Verbindung auf und ab. Bei schnell aufeinanderfolgenden Aktionen ineffizient. Zusammenlegung mit TD-2 (Connection-Pooling) sinnvoll | Niedrig | Neu (v0.1.2) |

---

## Noch nicht implementiert (geplant für 0.1.x)

Laut ursprünglicher MVP1-Roadmap stehen noch aus:

- [ ] **SMTP-Versand**: Senden / Antworten / Weiterleiten (SwiftMail SMTPServer-API steht bereit)
- [x] ~~**Basis-Aktionen**: Löschen, Verschieben, Gelesen/Ungelesen markieren, Flag setzen (IMAP STORE/MOVE)~~ **Erledigt (v0.1.2)**
- [ ] **Weitere Ordner**: aktuell wird nur INBOX synchronisiert – Sent, Drafts, Trash etc. fehlen. Zusätzlich: Ordner anlegen/löschen können (TD-10)
- [ ] **Account bearbeiten**: angelegte Konten können nur gelöscht, nicht editiert werden
- [ ] **Fehlerhandling**: durchgängig saubere Fehlermeldungen statt `try?`

---

## Dateien im Projekt (Stand v0.1.2)

| Datei | Zeilen (ca.) | Änderung | Beschreibung |
|---|---|---|---|
| `MailAccount.swift` | 45 | — | Konto-Datenmodell |
| `CachedMessage.swift` | 44 | Geändert | + `isFlagged`-Property |
| `InboxMessage.swift` | 35 | — | Server-Header-Modell (aktuell nicht aktiv) |
| `KeychainService.swift` | 75 | — | Keychain CRUD mit iCloud-Sync |
| `AccountStore.swift` | 55 | — | Account-Persistenz (iCloud KVS) |
| `MailConnectionTester.swift` | 45 | — | IMAP/SMTP-Verbindungstest |
| `MailFetchService.swift` | 175 | Geändert | + `\Flagged`-Sync beim Refresh, `isFlagged` beim Erstcache |
| `MessageStore.swift` | 365 | Geändert | + Migration `isFlagged`, `updateFlagged()`, `deleteMessage()` |
| `AttachmentManager.swift` | 123 | — | Temp-Dateien für Vorschau/Share, On-demand-IMAP-Download |
| `MailActionService.swift` | 195 | **Neu** | IMAP STORE/MOVE/LIST, Ordnerliste, `MailFolder`-Modell |
| `AddAccountViewModel.swift` | 60 | — | ViewModel für Konto-Einrichtung |
| `InboxViewModel.swift` | 62 | — | ViewModel für Unified Inbox |
| `AccountListView.swift` | 50 | — | Kontoverwaltungs-View |
| `AddAccountView.swift` | 80 | — | Konto-Einrichtungs-Formular |
| `InboxView.swift` | 155 | Geändert | + Swipe-Aktionen, Flag-Icon, Datumsformat, Fehler-Alert, Swipe-Funktionen |
| `MessageDetailView.swift` | 370 | Geändert | + Menü-Aktionen live, Ordner-Picker-Sheet, Auto-Gelesen, Flag-Icon, onChange-Callback |
| `AttachmentRow.swift` | 91 | — | Anhang-Zeile mit Typ-Icon, Share, Download-Status |
| `HTMLMailView.swift` | 95 | — | WKWebView-Wrapper (iOS + macOS) |
| `ContentView.swift` | 15 | — | Root-View |
| `MailwerkApp.swift` | 12 | — | App-Einstiegspunkt |

---

## Abhängigkeiten

Unverändert gegenüber v0.1.1:

| Package | Version | Zweck |
|---|---|---|
| [SwiftMail](https://github.com/Cocoanetics/SwiftMail) | Up to Next Major (≥ 1.11.0) | IMAP- und SMTP-Client (baut auf Swift NIO) |
| System-SQLite (`import SQLite3`) | – | Lokaler Nachrichten-Cache |
| QuickLook (`import QuickLook`) | System-Framework | Anhang-Vorschau |

---

## Xcode-Konfiguration

| Einstellung | Wert |
|---|---|
| **Xcode** | 26.6 |
| **Swift** | 5.0 |
| **Deployment Targets** | iOS 26.5, macOS 26.5, visionOS 26.5 |
| **Bundle Identifier** | `de.sieber-bw.Mailwerk` |
| **Development Team** | 62QD57DH52 |
| **Capabilities** | iCloud (Key-value storage), Keychain Sharing |
| **Supported Platforms** | iphoneos, iphonesimulator, macosx, xros, xrsimulator |
| **Localizations** | German (default), English |
| **MARKETING_VERSION** | 0.1.2 → ab nächstem Commit 0.1.3 |
