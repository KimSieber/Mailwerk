# Mailwerk – Entwicklungsdokumentation v0.1.17

2026-10-17 · Optimierungen: Farbgestaltung, Sammelansichten „Ungelesen“ und „Spam“, Mailkopf, eigene untere Leiste, Rückgängig-Balken, Filterlisten bearbeiten

---

## Zusammenfassung

v0.1.17 ist eine Optimierungsversion. Jedes Thema wurde einzeln beschrieben. Claude hat es auf Verständnis und offene Punkte geprüft und erst nach Freigabe umgesetzt.

**Themen und Ergebnis:**

| Thema | Inhalt | Ergebnis |
|---|---|---|
| A | Schriftfarbe Schwarz/Weiß als Auswahl | **Entfallen** – Schwarz bzw. Weiß ist ohnehin „Standard“ in Hell/Dunkel. |
| B | Hintergrundfarbe der App | Umgesetzt (`3baffd5`) |
| C+D | Sammelansichten „Ungelesen“ (mit Zähler) und „Spam“ (ohne Zähler) | Umgesetzt (`9f1de56`, enthält C1 und C2) |
| E | Betreff markierbar, Adressen im Mailkopf mit Menü wie Apple Mail | Umgesetzt (`dc1104e`) |
| – | Mails als Markdown exportieren | **Verworfen** |
| F | Untere Leiste größer, Liquid Glass, großer blauer Suchkreis in der Mitte | Umgesetzt (`0e07ca8`) |
| G | Rückgängig-Balken mit 5 Sekunden ablaufender Füllung | Umgesetzt (`0e07ca8`) |
| H | White-/Blacklist-Einträge bearbeiten | Umgesetzt (`ff345f0`) |

**Grundsatzentscheidung:** Für F und G weicht Mailwerk bewusst vom Apple-Standard ab. Die eigene untere Leiste ist als **USP** gewollt. Gebaut wird weiter mit Systembausteinen (Liquid Glass, `glassEffect`, `glassProminent`), aber in eigener Anordnung. Die Regel „keine Eigenbauten“ gilt damit für die Gestaltung nicht mehr absolut.

Tests: 584 → **606** (22 neue), alle grün. `MARKETING_VERSION` 0.1.17 in allen drei Zielen.

Zwischenfund: Auf dem Mac ließen sich Mails nicht mehr öffnen. Die Ursache war die **Umgebung** (macOS 26.4 und das veraltete Xcode), nicht der Code. Siehe „Mac-Fund“.

---

## B – Hintergrundfarbe (Nebelblau / Nachtblau)

**Wunsch:** Ein dezentes, edles Blau als Hintergrund wie bei Scanner Pro statt des grauen Systemhintergrunds.

**Entscheidungen:**

| Frage | Entscheidung |
|---|---|
| Hellmodus | **#DFE5F5** (Nebelblau) – das kräftigere von zwei Mustern |
| Dunkelmodus | **#121827** (Nachtblau) |
| Karten (Zeilen, Mailtext) | Hell **Weiß**; dunkel **#1C2438**. Hellblau getönte Listen wirkten unnatürlich, deshalb verworfen. |
| Umfang | ganze App: Liste, Mail, Verfassen, Seitenleiste, Einstellungen, Blätter |

**Umsetzung – `AppTheme.swift` (neu):**
- `AppThemePalette`: Farbpaare hell/dunkel als Hexwert, prüfbar ohne Oberfläche.
- `AppTheme.background` und `AppTheme.card`: dynamische Farben (UIColor bzw. NSColor), die dem Erscheinungsbild folgen.
- `View.appBackground()`: blendet den Systemhintergrund der Liste aus (`scrollContentBackground(.hidden)`) und legt den App-Hintergrund bis in die Ränder.
- `View.cardRowBackground(isSelected:)`: Kartenfarbe je Zeile (`listRowBackground`), bei Auswahl mit der Systemfüllung überlagert.
- Mailansicht: Kopf und Anhänge auf dem Hintergrund, der Text auf einer Karte über die volle Breite.
- Verfassen und Signatur-Editor: Eingabeflächen auf der Kartenfarbe.

---

## C+D – Sammelansichten „Ungelesen“ und „Spam“

**Wunsch:** Wie „Alle Eingänge“ und „Mit Kennzeichnung“ zwei weitere Sammelansichten. „Ungelesen“ mit Zähler, „Spam“ ohne.

**Entscheidungen:**

| Frage | Entscheidung |
|---|---|
| Datenquelle | **Nur der Cache**, wie bei den anderen Sammelansichten; Nachladen vom Server über die bestehenden Wege. |
| Ungelesen – Umfang | Ungelesene Mails aller **Posteingänge** mit eingeschaltetem Abruf |
| Ältere Ungelesene | Werden **beim Abruf nachgeholt** (C1), damit die Ansicht vollständig ist, auch außerhalb des 30-Tage-Fensters. Performance geprüft: einmalig, danach nur Neues. |
| Gelesen markieren in „Ungelesen“ | Die Mail **bleibt** sichtbar, bis die Ansicht verlassen oder die Liste neu gezogen wird. Sonst wäre sie nach dem Öffnen nicht wiederzufinden. Gilt **für alle Ordner** einheitlich. |
| Spam – Umfang | Die Spam-Ordner aller abgerufenen Postfächer |
| Reihenfolge | Alle Eingänge, Ungelesen (Zähler), Mit Kennzeichnung (Zähler), Spam |
| Ende der Liste | **Hinweis statt Knopf**: „Alle ungelesenen/gekennzeichneten Nachrichten – unabhängig vom Alter“ |

### C1 – Ältere ungelesene Mails abrufen

- `SyncStatePlanner.unreadBackfill(unseen:known:limit:)`: Aus den ungelesenen UIDs des Servers die noch nicht gecachten, **die höchsten zuerst**, höchstens `unreadBackfillLimit` = 200 je Abruf.
- `MailFetchService.refreshAndCache`, neuer Schritt 6 (nur INBOX): Diese Mails werden über `cacheMessages` **vollständig** geladen – Text/HTML und Anhänge bis 5 MB, wie jede andere Mail. Protokoll „✉️ … Ältere ungelesene“.
- Die Folgeschritte rücken eine Nummer weiter.

### C2 – Ansichten

- `MailboxSelection`: neue Fälle `.unread` („Ungelesen“, Symbol `envelope.badge`) und `.spam` („Spam“, `xmark.bin`).
- `MessageStore`:
  - Abfragen über **Ordnerpaare** (`FolderKey(accountID, folder)`): `messages(in folders:)`, Hilfen `folderCondition` und `bind(_:folders:from:)`.
  - `unreadInboxMessages(accountIDs:keeping:)`: ungelesene Posteingangsmails plus die festgehaltenen IDs.
  - `unreadInboxCount(accountIDs:)` für den Zähler.
  - Suche und Adressvorschläge arbeiten ebenfalls mit Ordnerpaaren.
- `SearchScope` neu gefasst (`folders`, `flaggedOnly`, `serverSearchable`; `make(for:fetchingAccountIDs:spamFolders:)`). „Ungelesen“ hat keine Serversuche.
- `InboxViewModel`:
  - `keptUnreadIDs` hält gelesen markierte Mails, bis die Ansicht verlassen oder neu gezogen wird (`releaseKeptUnread()`).
  - `spamFolders`, `unreadCount`; Sync-Zustand und „Ältere laden“ auch für Spam.
- `FolderSidebarView.collectionRow`: die vier Sammelansichten in der festgelegten Reihenfolge.
- `InboxView`: Hinweis am Listenende (`completeListNote`), eigene Texte für leere Ansichten.

---

## E – Mailkopf: Betreff und Adressen

**Wunsch:** Betreff und Mailadressen im Kopf markieren und kopieren können.

**Entscheidungen:**

| Frage | Entscheidung |
|---|---|
| Betreff | **Markierbar** (Text auswählen, kopieren) |
| Adressen | Antippen öffnet ein **Menü wie Apple Mail** |
| Menüeinträge | Kopfzeile = Adresse; „Adresse kopieren“, „Suchen nach „…““, „Kontaktkarte anzeigen“, „Neue E-Mail an „…““ |
| Anzeige | **Nur der Name** (wie Apple Mail), Adresse nur ohne Namen |
| „Antwort an“ | Zeile nur, wenn sie vom Absender abweicht |

**Umsetzung:**
- `HeaderPerson` (neu, Modell): Name, Adresse, Anzeigetitel, `searchPerson` (für die Suche). `list(_:)` ohne Doppelte, `replyTo(_:sender:)`.
- `MessageDetailHeader` neu aufgebaut:
  - Betreff mit `.textSelection(.enabled)`.
  - Zeilen Von/An/Kopie/Antwort an mit `FlowLayout`; jede Person ist ein `HeaderPersonMenu` (`Menu`, `.menuStyle(.button)`, ohne Pfeil).
- „Suchen nach“: schließt die Mail, öffnet die Suche der Liste und setzt die Person als Marke (`InboxView.startPersonSearch`, 400 ms Verzögerung bis die Liste steht; `SearchViewModel.startSearch(for:)`). Nur angeboten, wo eine Liste dahintersteht (`onSearchPerson`).
- `ContactCardView` (neu): Apple-Kontaktkarte.
  - Steht die Adresse im Adressbuch, erscheint dieser Kontakt.
  - Sonst eine Karte mit Name und Adresse; auf iPhone/iPad mit „Neuen Kontakt erstellen“ / „Zu bestehendem Kontakt hinzufügen“ (`forUnknownContact` in einer Navigation).
  - Mac: Anzeige nur; Anlegen über die App Kontakte.
- „Neue E-Mail an“: über einen `mailto:`-Link, also den bestehenden Verfassen-Weg.

---

## Mac-Fund: Mails ließen sich nicht öffnen

**Fund (erster Mac-Test der Version):** Ein Klick auf eine Mail baute die Ansicht auf und schloss sie sofort wieder. Das Protokoll zeigte „⏱ Mail geöffnet“, auf dem Bildschirm erschien nichts. Simulator unauffällig.

**Analyse:**
- Vermutung „Kartenhintergrund (`listRowBackground`) stört die Auswahl auf dem Mac“: mit Mac-Variante ohne diesen Hintergrund geprüft – **widerlegt**, zurückgenommen.
- Ältere Stände ausgecheckt (Stash, „Check out …“): Der Fehler trat auch bei `e23c4c2` (v0.1.16 Doku) und `3e7faf3` auf, also **vor** v0.1.17.
- Vermutung „das Gelesen-Markieren lädt die Liste neu“: ungelesene und gelesene Mail verhielten sich gleich – **widerlegt**.
- Konsole: `XPCConnectionTerminationWatchdog` – der Web-Prozess der Mailansicht wurde vom System beendet.

**Ursache und Lösung:** Nach Aktualisierung von macOS 26.4 → **27.0.1** und Xcode → **27.1** öffneten sich die Mails wieder. Ursache war die Umgebung (veraltetes Xcode zum System bzw. WebKit), kein Code. Nichts zurückgebaut.

**Lehren:**
- Ein ausgecheckter Stand **vor Schema-Stufe 7** (z. B. v0.1.15) liest den Cache nicht mehr – keine Mails. Für Rückblicke nur Stände ab v0.1.16 nehmen.
- Noch nicht eingecheckte neue Dateien brechen den Build alter Stände („Cannot find type …“). Sie müssen dafür vorübergehend aus dem Projektordner genommen werden.
- In Xcode heißt es **Source Control Navigator → Rechtsklick auf Commit → „Check out "<hash>"…“** und zurück **„Switch to "main"…“** (kein „Branch from…“).

---

## F – Eigene untere Leiste

**Wunsch:** Größere Knöpfe im Liquid-Glass-Stil, in der Mitte ein großer blauer Suchknopf (Vorbild Scanner Pro). Harmonische Farbgestaltung.

**Entscheidungen:**

| Frage | Entscheidung |
|---|---|
| Farbe | **Akzentfarbe Mailwerk-Blau** für die ganze App (Empfehlung B): hell **#3A6FE8**, dunkel **#5B8AF0** – passend zu Nebelblau/Nachtblau |
| Glanz | Suchkreis mit Glanzeffekt in **Hell und Dunkel** |
| Suchfeld | **Oben** unter dem Titel; der Suchkreis unten öffnet es, die Tastatur steht unten → weiter einhändig |
| Suchfeld immer sichtbar? | Nein: Es erscheint beim Herunterziehen der Liste bzw. über den Suchkreis (iOS-Verhalten von `.automatic`). |

**Umsetzung:**
- Asset **`AccentColor`** (hell/dunkel). Die Erweiterungen bekommen sie über `NSAccentColorName = AccentColor` in `MailwerkShare/Info.plist` und `MailwerkShareMac/Info.plist` (die Build-Einstellung „Global Accent Color Name“ fand sich dort nicht).
- `ListBottomBar` (neu):
  - Glas-Kapsel 224 × 58 pt mit Sortieren (links) und Neue Mail (rechts), `glassEffect(.regular.interactive())`.
  - Darüber der Suchkreis: `buttonStyle(.glassProminent)`, `.buttonBorderShape(.circle)`, `.controlSize(.extraLarge)`, Akzentfarbe.
  - Kapsel und Kreis sind **getrennte** Glasflächen. In einem gemeinsamen `GlassEffectContainer` verschmolzen sie, und der Kreis wurde auf die Kapselhöhe beschnitten und unscharf.
  - `SortBarLabel`: abweichende Sortierung = weißes Symbol auf einem Kreis in der Akzentfarbe (löst den offenen Punkt „Glaseffekt des blauen Sortierknopfs“).
- `InboxView`:
  - iPhone/iPad ohne Einträge in `.bottomBar`. Die Leiste sitzt in `safeAreaInset(edge: .bottom)` (`bottomInset`): im Auswahlmodus die Befehlsleiste, sonst `ListBottomBar`, während der Suche nichts.
  - Suchfeld `searchable(placement: .navigationBarDrawer(displayMode: .automatic))` (`searchPlacement`), Mac `.automatic`. `searchToolbarBehavior(.minimize)` und die `DefaultToolbarItem(kind: .search)` entfallen. Mit Platz in der Symbolleiste setzte iOS 26 einen **zweiten Suchknopf** unten ein.
  - Sortiermenü-Inhalt gemeinsam (`sortMenuContent`); Mac-Symbolleiste in der Akzentfarbe.

---

## G – Rückgängig-Balken

**Wunsch:** Der Hinweis „Rückgängig“ zeigt die 5 Sekunden als ablaufende Füllung. Ein ✕ braucht es nicht, wenn sich der Balken nach unten wegwischen lässt.

**Umsetzung (`UndoBar` in `InboxView`, `UndoOffer`):**
- Kapsel in Liquid Glass, getönt in der Akzentfarbe (`glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())`), Symbol je Aktion (`UndoOffer.systemImage(for:)`).
- **Antippen** = rückgängig; **nach unten wischen** (> 30 pt) blendet aus; kein ✕.
- Füllung: weiß 22 % über dem Blau, schrumpft von rechts nach links. Berechnet in `TimelineView(.animation)` aus der verstrichenen Zeit (`remaining(at:)`). Ein `withAnimation` beim Erscheinen wurde von der Einblende-Animation verschluckt – der Balken lief nicht.
- `UndoOffer.duration` = 5 s an einer Stelle; das ViewModel nutzt denselben Wert. Jedes neue Angebot baut den Balken neu (`.id(offer.id)`).

---

## H – White-/Blacklist-Einträge bearbeiten

**Wunsch:** Einträge der Filterlisten korrigieren können statt löschen und neu anlegen.

**Entscheidungen:**

| Frage | Entscheidung |
|---|---|
| Auslöser | **Langes Drücken** → Kontextmenü „Bearbeiten“ / „Löschen“. **Kurzes Antippen bearbeitet nicht** (zu leicht versehentlich). |
| Bearbeiten | Rückfrage mit Eingabefeld, vorbelegt; Prüfung wie beim Anlegen, auch gegen die **andere** Liste |
| Neuer Eintrag | Knopf **„Neuer Eintrag …“** als erste Zeile mit derselben Rückfrage; das feste Eingabefeld entfällt |
| Löschen | Wischen bleibt, jetzt **mit Bestätigung**; ebenso über das Kontextmenü |

**Umsetzung:**
- `FilterListEditing` (neu, `nonisolated enum`, reine Logik):
  - `editText(for:)` – Vorbelegung;
  - `plan(editing:input:)` → `unchanged`, `invalid`, `multiple` (nur ein Eintrag erlaubt) oder `replace(FilterListInputEntry)`;
  - `save(_:replacing:in:)` – erst den neuen Eintrag anlegen, dann den alten entfernen. Scheitert das Anlegen (Konflikt), bleibt der alte Eintrag erhalten.
- `FilterListView` neu aufgebaut: `EditorRequest` (`.new`, `.edit(item)`), Rückfrage-Feld mit `.emailInput()`, Kontextmenü, Wischen ohne „ganz durchwischen“ (rot, nicht-destruktive Rolle, damit die Zeile bis zur Bestätigung bleibt), Ergebnisse als `AlertItem`.

---

## Geänderte Dateien (gesamte Version)

```
Mailwerk.xcodeproj/project.pbxproj          # Version 0.1.17 (drei Ziele)
MailwerkShare/Info.plist                    # NSAccentColorName
MailwerkShareMac/Info.plist                 # NSAccentColorName
Mailwerk/
├── Assets.xcassets/AccentColor.colorset/   # neu: Mailwerk-Blau hell/dunkel
├── Models/
│   ├── HeaderPerson.swift                  # neu: Person im Mailkopf
│   ├── MailboxSelection.swift              # .unread, .spam
│   └── SearchScope.swift                   # Ordnerpaare, Spam, Ungelesen
├── Services/
│   ├── MailFetchService.swift              # Schritt 6: ältere Ungelesene
│   ├── MessageStore.swift                  # Ordnerpaare, Ungelesen-Abfragen, Zähler
│   ├── Spam/FilterListEditing.swift        # neu: Bearbeiten-Logik
│   └── Sync/SyncStatePlanner.swift         # unreadBackfill
├── ViewModels/
│   ├── InboxViewModel.swift                # keptUnreadIDs, spamFolders, unreadCount
│   ├── SearchViewModel.swift               # Ordnerpaare, startSearch(for:)
│   └── UndoOffer.swift                     # duration, systemImage(for:)
└── Views/
    ├── AppTheme.swift                      # neu: Farben, appBackground, cardRowBackground
    ├── ListBottomBar.swift                 # neu: eigene untere Leiste
    ├── ContactCardView.swift               # neu: Kontaktkarte
    ├── InboxView.swift                     # Leiste, Suchfeld oben, UndoBar, Hinweis am Ende
    ├── MessageDetailHeader.swift           # Betreff markierbar, Personen-Menü
    ├── MessageDetailView.swift             # Karte, Kontaktkarte, Personensuche
    ├── FilterListView.swift                # Kontextmenü, „Neuer Eintrag …“
    ├── Folders/FolderSidebarView.swift     # vier Sammelansichten
    ├── Folders/SideDrawer.swift            # Hintergrund
    ├── Folders/FolderMoveSheet.swift       # Hintergrund
    ├── ServerMessageLoader.swift           # Personensuche
    ├── ComposeView.swift                   # Kartenfarbe
    ├── SignatureEditorView.swift           # Kartenfarbe
    ├── AccountListView.swift               # Hintergrund
    ├── AddAccountView.swift                # Hintergrund
    ├── EditAccountView.swift               # Hintergrund
    └── SpamSettingsView.swift              # Hintergrund
MailwerkTests/
├── AppThemeTests.swift                     # neu, 2 Tests
├── HeaderPersonTests.swift                 # neu, 4 Tests
├── FilterListEditingTests.swift            # neu, 6 Tests
├── SyncStatePlannerTests.swift             # +3 Tests (unreadBackfill)
├── MessageStoreListTests.swift             # +Tests Ungelesen/Ordnerpaare
├── MessageStoreSearchTests.swift           # Ordnerpaare
├── SearchPersonTests.swift                 # Ordnerpaare
└── MessageMenuTests.swift                  # +2 Tests (Rückgängig)
```

---

## Testverfahren

**Automatisch:** **606 Tests** (Simulator), alle grün. Vorab unter Linux (Swift 6.2, SwiftMail 1.15.0 im SwiftPM-Paket) übersetzt und getestet: `AppThemePalette`, `SyncStatePlanner`, `MessageStore` (Ordnerpaare, Ungelesen), `SearchScope`, `HeaderPerson`, `UndoOffer`, `FilterListEditing`. Platzhalter für `os.Logger`, SQLite-Modul, SwiftMail-`EmailAddress`, `MailAddress`, `AccountColor` und `FilterEntry`.

**Manuell:**

| Nr. | Test | Ergebnis |
|---|---|---|
| 1 | Hintergrund Nebelblau/Nachtblau in Liste, Mail, Verfassen, Einstellungen (iPhone, Mac) | ✔ |
| 2 | „Ungelesen“: Zähler, ältere Ungelesene nach Abruf vorhanden, gelesene Mail bleibt bis Verlassen/Ziehen | ✔ |
| 3 | „Spam“: alle Spam-Ordner, kein Zähler, Hinweis am Listenende | ✔ |
| 4 | Betreff markieren; Adressmenü: kopieren, suchen, Kontaktkarte, neue Mail | ✔ |
| 5 | Mac: Mails öffnen (nach Update macOS 27.0.1 / Xcode 27.1) | ✔ |
| 6 | Untere Leiste: Größe, Glanz hell/dunkel, ein einziger Suchknopf, Sortierung hervorgehoben | ✔ (nach Korrekturen) |
| 7 | Rückgängig-Balken: Füllung läuft 5 s, Antippen, Wegwischen | ✔ (nach Korrektur) |
| 8 | Filterlisten: Kontextmenü Bearbeiten/Löschen, Konflikt mit anderer Liste, „Neuer Eintrag …“, Wischen mit Bestätigung | ✔ |

---

## Beobachtungen

- **Suchfeld oben:** Gewünscht wäre es unten. Unten setzt iOS 26 neben der eigenen Leiste einen zweiten Suchknopf ein. Die Bedienung bleibt einhändig (Suchkreis und Tastatur unten). Vorerst so belassen.
- **Ältere Ungelesene werden vollständig geladen** (nicht nur Kopfdaten), höchstens 200 je Abruf. Ein Postfach mit sehr vielen alten Ungelesenen füllt sich über mehrere Abrufe.
- **Xcode schreibt Info.plist neu** (Anführungszeichen als `&quot;`) – unbedenklich.
- **Warnungen** zur isolierten `Hashable`-Konformität von `FilterListInputEntry` (unter Linux gesehen) bestanden schon vorher.

## Offene Punkte (neu/geändert)

- **Erledigt:** Liquid-Glass-Effekt des blauen Sortierknopfs (durch die eigene Leiste).
- **Suchfeld unten** statt oben, falls iOS es künftig ohne zweiten Suchknopf erlaubt.

## Nächste Schritte

- **v0.1.18: Anmeldung (OAuth 2) für Outlook** – siehe Übergabe v0.1.18.
