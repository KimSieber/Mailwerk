# Mailwerk – Entwicklungsdokumentation v0.2.3

2026-10-25 · „Performance-Optimierung“: kürzere Ladezeiten, keine Hänger während des Abrufs, flüssige Liste, schnelles Öffnen von Mails, paralleler Abruf der Postfächer

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen. Grundlage ist der Prüfbericht (`Documentation/Intern/Mailwerk_v0.2.3_Performance-Pruefbericht.md`) mit den Befunden P-01 bis P-21 und den Messergebnissen.

---

## Zusammenfassung

v0.2.3 ändert die Funktion nicht, sondern die Arbeitsweise: Datenhaltung, Abruf, Spamfilter und Suchindex laufen abseits des Hauptthreads, die Datenbank schreibt in gebündelten Transaktionen, die Liste rechnet ihre Zeilen einmal vor, Mails öffnen im Hintergrund, und die Postfächer werden begrenzt parallel abgerufen.

| Paket | Inhalt | Befunde |
|---|---|---|
| **a** | Messbasis, Datenbank: WAL, Anweisungs-Cache, Paket-Transaktionen, Flags nur bei Änderung, Index auf Anhänge | P-03, P-04, P-05, P-20 |
| **b** | Hauptthread entlasten: getrennte Lese-/Schreibverbindung, Cache-Lesen, Abruf, Spamfilter, Suchindex im Hintergrund | P-01, P-02, P-10 |
| **c** | Flüssige Liste: vorberechnete Zeilenmodelle, `Equatable`-Zeilen, Absenderbilder als Vorschaubilder | P-06, P-07, P-08, P-09 |
| **d** (Teil 1, 2) | Eine Verbindung je Postfach, Öffnen im Hintergrund, Web-Ansicht-Pool, Anzeige-Hinweise beim Abruf gespeichert, Filterlisten im Speicher, Ordnerübersicht im Hintergrund, Start, Such-Entprellung | P-11, P-12, P-13, P-14, P-17, P-18 |
| **e** | Postfächer begrenzt parallel abrufen | P-21 |

| Kennzahl | Vorher | Nachher | Quelle |
|---|---|---|---|
| Liste aus dem Cache | auf dem Hauptthread | Ø 5–17 ms, im Hintergrund | Instruments (Messung 2) |
| Mail öffnen („Mail sichtbar“) | Hänger 276 ms, „sehr lange“ | typisch 85–120 ms | Konsole, Debug-Build |
| Abruf aller 5 Postfächer | 10–17 s, nacheinander | **5 s** (9 s beim ersten Abruf nach dem Start) | Konsole, Debug-Build |
| Start | Liste erst nach Abruf | Liste sofort, Abruf wartet auf die erste Liste | Beobachtung |
| Hänger während der Nutzung | 2 Microhangs (373 ms, 276 ms) | keine mehr beobachtet | Beobachtung |

Tests: 781 → **849** `@Test`-Funktionen, alle grün. Version **0.2.3**. Gebaut und getestet auf iPhone (echtes Gerät) und Mac. Watch und iPad sind erst über TestFlight prüfbar (Abschnitt 9).

| Commit | Inhalt |
|---|---|
| `6dc870b` | v0.2.3a–c – Datenbank, Hauptthread, Liste |
| `78244a2` | v0.2.3d (Teil 1) – eine Verbindung je Postfach, schnelleres Öffnen |
| `3924e9f` | v0.2.3d (Teil 2) – Ordnerübersicht, Start, Suche, Messpunkte |
| (dieser) | v0.2.3e – paralleler Abruf, Doku |

---

## 1. Entscheidungen

| Thema | Entscheidung |
|---|---|
| Vorgehen | Zuerst messen, dann ändern: Messbasis (Signposts, Konsolenzeiten) vor den Eingriffen; Wirkung je Paket belegt |
| Hauptthread | Datenhaltung und Netzwerkverarbeitung gezielt `nonisolated`/`@concurrent`; Standardisolierung `MainActor` bleibt |
| Mail-Aktionen (`MailActionService`), Watch-Stand | **zurückgestellt**: Aktionen Ø 0,7 s, fast nur Serverwartezeit, ohne Hänger; Watch-Stand noch nicht gemessen |
| Logo-Vorladen (P-09, Punkt 3) | **zurückgestellt** bis zur Scroll-Messung bei frischer Installation; einplanen, wenn dabei Ruckeln oder Aufblitzen auftritt |
| P-15 (Struktur/Teile gebündelt), P-16 (CONDSTORE/QRESYNC) | nur als Entscheidungsvorlage (Prüfbericht 9.6), nicht umgesetzt; erst nach Paket e beurteilen, ob der Abruf noch zu lang ist |
| Parallelität | höchstens 3 Postfächer gleichzeitig, höchstens 2 je IMAP-Server (Server drosseln zu viele gleichzeitige Anmeldungen) |
| Messkonfiguration | eigene Build-Konfiguration „Profile“ mit Bundle-Suffix `.dev`; überschreibt nie die produktive TestFlight-App |

---

## 2. Datenbank (Paket a)

- WAL-Modus mit Anweisungs-Cache; Anweisungen werden nicht mehr bei jedem Aufruf neu übersetzt.
- Schreiben in Paketen mit Savepoints statt einer Transaktion je Mail bzw. je Flag-Änderung.
- Flags bekannter Mails werden nur noch bei Änderung geschrieben.
- Index `idx_attachment_message` (Schema 8).
- Folge für die Messung: Signposts (`Log.Interval`) und Konsolenzeiten (`⏱ …`) an Abruf, Listenaufbau und Mail-Öffnen.

## 3. Hauptthread (Paket b)

- `MessageStore` mit getrennter Lese- und Schreibverbindung.
- `InboxCacheReader` liest die Liste abseits des Hauptthreads.
- Abruf (`MailFetchService`), Spamfilter und Suchindex-Aufbau laufen mit `@concurrent` bzw. `nonisolated`; Ergebnisse werden mit Zähler (Generation) gegen veraltete Antworten abgesichert.

## 4. Liste (Paket c)

- `MessageRowModel`: Zeile wird einmal vorberechnet (Adresse, Spam-Einstufung, Bildentscheidung), Zeilen sind `Equatable`.
- Absenderbilder: Dekodieren und Verkleinern (120 px, ImageIO) im Hintergrund; Änderungen je Domain statt globalem Zähler.

## 5. Abruf und Öffnen (Paket d)

### 5.1 Eine Verbindung je Postfach (P-13)

`AccountRefreshService` ruft Spamfilter-Schritt, Posteingang und Spam-Ordner über **eine** IMAP-Verbindung ab. Mit der zweiten Verbindung entfiel eine unbeabsichtigte „Wiederholung“ der Anmeldung; Gmail lief deshalb in die Anmelde-Frist (5 s) und meldete „nicht erreichbar“.

- **Lösung:** scheitert die Anmeldung, bevor Arbeit begonnen hat, folgt **ein** neuer Versuch nach 2 s, wenn das Netz da ist (`shouldRetryLogin`, `loginRetryDelay`).
- Verbindungsverlust im Spamfilter-Schritt: der Abruf verbindet neu (`failureHandling(forSpamStepError:)`).
- `SpamFilterService.filterInbox(on:…)` arbeitet auf der übergebenen Verbindung; `resolveSpamFolder` ist `nonisolated static`.
- Filterlisten werden im Speicher gehalten (`CachingFilterListRepository`, Dekorierer um `SwiftDataFilterListRepository`; `refreshedLists()` vor jedem Filterlauf).

### 5.2 Mail öffnen (P-11, P-12)

- `MessageOpenPreparation`: Laden aus dem Cache, Aufbereiten des Inhalts, Teilen-Dateien und Sprache laufen im Hintergrund; `MessageDetailLoader.load()` ist asynchron.
- **Anzeige-Hinweise** (`MessageDisplayHints`: externe Inhalte, eigene Farben, Sprache) werden beim Abruf berechnet und je Mail gespeichert (Schema 9, versioniert); beim Öffnen entfällt die Berechnung. Ältere Mails: einmalig beim Öffnen berechnet und gespeichert.
- `MailWebViewPool`: zwei vorgewärmte Web-Ansichten (`prewarm()` 1 s nach dem Start), Wiederverwendung (`take()`/`recycle(_:)`, zurückgesetzt auf leeres Dokument). `HTMLMailView` meldet das Ende des Ladens (`onLoaded`), darauf endet die Messung „Mail sichtbar“ (`MessageOpenTimer`).
- Mehrere Zustände (`visibleAttachments`, `usesOwnColors`, Teilen-Dateien) hängen an Zählern, damit ein schneller Mailwechsel keine veralteten Ergebnisse anzeigt.

### 5.3 Weiteres

- **Ordnerübersicht (P-14):** Ordnerbaum im Hintergrund geladen (`MailActionService.loadFolderTree`, `cachedFolderTree`); `FolderCatalog.CachedLoader` asynchron.
- **Start (P-18):** Datenbank früh im Hintergrund geöffnet (`MailwerkApp`), Startmeldung abseits des Hauptthreads, Suchindex-Aufbau im Hintergrund, `LaunchTimer`. Der erste Abruf wartet auf die erste Liste (`waitForFirstList`), damit die Anzeige nicht mit dem Abruf konkurriert.
- **Suche (P-17):** Entprellung 150 ms, lokale Suche und Personensuche im Hintergrund (`SearchViewModel`).
- Als `nonisolated` markiert (Zugriff aus dem Hintergrund): `MailPrintFormatter`, `AttachmentManager` (Dateiname, Temp-Datei), `AttachmentFilename.completedFilename`.

## 6. Paralleler Abruf (Paket e, P-21)

- `ParallelRefreshPlanner` (reine Planungslogik, `nonisolated`): Warteschlange von Postfächern mit Server (Host); `nextStartable`/`startableItems` liefern, was starten darf (höchstens 3 gesamt, 2 je Host); `finish`, `dropPending`, `isFinished`.
- `InboxViewModel.performRefresh` startet die Abrufe in einer `withTaskGroup`; jedes Postfach läuft einmal je Runde, nachträglich hinzugekommene laufen mit (`newRefreshItems(known:)`).
- Die Liste lädt während des Abrufs **zusammengefasst** neu (`scheduleListReload`, höchstens alle 300 ms) und einmal am Ende.
- Netzverlust bricht laufende Abrufe ab und verwirft wartende; Fehler je Postfach werden gesammelt und einmal gemeldet. Erreichbarkeit je Postfach (v0.2.2) bleibt unverändert.
- Konsole: `⏱ Abruf <Konto>: … ms` je Postfach, `⏱ Abruf gesamt: … ms`; überlappende Abrufe sind an den Zeitstempeln von `🔄 Refresh gestartet` erkennbar.

---

## 7. Dateien

**Neu (`Mailwerk/`):**

| Datei | Inhalt |
|---|---|
| `Services/AccountRefreshService.swift` | Abruf eines Postfachs über eine Verbindung, Wiederholung der Anmeldung |
| `Services/ParallelRefreshPlanner.swift` | Planung des begrenzt parallelen Abrufs |
| `Services/MessageOpenPreparation.swift` | Mail im Hintergrund laden und aufbereiten |
| `Services/MessageDisplayHints.swift` | Anzeige-Hinweise je Mail (versioniert) |
| `Services/Spam/CachingFilterListRepository.swift` | Filterlisten im Speicher |
| `Services/LaunchTimer.swift`, `Services/MessageOpenTimer.swift` | Messpunkte Start und Mail sichtbar |
| `Views/MailWebViewPool.swift` | vorgewärmte Web-Ansichten |
| (Pakete a–c) `InboxCacheReader`, `MessageRowModel`, `DecodedImage` u. a. | siehe Commit `6dc870b` |

**Geändert (Auswahl):** `MessageStore` (WAL, Savepoints, Schema 8 und 9, Lese-/Schreibverbindung, Hinweise), `MailFetchService`, `SpamFilterService`, `FilterListRepository`, `InboxViewModel`, `SearchViewModel`, `InboxView`, `MessageDetailView`, `HTMLMailView`, `MailActionService`, `FolderCatalog`, `MailwerkApp`, `Log`. Projekt: `MARKETING_VERSION` 0.2.3 (alle Ziele); Anzeigename über `INFOPLIST_KEY_CFBundleDisplayName = $(MAILWERK_DISPLAY_NAME)`.

**Tests (neu in d/e):** `AccountRefreshServiceTests` (10), `MessageOpenPreparationTests` (4), `CachingFilterListRepositoryTests` (4), `MessageDisplayHintsTests` (7), `MailWebViewPoolTests` (6), `MessageOpenTimerTests` (4), `ParallelRefreshPlannerTests` (6). Schema-Erwartung 8 → 9 in `MessageStoreTransactionTests`, `MessageStoreSyncTests`, `MessageStoreListTests`.

---

## 8. Tests und Messung

| Punkt | Ergebnis |
|---|---|
| Bau iPhone, Mac; alle Tests | erfolgreich |
| Gmail, Outlook, manitu, weitere: Abruf ohne Fehlermeldung | erfolgreich |
| Mails öffnen (Text, HTML, mit „Inhalte laden“, Anhänge, Teilen, Drucken) | erfolgreich, „Mail sichtbar“ 85–120 ms |
| Liste beim Start sofort | erfolgreich |
| Abruf aller 5 Postfächer, neue Mail | 5 s |
| Abruf direkt nach dem Start | 9 s (Anmeldungen, Token-Erneuerung) |
| Suche, Ordnerübersicht, Spamfilter, Funktionstests | erfolgreich |
| Watch-Stand, Scrollen nach frischer Installation | nicht gemessen (siehe Abschnitt 10) |

---

## 9. Beobachtungen und Erkenntnisse

- **Hänger kommen vom Hauptthread, nicht vom Netz:** Netzwerk-I/O wartet außerhalb, die Weiterverarbeitung der Antworten gehörte auf den Hintergrund.
- **Lange Abrufe (14–18 s) = hängende erste Anmeldung** bei manitu/Gmail: 5 s Zeitüberschreitung, rund 5 s Abbau der Verbindung in SwiftMail, 2 s Pause vor dem zweiten Versuch. Der parallele Abruf überdeckt das; eine kürzere Frist ist vorgemerkt.
- **Outlook:** rund 4,3 s je Abruf, ca. 300 ms je Befehl (Serverlatenz) – nicht beeinflussbar.
- **Zweite Verbindung versteckte einen Fehler:** Die frühere zweite Verbindung wiederholte die Anmeldung unbeabsichtigt; beim Entfernen musste die Wiederholung ausdrücklich eingebaut werden.
- **Start:** Das frühe Öffnen der Datenbank allein brachte kaum Zeit; erst das Warten des Abrufs auf die erste Liste ließ die Anzeige sofort erscheinen.
- **Debug-Zeiten:** Konsolenwerte stammen aus dem Debug-Build; Instruments-Messungen mit der Konfiguration „Profile“ (Release-ähnlich).
- **Raw-String-Literale in Tests:** HTML mit `"#` darin braucht `##"…"##`.
- **Test-Importe:** `SwiftUI`-Typen in Tests (`Binding.constant`) brauchen `import SwiftUI`.
- **Anzeigename:** `CFBundleDisplayName` nicht in Xcode unter *General* ändern – Xcode ersetzte sonst den Platzhalter durch einen festen Wert.

---

## 10. Hinweise für den Betrieb und Abnahme über TestFlight (offen)

- Beim Start zeigt die App die Liste sofort; der erste Abruf kann wegen Anmeldungen bis ca. 9 s dauern.
- Erscheint „nicht erreichbar“ bei einzelnen Postfächern nach hängender Anmeldung, Konsole sichern (`🔄`, `⏱ Abruf …`, `📴 …`).
- Die produktive App heißt nach dem Hochladen in TestFlight wieder „Mailwerk“; „Mailwerk Dev“ bleibt für Xcode-Läufe.

| Nr. | Gerät | Prüfung | Erwartung |
|---|---|---|---|
| 1 | iPhone | Scrollen durch „Alle Eingänge“ nach frischer Installation (Instruments „Animation Hitches“) | kein Ruckeln; sonst Logo-Vorladen einplanen |
| 2 | Watch | Stand der Watch-Anbindung messen (P-19) | Entscheidung über Verlagerung in den Hintergrund |
| 3 | iPad, Watch | Abnahme wie in v0.2.1/v0.2.2 | siehe dortige Abschnitte |

---

## Gesamtstand des Projekts (Stand 25.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS, macOS und watchOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`.
- Version **0.2.3**, **849 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkWatch Watch App, MailwerkWatchWidgetExtension, MailwerkTests, MailwerkUITests.
- **Verteilung:** TestFlight (zwei Testpersonen); 0.2.2 und 0.2.3 noch hochzuladen. „Mailwerk Dev“ per Xcode auf iPhone, iPad-Simulator und Mac.

### Funktionsumfang
Unverändert gegenüber v0.2.2 (Unified Inbox, Sammelansichten, Erreichbarkeit je Postfach, Ordnerleiste, Offline-Cache mit FTS5, iPad-Spaltenlayout, sichere HTML-Ansicht, Übersetzung, Verfassen, clientseitiger Spamfilter, Suche, Teilen, OAuth 2, Apple Watch). Details: Entwicklungsdokumentation v0.2.2.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus; iOS/macOS/watchOS 26.5. Xcode 27.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage).
- Datenbank: SQLite (WAL, getrennte Lese-/Schreibverbindung, Savepoint-Pakete), Schema **9**, FTS5-Suchindex.
- Abruf: eine IMAP-Verbindung je Postfach und Runde, höchstens 3 Postfächer gleichzeitig (2 je Server).
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Tokens: iCloud-Schlüsselbund; Filterlisten und Signaturen: SwiftData/CloudKit; Abruf-Schalter: UserDefaults (je Gerät).
- Test/Produktion: Bundle-Suffix `.dev`; Build-Konfiguration „Profile“ für Instruments.

### Arbeitsregeln (verbindlich)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher abstimmen.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen; klare Anweisungen mit genauem Menüpfad.
- Ursache belegen, nicht raten (Rohdaten, Konsole, Quelltext, Git-Historie).
- **Lokale Sitzung:** Lieferung als ganze Dateien direkt in den Projektordner, mit Liste der Zielordner; Git nur lesend; Claude committet nicht. Commit-Text erst zum Abschluss einer Stufe nach erfolgreicher Abnahme.
- Versionen werden nicht mit bekannten Fehlern abgeschlossen.
- Projekteinstellungen, die sich nur in Xcode ändern lassen, manuell nach Anleitung.
- Inline-Doku: Datei-Header (Zweck, Abgrenzung, Abhängigkeiten), Kopfkommentar je Funktion, Deutsch, keine Versionsverweise; Tests nur mit kurzen Kommentaren.
- Öffentliche Dokumentation ohne persönliche Bezüge; Arbeitsdokumente in `Documentation/Intern/` (nicht in Git).
- Keine Sonderlösungen für einzelne Anbieter; Apple-Bausteine; keine veralteten APIs.
- Tests dürfen keine Produktivdaten verändern; Apps auf dem iPhone nie löschen; die Profile-Konfiguration darf die TestFlight-App nie überschreiben.

### Offene Punkte
- **Performance:** Watch-Stand messen (P-19); Scroll-Messung nach frischer Installation → Entscheidung Logo-Vorladen; kürzere Frist bei hängender Anmeldung; P-15a/P-15b und P-16 (Prüfbericht 9.6) nur bei Bedarf; `MailActionService` in den Hintergrund nur bei messbarem Gewinn.
- **Übersetzung:** zweiter Dienst für Sprachen ohne Apple-Unterstützung; erste Übersetzung ohne Netz ungeprüft.
- **iPad/Watch:** Abnahme über TestFlight (v0.2.1, v0.2.2); Server-Treffer der Suche im Spaltenlayout.
- **Mac:** Spaltenlayout und Menübefehle (eigene Version); größere HTML-Mails öffnen sich teils nicht.
- **H6 (Rest):** Ordnerliste über eigene Verbindung kann bei Gmail noch in die Zeitüberschreitung laufen; ggf. mit Push/IDLE.
- **Default Mail App:** Antrag abgelehnt; neu beantragen mit TestFlight-Link.
- **MailwerkUITests:** Ordner fehlt auf der Platte – aufräumen oder neu anlegen.
- **Azure-Probephase:** nach Ablauf Outlook neu anmelden; vor App Store Herausgeber-Verifizierung.
- Weitere: `mailto:`-Randfall, Whitelist mit `X-Spam-Flag: YES`, Gmail per OAuth, Kopfdaten außerhalb des Zeitfensters, N14 Offline-Warteschlange, Ordner abonnieren, DKIM/Authentication-Results, Suchfeld unten, Teilen (große Videos, HEIC).

### Fahrplan
- **Jetzt:** v0.2.3 committen, TestFlight-Build 0.2.3 (und 0.2.2) hochladen, Abnahme iPad und Watch; dabei Watch-Stand und Scrollen messen.
- **Danach:** Mac-Fassung (Spaltenlayout, Menübefehle, „größere HTML-Mails“).
- **Später:** zweiter Übersetzungsdienst, H6, Push/IDLE, P-15/P-16, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung.
