# Mailwerk – Entwicklungsdokumentation v0.2.0

2026-10-18 · „Apple Watch“: Mailwerk als Watch-App – neueste Mails lesen, gelesen/ungelesen, Kennzeichen, Spam/Vertrauen, Zähler als Komplikation

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen.

---

## Zusammenfassung

v0.2.0 bringt Mailwerk auf die Apple Watch. Die Watch speichert ihre Mails selbst und bleibt ohne iPhone bedienbar; abgerufen wird über das iPhone, auch wenn die App dort geschlossen ist. Umgesetzt in einer Cloud-Sitzung (Code auf eigenem Branch); die neuen Ziele werden lokal in Xcode angelegt (Abschnitt 6).

| Bereich | Ergebnis |
|---|---|
| Grundsatz | Watch spricht nicht selbst mit den Mailservern (watchOS lässt es nicht zu) – Weg A über das iPhone, Watch mit eigenem Speicher |
| Ansichten | Alle Eingänge, Ungelesen (Zähler), Mit Kennzeichnung (Zähler), Spam |
| Aktionen | gelesen/ungelesen, Kennzeichen, Spam/Vertrauen (alle Einträge wie in der App) – sofort auf der Watch, auf dem Server sofort bzw. sobald das iPhone erreichbar ist |
| Speicher | 50 neueste + ungelesene + gekennzeichnete, höchstens 100; dazu 20 neueste Spam; HTML gespeichert, Anhänge nur als Name |
| Komplikation | Zahl der ungelesenen Mails (Zifferblatt und Smart Stack) |
| Handoff | „Auf iPhone fortfahren“ öffnet die Mail in der App |

Tests: 705 → **743** Testfunktionen (`@Test`, 38 neu). `MARKETING_VERSION` 0.2.0 (Build 1) in Mailwerk, MailwerkShare und MailwerkShareMac; die beiden neuen Ziele erhalten dieselbe Version beim Anlegen. **Stand bei Übergabe: nicht gebaut, nicht getestet** – in der Cloud-Sitzung gibt es kein Xcode.

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
3. **Einzelne Aktion:** Nur die Aktion geht zum iPhone, ohne Abruf.
4. **Ohne iPhone:** Die Watch zeigt ihren gespeicherten Stand („iPhone nicht erreichbar“, „Stand: …“). Aktionen wirken sofort und kommen mit der nächsten Verbindung mit.
5. **Hintergrund:** Ruft die iPhone-App selbst ab (Start, Herunterziehen), schickt sie den neuen Stand samt den Inhalten, die die Watch noch nicht hat, als Datei (`transferFile`). watchOS weckt die Watch-App kurz; beim nächsten Öffnen ist alles da.

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

### Darstellung des HTML

watchOS hat keine Web-Ansicht. Das HTML wird mit dem vorhandenen `HTMLRichTextParser` in Absätze, Fett, Kursiv, Unterstrichen, Links, Listen und Bilder zerlegt und mit SwiftUI gesetzt. Tabellenlayouts (Newsletter) werden flach; Textfarben und Schriftgrößen der Mail entfallen (dunkler Grund der Watch), große Schrift wird fett. Bilder: `data:` immer, `http(s)` nur nach Freigabe, `cid:` nie.

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

**Neu – Watch-App (`MailwerkWatch/`):** `MailwerkWatchApp`, `WatchStore`, `WatchConnector`, `WatchRootView`, `WatchMailListView`, `WatchMailRow` (mit `WatchAvatarView`), `WatchMailDetailView`, `WatchRichTextView`, `WatchSpamActionsView`, `MailwerkWatch.entitlements`.

**Neu – Komplikation (`MailwerkWatchComplication/`):** `MailwerkUnreadWidget`, `MailwerkWatchWidget.entitlements`.

**Geändert:**

| Datei | Änderung |
|---|---|
| `MailwerkApp` | startet `WatchBridge` beim App-Start (auch beim Start im Hintergrund) |
| `InboxViewModel` | `onInboxesRefreshed` nach jedem Abruf der Posteingänge |
| `InboxView` | Handoff: öffnet die Mail der Watch als Blatt |
| `Info.plist` | `NSUserActivityTypes`: `de.sieber-bw.Mailwerk.mail` |
| `MessageMenu`, `MessageActionDialogs` | nutzen `SpamMenuChoice` (Texte unverändert) |
| `FilterAddress` | `sender(fromHeader:)` nur mit SwiftMail (`canImport`), damit die Datei auch auf der Watch übersetzt |
| `FilterEntry` | `FilterEntryKind` ist `Codable` |
| `ContactImageDirectory` | `thumbnailData(for:)` für die Watch; Datenschutzhinweis ergänzt |
| `ListDateFormatter` | `compactString(for:)` (Kurzform „Mo, 12.10.“) |
| `Log` | Kategorie `Watch` |
| Projekt | `MARKETING_VERSION` 0.2.0, `CURRENT_PROJECT_VERSION` 1 |

**Tests (neu):** `WatchMailSelectionTests`, `WatchWireTests`, `WatchMailboxTests`, `WatchAppGroupTests`, `WatchSnapshotBuilderTests`, `SpamMenuChoiceTests`; erweitert: `ListDateFormatterTests`.

**Datenschutz:** Kontaktbilder verlassen das iPhone nur verkleinert zur eigenen Watch und nur für Absender der dorthin gelieferten Mails. Auf der Watch liegen höchstens 120 Mails samt Inhalt; nicht mehr gebrauchte Inhalte und Bilder werden nach jeder Lieferung gelöscht.

---

## 5. Prüfen in Xcode vor dem Commit

- Mailwerk (iPhone, Mac) bauen: ⇧⌘K, ⌘B – die neuen Dateien unter `Mailwerk/` gehören über den synchronisierten Ordner automatisch zu Mailwerk und den Teilen-Erweiterungen.
- Tests: ⌘U, erwartet **743**.
- Watch-App: Schema „MailwerkWatch Watch App“, Ziel die gekoppelte Watch.

---

## 6. Einrichtung in Xcode (manuell, einmalig)

Vorher Xcode beenden, Branch holen (`git fetch`, `git switch claude/tender-feynman-m0y38w`), dann Xcode öffnen.

### 6.1 Ziel Watch-App

1. **File → New → Target… → watchOS → App → Next.**
2. Product Name `MailwerkWatch`, Team wie bisher, **Watch App for Existing iOS App**, Companion: `Mailwerk`, Testing System **None** → **Finish**, Schema aktivieren. Das Ziel heißt danach „MailwerkWatch Watch App“.
3. Den neu angelegten Ordner **„MailwerkWatch Watch App“** im Navigator löschen (**Move to Trash**) – er enthält nur die Vorlage.
4. Rechtsklick auf das Projekt → **Add Files to "Mailwerk"…** → Ordner `MailwerkWatch` → **Create folders**, Ziel nur **MailwerkWatch Watch App**.
5. Ziel „MailwerkWatch Watch App“ → **Build Settings** (All, beide Konfigurationen):
   - Product Bundle Identifier: `de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX).watchkitapp`
   - `INFOPLIST_KEY_WKCompanionAppBundleIdentifier`: `de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX)`
   - `INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp` („Supports Running Without iOS App Installation“): **No**
   - `INFOPLIST_KEY_CFBundleDisplayName`: `$(MAILWERK_DISPLAY_NAME)`
   - watchOS Deployment Target: **26.5**
   - Swift Language Version **5**, Default Actor Isolation **MainActor**, Approachable Concurrency **Yes**, Member Import Visibility (Upcoming Feature) **Yes** – wie im Ziel Mailwerk
   - Marketing Version **0.2.0**, Current Project Version **1**
   - Code Signing Entitlements: `MailwerkWatch/MailwerkWatch.entitlements`
   - App Icon (`ASSETCATALOG_COMPILER_APPICON_NAME`): `AppIcon`
   - Global Accent Color Name: leer (die Akzentfarbe liegt im Asset-Katalog der App, der nicht zur Watch gehört)
   - benutzerdefiniert (+ → Add User-Defined Setting): `REGISTER_APP_GROUPS` = `YES`
   - „Supports Running Without iOS App Installation“ bietet die Vorlage nicht an; ohne Eintrag gilt „No“
6. **Signing & Capabilities:** automatische Signierung; die App Group steht in der Entitlements-Datei (wie beim iPhone mit `$(MAILWERK_BUNDLE_SUFFIX)`). Falls Xcode „App Groups“ nicht registriert: + Capability → App Groups → Gruppe `group.de.sieber-bw.Mailwerk.dev` bzw. `group.de.sieber-bw.Mailwerk` anhaken und danach in der Entitlements-Datei wieder den Wert mit `$(MAILWERK_BUNDLE_SUFFIX)` herstellen.
7. **Zielzugehörigkeit** (Navigator: Dateien mit ⌘-Klick wählen → File Inspector → Target Membership → **MailwerkWatch Watch App** anhaken):
   - `Mailwerk/AppIcon.icon` (`Assets.xcassets` nicht – Xcode bietet dafür keine Zuordnung an, und die Watch braucht sie nicht)
   - `Mailwerk/Models/AccountColor.swift`, `Mailwerk/Models/SenderDomain.swift`
   - `Mailwerk/Services/Log.swift`, `ListDateFormatter.swift`, `HTMLRichTextParser.swift`
   - `Mailwerk/Services/Spam/FilterAddress.swift`, `FilterDomain.swift`, `FilterEntry.swift`, `SpamClassifier.swift`, `SpamHeaderParser.swift`, `SpamMark.swift`, `SpamMenuChoice.swift`
   - `Mailwerk/Services/Watch/WatchTransfer.swift`, `WatchWire.swift`, `WatchMailbox.swift`, `WatchAppGroup.swift`
   - **nicht:** `WatchBridge.swift`, `WatchSnapshotBuilder.swift`, `WatchMailSelection.swift` (nur iPhone)

### 6.2 Ziel Komplikation

1. **File → New → Target… → watchOS → Widget Extension.** Product Name `MailwerkWatchWidget`, **ohne** Include Control und **ohne** Configuration App Intent, Embed in **MailwerkWatch Watch App** → Finish (Schema nicht aktivieren). Das Ziel heißt danach „MailwerkWatchWidgetExtension“.
2. Im neuen Ordner **„MailwerkWatchWidget“** nur die beiden Swift-Dateien der Vorlage löschen (**Move to Trash**). `Info.plist` (Kennung als Widget-Erweiterung) und `Assets.xcassets` bleiben.
3. **Add Files to "Mailwerk"…** → Ordner `MailwerkWatchComplication` → **Create folders**, Ziel nur **MailwerkWatchWidgetExtension** (nicht zusätzlich die Watch-App – sonst „'main' attribute can only apply to one type in a module“).
4. `MailwerkWatchWidget/Info.plist`: in der Zielzugehörigkeit **keinen** Haken (sonst „Multiple commands produce …Info.plist“); sie wirkt über „Info.plist File“.
5. Build Settings: Bundle Identifier `de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX).watchkitapp.MailwerkWatchWidget`; watchOS 26.5; Swift-Einstellungen wie 6.1; Marketing Version 0.2.0, Build 1; `INFOPLIST_KEY_CFBundleDisplayName` = `$(MAILWERK_DISPLAY_NAME)`; Code Signing Entitlements `MailwerkWatchComplication/MailwerkWatchWidget.entitlements`; benutzerdefiniert `REGISTER_APP_GROUPS` = `YES`.
6. Zielzugehörigkeit **MailwerkWatchWidgetExtension** für `Mailwerk/Services/Watch/WatchAppGroup.swift` und `Mailwerk/Services/ListDateFormatter.swift`.
7. Später aufräumen (vorgemerkt): `Info.plist` und `Assets.xcassets` nach `MailwerkWatchComplication` verschieben, „Info.plist File“ anpassen, leeren Ordner `MailwerkWatchWidget` löschen.

### 6.3 Ziel Mailwerk (iPhone/Mac)

- **Build Phases → Embed Watch Content** und **Target Dependencies** (MailwerkWatch Watch App): Filter auf **iOS** setzen, damit der Mac-Build die Watch-App nicht einbettet.
- Danach in Source Control prüfen, dass `project.pbxproj` keine festen Anzeigenamen („Mailwerk Dev“) enthält (Erfahrung aus v0.1.20).

**Mögliche Stolpersteine:**
- „Multiple commands produce …Info.plist“ bzw. eine `.entitlements`-Datei unter Copy Bundle Resources: die Datei im File Inspector aus der Zielzugehörigkeit nehmen (bei der Einrichtung aufgetreten, siehe 6.2).
- „'main' attribute can only apply to one type in a module“: Ordner `MailwerkWatchComplication` ist zusätzlich der Watch-App zugeordnet (bei der Einrichtung aufgetreten).
- Fehler zu `SwiftMail` in `FilterAddress.swift` beim Watch-Ziel: SwiftMail darf dem Watch-Ziel nicht zugeordnet sein (Frameworks-Liste des Ziels leer lassen).

---

## 7. Testplan (offen)

| Nr. | Prüfung | Erwartung |
|---|---|---|
| 1 | iPhone in der Nähe, iPhone-App geschlossen (nicht weggewischt), Watch-App öffnen | Stand sofort, „Aktualisiere …“, danach neue Mails und „Stand: …“ |
| 2 | wie 1, iPhone-App im App-Umschalter weggewischt | beobachten: Weckt iOS die App trotzdem? (offen) |
| 3 | iPhone aus bzw. Flugmodus | „iPhone nicht erreichbar“; lesen, gelesen, Kennzeichen, Spam funktionieren; nach Rückkehr des iPhones auf dem Server ausgeführt |
| 4 | Watch im WLAN, iPhone weit weg, aber online | beobachten, ob die Verbindung über iCloud vermittelt wird (offen) |
| 5 | iPhone-App öffnen und abrufen lassen, danach Watch-App öffnen | neue Mails schon vorhanden (Lieferung im Hintergrund) |
| 6 | Mehrere Postfächer, Watch weckt das iPhone im Hintergrund | kommt der frische Stand an? (Konsole, Kategorie „Watch“, „⌚️ …“) |
| 7 | Spam / Vertrauen bei Absender auf Subdomain | sechs Einträge; Rückfrage wie auf dem iPhone; Blockieren → Mail in „Spam“, auf dem iPhone in der Blacklist |
| 8 | Externe Bilder | vertrauenswürdiger Absender: sofort; sonst Knopf „Bilder laden“ |
| 9 | Komplikation „Ungelesen“ | Zahl stimmt, sinkt nach „gelesen“ |
| 10 | „Auf iPhone fortfahren“ | iPhone zeigt die Mail als Blatt |
| 11 | Begrenzung | höchstens 100 Eingangsmails + 20 Spam auf der Watch |
| 12 | Dev/Produktion | „Mailwerk Dev“ mit Testpostfächern; keine Produktivmails verändern |

---

## Beobachtungen und Erkenntnisse

- **Netz auf der Watch:** Eigene TCP-Verbindungen nur in Sonderfällen (TN3135) – ein IMAP-Client auf der Watch ist nicht möglich.
- **Keine Web-Ansicht auf watchOS:** HTML muss selbst gesetzt werden; der vorhandene, oberflächenfreie `HTMLRichTextParser` war dafür die Grundlage.
- **Grenze von WatchConnectivity:** rund 64 KB je Nachricht – Lieferungen deshalb gepackt und gestückelt; große Mengen im Hintergrund als Datei.
- **Gemeinsamer Code:** Nur Dateien ohne SwiftMail und ohne UIKit/AppKit/WebKit können zur Watch; `FilterAddress` brauchte dafür `canImport(SwiftMail)`.

---

## Gesamtstand des Projekts (Stand 18.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS, macOS und (neu) watchOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`. Lokaler Projektordner auf dem Entwicklungs-Mac.
- Version **0.2.0**, **743 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkTests, MailwerkUITests; neu (in Xcode anzulegen): MailwerkWatch Watch App, MailwerkWatchWidget.
- **Verteilung:** TestFlight (zwei Testpersonen), Upload mit „App Store Connect“. „Mailwerk Dev“ per Xcode auf iPhone und Mac. Auf dem Mac ist die produktive App noch nicht installiert.

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
- App-Icon aus Icon Composer (hell/dunkel) – iPhone, iPad, Mac; neu auch Watch.
- **Neu: Apple Watch** – vier Sammelansichten, lesen (HTML vereinfacht), gelesen/ungelesen, Kennzeichen, Spam/Vertrauen, Komplikation „Ungelesen“, Handoff; Abruf über das iPhone, eigener Speicher (höchstens 120 Mails).

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, MemberImportVisibility; iOS/macOS 26.5, watchOS 26.5. Xcode 27.1, macOS 27.0.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage) – nicht im Watch-Ziel.
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Refresh-Tokens: iCloud-Schlüsselbund; Filterlisten und Signaturen: SwiftData/CloudKit (`iCloud.de.sieber-bw.Mailwerk`); Abruf-Schalter: UserDefaults (je Gerät).
- Watch: WatchConnectivity (iPhone ↔ Watch), Speicher als Dateien in der App Group der Watch (`group.de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX)`), keine Zugangsdaten auf der Watch.
- Test/Produktion: Bundle-Suffix `.dev` für „Mailwerk Dev“ (auch für die Watch-Ziele); Anzeigename über `MAILWERK_DISPLAY_NAME`.

### Arbeitsregeln (verbindlich)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher abstimmen.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen; klare Anweisungen mit genauem Menüpfad.
- Ursache belegen, nicht raten (Rohdaten, Server-Dialog, Quelltext, Console, Git-Historie).
- **Lokale Sitzung:** Lieferung als ganze Dateien in den Projektordner; Git im Projektordner nur lesend; Claude committet nicht, Commit-Text wird mitgeliefert.
- **Cloud-Sitzung:** Claude arbeitet auf einem eigenen Branch, committet und pusht dort; gebaut und getestet wird lokal in Xcode; Übernahme nach `main` per Pull Request.
- Projekteinstellungen, die sich nur in Xcode oder Icon Composer ändern lassen, manuell nach Anleitung.
- Inline-Doku: Datei-Header (Zweck, Abgrenzung, Abhängigkeiten), DocC je Funktion, Deutsch, keine Versionsverweise.
- Öffentliche Dokumentation ohne persönliche Bezüge (siehe `CLAUDE.md`); Arbeitsdokumente in `Documentation/Intern/`.
- Keine Sonderlösungen für einzelne Anbieter; Gestaltung mit Apple-Bausteinen, eigene Anordnungen als USP erlaubt.
- Tests dürfen keine Produktivmails verändern – Tests mit den Testpostfächern in „Mailwerk Dev“.

### Offene Punkte
- **v0.2.0:** Ziele in Xcode anlegen (Abschnitt 6), bauen, Testplan (Abschnitt 7) – insbesondere weggewischte iPhone-App, Verbindung über WLAN ohne iPhone in der Nähe, Hintergrundzeit bei mehreren Postfächern.
- **Watch, später möglich:** eingebettete Bilder (`cid:`) mitliefern; Mitteilungen; Mac als Lieferant ist technisch nicht möglich (WatchConnectivity nur mit dem gekoppelten iPhone).
- **Default Mail App:** Antwort von Apple abwarten; danach Capability „Default Mail App“ an `de.sieber-bw.Mailwerk` einrichten, neuen Build hochladen; Test-Postfach für Apple löschen.
- **Mac:** produktive „Mailwerk“ (TestFlight) noch nicht installiert.
- **Azure-Probephase:** nach Ablauf Outlook in „Mailwerk Dev“ neu anmelden; vor App Store Herausgeber-Verifizierung.
- **`mailto:`-Randfall:** bei offener QuickLook-Vorschau oder Rückfrage kann das Fenster ausbleiben – beobachten.
- **Spam:** Prüfung mit neu eingehender GMX/web.de-Mail eines Whitelist-Absenders mit `X-Spam-Flag: YES` steht noch aus.
- **App-Icon:** Wirkung des Glas-Effekts und der P3-Farben im Alltag beobachten.
- **Gmail per OAuth:** nur vorgemerkt.
- **Kopfdaten außerhalb des Zeitfensters nachfüllen (Weg B)**; **H6** Verbindungen je Konto wiederverwenden (ggf. Push/IDLE); **N14** Offline-Warteschlange; **Ordner abonnieren**; **DKIM/Authentication-Results**; sporadischer Gmail-Timeout; Suchfeld unten; Teilen (große Videos, HEIC, Mac-Gestaltung); Strukturempfehlungen (Protokolle/Injektion, SwiftLint/SwiftFormat, Lokalisierung).

### Fahrplan
- **v0.2.x:** Abnahme der Watch-App; Seitenleiste und Layout für iPad und Mac, Gestaltung der Teilen-Erweiterung auf dem Mac.
- **Später:** H6, Push/IDLE, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung (Default Mail App, Herausgeber-Verifizierung Microsoft, Datenschutzangaben – darin auch die Watch).
