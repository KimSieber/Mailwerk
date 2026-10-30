# Mailwerk – Entwicklungsdokumentation v0.3.1

2026-10-30 · „Refactoring durch Code-Review“: Robustheit, Trennung von Logik und Zugriffen, kleinere Funktionen, Tests der kritischen Pfade, benannte Konfiguration, vollständige Dateiheader

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln und offene Punkte für den nächsten Chat zusammen. Grundlage ist der Code-Review-Bericht vom 30.10.2026 (`Documentation/Intern/Mailwerk_v0.3.1_Code-Review_2026-10-30.md`, Prüfanweisung 1.0) auf dem öffentlichen Ausgangsstand v0.3.0 (`4000fed`).

---

## Zusammenfassung

v0.3.1 ändert keine Funktion. Die Version setzt die Befunde des Code-Reviews um: Gesamtindex **Q = 82,0 (gelb)**, schwächste Regeln Dateiheader (0,0), Konfiguration (0,0), Abhängigkeiten (50,0), kritische Pfade (79,2) und Eingabeprüfung (81,8). Kein Gate war verletzt (Geheimnisse, Injektion).

| Stufe | Inhalt | Regeln |
|---|---|---|
| **a** | Sofortmaßnahmen: `Package.resolved` eingecheckt, Eingaben an der Systemgrenze geprüft, verschluckte Fehler protokolliert, tote Deklarationen, erzählende Kommentare, fehlende Funktionskommentare | 17, 12, 11, 1, 8, 6 |
| **b** (Teil 1–3) | Logik von Server- und Datenbankzugriffen getrennt, lange Funktionen zerlegt, doppelter Code zusammengeführt | 4, 3, 2 |
| **c** (Teil 1, 2) | Views zerlegt, gemeinsame Angaben der Mailansicht gebündelt; Tests der ungetesteten kritischen Pfade | 3, 2, 4, 16 |
| **d** (Teil 1, 2) | Abstände, Radien, Animationen, Ports, Zeitlimits benannt; Namen mit Einheit; Dateiheader mit Autor und Datum | 9, 5, 7 |

| Kennzahl | v0.3.0 | v0.3.1 |
|---|---|---|
| Testfunktionen (`@Test`) | 856 | **885** |
| Neue reine (ohne Server testbare) Bausteine | – | 11 |
| Feste Zahlen in der Oberfläche (Regel 9) | 458 | rund 210 |
| Dateien mit vollständigem Header (Regel 7) | 0 von 197 | 203 von 203 |
| Geänderte Dateien (gegenüber `4000fed`) | – | 224 |

Ein neuer Prüflauf (Prüfanweisung 1.1, siehe Abschnitt 1) steht aus; er zeigt den neuen Gesamtindex.

| Commit | Inhalt |
|---|---|
| `8d8126b` | v0.3.1a – Sofortmaßnahmen & Robustheit |
| `9cbc371` | v0.3.1b – Logik von I/O trennen |
| `2d546bc` | v0.3.1c – Views zerlegen, kritische Pfade testen |
| `ae79d52` | v0.3.1d – Konfiguration benannt, Dateiheader |
| (dieser) | Dokumentation v0.3.1 |

---

## 1. Entscheidungen

- **Reihenfolge nach Nutzen je Aufwand:** zuerst die schnellen Punkte mit Sicherheitsbezug (a), dann Struktur (b, c), zuletzt Form (d). Die Dateiheader kamen bewusst ganz zum Schluss, damit „Geändert“ den Stand nach allen Umbauten zeigt.
- **Kein geändertes Verhalten:** Jede Stufe ist reines Refactoring. Einzige sichtbare Folge: die gemeinsame HTML-Maskierung maskiert jetzt überall auch `"` und `'` (Druck, zusammengesetzte Textteile).
- **Bool-Namen (Regel 5):** Die 89 Befunde (`showsImage`, `canSend`, `allowsRemoteContent` …) folgen den Swift API Design Guidelines. Statt sie umzubenennen, wurde die Prüfanweisung angepasst (Fassung **1.1**): In Swift gelten zusätzlich `can`, `shows`, `allows`, `uses`, `needs`, `supports`, `contains`, `stores`, `saves`, `requires`, `offers`, `did`, `was`, `had` und Formen auf „-ing“. Umbenannt wurden nur echte Ausreißer (Abkürzungen, fehlende Einheiten).
- **Konfiguration (Regel 9) gezielt statt vollständig:** wiederkehrende Werte als Stufen (`AppSpacing`, `AppCornerRadius`, `AppAnimation`) und fachliche Werte benannt; einzelne Rahmengrößen, Schriftgrößen und Deckkraftwerte bleiben vor Ort. Das Ziel „≤ 120 Werte“ ist damit nicht erreicht (rund 210), die Dichte liegt aber unter der Grenze von 10 je 1000 Zeilen.
- **Dateiheader:** Autor, „Erstellt“ und „Geändert“ in jeder Datei. „Erstellt“ ist das frühere Datum aus Anlagedatum der Datei und erster Entwicklungsdokumentation, die die Datei nennt – das Anlagedatum allein ist unzuverlässig, weil zurückgeschriebene Dateien für macOS neu angelegt sind. „Geändert“ wird ab jetzt bei jeder Lieferung nachgezogen.
- **Größenlimit beim Anhängen:** 50 MB (Gmail erlaubt 25 MB, die meisten anderen bis 50 MB). Gilt nur für Dateien beim Verfassen, nicht für empfangene Anhänge oder Fotos.

---

## 2. Sofortmaßnahmen (Stufe a)

- **Abhängigkeiten:** `Package.resolved` ist eingecheckt (aus `.gitignore` entfernt) – SwiftMail und swift-nio lösen bei jedem Build gleich auf.
- **Eingabeprüfung:** Ports nur 1–65535 (`MailAccount.port(from:)`, Hinzufügen und Bearbeiten); Datei-Import beim Verfassen wird vor dem Einlesen auf 50 MB geprüft (`AttachmentManager.maxImportBytes`); die vom Skript gemeldete Höhe des Signatur-Blocks wird auf 0–2000 pt begrenzt, NaN verworfen.
- **Fehler:** 13 stille `try?` protokollieren jetzt; das Trennen von IMAP und SMTP nach einem Fehler oder nach dem Versand läuft über `MailSession.disconnectQuietly`. Ein abgebrochener Abruf startet keinen zweiten Anmeldeversuch und keinen zweiten Spam-Abruf mehr.
- **Aufräumen:** 11 tote Deklarationen entfernt (nur von Tests genutzte Hilfen stehen jetzt als Erweiterung in den Testdateien); erzählende Kommentare entfernt oder als Begründung umformuliert; 28 Funktionskommentare ergänzt.
- **Komplikation:** `Log.swift` ist zusätzlich in `MailwerkWatchWidgetExtension` eingebunden (`WatchAppGroup` protokolliert).

---

## 3. Logik von Zugriffen trennen (Stufe b)

### 3.1 Abruf (Teil 1)
`MailFetchService` enthält nur noch Ablauf und Zugriffe; jede Funktion hat höchstens 35 Zeilen und 4 Parameter. Entscheidungen treffen reine Bausteine:

| Baustein | Aufgabe |
|---|---|
| `Sync/FetchClassifier` | Kopfdaten gegen den Cache einordnen: neu, Flags geändert, Kopfdaten nachtragen, ohne UID |
| `Sync/FetchedMessageMapping` | Mail, Anhang, Kopfdaten und Listeneintrag bauen; Ersatztexte und Content-ID-Regeln |
| `Search/ServerSearchPlan` | Kriterien, Auswahl und Reihenfolge der Serversuche |
| `ServerReconciliation.folderState` | Stand eines Ordners aus den Flags |

Protokollzeilen zu einem Ordner beginnen einheitlich mit „[Postfach/Ordner]“ (`FolderContext`).

### 3.2 Spamfilter, Abruf-Auswertung, Watch (Teil 2)
- `SpamFilterService.filterInbox` in benannte Schritte zerlegt; die Auswahl ungeprüfter Mails ist `SpamFilterPlanner.uncheckedUIDs`. `SpamRules` bündelt Filterlisten und Score-Obergrenze (auch in der Watch-App).
- `AccountRefreshService.evaluate` entscheidet nach einem Abruf: vollständig, nur Spam-Ordner fehlt (zweiter Versuch), gescheitert.
- `WatchBridge.failureHandling` bewertet Fehler von Watch-Aktionen; `WatchSnapshotBuilder` trennt Lesen (`cacheData`) und Zusammenstellen (`snapshot`).
- `MailConnectionTester.smtpTestError`, `SyncStatePlanner.ArrivalWindow`.

### 3.3 Weitere Dienste (Teil 3)
- `MessageStore`: Abfragehelfer `query`, `queryFirst`, `bindFolder` statt 13 gleich gebauter Leseschleifen.
- `HTMLEscaping`: eine Maskierung statt drei Fassungen mit unterschiedlichem Zeichenumfang.
- `MailActionService`: `FolderMessages` (Postfach, Ordner, UIDs) statt Einzel- und Mehrfach-Varianten; die Ordnerliste bereitet `Folders/MailboxListing` auf.
- `ComposeViewModel`: `Request` statt sechs Parametern, Inits in Schritte zerlegt; die Anhänge der Originalmail liest jetzt `ComposeView`.
- Kleinere: `ContactSuggestionService.rank`, `InlineImageLoader.tasks`, `FolderTreeBuilder.Placement`, `FilterListImport.Outcome`, `HTMLRichTextParser` und `RichTextHTML` in kleinere Funktionen.

---

## 4. Views und kritische Pfade (Stufe c)

- **`MessageDetailContext`** bündelt, was die Liste an fünf Stellen an die Mailansicht weitergibt (Postfächer, Spamfilter, Score-Grenze, Rückmeldung, Personensuche, Empfängeranzeige); `detailPlaceholder` ersetzt die viermal kopierte Gestaltung von Lade- und Hinweiszustand.
- **`InboxView`:** Start (`initialLoad`), Blätter, Serversuche und Listenzeile in benannte Teile zerlegt.
- **Formulare:** `oauthSections` in Abschnitte; `HeaderCircleButton.confirm` ohne ungenutzten Parameter; Import der Filterliste: Lesen (`readImportFile`) und Rückfragetext (`FilterListImport.confirmationMessage`) getrennt.
- **Tests der kritischen Pfade:** IMAP-Flags, Anmeldestand und Anmeldung per OAuth 2 (ohne Netz), Spam-Einstellungen, Schlüsselbund, Entwürfe-Ordner (`DraftService.draftsFolder`), Zusammenführen der Serversuche (`SearchViewModel.combine`), dazu die reinen Bausteine aus b.

---

## 5. Konfiguration, Namen, Header (Stufe d)

- **`AppTheme`:** `AppSpacing` (2–24 pt in neun Stufen), `AppCornerRadius` (6–12 pt), `AppAnimation` (`standard` 0,25 s, `quick` 0,2 s, `drawer` 0,28 s) – 197 Werte in 35 Views, Werte unverändert.
- **`MailPorts`:** `imaps` 993, `smtps` 465, `submission` 587.
- **Benannte Zeitlimits und Grenzen:** SMTP-Versand (60 s je Befehl, 120 s Inhalt), OAuth-Token-Anfrage (30 s), Absenderlogos (10 s / 20 s), erste Liste beim Start (3 s), Schriftgrößen-Tabellen, DNS-Längengrenzen, OAuth-Zufallslängen, JPEG-Qualität, FNV-Konstanten, Vorschlags- und Watch-Grenzen.
- **Namen:** `errorMessage`, `columnText`/`optionalColumnText`, `autoDownloadThresholdBytes`, `deliveryLifetimeSeconds`, `maxChunkSizeBytes`.
- **Header:** „Autor“, „Erstellt“, „Geändert“ in allen 203 Swift-Dateien unter `Mailwerk/`.

---

## 6. Dateien

**Neu (`Mailwerk/`):**

| Datei | Inhalt |
|---|---|
| `Services/HTMLEscaping.swift` | gemeinsame HTML-Maskierung |
| `Services/Sync/FetchClassifier.swift` | Einordnung der Kopfdaten gegen den Cache |
| `Services/Sync/FetchedMessageMapping.swift` | Modelle aus Server-Daten |
| `Services/Search/ServerSearchPlan.swift` | Logik der Serversuche |
| `Services/Folders/MailboxListing.swift` | Ordnerliste aufbereiten |
| `Views/MessageDetailContext.swift` | Angaben der Mailansicht, Platzhalter |

Neu außerdem `Package.resolved` (unter `Mailwerk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`).

**Geändert:** 224 Dateien gegenüber `4000fed`, darunter alle Swift-Dateien unter `Mailwerk/` (Header), `MailwerkWatch/WatchMailRow`, `WatchMailDetailView`, `project.pbxproj` (`Log.swift` in der Komplikation), `.gitignore`.

**Tests (neu):** `InputValidationTests`, `FetchPlanningTests`, `RefreshEvaluationTests`, `ExtractedLogicTests`, `CriticalPathTests`; angepasst u. a. `SyncStatePlannerTests`, `SpamMarkTests`, `FilterListImportTests`, `ShareContextTests`.

---

## 7. Tests

| Punkt | Ergebnis |
|---|---|
| Build aller Ziele (iOS, Mac, Watch-App, Komplikation, beide Share-Erweiterungen), Unit-Tests | erfolgreich |
| Abruf, Öffnen, Aktionen (gelesen, gekennzeichnet, verschieben, löschen – einzeln und mehrere) | erfolgreich |
| Antworten mit Zitat und Bild, Weiterleiten mit Anhang, Entwurf öffnen | erfolgreich |
| Serversuche, Kontaktvorschläge, Filterliste importieren, Postfach bearbeiten (OAuth) | erfolgreich |
| iPhone, iPad, Mac, Watch (Simulatoren), Optik und Animationen nach d | erfolgreich |
| Handoff Watch → iPhone | nicht prüfbar im Simulator; auch in der TestFlight-Version ohne Funktion (offener Punkt) |

---

## 8. Beobachtungen und Erkenntnisse

- **Fehlende Imports zeigen sich erst je Ziel:** `Logger`-Interpolation braucht `import os` in jeder Datei, die protokolliert; in der App fiel das nicht auf, in Komplikation und Share-Erweiterung schon. Ebenso `import SwiftMail` in Testdateien, die SwiftMail-Typen berühren.
- **`UIDSet` ist mehrdeutig,** sobald NIOIMAPCore sichtbar ist (Share-Ziel) – dort immer `SwiftMail.UIDSet` schreiben.
- **Standardwerte von Parametern** werden außerhalb des Main-Actors ausgewertet: Konstanten, die dort stehen, als `nonisolated static let` anlegen.
- **SwiftMail erwartet Zeitlimits als `TimeInterval`;** benannte Konstanten ausdrücklich typisieren.
- **Synchronisierte Ordner** in Xcode: neue Dateien brauchen keinen Projekteintrag; die Zugehörigkeit zu Watch-Zielen steht dagegen in Ausnahmelisten der `project.pbxproj`.

---

## Gesamtstand des Projekts (Stand 30.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS, macOS und watchOS. Repo `github.com/KimSieber/Mailwerk` (public, MIT-Lizenz; Name und Icon ausgenommen), Branch `main`.
- Version **0.3.1** (die Versionsnummer `MARKETING_VERSION` steht im Projekt noch auf 0.3.0 und wird manuell in Xcode gesetzt), **885 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkWatch Watch App, MailwerkWatchWidgetExtension, MailwerkTests, MailwerkUITests.
- **Ziel:** Veröffentlichung im App Store; neue Nacharbeiten nur aufnehmen, wenn sie dafür nötig sind.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; iOS/macOS/watchOS 26.5.
- **SwiftMail 1.15.0**, Versionen über `Package.resolved` festgelegt.
- Datenbank: SQLite (WAL, getrennte Lese-/Schreibverbindung), FTS5-Suchindex; Lesen über `query`/`queryFirst`.
- Abruf: eine IMAP-Verbindung je Postfach und Runde, höchstens 3 Postfächer gleichzeitig (2 je Server); Entscheidungen in reinen Planern (`SyncStatePlanner`, `ServerReconciliation`, `FetchClassifier`, `SpamFilterPlanner`, `ServerSearchPlan`).
- Erscheinungsbild: Farben, Abstände, Radien und Animationen zentral in `AppTheme`.

### Arbeitsregeln (verbindlich)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher abstimmen; große Schritte in 3–4 Teile mit eigenem Testpunkt.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen.
- Lieferung als ganze Dateien direkt in den Projektordner; Claude committet nicht; Commit-Text erst nach erfolgreicher Abnahme einer Stufe.
- Inline-Doku: Datei-Header (Autor, Erstellt, Geändert, Zweck, Abgrenzung, Abhängigkeiten), Kopfkommentar je Funktion, Deutsch; **„Geändert“ bei jeder Lieferung nachziehen**.
- Code-Review nach `code-review.md` (Fassung 1.1) als Maßstab für neue Stufen.
- Öffentliche Dokumentation ohne persönliche Bezüge; Arbeitsdokumente in `Documentation/Intern/` (nicht in Git).

### Offene Punkte
- **Handoff Watch → iPhone** funktioniert nicht (auch in der TestFlight-Version); eigenes Thema nach v0.3.1.
- **Code-Review:** neuer Prüflauf mit Fassung 1.1; Regel 9 (rund 210 verbliebene Einzelwerte) nur bei Bedarf weiter senken.
- Übrige offene Punkte unverändert wie in v0.2.4 (Mac: größere HTML-Mails, Übersetzung für weitere Sprachen, Abnahme iPad/Watch über TestFlight, Ordnerliste über eigene Verbindung, Default Mail App, Azure-Herausgeber-Verifizierung vor dem App Store).

### Fahrplan
- **Jetzt:** Versionsnummer 0.3.1 setzen, TestFlight-Build hochladen, neuer Prüflauf.
- **Danach:** Handoff, dann die für den App Store nötigen Punkte (Herausgeber-Verifizierung, Store-Auftritt, Screenshots).
