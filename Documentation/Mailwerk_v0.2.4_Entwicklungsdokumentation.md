# Mailwerk – Entwicklungsdokumentation v0.2.4

2026-10-27 · „Mac-Fassung“: Fenster, Spalten, Kopfleisten und Sheets nach dem Vorbild von iPhone/iPad, Mac-übliche Bedienung (Kontextmenüs, Tastaturkürzel, Hover, Drag & Drop, Menüleiste)

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen. Grundlage sind die Umsetzungsvorgabe v0.2.4 (Mac-Desktop-Anpassung, Punkte 1–13) und der Korrekturauftrag v0.2.4C (Abschnitte A–D), beide in `Documentation/Intern/`.

---

## Zusammenfassung

v0.2.4 macht aus der bisher nur „mitlaufenden“ Mac-Version eine eigenständige Mac-Fassung. Leitlinie: Der Mac übernimmt Aufbau und Bedienlogik der iPhone-/iPad-Fassung, weicht nur dort ab, wo eine iOS-Lösung auf dem Mac keinen Sinn ergibt (kein Vollbild-Knopf, Pfeiltasten statt Pfeil-Knöpfen, Hover statt langem Drücken).

| Stufe | Inhalt |
|---|---|
| **v0.2.4** (Vorgabe 1–13) | Schalter-Stil in Dialogen, Sheet-Größen, Kontextmenüs der Mailliste, Tastaturkürzel und Menü „Postfach“ auf dem Mac, Hover in der Liste, Mails auf Ordner ziehen, Menüleiste (`MacMenuCommands`), Anhänge herausziehen, Dateien ins Verfassen-Fenster ziehen |
| **v0.2.4C – A** | Fenster ohne System-Symbolleiste, eigenes Spaltengerüst wie iPad mit Breitenstufen, Kopfleiste über Liste und Mailansicht, eigenes Suchfeld |
| **v0.2.4C – B** | Scrollen in HTML-Mails, Knopf „Auf dem Server weitersuchen“ (alle Plattformen) |
| **v0.2.4C – C** | Einheitliche Kopfleiste der Sheets (✕ / ✓ / Senden) |
| **v0.2.4C – D** | Inhalte der Sheets als gruppierte Formulare mit Karten wie iOS |
| Nacharbeiten | Titel „Mailwerk“, Sprechblasen der Kennzeichen, drei Antwort-Knöpfe, Fotomediathek für Logos, Export der Filterlisten als Datei, Anhänge mit richtigem Dateinamen herausziehen, Rückfrage bei leerem Betreff (alle Plattformen) |

Ersetzt wurden aus der Vorgabe v0.2.4: Punkt 1 und 2 (NavigationSplitView), Punkt 4 (Mac-Toolbar) und Punkt 5 (Mindestbreite 800 pt). Die übrigen Punkte gelten weiter und wurden nach dem Umbau erneut geprüft.

Tests: 849 → **856** `@Test`-Funktionen (neu: `MacColumnLayoutTests`). Version **0.2.4**. Abnahme per Funktionstest auf dem Mac; iPhone und iPad unverändert bis auf die Punkte „Auf dem Server weitersuchen“ und „Rückfrage bei leerem Betreff“.

---

## 1. Entscheidungen

| Thema | Entscheidung |
|---|---|
| Grundsatz | Mac-Nutzer sind iPhone-Nutzer: Aufbau, Knöpfe und Abläufe wie auf iPhone/iPad; Mac-übliche Abweichungen nur, wo nötig |
| Fenster | `WindowGroup` mit `.windowStyle(.hiddenTitleBar)`; keine System-Symbolleiste mehr. Die oberste Zeile trägt nur die Fensterknöpfe und mittig „Mailwerk“ auf Nebelblau |
| Knöpfe | Eigene Kopfleisten je Spalte (gewöhnliche Views, keine `ToolbarItem`s) – kein Überlauf „»“, kein Flackern beim Mailwechsel |
| Spaltengerüst | Eigenes Gerüst wie iPad statt `NavigationSplitView`; feste Breiten, keine ziehbaren Trennlinien |
| Suche | Eigenes Suchfeld (`MacSearchField`), da `.searchable` auf dem Mac an die System-Symbolleiste gebunden ist; Logik unverändert im `SearchViewModel` |
| Servertreffer der Suche (Mac) | öffnen sich in der Mailansicht neben der Liste (die Liste hat dort keinen NavigationStack mehr) |
| Kreisknöpfe | 32 × 32 pt; grau für Abbrechen, Zurück und Zusatzaktionen, Akzentfarbe `#3A6FE8` mit weißem Symbol für Suchen, Sichern/Fertig und Senden |
| Antworten (Mac) | drei eigene Knöpfe (Antworten, Allen antworten, Weiterleiten) statt eines Knopfs mit Gedrückthalten – langes Klicken ist auf dem Mac unüblich |
| Erklärungen der Kennzeichen | auf dem Mac dieselbe Sprechblase wie auf iOS (Titel und Erklärung), beim Darüberfahren nach 0,25 s; der knappe System-Tooltip entfällt |
| Formulare | auf dem Mac `.formStyle(.grouped)` statt des Standardstils `.columns` (der Beschriftungen kürzte) |
| Vollbild der Mailansicht | auf dem Mac nicht vorhanden; Menübefehl „Vollbild beenden“ (Esc) nur auf iPhone/iPad |
| Leerer Betreff | Rückfrage „Ohne Betreff senden?“ mit „Senden“ / „Zurück“ – auf allen Plattformen |

---

## 2. Grundlage v0.2.4 (Vorgabe, Punkte 3 und 6–13)

- **Schalter in Dialogen:** Einzelne `Toggle`s erhalten `.toggleStyle(.switch)` – auf dem Mac Schalter statt Häkchen.
- **Sheet-Größen:** `MacSheetSize` mit festen Größenklassen (`form`, `list`, `compact`, `composer`).
- **Kontextmenü der Mailliste:** Rechtsklick öffnet dasselbe Menü wie in der Mailansicht (`MessageMenuItems`).
- **Tastaturkürzel:** `InboxCommands` auch auf dem Mac (⌘N, ⌘R, ⌘F, ⌘⌫, Menü „Postfach“); Pfeiltasten bewegen die Auswahl der Liste.
- **Hover:** Die Zeile unter dem Mauszeiger ist dezent getönt (`HoverCardRowBackground`, `CardRowBackground.isHovered`).
- **Mails auf Ordner ziehen:** in die feste Ordnerleiste, nur innerhalb desselben Postfachs.
- **Menüleiste:** `MacMenuCommands` – „Sidebar ein-/ausblenden“ (⌥⌘S), „Alle E-Mails auswählen“ (⌥⌘A), „Postfächer …“ (⌘,).
- **Anhänge herausziehen** aus der Mailansicht in Finder und andere Apps; **Dateien hineinziehen** ins Verfassen-Fenster (nur Datei-URLs).

---

## 3. Fenster und Spalten (v0.2.4C, A)

### 3.1 Breitenstufen (`MacColumnLayout`)

Reine, plattformneutrale Logik mit Unit-Tests.

| Element | Breite |
|---|---|
| Ordnerleiste | 280 pt |
| Mailliste neben geöffneter Mail | 380 pt |
| Mailansicht, Mindestbreite | 450 pt |
| Fenster, Mindestgröße | 380 × 500 pt |
| Fenster, Standardgröße | 1200 × 750 pt |

| Stufe | Bedingung | Darstellung |
|---|---|---|
| 1 | ≥ 1110 pt und Ordnerleiste eingeschaltet | Ordnerleiste, Liste, Mailansicht |
| 2 | ≥ 830 pt | Liste und Mailansicht; Ordnerleiste als einblendbare Leiste (`SideDrawer`) |
| 3 | darunter | eine Spalte wie auf dem iPhone; geöffnete Mail über die volle Breite mit Zurück-Knopf |

- Ohne geöffnete Mail reicht die Liste bis zum rechten Rand – kein Platzhalter mehr.
- Die Liste behält in allen Stufen ihre Identität (Breite 0 und Deckkraft statt Austausch des Ansichtsbaums); Suchzustand und Scrollposition bleiben erhalten.
- Ordner-Knopf und ⌥⌘S: ab 1110 pt feste Ordnerleiste ein/aus, darunter einblendbare Leiste (`folderButtonAction`).

### 3.2 Kopfleiste der Liste (`MacListHeaderBar`)

1. Knöpfe: Ordnerleiste, Aktualisieren (Kreisel während des Abrufs), Sortieren (bei geänderter Sortierung in der Akzentfarbe), Suchen (Akzentfarbe), Neue E-Mail; rechts außen Einstellungen. Im Auswahlmodus ersetzt dieselbe Zeile „Alle auswählen“, Anzahl und „Fertig“.
2. Titel der Ansicht (bei einem Ordner mit Farbpunkt), darunter Stand bzw. Verbindungshinweis, minütlich neu.
3. Suchfeld nur bei aktiver Suche (Lupe, ⌘F); Personen als Marke, Namensvorschläge per Klick oder ↑/↓ und Return; Esc bzw. ✕ beenden die Suche.

### 3.3 Kopfleiste der Mailansicht (`MacDetailHeaderBar`)

- Mitte: Farbpunkt und Postfach der Mail; passt der Name nicht zwischen gleich breite Ränder, rückt er neben die Knöpfe und wird gekürzt (`ViewThatFits`).
- Rechts: Antworten, Allen antworten, Weiterleiten, Aktionsmenü „…“ (Kreisel während einer Aktion).
- Links: nur in Stufe 3 der Zurück-Knopf.
- Gleiche Höhe in allen Zuständen; während die Mail lädt, steht die Leiste schon mit ausgegrauten Knöpfen (`MessageDetailLoader`, `ServerMessageLoader`) – kein Springen beim Mailwechsel.

---

## 4. Scrollen und Serversuche (v0.2.4C, B)

- **HTML-Mails scrollen:** Die Unterklasse `MailWebView` (in `HTMLMailView.swift`) reicht Mausrad- und Trackpad-Ereignisse an den äußeren ScrollView weiter; bei vergrößerter Mail scrollt die Web-Ansicht selbst. `createWebView()` und damit `MailWebViewPool` erzeugen sie auf dem Mac.
- **„Auf dem Server weitersuchen“** (alle Plattformen): Zeile wie „Ältere Nachrichten laden“, Symbol „Wolke mit Lupe“ (`CloudSearchSymbol`, Lupe ca. 62 % der Wolke, freigestellt), Zeile 2 „Treffer werden nur angezeigt, nicht gespeichert“ bzw. „Offline – nicht verfügbar“; während der Suche Kreisel und „Suche auf dem Server …“.

---

## 5. Sheets (v0.2.4C, C und D)

### 5.1 Kopfleiste (`SheetHeaderBar`, `macSheetHeader`)

Feste, nicht mitscrollende Leiste oben auf Nebelblau; keine Knopfleiste mehr am unteren Rand (Ausnahme: Formatierungsleiste im Verfassen-Fenster).

| Sheet / Ansicht | Links | Rechts |
|---|---|---|
| Postfächer | – | ✓ Fertig |
| Postfach hinzufügen | ✕ | ✓ Speichern (nur IMAP/SMTP) |
| Postfach bearbeiten | ✕ | ✓ Sichern |
| Signatur | ✕ | ✓ Sichern (ohne Return – Return gehört dem Editor) |
| Spamfilter | – | ✓ Fertig |
| Whitelist/Blacklist | < | Importieren, Exportieren |
| In Ordner verschieben | ✕ | – |
| Originalquelle | ✕ | Kopieren, Teilen |
| Verfassen, Entwurf, Teilen-Erweiterung | ✕ | Senden (Papierflieger) |

Tastatur: ✕ und < = Esc, ✓ = Return (wo sinnvoll), Senden = ⌘Return.

### 5.2 Inhalte

- Alle Formulare auf dem Mac im gruppierten Stil (`macGroupedForm()`), Abschnitte als Karten, Beschriftungen vollständig.
- **Postfächer:** Postfächer in einer Karte (Zeilenhöhe 45 pt, Farbpunkt 14 pt, „>“ als Hinweis auf Bearbeiten, Entfernen per Kontextmenü); eigene Karte „Postfach hinzufügen“; Karte „Standard-Postfach“ mit Erklärung unter der Beschriftung in derselben Zeile.
- **Spamfilter:** Sheet 520 × 600 pt (Inhalt ohne Scrollen); Whitelist/Blacklist als Zeilen mit „>“.
- **Whitelist/Blacklist:** „Exportieren“ ist wie auf iOS ein Knopf – ein Menü mit „Als Datei sichern …“ (Sichern-Dialog, `fileExporter`) und „Teilen“; das Teilen-Menü des Mac bietet kein Sichern als Datei.
- **Signatur:** Logo auch auf dem Mac „Aus Fotos“ (Fotomediathek, `PhotosPicker`).

---

## 6. Weitere Änderungen

- **Kennzeichen der Postfächer:** gleiche Texte auf allen Plattformen; auf dem Mac Sprechblase beim Darüberfahren (0,25 s) bzw. Klick (`AccountStatusBadges`).
- **Anhänge herausziehen:** Der Anhang wird beim Start des Ziehens als Datei ins Temp-Verzeichnis geschrieben und als Datei-URL übergeben (`AttachmentTransferable.itemProvider`) – der Finder übernimmt Namen und Endung.
- **Leerer Betreff:** `ComposeView.requestSend()` fragt nach („Senden“ / „Zurück“); alle Senden-Wege (Knopf, ⌘Return) laufen darüber.

---

## 7. Dateien

**Neu (`Mailwerk/Views/`):**

| Datei | Inhalt |
|---|---|
| `MacColumnLayout.swift` | Breitenstufen und Spaltenaufteilung (rein, getestet) |
| `MacListHeaderBar.swift` | Kopfleiste der Liste |
| `MacSearchField.swift` | Suchfeld mit Marke und Vorschlägen |
| `MacDetailHeaderBar.swift` | Kopfleiste der Mailansicht |
| `SheetHeaderBar.swift` | Kreisknöpfe, Kopfleiste der Sheets, `HeaderBottomLine` |
| `CloudSearchSymbol.swift` | Symbol „Wolke mit Lupe“ |
| `MacMenuCommands.swift` | zusätzliche Menübefehle des Mac |

Neu außerdem `Services/AttachmentTransferable.swift` (Anhang als ziehbare Datei).

**Geändert:** `MailwerkApp`, `ContentView`, `InboxView`, `MessageDetailView`, `ServerMessageLoader`, `HTMLMailView`, `InboxCommands`, `PlatformSheetSize`, `AppTheme`, `AttachmentRow`, `AccountListView`, `AddAccountView`, `EditAccountView`, `SignatureEditorView`, `SpamSettingsView`, `FilterListView`, `RawSourceView`, `ComposeView`, `DraftComposeLoader`, `AccountStatusBadges`, `FetchPausedBadge`, `FetchFailedBadge`, `SignInRequiredBadge`, `Folders/FolderMoveSheet`, `Folders/SideDrawer`. Projekt: `MARKETING_VERSION` 0.2.4 (alle Ziele).

**Tests (neu):** `MacColumnLayoutTests` (7).

---

## 8. Tests

| Punkt | Ergebnis |
|---|---|
| Fenster: oberste Zeile nur Fensterknöpfe und „Mailwerk“, Nebelblau | erfolgreich |
| Kopfleisten Liste/Mailansicht, kein Flackern, kein „»“ | erfolgreich |
| Breitenstufen 3 → 2 → 1 Spalte, Zurück-Knopf, Mindestbreite 380 pt | erfolgreich |
| Suche (Lupe, ⌘F, Marken, Vorschläge, Esc), Serversuche | erfolgreich |
| HTML-Mails scrollen, Zoom, Links, Textauswahl | erfolgreich |
| Sheets: Kopfleisten, Tastatur, Inhalte, Größen | erfolgreich |
| Kontextmenü, Kürzel, Hover, Drag & Drop (Mails, Anhänge, Dateien), Menüleiste | erfolgreich |
| Export der Filterlisten als Datei, Logo aus Fotos | erfolgreich |
| Rückfrage bei leerem Betreff | erfolgreich |

---

## 9. Beobachtungen und Erkenntnisse

- **`Divider` in `.overlay` einer `HStack`** übernimmt deren Richtung und wird senkrecht. Trennlinien an Kopfleisten deshalb als `Rectangle` mit fester Höhe (`HeaderBottomLine`).
- **Fenster ohne Titelleiste:** `safeAreaInsets.top` meldet in einer Überlagerung 0; der Titel steht deshalb in einer festen Zeile von 28 pt (Höhe der System-Titelleiste).
- **Ziehen von Dateien:** `FileRepresentation(exportedContentType: .data)` liefert keinen Dateinamen je Element – der Finder legte „Daten“ ohne Endung ab. Eine Datei-URL über `NSItemProvider(contentsOf:)` behält Namen und Endung.
- **Teilen auf dem Mac:** `ShareLink` bietet kein „Als Datei sichern“ wie iOS; dafür `fileExporter`.
- **Trennlinien im gruppierten Formular** des Mac lassen sich mit `.listRowSeparator(.hidden)` nicht ausblenden; was zusammengehört, steht in einer Zeile.
- **Tooltips (`help`)** erscheinen auf dem Mac verzögert und unzuverlässig; für Erklärungen eignet sich eine Sprechblase per `onHover` und `popover`.
- **`WKWebView` auf dem Mac** fängt Scroll-Ereignisse auch bei voller Inhaltshöhe ab; Weiterreichen in `scrollWheel(with:)` an den nächsten Responder.
- **Tastenkürzel:** Return als Bestätigung nur, wo kein Texteditor betroffen ist; Senden mit ⌘Return.

---

## Gesamtstand des Projekts (Stand 27.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS, macOS und watchOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`.
- Version **0.2.4**, **856 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkWatch Watch App, MailwerkWatchWidgetExtension, MailwerkTests, MailwerkUITests.
- **Verteilung:** TestFlight (zwei Testpersonen); 0.2.2–0.2.4 noch hochzuladen. „Mailwerk Dev“ per Xcode auf iPhone, iPad-Simulator und Mac.

### Funktionsumfang
Wie v0.2.3 (Unified Inbox, Sammelansichten, Erreichbarkeit je Postfach, Ordnerleiste, Offline-Cache mit FTS5, iPad-Spaltenlayout, sichere HTML-Ansicht, Übersetzung, Verfassen, clientseitiger Spamfilter, Suche, Teilen, OAuth 2, Apple Watch, paralleler Abruf), dazu die eigenständige Mac-Fassung dieser Version.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus; iOS/macOS/watchOS 26.5. Xcode 27.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage).
- Datenbank: SQLite (WAL, getrennte Lese-/Schreibverbindung, Savepoint-Pakete), Schema **9**, FTS5-Suchindex.
- Abruf: eine IMAP-Verbindung je Postfach und Runde, höchstens 3 Postfächer gleichzeitig (2 je Server).
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Tokens: iCloud-Schlüsselbund; Filterlisten und Signaturen: SwiftData/CloudKit; Abruf-Schalter: UserDefaults (je Gerät).
- Mac: Fenster `hiddenTitleBar`, eigenes Spaltengerüst (`MacColumnLayout`), eigene Kopfleisten statt System-Symbolleiste.
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
- **Mac:** größere HTML-Mails öffnen sich teils nicht (nach v0.2.4 erneut prüfen).
- **Performance:** Watch-Stand messen (P-19); Scroll-Messung nach frischer Installation → Entscheidung Logo-Vorladen; kürzere Frist bei hängender Anmeldung; P-15a/P-15b und P-16 nur bei Bedarf; `MailActionService` in den Hintergrund nur bei messbarem Gewinn.
- **Übersetzung:** zweiter Dienst für Sprachen ohne Apple-Unterstützung; erste Übersetzung ohne Netz ungeprüft.
- **iPad/Watch:** Abnahme über TestFlight (v0.2.1, v0.2.2); Server-Treffer der Suche im Spaltenlayout des iPad.
- **H6 (Rest):** Ordnerliste über eigene Verbindung kann bei Gmail noch in die Zeitüberschreitung laufen; ggf. mit Push/IDLE.
- **Default Mail App:** Antrag abgelehnt; neu beantragen mit TestFlight-Link.
- **MailwerkUITests:** Ordner fehlt auf der Platte – aufräumen oder neu anlegen.
- **Azure-Probephase:** nach Ablauf Outlook neu anmelden; vor App Store Herausgeber-Verifizierung.
- Weitere: `mailto:`-Randfall, Whitelist mit `X-Spam-Flag: YES`, Gmail per OAuth, Kopfdaten außerhalb des Zeitfensters, N14 Offline-Warteschlange, Ordner abonnieren, DKIM/Authentication-Results, Suchfeld unten, Teilen (große Videos, HEIC).

### Fahrplan
- **Jetzt:** v0.2.4 committen, TestFlight-Builds 0.2.2–0.2.4 hochladen, Abnahme iPad und Watch; dabei Watch-Stand und Scrollen messen.
- **Danach:** offene Mac-Punkte (größere HTML-Mails), zweiter Übersetzungsdienst.
- **Später:** H6, Push/IDLE, P-15/P-16, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung.
