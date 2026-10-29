# Mailwerk – Entwicklungsdokumentation v0.1.3

2026-09-20 · Commit-Stand vor Übergang auf 0.1.4

---

## Zusammenfassung

Version 0.1.3 implementiert die Account-Bearbeitung und führt die farbliche Account-Kennzeichnung in der Inbox ein. Bestehende Konten können jetzt vollständig editiert werden (alle Felder inkl. Passwort und Verbindungstest). Jedem Account kann optional eine Farbe aus einer 12-Farben-Palette zugewiesen werden, die als 4px vertikaler Streifen am linken Rand der Inbox-Zeile angezeigt wird. Im Gegenzug entfällt die Account-Name-Textzeile in der Inbox — das spart Zeilenhöhe und ermöglicht mehr sichtbare E-Mails.

Zusätzlich wurden UX-Verbesserungen an der Account-Verwaltung vorgenommen: Schließen-Button (X) statt Swipe-Down, aussagekräftigerer Titel und ein passenderes Toolbar-Icon.

---

## Projektstruktur (Änderungen gegenüber v0.1.2)

```
Mailwerk/
├── Models/
│   ├── MailAccount.swift               # + colorHex-Property
│   ├── AccountColor.swift              # NEU – Farbpalette (enum, 12 Farben) + Color(hex:) Extension
│   ├── CachedMessage.swift             # unverändert
│   └── InboxMessage.swift              # unverändert (aktuell nicht aktiv genutzt)
├── ViewModels/
│   ├── AddAccountViewModel.swift       # unverändert
│   └── InboxViewModel.swift            # unverändert
├── Views/
│   ├── AccountListView.swift           # + Tap→Edit, Farbpunkt, X-Schließen, Titel "Postfächer"
│   ├── AddAccountView.swift            # unverändert
│   ├── EditAccountView.swift           # NEU – Bearbeitungsformular mit Farbwähler
│   ├── ColorPickerGrid.swift           # NEU – Farbauswahl-Grid (12 Farben + "Keine")
│   ├── InboxView.swift                 # + Farbstreifen in InboxRow, Account-Name entfernt, Zahnrad-Icon
│   ├── MessageDetailView.swift         # unverändert
│   ├── AttachmentRow.swift             # unverändert
│   └── HTMLMailView.swift              # unverändert
├── Services/
│   ├── KeychainService.swift           # unverändert
│   ├── AccountStore.swift              # + updateAccount()
│   ├── MailConnectionTester.swift      # unverändert
│   ├── MailFetchService.swift          # unverändert
│   ├── MessageStore.swift              # unverändert
│   ├── AttachmentManager.swift         # unverändert
│   └── MailActionService.swift         # unverändert
├── MailwerkApp.swift
└── ContentView.swift
```

---

## Erledigte Schritte (v0.1.3)

### AccountColor (neues Modell)

- **Neues `enum AccountColor: String, CaseIterable, Identifiable, Codable`** mit 12 vordefinierten Farben: Blau, Türkis, Grün, Koralle, Rot, Rosa, Violett, Bernstein, Braun, Schiefer, Marine, Magenta.
- **`rawValue`** ist der Hex-String (z. B. `"#378ADD"`), dient gleichzeitig als Persistenzformat.
- **`displayName`**: Deutscher Anzeigename für den Farbwähler.
- **`color`**: Computed Property, liefert `SwiftUI.Color` via `Color(hex:)`.
- **`from(hex:)`**: Statische Factory-Methode, mappt einen gespeicherten Hex-String zurück auf den Enum-Case (oder `nil`).
- **`Color(hex:)` Extension**: Initialisiert eine `SwiftUI.Color` aus einem Hex-String (z. B. `"#378ADD"`). Wird von `AccountColor.color` und `InboxRow` genutzt.

### MailAccount erweitert

- **Neue optionale Property `colorHex: String?`**: Speichert den Hex-Wert der gewählten Account-Farbe. `nil` = keine Farbmarkierung (opt-in). Default-Wert `nil` im Init stellt Abwärtskompatibilität sicher — bestehende JSON-Daten ohne Farbe werden fehlerfrei decodiert.

### AccountStore erweitert

- **Neue Methode `updateAccount(_:newPassword:)`**: Aktualisiert einen bestehenden Account im Array und persistiert ihn. Passwort wird nur im Keychain überschrieben, wenn ein nicht-leerer neuer Wert übergeben wird. Bestehende Methoden (`addAccount`, `removeAccount`) bleiben unverändert.

### ColorPickerGrid (neue View)

- **`LazyVGrid`** mit 6 festen Spalten (44pt Breite, 8pt Abstand), gute Tap-Targets auf allen Plattformen.
- **Erste Position**: „Keine Farbe"-Option (Strich-Kreis mit Minus-Symbol, Häkchen wenn aktiv).
- **12 Farbkreise**: Gefüllt mit der jeweiligen Farbe, weißes Häkchen auf dem ausgewählten.
- **`@Binding var selection: AccountColor?`**: `nil` = keine Farbe.
- **`onTapGesture` statt `Button`**: Vermeidet SwiftUI-Form-Tap-Konflikte, die dazu führten, dass Button-Taps im Form-Kontext nicht korrekt registriert wurden.
- **`.contentShape(Circle())`**: Stellt sicher, dass der gesamte Kreisbereich tappbar ist.

### EditAccountView (neue View)

- **Vollständiges Bearbeitungsformular** mit allen Account-Feldern: Anzeigename, Benutzername/E-Mail, Passwort (optional — leer = unverändert), IMAP-Host/Port, SMTP-Host/Port, Farbwahl.
- **Passwort-Handling**: `SecureField` mit Platzhaltertext „Neues Passwort (leer = unverändert)". Beim Verbindungstest wird das neue Passwort verwendet, falls eingegeben, sonst das bestehende aus dem Keychain.
- **Verbindungstest**: Identisch zu `AddAccountView` — testet IMAP und SMTP mit den aktuellen Formularwerten.
- **Farbsektion**: Eingebettete `ColorPickerGrid` als eigene `Section("Farbe")`.
- **Validierung**: Speichern-Button nur aktiv, wenn Pflichtfelder ausgefüllt und Ports numerisch.
- **`try?` beim Speichern**: Konsistent mit `AddAccountView` (TD-1 bleibt offen).

### AccountListView angepasst

- **Tap auf Account öffnet `EditAccountView`** als Sheet (`sheet(item: $editingAccount)`).
- **Farbpunkt** (12pt Kreis) neben dem Account-Namen, nur wenn `colorHex` gesetzt ist.
- **Schließen-Button**: „X" (`xmark`) in der Toolbar (`placement: .cancellationAction`) statt Swipe-Down — konsistenter mit Apple-Konventionen für modale Sheets.
- **Titel geändert**: Von „Mailwerk" zu „Postfächer".
- **`.tint(.primary)`** auf dem Button-Label, damit der Accounttext nicht blau eingefärbt wird.

### InboxRow angepasst (InboxView)

- **Account-Name-Textzeile entfernt**: `message.accountDisplayName` wird nicht mehr angezeigt → spart eine Zeile Höhe pro Mail.
- **Farbstreifen**: 4px breiter vertikaler Balken am linken Rand, volle Zeilenhöhe, Farbe aus `account.colorHex`. Kein Streifen wenn `colorHex == nil`.
- **8px Padding** zwischen Streifen und Textinhalt für saubere Optik.
- **Farb-Lookup**: `InboxRow` erhält `colorHex` als Parameter, aufgelöst über `accountStore.accounts.first(where:)?.colorHex`.
- **Toolbar-Icon geändert**: Von `envelope.badge.person.crop` zu `gearshape` (Zahnrad) — intuitiver für „Einstellungen/Verwaltung".

---

## Getroffene Architektur- & Design-Entscheidungen (v0.1.3)

| Entscheidung | Begründung |
|---|---|
| **Hex-String in `MailAccount` statt Enum-Case** | Maximale Abwärtskompatibilität: bestehende JSON-Daten ohne `colorHex` werden mit `nil` decodiert (kein Streifen). Neue Farben können später ergänzt werden, ohne bestehende Daten zu invalidieren. |
| **`colorHex` optional statt Default-Farbe** | Opt-in-Prinzip: Benutzer entscheidet selbst, ob er Farben nutzen möchte. Keine Farbe = kein Streifen = kein Informationsverlust durch falsche Zuordnung. |
| **12 feste Farben statt freier ColorPicker** | Bewusste Einschränkung auf gut unterscheidbare, voneinander abgesetzte Töne. Ein freier Picker würde zu ähnlichen, schwer unterscheidbaren Farben führen. 12 ist zukunftssicher für den geplanten Anwendungsfall (max. 5-6 Konten realistisch). |
| **Farbwahl immer manuell, kein Auto-Vorschlag** | Benutzer haben oft eine logische Ableitung (blau = offiziell, grün = ungezwungen etc.). Auto-Zuweisung würde dem entgegenstehen. |
| **`onTapGesture` statt `Button` im Farbwähler** | `Button` innerhalb von SwiftUI `Form`/`Section` hatte Tap-Registrierungsprobleme (nur letzter Kreis reagierte). `onTapGesture` + `.contentShape(Circle())` löst das zuverlässig. |
| **Account-Name in Inbox entfernen statt beibehalten** | Platzgewinn war die explizite Anforderung. Die Farbe transportiert die Account-Zugehörigkeit visuell schneller als Text. Bei Bedarf bleibt die Info in der Detailansicht sichtbar. |
| **`updateAccount` statt Löschen+Neu-Anlegen** | Erhält die `id` des Accounts — damit bleiben Keychain-Eintrag, Cache-Referenzen und iCloud-Sync intakt. |
| **Passwort-Feld leer = unverändert** | Sicherheits- und UX-Entscheidung: Das bestehende Passwort wird nie im Klartext angezeigt. Nur bei tatsächlicher Änderung wird der Keychain aktualisiert. |
| **Zahnrad statt Briefumschlag als Toolbar-Icon** | `envelope.badge.person.crop` war mit den Inbox-Inhalten verwechselbar. `gearshape` ist universell für Verwaltung/Einstellungen und unterscheidet sich klar vom Mailinhalt. |
| **X-Button statt Swipe-Down für AccountListView** | Apple-Konvention: Modale Sheets werden mit „X" geschlossen, der Zurück-Pfeil ist für Navigation-Stack-Push/Pop. |

---

## Bugfixes (v0.1.3)

- **Farbwähler-Tap nicht registriert**: `Button` innerhalb von `Form`/`Section` führte dazu, dass nur der letzte Farbkreis auf Taps reagierte. Fix: `onTapGesture` + `.contentShape(Circle())` statt `Button`.

---

## Bekannte Technical Debts / Offene Nacharbeiten

| # | Bereich | Beschreibung | Priorität | Status |
|---|---|---|---|---|
| TD-1 | Postfach-UI | `try?` beim Speichern/Löschen/Aktualisieren von Accounts schluckt Keychain-Fehler stillschweigend — betrifft jetzt auch `EditAccountView` | Mittel | Offen (aus v0.1.0, erweitert in v0.1.3) |
| TD-2 | IMAP-Verbindung | Kein Connection-Pooling/IDLE, für jeden Refresh und jede Aktion neue Verbindung | Niedrig | Offen (geplant für 0.4.x) |
| TD-3 | Cache-Sync | Kein Abgleich bei serverseitiger Löschung/Verschiebung – Mail bleibt dauerhaft im Cache | Mittel | Offen (aus v0.1.0) |
| TD-4 | Cache-Flags | ~~Nur isUnread wurde synchronisiert~~ | ~~Mittel~~ | **Erledigt (v0.1.2)**: `\Flagged` wird jetzt auch synchronisiert; `\Answered` bleibt offen |
| TD-7 | Inbox-UI | `ContentUnavailableView` ist nicht scrollbar → Pull-to-Refresh greift im leeren Zustand nicht, App muss neu gestartet werden | Mittel | Offen (aus v0.1.1) |
| TD-8 | Erster Abruf | Erstabruf dauert ca. 4–6 Minuten bei 300 Mails (Body-Download pro Mail). Spinner + inkrementeller Aufbau lindern das UX-Problem, aber die Laufzeit selbst ist hoch | Niedrig | Offen (aus v0.1.1) |
| TD-9 | Diagnose-Logging | `print()`-Diagnose-Ausgaben (📬, 📋, 🔄, 📎, 🗑️, 📁, 🚩 etc.) sind noch aktiv – vor einer Release-Version entfernen oder hinter ein Debug-Flag setzen | Niedrig | Offen (aus v0.1.1) |
| TD-10 | Ordnerverwaltung | Ordner anlegen und löschen (IMAP CREATE/DELETE) ist noch nicht möglich – Anforderung für das Feature „Weitere Ordner" vorgemerkt | Mittel | Offen (aus v0.1.2) |
| TD-11 | IMAP-Aktionen | Jede Aktion (Flag, Gelesen, Löschen, Verschieben) baut eine eigene IMAP-Verbindung auf und ab. Bei schnell aufeinanderfolgenden Aktionen ineffizient. Zusammenlegung mit TD-2 (Connection-Pooling) sinnvoll | Niedrig | Offen (aus v0.1.2) |

---

## Noch nicht implementiert (geplant für 0.1.x)

Laut ursprünglicher MVP1-Roadmap stehen noch aus:

- [ ] **SMTP-Versand**: Senden / Antworten / Weiterleiten (SwiftMail SMTPServer-API steht bereit)
- [x] ~~**Basis-Aktionen**: Löschen, Verschieben, Gelesen/Ungelesen markieren, Flag setzen (IMAP STORE/MOVE)~~ **Erledigt (v0.1.2)**
- [ ] **Weitere Ordner**: aktuell wird nur INBOX synchronisiert – Sent, Drafts, Trash etc. fehlen. Zusätzlich: Ordner anlegen/löschen können (TD-10)
- [x] ~~**Account bearbeiten**: angelegte Konten können nur gelöscht, nicht editiert werden~~ **Erledigt (v0.1.3)**
- [ ] **Fehlerhandling**: durchgängig saubere Fehlermeldungen statt `try?`

---

## Dateien im Projekt (Stand v0.1.3)

| Datei | Zeilen (ca.) | Änderung | Beschreibung |
|---|---|---|---|
| `MailAccount.swift` | 50 | Geändert | + `colorHex`-Property |
| `AccountColor.swift` | 70 | **Neu** | Farbpalette (12 Farben), Hex-Enum, `Color(hex:)` Extension |
| `CachedMessage.swift` | 44 | — | Lokal gecachte Nachricht inkl. Body |
| `InboxMessage.swift` | 35 | — | Server-Header-Modell (aktuell nicht aktiv) |
| `KeychainService.swift` | 75 | — | Keychain CRUD mit iCloud-Sync |
| `AccountStore.swift` | 65 | Geändert | + `updateAccount()` |
| `MailConnectionTester.swift` | 45 | — | IMAP/SMTP-Verbindungstest |
| `MailFetchService.swift` | 175 | — | IMAP-Refresh mit Cache-Sync |
| `MessageStore.swift` | 365 | — | SQLite-Cache (CRUD, Migrationen) |
| `AttachmentManager.swift` | 123 | — | Temp-Dateien für Vorschau/Share, On-demand-IMAP-Download |
| `MailActionService.swift` | 195 | — | IMAP STORE/MOVE/LIST, Ordnerliste, `MailFolder`-Modell |
| `AddAccountViewModel.swift` | 60 | — | ViewModel für Konto-Einrichtung |
| `InboxViewModel.swift` | 62 | — | ViewModel für Unified Inbox |
| `AccountListView.swift` | 70 | Geändert | + Tap→Edit-Sheet, Farbpunkt, X-Schließen, Titel „Postfächer" |
| `AddAccountView.swift` | 80 | — | Konto-Einrichtungs-Formular |
| `EditAccountView.swift` | 140 | **Neu** | Konto-Bearbeitungsformular mit Farbwähler und Verbindungstest |
| `ColorPickerGrid.swift` | 55 | **Neu** | Farbauswahl-Grid (12 Farben + „Keine") |
| `InboxView.swift` | 150 | Geändert | + Farbstreifen in InboxRow, Account-Name entfernt, Zahnrad-Icon |
| `MessageDetailView.swift` | 370 | — | Detailansicht mit Aktionsmenü |
| `AttachmentRow.swift` | 91 | — | Anhang-Zeile mit Typ-Icon, Share, Download-Status |
| `HTMLMailView.swift` | 95 | — | WKWebView-Wrapper (iOS + macOS) |
| `ContentView.swift` | 15 | — | Root-View |
| `MailwerkApp.swift` | 12 | — | App-Einstiegspunkt |

---

## Abhängigkeiten

Unverändert gegenüber v0.1.2:

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
| **MARKETING_VERSION** | 0.1.3 → ab nächstem Commit 0.1.4 |
