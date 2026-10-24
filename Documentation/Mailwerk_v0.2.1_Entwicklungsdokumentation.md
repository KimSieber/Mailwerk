# Mailwerk – Entwicklungsdokumentation v0.2.1

2026-10-22 · „iPad-Optimierung“: Spaltenlayout mit Liste und Mail nebeneinander, feste Ordnerleiste, Tastatur und Menüleiste, Ziehen auf Ordner – dazu zwei Fehlerbehebungen

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen.

---

## Zusammenfassung

v0.2.1 nutzt den großen Bildschirm des iPad: Eine angetippte Mail erscheint rechts neben der Liste statt per Push. Im Querformat steht auf Wunsch die Ordnerleiste dauerhaft als dritte Spalte. Umgesetzt in drei Stufen in einer lokalen Sitzung (Dateien direkt in den Projektordner, Commit lokal).

| Stufe | Inhalt |
|---|---|
| **a** | Spaltenlayout: ohne geöffnete Mail Liste auf voller Breite, mit Mail Liste + Mail; im Querformat wahlweise drei Spalten; Vollbild der Mailansicht |
| **b** | Gemeinsamer Code iPhone/iPad; geöffnete Mail markiert; vorige/nächste Mail; Tastatur und Menüleiste; Ziehen auf Ordner; Posteingang und Spam über eine Verbindung |
| **c** | Anhänge ohne Dateiendung öffnen; Watch-Aktualisierung (nicht nachstellbar, geschlossen) |

| Bereich | Ergebnis |
|---|---|
| iPad Hochformat | Liste + Mail (2 Spalten), Vollbild per Knopf |
| iPad Querformat | 2 Spalten (Ordner per einblendbarer Leiste) oder 3 Spalten (Ordnerleiste fest) – Einstellung je Gerät |
| Ohne geöffnete Mail | Liste auf voller (verbleibender) Breite, in beiden Ausrichtungen |
| Navigation | Tipp oder Pfeiltasten ↑/↓ wählen die Mail; Pfeil-Knöpfe in der Mailansicht; nach Löschen/Verschieben rückt die nächste Mail nach |
| Tastatur | ⌘N, ⌘R, ⌘F, ⌘⌫, Esc über die Menüleiste des iPad (Abnahme auf dem Gerät offen) |
| Ziehen | Mail auf einen Ordner der festen Ordnerleiste → verschieben |
| iPhone, Mac | Verhalten unverändert (Push-Navigation) |

Tests: 743 → **759** Testfunktionen (`@Test`, 16 neu), alle grün. Version **0.2.1 (Build 1)**. Gebaut und getestet für iPhone und iPad (Simulator), Mac gebaut. Offen ist die Abnahme von Menüleiste und ⌘-Kürzeln auf einem echten iPad (Abschnitt 7).

| Commit | Inhalt |
|---|---|
| `219e98d` | v0.2.1a – Spaltenlayout, Statusleiste, feste Ränder, dauerhafte Ordnerleiste |
| `de608b1` | v0.2.1b – gemeinsamer Code, Navigation, Tastatur, Ziehen, Abruf über eine Verbindung |
| (dieser) | v0.2.1c – Endung für Anhänge, Doku |

---

## 1. Anforderungen und Entscheidungen

| Thema | Entscheidung |
|---|---|
| Spalten im Hochformat | immer zwei (Liste + Mail); drei Spalten passen visuell nicht |
| Spalten im Querformat | Nutzer wählt: drei Spalten (Ordnerleiste fest) oder zwei (Ordnerleiste nur einblendbar) – Menü „Einstellungen“ → „Drei Spalten im Querformat“, gespeichert je Gerät (`@AppStorage("iPadLandscapeThreeColumns")`) |
| Ohne geöffnete Mail | Liste auf voller Breite – beim Start und nach jedem Ordnerwechsel, in beiden Ausrichtungen |
| Vollbild | Knopf links oben in der Mailansicht schaltet zwischen Spalten und Vollbild |
| Untere Leiste | bleibt, mittig zur Listenspalte |
| Hervorhebung der geöffneten Mail | hellblau in der Akzentfarbe – wie die gewählte Ansicht in der Ordnerleiste daneben |
| Kürzel | ⌘N, ⌘R, ⌘F, ↑/↓, ⌘⌫ (statt ⌫, wie Apple Mail), Esc |
| Ziehen auf Ordner | nur bei fester Ordnerleiste, nur innerhalb des Postfachs |
| Mac | eigene spätere Version |
| Zeiger-Effekte (Hover) | nicht gewünscht |

**Abweichungen von der ersten Planung (beim Test entschieden):**

| Geplant | Umgesetzt | Grund |
|---|---|---|
| Drei Spalten nur mit geöffneter Mail | Ordnerleiste bei drei Spalten **dauerhaft**, auch ohne Mail | Beim Ordnerwechsel schloss sich die Mail – und damit verschwand die Leiste, in der man gerade wählt |
| „X“ zum Verlassen des Vollbilds | Pfeil-Symbol zum Verkleinern | Ein Knopf für beide Richtungen; beim Test so abgenommen |
| Pfeiltasten als eigene Kürzel | Pfeiltasten bewegen die **Auswahl der Liste** (Tastaturnavigation von iPadOS) | iPadOS gibt einfache Pfeiltasten an die eigene Tastaturnavigation, nicht an Menübefehle (Abschnitt 8) |
| Hervorhebung grau | hellblau | grau war aus der Mehrfachauswahl übernommen, nicht bewusst gewählt |
| ⌘N zusätzlich zu „Neues Fenster“ | „Neue E-Mail“ **ersetzt** „Neues Fenster“ im Menü „Ablage“ | wie Apple Mail; Mailwerk ist auf ein Fenster ausgelegt (Liste und Zustand je App nur einmal) |

---

## 2. Aufbau des Spaltenlayouts

**Kein `NavigationSplitView`:** Es hält die Detailspalte immer frei und kann „Liste auf voller Breite, solange keine Mail offen ist“ nicht abbilden. Stattdessen ein eigenes Gerüst aus `HStack`.

```
InboxView.body
 ├─ usesColumns (horizontalSizeClass == .regular, nur iOS)
 │   └─ regularColumns:  [Ordnerleiste?] | listStack | [Divider + NavigationStack(Mail)]
 └─ sonst
     └─ listStack: NavigationStack(listContent) – Push wie bisher (iPhone, Mac)
```

| Zustand | Ordnerleiste | Liste | Mail |
|---|---|---|---|
| keine Mail | bei drei Spalten im Querformat | volle (verbleibende) Breite | – |
| Mail offen | bei drei Spalten im Querformat (280 pt) | 320 pt hoch / 380 pt quer | Rest |
| Vollbild | – | Breite 0, unsichtbar, nicht antippbar | volle Breite |

**Grundsatz: ein festes Gerüst, nur die Breiten ändern sich.** Liste, Suchfeld und Navigation werden nie neu angelegt; die Scrollposition bleibt beim Öffnen einer Mail erhalten. Erste Fassung tauschte je Zustand den ganzen Ansichtsbaum – beim Antippen einer Mail fror die App danach ein (Hauptthread im Ruhezustand, 0 % CPU, keine Eingaben mehr; Abschnitt 8).

**Ausrichtung:** aus der tatsächlichen Fenstergröße (`onGeometryChange`, Breite > Höhe) – stimmt auch bei Split View und Stage Manager. `UIScreen.main` ist ab iOS 26 veraltet.

**Ordnerwechsel** schließt die geöffnete Mail. **Wird das Fenster schmal** (Größenklasse kompakt), gilt wieder Push; die Auswahl entfällt.

**Feste Abstände:** iOS bemisst Seitenrand der Liste und Innenabstand der Zeilen nach der Breite – beim Wechsel von voller Breite auf Spaltenbreite sprangen Karte und Zeileninhalt um einige Punkt. Im Spaltenlayout sind beide fest 16 pt (`ColumnListMargins`, `ColumnRowInsets` mit `listRowInsets(.horizontal, …)` ab iOS 26), auf iPhone und Mac unverändert.

**Statusleiste:** getönte Fläche hinter dem ganzen Gerüst; die Liste wird im Vollbild per Deckkraft ausgeblendet, nicht mit `.clipped()` (das schnitt die Tönung unter der Statusleiste ab – weißer Balken).

---

## 3. v0.2.1b im Einzelnen

### 3.1 Gemeinsamer Code iPhone/iPad

Nach a gab es Liste, Zeile, Symbolleiste und die Modifier-Kette zweimal (gut 400 Zeilen). Zusammengeführt: Beide Layouts nutzen `listStack`/`listContent`, `messageList`, `messageRow` und `listToolbar`; die einzige Weiche ist `usesColumns` (wie ein Tipp öffnet). Abruf, Beobachter und Blätter hängen gemeinsam am äußeren Element (`withListLifecycle`, `withSelectionTracking`, `withSheets`).

**Dabei behobener Fehler aus a:** Auf dem iPad lud ein Ordnerwechsel nicht vom Server nach – der Beobachter dafür stand nur in der iPhone-Fassung.

### 3.2 Geöffnete Mail, vorige/nächste

- Im Spaltenlayout ist die geöffnete Mail die **Auswahl der Liste** (`List(selection:)`, `columnSelection`). Tipp und Pfeiltasten setzen sie über die Tastaturnavigation des Systems. Im Auswahlmodus und in Entwürfen gilt die gewöhnliche Liste.
- **Farbe:** Bei Auswahl stellt das System die Schrift auf Weiß um (passend zu seinem kräftigen Auswahlhintergrund). Die Karte hinterlegt aber hellblau (`CardRowBackground(isOpened:)`, Akzentfarbe 16 %); die Zeile legt ihre Farbstufen deshalb fest auf die Textfarben des Systems (`foregroundStyle(.label, .secondaryLabel, .tertiaryLabel)`). Ein Versuch über `backgroundProminence` wirkte nicht.
- **Pfeil-Knöpfe** ↑/↓ links oben in der Mailansicht (`MessageStepButtons`); am Listenende ausgegraut.
- **Nachrücken:** Verschwindet die geöffnete Mail aus der Liste (gelöscht, verschoben), öffnet sich die darunter, sonst die darüber (`MessageStepping.replacement`). In „Ungelesen“ bleiben gelesene Mails bis zum Herunterziehen stehen (`keptUnreadIDs`) – keine Kettenreaktion. Folge (bewusst so belassen): Zieht man in „Ungelesen“ bei offener Mail herunter, fällt sie heraus und die nächste öffnet sich und wird gelesen.
- Die Liste rollt mit (`ScrollViewReader`).

### 3.3 Tastatur und Menüleiste (`InboxCommands`)

Szenenbefehle (`.commands`) sind der Weg, den iPadOS für Kürzel vorsieht; sie stehen in der Menüleiste des iPad. Die Liste liefert ihre Aktionen per `focusedSceneValue(\.inboxCommands, …)`; eine fehlende Aktion graut Befehl und Kürzel aus.

| Menü | Befehl | Kürzel |
|---|---|---|
| Ablage | Neue E-Mail (ersetzt „Neues Fenster“) | ⌘N |
| Postfach | Aktualisieren | ⌘R |
| Postfach | Suchen | ⌘F |
| Postfach | Nächste / Vorige E-Mail | – (↑/↓ über die Listenauswahl) |
| Postfach | E-Mail löschen (mit Rückfrage) | ⌘⌫ |
| Postfach | Vollbild beenden | Esc |

Nur iOS (`#if os(iOS)` in `MailwerkApp`); der Mac behält seine Symbolleiste und ⌘R am Knopf „Aktualisieren“.

**Verworfen:** Kürzel an unsichtbaren Knöpfen in der Ansicht (Muster von „Originalquelle“ ⌥⌘U) – kamen unter iPadOS nicht an.

### 3.4 Ziehen auf Ordner

- Zeilen sind im Spaltenlayout ziehbar (`draggable`, nur die Cache-ID), Ordnerzeilen der **festen** Ordnerleiste nehmen an (`dropDestination(for:isEnabled:action:)`, ab iOS 26).
- Angenommen werden nur Ziehvorgänge aus Mailwerk selbst (`DropSession.localSession`); welche Kennungen gültig sind, prüft `MessageSelection.dropTargets` (nur Mails der Liste, gleiches Postfach, gültiger Zielordner). Ziehen in ein anderes Postfach meldet, warum nichts geschieht.
- Hervorhebung des Zielordners beim Darüberziehen erst ab iOS 27 (`onDropSessionUpdated`); unter iOS 26 funktioniert das Ablegen ohne Hervorhebung. Die ältere Variante mit `isTargeted` wird mit iOS 27.2 veraltet und wurde deshalb nicht genommen.

### 3.5 Posteingang und Spam über eine Verbindung

**Befund:** Der Stand der Sicht „Spam“ blieb gelegentlich hinter „Alle Eingänge“ zurück – unabhängig davon, aus welcher Sicht aktualisiert wurde. Konsole: Bei Gmail lief die **Anmeldung** (LOGIN) in die Zeitüberschreitung von 5 s, beim Spam-Ordner wie bei der Ordnerliste. Nicht die Ordnerstruktur – der Ordner war noch gar nicht gewählt. Ursache: Je Postfach und Abruf entstanden mehrere Verbindungen kurz hintereinander (Spamfilter, Posteingang, Spam-Ordner, parallel die Ordnerliste); Gmail bremst dichte Anmeldefolgen.

**Lösung:**
- `MailFetchService.refreshAndCache(_:folders:)` ruft mehrere Ordner über **eine** Verbindung ab; der Abruf eines Ordners ist in `syncFolder` herausgezogen, der Ein-Ordner-Aufruf verhält sich wie bisher.
- `InboxViewModel.refreshAccount` holt Posteingang und Spam-Ordner gemeinsam; scheitert nur der Spam-Ordner, folgt nach 2 s ein zweiter Versuch allein (`retrySpamFolder`).
- **Vermerken:** Bricht der Abruf beim Spam-Ordner ab, gilt der Posteingang trotzdem als aktuell (sein Abruf war vollständig). Scheitert erst das Abmelden, wird wie bisher nichts vermerkt. Bisher galt: Stand nur nach erfolgreichem Abmelden.

---

## 4. v0.2.1c im Einzelnen

### 4.1 Anhänge ohne Dateiendung

**Befund:** Ein Anhang „Kundendokumente“ mit `Content-Type: application/pdf` ließ sich nicht öffnen und wurde ohne Endung gespeichert. iOS erkennt den Typ für Vorschau und Teilen an der Endung.

**Lösung (`AttachmentFilename`):** Fehlt eine bekannte Endung, wird die zum Typ passende angehängt („Kundendokumente.pdf“) – aus Apples Typ-Verzeichnis (`UTType(mimeType:).preferredFilenameExtension`), keine eigene Tabelle.

| Fall | Ergebnis |
|---|---|
| keine Endung, Typ bekannt | Endung angehängt |
| bekannte Endung (auch abweichend vom Typ, auch Großbuchstaben) | unverändert |
| Punkt ohne bekannte Endung („Rechnung 2026.10“) | Endung angehängt |
| Typ ohne bekannte Endung (`application/octet-stream`, unbekannt) | unverändert |

Gilt beim Öffnen und Teilen (`AttachmentManager.writeTempFile`), in der Anhangliste (`AttachmentRow`) und **beim Weiterleiten** (`ComposeViewModel`), damit auch der Empfänger die Datei öffnen kann. Im Cache bleibt der Originalname.

### 4.2 Watch: „Aktualisieren“ löste keinen Abruf aus

Gemeldet: Aktualisieren auf der Watch zeigte nur den Stand des iPhones, ohne neuen Abruf. Der Code sieht den Abruf vor (Watch schickt `sync(…, refresh: true)`, iPhone ruft danach `InboxViewModel.refresh()` und schickt den neuen Stand). Beim Nachstellen funktionierte es in allen Fällen (App im Vorder- und Hintergrund, geschlossen). **Geschlossen ohne Änderung**, wird in der Praxis beobachtet. Vermutung, falls es wieder auftritt: iOS hält die im Hintergrund geweckte App an, bevor der Abruf aller Postfächer fertig ist – dann Konsole des iPhones (Kategorie „Watch“, „⌚️ …“, „🔄 Refresh …“) sichern.

---

## 5. Dateien

**Neu:**

| Datei | Inhalt |
|---|---|
| `Mailwerk/ViewModels/MessageStepping.swift` | vorige/nächste Mail, nachrückende Mail (rein, `nonisolated`) |
| `Mailwerk/Views/InboxCommands.swift` | Menübefehle und Kürzel (`InboxCommandActions`, `FocusedValues.inboxCommands`) |
| `Mailwerk/Services/AttachmentFilename.swift` | Endung für Anhänge, `CachedAttachment.completedFilename` |

**Geändert:**

| Datei | Änderung |
|---|---|
| `InboxView` | Spaltenlayout, gemeinsamer Code iPhone/iPad, Auswahl der geöffneten Mail, Ziehen, Aktionen für die Menübefehle, feste Abstände |
| `MessageDetailView` | Knöpfe Vollbild und vorige/nächste Mail (`MessageStepButtons`) |
| `FolderSidebarView` | Ordner nehmen gezogene Mails an (`onDropMessages`, `MessageDropTarget`) |
| `SideDrawer` | Kommentar: Einsatz neben der festen Ordnerleiste |
| `AppTheme` | `CardRowBackground(isOpened:)` – hellblau für die geöffnete Mail |
| `MessageSelection` | `dropTargets` |
| `MailFetchService` | `refreshAndCache(_:folders:)`, `syncFolder`, `FolderRefreshError` |
| `InboxViewModel` | Posteingang + Spam über eine Verbindung, `retrySpamFolder` |
| `MailwerkApp` | `.commands { InboxCommands() }` (iOS) |
| `AttachmentManager`, `AttachmentRow`, `ComposeViewModel` | Dateiname mit Endung |
| Projekt | `MARKETING_VERSION` 0.2.1 |

**Tests:** neu `MessageSteppingTests` (9), `AttachmentFilenameTests` (5); erweitert `MessageSelectionTests` (+2).

Neue Dateien in `Mailwerk/` werden über die synchronisierten Ordner automatisch eingebunden (App und Teilen-Erweiterungen; nicht Watch).

---

## 6. Tests

| Punkt | Ergebnis |
|---|---|
| Bau iPhone, iPad, Mac; 759 Tests | erfolgreich |
| iPhone: Liste, Mail öffnen, zurück, Aktionen | unverändert, erfolgreich |
| iPad hoch/quer, 2/3 Spalten, Vollbild, Ordnerwechsel | erfolgreich |
| Markierung, Pfeil-Knöpfe, Pfeiltasten, Nachrücken | erfolgreich |
| Ziehen auf Ordner (drei Spalten) | erfolgreich |
| Stand „Spam“ = „Alle Eingänge“ nach Aktualisieren aus jeder Sicht | erfolgreich |
| Anhang ohne Endung: Anzeige, Vorschau, Weiterleiten | erfolgreich |
| Menüleiste, ⌘N/⌘R/⌘F/⌘⌫/Esc | im Simulator nicht prüfbar (Abschnitt 8) |

---

## 7. Abnahme auf dem echten iPad (offen, über TestFlight)

| Nr. | Prüfung | Erwartung |
|---|---|---|
| 1 | Menüleiste: „Ablage“ → „Neue E-Mail“, „Postfach“ öffnen | Menüs öffnen sich; Befehle passend aktiv/ausgegraut |
| 2 | ⌘N, ⌘R, ⌘F | neue E-Mail, Abruf, Suchfeld |
| 3 | Mail geöffnet: ⌘⌫ | Rückfrage, danach nächste Mail |
| 4 | Vollbild: Esc | zurück zu den Spalten |
| 5 | Vollbild, Verfassen-Fenster offen: Esc | betrifft das Verfassen-Fenster, nicht das Vollbild dahinter |
| 6 | ↑/↓ mit Tastatur | Auswahl wandert, Mail rechts folgt |

---

## Beobachtungen und Erkenntnisse

- **Device Hub (Xcode 27):** Die Simulator-App heißt jetzt Device Hub; „Capture keyboard“ (über der Gerätefläche, nur im großen Fenster) leitet Tasten ans Gerät – **die ⌘-Taste aber nicht** (⌘A im Suchfeld ergibt „a“). Die Menüleiste des iPad lässt sich dort nicht bedienen (auch die Systemmenüs nicht). ⌘-Kürzel und Menüs sind deshalb nur auf dem Gerät prüfbar.
- **iPadOS-Tastaturnavigation:** Einfache Pfeiltasten gehen an die Fokusnavigation (sie sprang ins Suchfeld), nicht an Menübefehle. Pfeiltasten in Listen daher über die Listenauswahl.
- **Einfrieren ohne Last:** 0 % CPU und Hauptthread in `mach_msg2_trap` heißt: App wartet, Eingaben kommen nicht an – Hinweis auf einen hängengebliebenen UIKit-Übergang, hier durch Austausch des ganzen Ansichtsbaums mitten in der Berührung.
- **Breitenabhängige Ränder:** Seitenrand der Liste und Zeilenabstand richten sich nach der Containerbreite; für ruhige Spaltenwechsel fest setzen.
- **`.clipped()` und sicherer Bereich:** schneidet auch Hintergründe ab, die unter die Statusleiste reichen.
- **Gmail:** dichte Folgen neuer Anmeldungen laufen in die Zeitüberschreitung (5 s für LOGIN in SwiftMail) – Verbindungen bündeln.

---

## Gesamtstand des Projekts (Stand 22.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS, macOS und watchOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`. Lokaler Projektordner auf dem Entwicklungs-Mac.
- Version **0.2.1**, **759 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkWatch Watch App, MailwerkWatchWidgetExtension, MailwerkTests, MailwerkUITests.
- **Verteilung:** TestFlight (zwei Testpersonen), zuletzt Build 0.2.0 (1); 0.2.1 noch hochzuladen. „Mailwerk Dev“ per Xcode auf iPhone, iPad-Simulator und Mac.

### Funktionsumfang (bis v0.2.1)
- Unified Inbox mehrerer IMAP/SMTP-Postfächer, Abruf je Postfach ein-/ausschaltbar (je Gerät), Farben je Postfach, Absenderbilder (Kontakte, Favicons).
- Sammelansichten: Alle Eingänge, Ungelesen, Mit Kennzeichnung, Spam. Jeder Abruf holt je Postfach Posteingang und Spam-Ordner über eine Verbindung.
- Ordnerleiste mit Ordnerbaum, Ordner anlegen/löschen, Verschieben-Dialog, Offline-Cache (SQLite, FTS5-Suchindex), Server-Abgleich, „Ältere laden“.
- **iPad:** Spaltenlayout (Liste + Mail, im Querformat wahlweise mit fester Ordnerleiste), Vollbild, vorige/nächste Mail, Pfeiltasten, Menüleiste mit Kürzeln, Ziehen auf Ordner.
- Mailansicht: HTML sicher (CSP, externe Inhalte auf Knopf), Dunkelmodus, Zoom, eingebettete Bilder, Originalquelle mit Suche, Drucken, Teilen; Anhänge ohne Endung bekommen die passende.
- Verfassen: Rich-Text-Editor, Anhänge, Bilder im Text, Signaturen, Entwürfe, Absender-Regeln; `mailto:`-Links von außen.
- Spamfilter (clientseitig): White-/Blacklist über CloudKit, Domains samt Subdomains, Spam-Header, Blockieren/Vertrauen je Mail, Listen bearbeiten/exportieren/importieren.
- Suche (lokal, Namen, Server), Sortierung, Mehrfachauswahl, Kontextmenü, Rückgängig-Balken, eigene untere Leiste.
- Teilen mit Mailwerk (Erweiterungen iOS und Mac). Anmeldung per Passwort und OAuth 2 (Outlook.com).
- **Apple Watch:** vier Sammelansichten, lesen, gelesen/ungelesen, Kennzeichen, Spam/Vertrauen, Komplikation, Handoff; Abruf über das iPhone.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus; iOS/macOS/watchOS 26.5. Xcode 27.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage).
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Tokens: iCloud-Schlüsselbund; Filterlisten und Signaturen: SwiftData/CloudKit; Abruf-Schalter und Spalten-Einstellung: UserDefaults (je Gerät).
- Test/Produktion: Bundle-Suffix `.dev` für „Mailwerk Dev“.

### Arbeitsregeln (verbindlich)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher abstimmen.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen; klare Anweisungen mit genauem Menüpfad.
- Ursache belegen, nicht raten (Rohdaten, Konsole, Quelltext, Git-Historie).
- **Lokale Sitzung:** Lieferung als ganze Dateien direkt in den Projektordner; Git nur lesend; Claude committet nicht. Commit-Text erst zum Abschluss einer Stufe nach erfolgreicher Abnahme, nicht für Zwischenschritte.
- Versionen werden nicht mit bekannten Fehlern abgeschlossen.
- Projekteinstellungen, die sich nur in Xcode ändern lassen, manuell nach Anleitung.
- Inline-Doku: Datei-Header (Zweck, Abgrenzung, Abhängigkeiten), DocC je Funktion, Deutsch, keine Versionsverweise.
- Öffentliche Dokumentation ohne persönliche Bezüge (siehe `CLAUDE.md`); Arbeitsdokumente in `Documentation/Intern/`.
- Keine Sonderlösungen für einzelne Anbieter; Gestaltung mit Apple-Bausteinen; keine veralteten APIs (keine Warnungen).
- Tests dürfen keine Produktivmails verändern – Tests mit den Testpostfächern in „Mailwerk Dev“.

### Offene Punkte
- **iPad:** Abnahme Menüleiste und ⌘-Kürzel auf dem Gerät (Abschnitt 7); Server-Treffer der Suche öffnen im Spaltenlayout per Push in der schmalen Listenspalte; Hervorhebung beim Ziehen erst ab iOS 27.
- **Watch:** Aktualisieren in der Praxis beobachten (Abschnitt 4.2); Testplan auf der echten Watch (v0.2.0, Abschnitt 8); eingebettete Bilder, Mitteilungen.
- **Mac:** Spaltenlayout und Menübefehle (eigene Version); größere HTML-Mails öffnen sich teils nicht (v0.2.0); produktive „Mailwerk“ noch nicht installiert.
- **H6 (Rest):** Ordnerliste lädt über eine eigene Verbindung und kann bei Gmail noch in die Zeitüberschreitung laufen („Erneut versuchen“); übrige Aktionen ohne Verbindungswiederverwendung; ggf. mit Push/IDLE.
- **Default Mail App:** Antwort von Apple abwarten, danach Capability einrichten.
- **MailwerkUITests:** Ordner fehlt auf der Platte – aufräumen oder neu anlegen.
- **Azure-Probephase:** nach Ablauf Outlook neu anmelden; vor App Store Herausgeber-Verifizierung.
- Weitere: `mailto:`-Randfall, Spam-Prüfung Whitelist mit `X-Spam-Flag: YES`, Gmail per OAuth, Kopfdaten außerhalb des Zeitfensters (Weg B), N14 Offline-Warteschlange, Ordner abonnieren, DKIM/Authentication-Results, Suchfeld unten, Teilen (große Videos, HEIC), Strukturempfehlungen.

### Fahrplan
- **Nächste Version:** TestFlight 0.2.1, Abnahme iPad-Kürzel und Watch auf den Geräten.
- **v0.2.x:** Mac-Fassung (Spaltenlayout, Menübefehle, „größere HTML-Mails“), Gestaltung der Teilen-Erweiterung auf dem Mac.
- **Später:** H6, Push/IDLE, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung.
