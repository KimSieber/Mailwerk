# Mailwerk – Entwicklungsdokumentation v0.2.0

2026-10-20 · „Apple Watch“: Mailwerk als Watch-App – neueste Mails lesen, gelesen/ungelesen, Kennzeichen, Spam/Vertrauen, Zähler als Komplikation

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen.

---

## Zusammenfassung

v0.2.0 bringt Mailwerk auf die Apple Watch. Die Watch speichert ihre Mails selbst und bleibt ohne iPhone bedienbar; abgerufen wird über das iPhone, auch wenn die App dort geschlossen ist. Umgesetzt in einer Cloud-Sitzung (Code auf eigenem Branch); die beiden neuen Ziele wurden lokal in Xcode angelegt (Abschnitt 6).

| Bereich | Ergebnis |
|---|---|
| Grundsatz | Watch spricht nicht selbst mit den Mailservern (watchOS lässt es nicht zu) – Abruf über das iPhone, Watch mit eigenem Speicher |
| Ansichten | Alle Eingänge, Ungelesen (Zähler), Mit Kennzeichnung (Zähler), Spam |
| Aktionen | gelesen/ungelesen, Kennzeichen, Spam/Vertrauen (alle Einträge wie in der App) – sofort auf der Watch, auf dem Server sofort bzw. sobald das iPhone erreichbar ist |
| Abgleich | beim Öffnen der Watch-App; bei offener Watch-App sofort in beide Richtungen; nach Abrufen der iPhone-App im Hintergrund |
| Speicher | 50 neueste + ungelesene + gekennzeichnete, höchstens 100; dazu 20 neueste Spam; HTML gespeichert, Anhänge nur als Name |
| Komplikation | Zahl der ungelesenen Mails (Zifferblatt und Smart Stack) |
| Handoff | „Auf iPhone fortfahren“ öffnet die Mail in der App |

Tests: 705 → **743** Testfunktionen (`@Test`, 38 neu), alle grün. Version **0.2.0 (Build 1)** in allen fünf App-Zielen (Mailwerk, MailwerkShare, MailwerkShareMac, MailwerkWatch Watch App, MailwerkWatchWidgetExtension). Gebaut für iPhone, Mac und Watch; Funktionstest mit gekoppelten Simulatoren erfolgreich; **TestFlight-Build 0.2.0 (1) hochgeladen**. Offen ist der Test auf einer echten Watch (Abschnitt 8).

| Commit | Inhalt |
|---|---|
| `c231c13` | Watch-App, Komplikation, Anbindung auf dem iPhone, Tests, Doku |
| `84d482f` | Warnungen in `WatchSnapshotBuilder`, Einrichtung nach erster Durchführung |
| `31674fc` | Mailkopf auf der Watch (Datum/Spam je eine Zeile), Abgleich sofort bei offener Watch-App |
| `70c753b` | Ziele in Xcode angelegt (Projektdatei, Schemata) |
| (dieser) | Aufräumen: Ordner der Komplikation zusammengeführt, Doku |

---

## 1. Grundsatzentscheidung: keine eigene Mailverbindung auf der Watch

**Ausgangswunsch:** Die Watch arbeitet unabhängig vom iPhone und spricht selbst mit den Mailservern.

**Hindernis (belegt):** watchOS erlaubt Apps nur `URLSession` (HTTPS, WebSockets). Eigene TCP-Verbindungen (`NWConnection`, Sockets) sind laut Apple TN3135 „Low-level networking on watchOS“ nur in Sonderfällen erlaubt, vor allem während einer aktiven Audio-Sitzung. IMAP (Port 993) und SMTP fallen nicht darunter. SwiftMail ließe sich zwar übersetzen, die Verbindung würde aber zur Laufzeit abgewiesen. Ein Umweg über eine Audio-Sitzung würde die App-Prüfung nicht bestehen und ist laut Entwicklerforum unter watchOS 26 auch technisch instabil.

**Geprüfte Wege:**

| Weg | Prinzip | Bewertung |
|---|---|---|
| **A (gewählt)** | Watch fragt das iPhone (WatchConnectivity); iPhone ruft per IMAP ab und liefert | kein Server, keine Sonderlösung; Watch speichert selbst und bleibt ohne iPhone bedienbar |
| B | eigener Vermittlungsserver (IMAP → HTTPS) | Betrieb, Kosten, Passwörter auf fremdem Server – verworfen |
| C | HTTP-Schnittstellen der Anbieter (Gmail-API, Microsoft Graph) | nicht für manitu, Posteo, GMX; widerspricht „keine Sonderlösungen“ – verworfen |
| D | Spiegel über CloudKit, befüllt von iPhone/Mac | Aktualität hängt an seltenen Hintergrundabrufen – verworfen |

**Entschieden:** Weg A. Die Watch-App soll so weit wie möglich unabhängig sein und speichert ihre Mails deshalb selbst.

---

## 2. Anforderungen (abgestimmt)

| Thema | Entscheidung |
|---|---|
| Zweck | Die Watch dient dem Lesen. Kein Verfassen, weder Antwort noch neue Mail. |
| Liste | wie in der App: Absender, Betreff, Datum, ungelesen, Kennzeichen, `[SPAM]`, Absenderbild, Postfachfarbe; keine Vorschau des Inhalts |
| Wischgesten | wie in der App: nach rechts gelesen/ungelesen, nach links Kennzeichen; kein Löschen |
| Öffnen | markiert als gelesen (wie in der App) |
| Sortierung | fest nach Datum, neueste oben |
| Push | keiner (wie in der iPhone-App) |
| Zähler | Ungelesen als Komplikation und in der Startansicht; Kennzeichnung in der Startansicht |
| Begrenzung | über alle Postfächer gemeinsam: 50 neueste Eingangsmails + alle ungelesenen + alle gekennzeichneten, höchstens 100 (darüber gewinnen die neuesten); zusätzlich die 20 neuesten Spam-Mails |
| Inhalt | HTML wird gespeichert; Bilder werden beim Anzeigen nachgeladen; Anhänge nur als Name und Größe |
| Externe Bilder | dieselbe Regel wie auf dem iPhone: sofort bei vertrauenswürdigem Absender (`SpamClassifier.trustsSender`), sonst Knopf „Bilder laden“ |
| Abruf | beim Öffnen der Watch-App ruft das iPhone den aktuellen Serverstand ab – auch Mails, die das iPhone selbst noch nicht hatte; die Abruf-Schalter des iPhones gelten auch für die Watch |
| Spam / Vertrauen | dieselben Einträge wie auf dem iPhone (Adresse, Domain, Hauptdomain bei Subdomain – je Blockieren und Vertrauen), dieselbe Rückfrage |
| Konflikte | der Server ist das führende System; Aufträge zu nicht mehr vorhandenen Mails werden verworfen |
| Handoff | „Auf iPhone fortfahren“ aus der geöffneten Mail |
| Mindestversion | watchOS 26.5; die Watch-App wird zusammen mit der iPhone-App installiert |
| Testgerät | Watch ohne eSIM (WLAN und Bluetooth) |

**Abweichung vom Entwurf während der Abstimmung:** Vorgesehen war, dass die Watch Einträge in die Filterlisten selbst über iCloud schreibt. Umgesetzt ist: Die Watch übernimmt den Eintrag sofort in ihre eigene Kopie der Listen (Anzeige, `[SPAM]`, Bilder), das iPhone trägt ihn in die Filterlisten (iCloud) ein und verschiebt die Mail. Grund: kein CloudKit, SwiftData und iCloud-Abgleich auf der Watch nötig – weniger Fehlerquellen. Folge: Ohne iPhone kommt der Eintrag erst mit der nächsten Verbindung auf die anderen Geräte.

**Nachgeschärft beim Test:** Änderungen kommen bei offener Watch-App sofort in beide Richtungen an (Abschnitt 3, Ablauf 5) statt erst nach „Aktualisieren“.

---

## 3. Aufbau

```
Watch-App                      iPhone-App (auch im Hintergrund)           Mailserver
───────────                    ─────────────────────────────────          ──────────
WatchRootView ─ öffnen ─┐
                        ▼
WatchConnector ── sync(Aktionen, Abruf) ──► WatchBridge
      ▲    ◄── Stand aus dem Cache (sofort) ──┤
      │                                       ├─ Aktionen → MessageActions / SpamFilterService ──► IMAP
      │                                       ├─ InboxViewModel.refresh() (wie in der App) ─────► IMAP
      │    ◄── neuer Stand (Nachricht) ───────┘
      ├── content(IDs, Bilder) ──────────────► WatchSnapshotBuilder (Cache)
      │    ◄── Inhalte, Absenderbilder ───────┘
WatchStore (Dateien) ── badge.plist ──► Komplikation
```

### Ablauf

1. **Öffnen / Aktualisieren:** Die Watch schickt alle offenen Aktionen samt Abrufwunsch. Das iPhone antwortet sofort mit dem Stand aus seinem Cache, führt die Aktionen aus, ruft alle eingeschalteten Postfächer ab (über `InboxViewModel.refresh()`, damit sich Abrufe mit der App nicht doppeln) und schickt den neuen Stand als eigene Nachricht.
2. **Inhalte:** Fehlende Inhalte und Absenderbilder holt die Watch in Gruppen nach (6 Mails bzw. 20 Bilder je Anfrage), neueste zuerst. Eine geöffnete Mail ohne Inhalt wird sofort angefragt.
3. **Einzelne Aktion:** Nur die Aktion geht zum iPhone, ohne Abruf; die Liste auf dem iPhone lädt danach neu.
4. **Ohne iPhone:** Die Watch zeigt ihren gespeicherten Stand („iPhone nicht erreichbar“, „Stand: …“). Aktionen wirken sofort und kommen mit der nächsten Verbindung mit.
5. **Sofort bei offener Watch-App:** Ändert sich auf dem iPhone etwas (Aktion in der App, Abruf), schickt das iPhone den neuen Stand aus dem Cache nach etwa 1 Sekunde an die offene Watch-App; mehrere Änderungen werden zusammengefasst, unveränderte Stände gehen nicht hinaus. Ist die Watch-App geschlossen, kommt der Stand beim nächsten Öffnen.
6. **Hintergrund:** Ruft die iPhone-App selbst ab (Start, Herunterziehen), schickt sie den neuen Stand samt den Inhalten, die die Watch noch nicht hat, als Datei (`transferFile`). watchOS weckt die Watch-App kurz; beim nächsten Öffnen ist alles da.

### Übertragung

| Punkt | Umsetzung |
|---|---|
| Form | binäre Property-List, gepackt mit LZFSE |
| Größe | WatchConnectivity nimmt je Nachricht nur rund 64 KB; jede Lieferung wird in Stücke von 48 000 Byte geteilt, die übrigen Stücke holt die Watch einzeln ab (5 Minuten bereit) |
| Mailkopf | auf dem iPhone fertig aufbereitet (Name, Adresse, Initialen, Farbe, Absender für die Filterlisten) – die Watch hat keinen Adressparser (SwiftMail) |
| Inhalt | HTML bis 1 MB (darüber nur Text), Text bis 300 KB (darüber gekürzt), Kopie-Empfänger, Anhänge nur Name und Größe; eingebettete Bilder (`cid:`) nicht |
| Absenderbilder | Kontaktbild vor Logo wie in der Liste, verkleinert auf 96 px (PNG); ob gezeigt wird, entscheidet die Watch mit den Listen (Spam: leerer Kreis) |
| Doppeltes Ausführen | das iPhone merkt sich ausgeführte Aktionen; offene Aktionen derselben Art an derselben Mail ersetzt die Watch durch die neuere |
| Verbindungsfehler | Aktion bleibt offen und kommt wieder; andere Fehler meldet die Watch („Aktion nicht ausgeführt“) |
| Hintergrundzeit iPhone | `ProcessInfo.performExpiringActivity` hält die App für Aktionen und Abruf wach (soweit iOS es zulässt) |

### Zustand auf der Watch (`WatchMailbox`)

- Jede Lieferung ersetzt den Stand vollständig; ältere Lieferungen werden übergangen.
- Offene Aktionen werden auf jede Lieferung erneut angewandt, bis das iPhone ihr Ergebnis meldet – nichts springt zurück.
- Blockieren legt die Mail sofort nach „Spam“ und trägt den Wert in die Listen der Watch ein; Vertrauen holt sie zurück. Steht der Wert schon auf der anderen Liste, wird abgelehnt (wie auf dem iPhone).
- Ungelesen-Zähler: Gesamtzahl laut iPhone (auch außerhalb der 100) plus Änderungen auf der Watch.
- Sicht „Ungelesen“ behält beim Besuch gelesene Mails bis zum Verlassen (wie in der App).

### Darstellung auf der Watch

- **HTML:** watchOS hat keine Web-Ansicht. Das HTML wird mit dem vorhandenen `HTMLRichTextParser` in Absätze, Fett, Kursiv, Unterstrichen, Links, Listen und Bilder zerlegt und mit SwiftUI gesetzt. Tabellenlayouts (Newsletter) werden flach; Textfarben und Schriftgrößen der Mail entfallen (dunkler Grund der Watch), große Schrift wird fett. Bilder: `data:` immer, `http(s)` nur nach Freigabe, `cid:` nie.
- **Mailkopf:** Absenderbild, Name, Adresse; Datum und Spam-Einschätzung je in einer eigenen Zeile (nebeneinander wäre es zu eng); An, Kopie, Betreff.
- **Aktionen:** unten drei Knöpfe – gelesen/ungelesen, Kennzeichen, „Spam / Vertrauen“.

---

## 4. Dateien

**Neu – gemeinsam (iPhone-App und Watch-App):**

| Datei | Inhalt |
|---|---|
| `Mailwerk/Services/Watch/WatchTransfer.swift` | Übertragungstypen: `WatchMail`, `WatchSnapshot`, `WatchBody`, `WatchAction`, Anfragen und Lieferungen, `WatchHandoff` |
| `Mailwerk/Services/Watch/WatchWire.swift` | Kodieren, Packen, Stückeln, `WatchChunkAssembler` |
| `Mailwerk/Services/Watch/WatchMailbox.swift` | Zustand der Watch: Lieferung + offene Aktionen, Sichten, Zähler |
| `Mailwerk/Services/Watch/WatchAppGroup.swift` | App Group aus der Bundle-ID, `WatchBadge` für die Komplikation |
| `Mailwerk/Services/Spam/SpamMenuChoice.swift` | `SpamMenuRequest`, `SpamMenuSection` (aus `MessageMenu` herausgelöst), `SpamMenuTexts` (Rückfrage, Meldungen, Symbole) |

**Neu – nur iPhone:**

| Datei | Inhalt |
|---|---|
| `Mailwerk/Services/Watch/WatchMailSelection.swift` | Begrenzung 50/100/20 |
| `Mailwerk/Services/Watch/WatchSnapshotBuilder.swift` | Stand, Inhalte und Bilder aus dem Cache |
| `Mailwerk/Services/Watch/WatchBridge.swift` | WatchConnectivity auf dem iPhone (`#if os(iOS)`) |

**Neu – Watch-App (`MailwerkWatch/`, Ziel „MailwerkWatch Watch App“):** `MailwerkWatchApp`, `WatchStore`, `WatchConnector`, `WatchRootView`, `WatchMailListView`, `WatchMailRow` (mit `WatchAvatarView`), `WatchMailDetailView`, `WatchRichTextView`, `WatchSpamActionsView`, `MailwerkWatch.entitlements`.

**Neu – Komplikation (`MailwerkWatchComplication/`, Ziel „MailwerkWatchWidgetExtension“):** `MailwerkUnreadWidget`, `Info.plist` (Kennung als Widget-Erweiterung), `Assets.xcassets` (Akzent- und Hintergrundfarbe der Vorlage), `MailwerkWatchWidget.entitlements`.

**Geändert:**

| Datei | Änderung |
|---|---|
| `MailwerkApp` | startet `WatchBridge` beim App-Start (auch beim Start im Hintergrund) |
| `InboxViewModel` | `onInboxesRefreshed` nach jedem Abruf der Posteingänge, `onCacheReloaded` nach jedem Neuladen der Liste |
| `InboxView` | Handoff: öffnet die Mail der Watch als Blatt |
| `Info.plist` | `NSUserActivityTypes`: `de.sieber-bw.Mailwerk.mail` |
| `MessageMenu`, `MessageActionDialogs` | nutzen `SpamMenuChoice` (Texte unverändert) |
| `FilterAddress` | `sender(fromHeader:)` nur mit SwiftMail (`canImport`), damit die Datei auch auf der Watch übersetzt |
| `FilterEntry` | `FilterEntryKind` ist `Codable` |
| `ContactImageDirectory` | `thumbnailData(for:)` für die Watch; Datenschutzhinweis ergänzt |
| `ListDateFormatter` | `compactString(for:)` (Kurzform „Mo, 12.10.“) |
| `Log` | Kategorie `Watch` |
| Projekt | zwei neue Ziele samt Schemata; `MARKETING_VERSION` 0.2.0, `CURRENT_PROJECT_VERSION` 1 |

**Tests (neu):** `WatchMailSelectionTests`, `WatchWireTests`, `WatchMailboxTests`, `WatchAppGroupTests`, `WatchSnapshotBuilderTests`, `SpamMenuChoiceTests`; erweitert: `ListDateFormatterTests`.

**Datenschutz:** Kontaktbilder verlassen das iPhone nur verkleinert zur eigenen Watch und nur für Absender der dorthin gelieferten Mails. Auf der Watch liegen höchstens 120 Mails samt Inhalt; nicht mehr gebrauchte Inhalte und Bilder werden nach jeder Lieferung gelöscht. Zugangsdaten kommen nie auf die Watch.

---

## 5. Zielzuordnung und Einstellungen (Endstand)

| Ziel | Bundle-ID (Release; Debug mit `.dev`) | Ordner | Besonderheiten |
|---|---|---|---|
| MailwerkWatch Watch App | `de.sieber-bw.Mailwerk.watchkitapp` | `MailwerkWatch/` + 17 Dateien aus `Mailwerk/` | `WKCompanionAppBundleIdentifier` = iPhone-App; Icon `AppIcon.icon` (unterstützt watchOS); keine Akzentfarbe; kein SwiftMail |
| MailwerkWatchWidgetExtension | `de.sieber-bw.Mailwerk.watchkitapp.MailwerkWatchWidget` | `MailwerkWatchComplication/` + `WatchAppGroup.swift`, `ListDateFormatter.swift` | `Info.plist` nur über „Info.plist File“, nicht als Ressource |

Beide: watchOS 26.5, Swift 5, Default Actor Isolation MainActor, Approachable Concurrency, Member Import Visibility, `REGISTER_APP_GROUPS = YES`, App Group `group.de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX)`, Anzeigename `$(MAILWERK_DISPLAY_NAME)`. Im Ziel Mailwerk wird die Watch-App nur für iOS eingebettet (Filter iOS).

**Gemeinsame Dateien der Watch-App:** `AppIcon.icon`, `Models/AccountColor`, `Models/SenderDomain`, `Services/Log`, `ListDateFormatter`, `HTMLRichTextParser`, `Services/Spam/` (`FilterAddress`, `FilterDomain`, `FilterEntry`, `SpamClassifier`, `SpamHeaderParser`, `SpamMark`, `SpamMenuChoice`), `Services/Watch/` (`WatchTransfer`, `WatchWire`, `WatchMailbox`, `WatchAppGroup`). Nur iPhone: `WatchBridge`, `WatchSnapshotBuilder`, `WatchMailSelection`.

**Neue gemeinsame Datei:** Soll eine Datei aus `Mailwerk/` künftig auch auf der Watch laufen, muss sie ohne SwiftMail, UIKit/AppKit und WebKit auskommen und im File Inspector zusätzlich dem Watch-Ziel zugeordnet werden.

---

## 6. Einrichtung in Xcode (wie durchgeführt)

### 6.1 Watch-App

1. **File → New → Target… → watchOS → App.** Product Name `MailwerkWatch`, **Watch App for Existing iOS App** (Mailwerk), Testing System None → Finish, Schema aktivieren. Ziel: „MailwerkWatch Watch App“.
2. Vorlagenordner „MailwerkWatch Watch App“ löschen (Move to Trash).
3. **Add Files to "Mailwerk"…** → Ordner `MailwerkWatch` → Reference files in place, **Create folders**, nur Ziel „MailwerkWatch Watch App“. Die Optionen erscheinen erst nach „Add“.
4. Build Settings (beide Konfigurationen): Bundle-ID `de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX).watchkitapp`; WatchKit Companion App Bundle Identifier `de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX)`; Bundle Display Name `$(MAILWERK_DISPLAY_NAME)`; Marketing Version 0.2.0, Build 1; watchOS 26.5; Swift-Einstellungen wie Mailwerk; Code Signing Entitlements `MailwerkWatch/MailwerkWatch.entitlements`; `ASSETCATALOG_COMPILER_APPICON_NAME` = AppIcon (erscheint unter „User-Defined“); Global Accent Color Name leer; benutzerdefiniert `REGISTER_APP_GROUPS` = YES. „Supports Running Without iOS App Installation“ setzt die Vorlage nicht – ohne Eintrag gilt „No“.
5. Kontrolle der Bundle-ID: Leiste der Build Settings auf **Values** stellen (statt Definitions).
6. Zielzugehörigkeit der 17 gemeinsamen Dateien (Abschnitt 5) per File Inspector. `Assets.xcassets` der App wird nicht zugeordnet (Xcode bietet es nicht an; die Watch braucht es nicht).

### 6.2 Komplikation

1. **File → New → Target… → watchOS → Widget Extension.** Product Name `MailwerkWatchWidget`, **ohne** Include Control, **ohne** Configuration App Intent, Embed in „MailwerkWatch Watch App“ → Finish, Schema nicht aktivieren. Ziel: „MailwerkWatchWidgetExtension“.
2. Aus der Vorlage nur die beiden Swift-Dateien löschen; `Info.plist` und `Assets.xcassets` wurden beim Aufräumen nach `MailwerkWatchComplication/` verschoben, der Vorlagenordner entfernt.
3. **Add Files to "Mailwerk"…** → Ordner `MailwerkWatchComplication` → Create folders, nur Ziel „MailwerkWatchWidgetExtension“.
4. Build Settings: Bundle-ID `de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX).watchkitapp.MailwerkWatchWidget`; Anzeigename, Version, watchOS, Swift wie 6.1; Code Signing Entitlements `MailwerkWatchComplication/MailwerkWatchWidget.entitlements`; `REGISTER_APP_GROUPS` = YES.
5. Zielzugehörigkeit für `WatchAppGroup.swift` und `ListDateFormatter.swift`.

### 6.3 Ziel Mailwerk

Build Phases → Target Dependencies und Embed Watch Content: Filter **iOS**.

### Aufgetretene Stolpersteine

| Meldung | Ursache | Lösung |
|---|---|---|
| „Multiple commands produce …Info.plist“ | `Info.plist` der Komplikation zusätzlich als Ressource | Zielzugehörigkeit der Datei entfernen (Ausnahme im Projekt) |
| „'main' attribute can only apply to one type in a module“ | Ordner der Komplikation zusätzlich der Watch-App zugeordnet | Zuordnung des Ordners auf die Komplikation beschränken |
| Warnung „Call to main actor-isolated static method 'candidate' in a synchronous nonisolated context“ | Funktion direkt an `map` übergeben | Closure `{ candidate($0) }` |
| Git: Einträge `AD` für Kopien von `MailwerkWatchComplication` in anderen Ordnern | Xcode hatte beim Hinzufügen Kopien vorgemerkt | `git restore --staged …` vor dem Commit |
| Watch nicht als Ziel in Xcode | vermutlich Richtlinie des verwalteten Firmen-iPhones (nicht belegt) | Test mit gekoppelten Simulatoren, echte Watch über TestFlight |

**Aufräumen (nach dem Upload):** `Info.plist` und `Assets.xcassets` der Komplikation in `MailwerkWatchComplication/` verschoben, Vorlagenordner `MailwerkWatchWidget/` samt leerem AppIcon-Platzhalter entfernt; Projektdatei angepasst (Ordnerverweis, Ausnahme für die Info.plist, „Info.plist File“). **Vor dem nächsten Archivieren einmal bauen**, da diese Änderung nach dem Upload kam.

---

## 7. Erster Test im Simulator

Echte Watch: Xcode zeigt die gekoppelte Watch nicht an (vermutlich Richtlinie des verwalteten Firmen-iPhones, nicht belegt). Getestet wurde deshalb mit gekoppelten Simulatoren (iPhone 17 + Apple Watch Series 11, 46 mm).

| Punkt | Ergebnis |
|---|---|
| Bau iPhone, Mac, Watch; 743 Tests | erfolgreich |
| Verbindung, Startansicht mit Zählern, Liste, Mailansicht, gelesen beim Öffnen, Gelesen-Status auf dem iPhone | erfolgreich |
| Datum und Spam-Einschätzung im Mailkopf nebeneinander und umbrochen | geändert: je eine eigene Zeile, einzeilig – erfolgreich nachgetestet |
| Änderungen kamen erst nach „Aktualisieren“ an | geändert: sofort bei offener Watch-App in beide Richtungen – erfolgreich nachgetestet |
| Archiv und Upload TestFlight 0.2.0 (1) mit Watch-App und Komplikation | erfolgreich |

---

## 8. Testplan auf der echten Watch (offen, über TestFlight)

| Nr. | Prüfung | Erwartung |
|---|---|---|
| 1 | Bedienbarkeit: Größe, Wischgesten, Knöpfe der Mailansicht mit dem Finger | gut bedienbar |
| 2 | iPhone in der Nähe, iPhone-App geschlossen (nicht weggewischt), Watch-App öffnen | Stand sofort, „Aktualisiere …“, danach neue Mails und „Stand: …“ |
| 3 | wie 2, iPhone-App im App-Umschalter weggewischt | beobachten: Weckt iOS die App trotzdem? |
| 4 | iPhone aus bzw. Flugmodus | „iPhone nicht erreichbar“; lesen, gelesen, Kennzeichen, Spam funktionieren; nach Rückkehr des iPhones auf dem Server ausgeführt |
| 5 | Watch im WLAN, iPhone weit weg, aber online | beobachten, ob die Verbindung über iCloud vermittelt wird |
| 6 | iPhone-App öffnen und abrufen lassen, danach Watch-App öffnen | neue Mails schon vorhanden (Lieferung im Hintergrund) |
| 7 | mehrere Postfächer, Watch weckt das iPhone im Hintergrund | kommt der frische Stand an? (Konsole, Kategorie „Watch“, „⌚️ …“) |
| 8 | Spam / Vertrauen bei Absender auf Subdomain | sechs Einträge; Rückfrage wie auf dem iPhone; Blockieren → Mail in „Spam“, auf dem iPhone in der Blacklist |
| 9 | Externe Bilder | vertrauenswürdiger Absender: sofort; sonst Knopf „Bilder laden“ |
| 10 | Komplikation „Ungelesen“ auf dem Zifferblatt | Zahl stimmt, sinkt nach „gelesen“ |
| 11 | „Auf iPhone fortfahren“ | iPhone zeigt die Mail als Blatt |
| 12 | Begrenzung | höchstens 100 Eingangsmails + 20 Spam auf der Watch |

Installation bei den Testpersonen: TestFlight auf dem iPhone; die Watch-App installiert sich automatisch oder über die Watch-App des iPhones (App-Liste → Mailwerk → Installieren).

---

## Beobachtungen und Erkenntnisse

- **Netz auf der Watch:** Eigene TCP-Verbindungen nur in Sonderfällen (TN3135) – ein IMAP-Client auf der Watch ist nicht möglich.
- **Keine Web-Ansicht auf watchOS:** HTML muss selbst gesetzt werden; der vorhandene, oberflächenfreie `HTMLRichTextParser` war dafür die Grundlage.
- **Grenze von WatchConnectivity:** rund 64 KB je Nachricht – Lieferungen deshalb gepackt und gestückelt; große Mengen im Hintergrund als Datei.
- **Gemeinsamer Code:** Nur Dateien ohne SwiftMail und ohne UIKit/AppKit/WebKit können zur Watch; `FilterAddress` brauchte dafür `canImport(SwiftMail)`.
- **Xcode 27:** Optionen beim Hinzufügen von Ordnern erst nach „Add“; gekoppelte Uhren erscheinen nicht mehr in der Mitte des Geräte-Fensters; „Values“ zeigt aufgelöste Build-Einstellungen.
- **Simulatoren:** WatchConnectivity funktioniert zwischen gekoppelten Simulatoren – fast alle Funktionen sind ohne echte Watch prüfbar.

---

## Gesamtstand des Projekts (Stand 20.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS, macOS und watchOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`. Lokaler Projektordner auf dem Entwicklungs-Mac.
- Version **0.2.0**, **743 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkWatch Watch App, MailwerkWatchWidgetExtension, MailwerkTests, MailwerkUITests.
- **Verteilung:** TestFlight (zwei Testpersonen), Build 0.2.0 (1) mit Watch-App. „Mailwerk Dev“ per Xcode auf iPhone und Mac. Auf dem Mac ist die produktive App noch nicht installiert.

### Funktionsumfang (bis v0.2.0)
- Unified Inbox mehrerer IMAP/SMTP-Postfächer, Abruf je Postfach ein-/ausschaltbar (je Gerät), Farben je Postfach, Absenderbilder (Kontakte, Favicons) in Liste und Mailansicht.
- Sammelansichten: Alle Eingänge, Ungelesen (Zähler), Mit Kennzeichnung (Zähler), Spam (alle Spam-Ordner, auch ohne Filter).
- Ordnerleiste mit Ordnerbaum, Ordner anlegen/löschen, Verschieben-Dialog, Offline-Cache (SQLite, WAL, Schema-Stufe 7, Header-Version 3, FTS5-Suchindex), Server-Abgleich, „Ältere laden“.
- Mailansicht: HTML sicher (CSP, externe Inhalte auf Knopf), Dunkelmodus, Zoom, eingebettete Bilder, Originalquelle mit Suche, Drucken, Teilen, Mailkopf mit Adressmenü und Absenderbild, Spam-Einschätzung in der Datumszeile.
- Verfassen: Rich-Text-Editor mit Formatierungsleiste, Anhänge, Bilder im Text, Signaturen je Postfach, Entwürfe, Absender-Regeln; `mailto:`-Links von außen (Standard-Postfach).
- Spamfilter (clientseitig): White-/Blacklist über CloudKit, Domains samt Subdomains, Spam-Header, Whitelist schlägt Server-Einstufung, Blockieren/Vertrauen je Mail, Listen bearbeiten, exportieren, importieren.
- Suche (lokal, Namen, Server), Sortierung, Mehrfachauswahl, Kontextmenü, Rückgängig-Balken, eigene untere Leiste (Liquid Glass).
- Teilen mit Mailwerk (Erweiterungen iOS und Mac).
- Anmeldung: Passwort (manitu, GMX, web.de, Posteo, Gmail mit App-Passwort) und OAuth 2 (Outlook.com).
- App-Icon aus Icon Composer (hell/dunkel) – iPhone, iPad, Mac, Watch.
- **Apple Watch** – vier Sammelansichten, lesen (HTML vereinfacht), gelesen/ungelesen, Kennzeichen, Spam/Vertrauen, Komplikation „Ungelesen“, Handoff; Abruf über das iPhone, eigener Speicher (höchstens 120 Mails), Abgleich sofort bei offener Watch-App.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, MemberImportVisibility; iOS/macOS/watchOS 26.5. Xcode 27.1, macOS 27.0.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage) – nicht im Watch-Ziel.
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Refresh-Tokens: iCloud-Schlüsselbund; Filterlisten und Signaturen: SwiftData/CloudKit (`iCloud.de.sieber-bw.Mailwerk`); Abruf-Schalter: UserDefaults (je Gerät).
- Watch: WatchConnectivity (iPhone ↔ Watch), Speicher als Dateien in der App Group der Watch, keine Zugangsdaten auf der Watch.
- Test/Produktion: Bundle-Suffix `.dev` für „Mailwerk Dev“ (auch für die Watch-Ziele); Anzeigename über `MAILWERK_DISPLAY_NAME`.

### Arbeitsregeln (verbindlich)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher abstimmen.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen; klare Anweisungen mit genauem Menüpfad.
- Ursache belegen, nicht raten (Rohdaten, Server-Dialog, Quelltext, Console, Git-Historie).
- **Lokale Sitzung:** Lieferung als ganze Dateien in den Projektordner; Git im Projektordner nur lesend; Claude committet nicht, Commit-Text wird mitgeliefert.
- **Cloud-Sitzung:** Claude arbeitet auf einem eigenen Branch, committet und pusht dort; gebaut und getestet wird lokal in Xcode; Übernahme nach `main` per Pull Request. Änderungen, die nur Xcode vornimmt (neue Ziele, Projektdatei), werden lokal committet und auf denselben Branch gepusht – vorher `git status` prüfen (keine unerwarteten Einträge, kein fester „Mailwerk Dev“).
- Projekteinstellungen, die sich nur in Xcode oder Icon Composer ändern lassen, manuell nach Anleitung.
- Inline-Doku: Datei-Header (Zweck, Abgrenzung, Abhängigkeiten), DocC je Funktion, Deutsch, keine Versionsverweise.
- Öffentliche Dokumentation ohne persönliche Bezüge (siehe `CLAUDE.md`); Arbeitsdokumente in `Documentation/Intern/`.
- Keine Sonderlösungen für einzelne Anbieter; Gestaltung mit Apple-Bausteinen, eigene Anordnungen als USP erlaubt.
- Tests dürfen keine Produktivmails verändern – Tests mit den Testpostfächern in „Mailwerk Dev“.

### Offene Punkte
- **Watch:** Testplan auf der echten Watch (Abschnitt 8) über TestFlight; Watch in Xcode nicht als Ziel wählbar (vermutlich Richtlinie des Firmen-iPhones – bei Bedarf mit der IT klären oder privates iPhone).
- **Watch, später möglich:** eingebettete Bilder (`cid:`) mitliefern; Mitteilungen; Mac als Lieferant ist technisch nicht möglich (WatchConnectivity nur mit dem gekoppelten iPhone).
- **Mac – größere HTML-Mails öffnen sich nicht (für die Überarbeitung der Mac-Version):** Auf dem Mac öffnen sich größere HTML-Mails (ab etwa 25 KB, alle Postfächer) teils gar nicht, teils kurz und schließen sich wieder, teils erst beim zweiten Klick; kleine Mails öffnen sich. Konsole: „⏱ Mail geöffnet“, „⏱ HTML geladen“, danach übliche Sandbox-Meldungen des Web-Prozesses und zuletzt `XPCConnectionTerminationWatchdog` (Abbau der Web-Ansicht – eher Folge als Ursache). Widerlegt: Abruf nach dem Start. Unklar: Einfluss der Fenstergröße. v0.2.0 ändert den Web-Teil der Mailansicht nicht. Zuerst prüfen: tritt es auch mit v0.1.20 auf? Ähnliches Bild in v0.1.17 (damals Umgebung).
- **Default Mail App:** Antwort von Apple abwarten; danach Capability „Default Mail App“ an `de.sieber-bw.Mailwerk` einrichten, neuen Build hochladen; Test-Postfach für Apple löschen.
- **Mac:** produktive „Mailwerk“ (TestFlight) noch nicht installiert.
- **MailwerkUITests:** Ordner fehlt auf der Platte (rot im Navigator) – aufräumen oder neu anlegen.
- **Azure-Probephase:** nach Ablauf Outlook in „Mailwerk Dev“ neu anmelden; vor App Store Herausgeber-Verifizierung.
- **`mailto:`-Randfall:** bei offener QuickLook-Vorschau oder Rückfrage kann das Fenster ausbleiben – beobachten.
- **Spam:** Prüfung mit neu eingehender GMX/web.de-Mail eines Whitelist-Absenders mit `X-Spam-Flag: YES` steht noch aus.
- **App-Icon:** Wirkung des Glas-Effekts und der P3-Farben im Alltag beobachten.
- **Gmail per OAuth:** nur vorgemerkt.
- **Kopfdaten außerhalb des Zeitfensters nachfüllen (Weg B)**; **H6** Verbindungen je Konto wiederverwenden (ggf. Push/IDLE); **N14** Offline-Warteschlange; **Ordner abonnieren**; **DKIM/Authentication-Results**; sporadischer Gmail-Timeout; Suchfeld unten; Teilen (große Videos, HEIC, Mac-Gestaltung); Strukturempfehlungen (Protokolle/Injektion, SwiftLint/SwiftFormat, Lokalisierung).

### Fahrplan
- **Nächste Version:** Abnahme der Watch-App auf dem Gerät; Übernahme nach `main` per Pull Request.
- **v0.2.x:** Seitenleiste und Layout für iPad und Mac (samt Mac-Fund „größere HTML-Mails“), Gestaltung der Teilen-Erweiterung auf dem Mac.
- **Später:** H6, Push/IDLE, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung (Default Mail App, Herausgeber-Verifizierung Microsoft, Datenschutzangaben – darin auch die Watch).
