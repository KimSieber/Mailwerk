# Mailwerk – Stand nach v0.1.7 und nächste Schritte

Stand: 2026-09-30 · Übergabe für den Start von v0.1.8 in einem neuen Chat

---

## 1. Projekt in Kürze

Mailwerk ist ein eigener Mail-Client für iPhone, iPad und Mac (Swift/SwiftUI, Multiplatform-App) mit gemeinsamer Ansicht mehrerer Postfächer und eigenem Spamfilter. Alle drei Postfächer liegen bei manitu (IMAP/SMTP, nur verschlüsselt). Das Ziel ist, die Postfächer künftig ausschließlich über Mailwerk zu bedienen.

- Repo: `KimSieber/Mailwerk` (public), Bundle-ID `de.sieber-bw.Mailwerk`
- IMAP/SMTP: SwiftMail 1.12.0 (Cocoanetics)
- Cache: System-SQLite (`import SQLite3`), Filterlisten in SwiftData mit iCloud (CloudKit)
- Einstellungen: Swift 5, Default Actor Isolation MainActor, Approachable Concurrency
- Testgeräte: iPhone (real) und Mac. Der Simulator ist für iCloud unzuverlässig und zum Scrollen mühsam.

---

## 2. Was funktioniert (Stand v0.1.7e)

| Bereich | Stand |
|---|---|
| Postfächer | Einrichten, bearbeiten (alle Felder), Farbe, Standard-Postfach, Verbindungstest; Keychain-Fehler werden gemeldet |
| Abruf & Cache | 30-Tage-Fenster, Body + Anhänge ≤ 5 MB, Flags-Abgleich; ältere Mails per Button nachladbar (bis App-Neustart) |
| Anzeige | „Alle Eingänge", „Mit Kennzeichnung" (mit Zähler und Rückgängig), jeder Ordner einzeln; zweite Titelzeile mit Stand („Aktualisiert: vor 5 Min.") |
| Ordnerleiste | Einfahrleiste links (iPhone), Postfächer aufklappbar, Ordnerbaum mit Einrückung, einheitliche deutsche Namen für Sonderordner, Farbpunkt am gewählten Ordner |
| Offline | Kein Abruf ohne Netz, keine Fehlermeldung; Titel „Offline · Stand: …"; automatischer Abruf, wenn das Netz zurückkommt |
| Mail-Aktionen | Lesen, Kennzeichnen, Verschieben, Löschen, Spam/Vertrauen (Untermenü), Teilen (HTML-Datei + Anhänge), Drucken (mit Anhangsliste) |
| HTML-Mails | Breiten angepasst, Links antippbar (extern bzw. mailto → Mailwerk), JavaScript aus |
| Versand | Neu/Antworten/Allen antworten/Weiterleiten, HTML-Editor, eigene Anhänge, Gesendet-Kopie |
| Spamfilter | Clientseitig auf den Posteingängen (30 Tage), Black-/Whitelist per iCloud auf allen Geräten, Export für das manitu-Portal |

---

## 3. Arbeitsweise (bitte beibehalten)

- **Kleine MVPs** (z. B. v0.1.8a, b, …). Große Schritte werden in 3–4 Abschnitte mit eigenem Testpunkt geteilt. Nach jedem Schritt wartet Claude auf Kims Bestätigung.
- **Committet wird erst, wenn ein MVP als Ganzes erreicht ist.** Zwischenstände werden nicht gepusht, deshalb arbeitet Claude mit seiner lokalen Kopie der zuletzt gelieferten Dateien weiter.
- **Lieferung:** immer ganze Dateien zum Download plus Tabelle „Datei – Zielordner – Art". Keine Claude-Code-Prompts, keine Code-Schnipsel zum Einfügen.
- **Vor jeder Umsetzung** den aktuellen Code aus dem Repo lesen, nicht aus dem Gedächtnis schreiben. Genutzte SwiftMail-APIs im Quelltext von 1.12.0 prüfen.
- **Bei Fehlern erst analysieren,** dann einen begründeten Lösungsweg vorschlagen und erst nach Zustimmung umsetzen. Nicht herumprobieren.
- **Selbst kompilieren, wo möglich:** Claude prüft reine Logik und Tests in einer Swift-6.2-Toolchain für Linux mit Kims Projekteinstellungen, einschließlich echter SQLite. SwiftUI, SwiftMail und Apple-Frameworks lassen sich dort nicht bauen. Solche Dateien bleiben klein und nutzen nur bekannte APIs.
- Themen vollständig abschließen, keine langen TODO-Listen. Zu jeder abgeschlossenen Version gehört eine Entwicklungsdokumentation als OnePager.

---

## 4. Wichtige Erkenntnisse (nicht wiederholen)

| Thema | Erkenntnis |
|---|---|
| SwiftUI `Group` | Modifier an einer Group wirken auf **jedes Kind einzeln**. Liefert ein Zweig zwei Views, erscheint die Toolbar doppelt. Jeder Zweig muss genau ein View liefern (Kommentar in `InboxView`). |
| Swift 6.2 | Gespeicherte async-Closures ohne feste Isolation werden `nonisolated(nonsending)` und bekamen im Test beschädigte Parameter. Closures deshalb ausdrücklich `@MainActor` deklarieren (siehe `FolderCatalog.Loader`). |
| Concurrency-Warnung | `[weak self]` in einem Task erneut erfassen (`Task { @MainActor [weak self] in … }`), statt die äußere Variable zu lesen. |
| IMAP-Antwortgröße | Eine SEARCH über ganze große Ordner führt zu `PayloadTooLargeError`. Suchen immer zeitlich oder abschnittsweise begrenzen. |
| Sequenznummern | Nach dem IMAPSYNC im August 2026 sagt die Ablagereihenfolge nichts über das Datum aus. Nachricht Nr. 1 ist nicht die älteste. |
| Netzstatus | `NWPathMonitor` meldet im Flugmodus mit Apple Watch einen Pfad über Bluetooth. Als online gelten nur WLAN, Mobilfunk und Kabel. |
| Datumsgrenzen | IMAP SINCE/BEFORE ist tagesgenau, das Aufräumen im Cache sekundengenau. Fenstergrenzen deshalb auf Tagesanfang legen. |
| App-Start-Aktionen | Gehören in `MailwerkApp.init`, nicht in View- oder ViewModel-Initialisierer, denn die laufen mehrfach. |
| WebView | Die abgeschaltete Interaktion hat das Menüproblem nicht gelöst und wurde zurückgenommen. |

---

## 5. Offene Punkte

### Ordnerverwaltung (Rest)
1. **Ordner anlegen und löschen.** Das ist seit v0.1.2 als Anforderung festgehalten. Offen ist, ob Umbenennen dazugehört.
2. **Verschieben-Dialog mit Ordnerbaum** und einheitlichen Namen. Der Dialog ist noch flach und nutzt die Servernamen.
3. **Ordnerliste offline verfügbar.** Die Leiste zeigt offline „Ordner konnten nicht geladen werden".
4. **Ungelesen-Zähler** an den Ordnern in der Leiste.

### Cache und Abgleich
5. **Abgleich mit dem Server.** Mails, die anderswo gelöscht oder verschoben wurden, bleiben im Cache stehen. Nachgeladene ältere Mails bekommen keine Flag-Änderungen.
6. **Postfach löschen.** Dessen Mails und Anhänge bleiben unsichtbar im Cache. Das ist datenschutzrelevant.

### Plattformen
7. **Feste Seitenleiste auf dem Mac,** auf dem iPad abhängig von Hoch- oder Querformat. Dazu kommt die Stand-Anzeige auf dem Mac, wo der Titel in der Fensterleiste steht.

### Beobachten
8. **Aktionsmenü** bei einzelnen komplexen Mails knapp abgeschnitten. Neue Beispiele sammeln, dann analysieren.

### Roadmap (später)
- **Volltextsuche** (SQLite FTS5). Die Eingabe kommt an den unteren Bildschirmrand, dieser Bereich bleibt frei.
- **Signaturen** (HTML, je Postfach).
- **Konversations-Threading.**
- **0.4.x:** eigener Push-Server (IDLE + APNs), Posteo-Unterstützung.

---

## 6. Vorschlag für v0.1.8

| MVP | Inhalt | Warum in dieser Reihenfolge |
|---|---|---|
| v0.1.8a | Ordner anlegen und löschen (ggf. umbenennen) | Baut direkt auf Leiste und Ordnerbaum auf; schließt die eigentliche Ordnerverwaltung ab |
| v0.1.8b | Verschieben-Dialog mit Ordnerbaum + Ordnerliste offline | Nutzt dieselbe Baumkomponente; danach ist die Ordnerverwaltung rund |
| v0.1.8c | Server-Abgleich des Caches + Bereinigung beim Löschen eines Postfachs | Beides betrifft dieselbe Frage, welche Mails der Cache halten soll |
| später | Ungelesen-Zähler, Mac-/iPad-Seitenleiste | Komfort; unabhängig von den übrigen Punkten |

**Zu klären zum Start von v0.1.8a:**
- Gehört Umbenennen dazu?
- Wo wird ein Ordner angelegt: oberste Ebene, unter einem gewählten Ordner oder beides?
- Was passiert beim Löschen eines Ordners, der noch Mails oder Unterordner enthält?
- Sind Sonderordner (Posteingang, Gesendet, Spam …) vor dem Löschen geschützt?

---

## 7. Dokumente im Projekt

- `Mailwerk___Projekt-Initialdokumentation.md`: Ziele, Architektur, Roadmap
- `Mailwerk_Spamfilter_Konzept.md`, `Mailwerk_iCloud-Sync_Problemanalyse.md`
- `Mailwerk_v0_1_0` … `v0_1_7e_Entwicklungsdokumentation.md`: je Version ein OnePager
- dieses Dokument: Übergabe für v0.1.8
