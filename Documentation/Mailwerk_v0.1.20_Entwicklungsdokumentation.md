# Mailwerk – Entwicklungsdokumentation v0.1.20

2026-10-18 · „Hilfsfunktionen und Design“: Suche in der Originalquelle, Absenderbild in der Mailansicht, neues App-Icon (Nebelblau, Dunkelmodus auf iPhone, iPad und Mac), Anzeigename der TestFlight-App

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen.

---

## Zusammenfassung

v0.1.20 schließt den Rest aus „Spam und Optik“ ab und ergänzt eine Hilfsfunktion sowie einen Fehler aus v0.1.19. Erstmals wurde eine Version vollständig in einer **Cloud-Sitzung** (Claude Code im Browser) umgesetzt: Code auf eigenem Branch, Prüfung lokal in Xcode.

| Jira | Inhalt | Ergebnis | Commit |
|---|---|---|---|
| – | Originalquelle durchsuchbar | umgesetzt | `3903fe6` |
| MW-31 | Icon aus der Liste auch in der Mailansicht | umgesetzt | `3903fe6` |
| MW-33 | App-Icon: Hintergrund Nebelblau, Umschlag in Button-Blau | umgesetzt (Entwurf B) | `c2a9cb1`, `6b159e0` |
| MW-34 | App-Icon Dunkelmodus | umgesetzt (Entwurf 3 „Nachtblau negativ“), auch auf dem Mac | `4865053`, `10a25f9`, `6b159e0` |
| – | Bug: TestFlight-App heißt „Mailwerk Dev“ | behoben | `3903fe6` |

Tests: 698 → **705** Testfunktionen (`@Test`, 7 neu), alle grün. `MARKETING_VERSION` 0.1.20 in Mailwerk, MailwerkShare und MailwerkShareMac. Alle Punkte auf iPhone und Mac abgenommen; TestFlight-Build 0.1.20 hochgeladen.

---

## 1. Suche in der Originalquelle

**Anforderung:** Im Blatt „Originalquelle“ einen Begriff, ein Wort oder einen Satz suchen; erster Treffer, mit „Weiter“ zum nächsten, nach dem letzten wieder vorne; ohne Rücksicht auf Groß-/Kleinschreibung, sonst bewusst einfach.

### Verhalten

| Punkt | Umsetzung |
|---|---|
| Ort | Suchleiste über dem Text, nur wenn die Quelle geladen ist |
| Suche | genau die Eingabe (auch Leerzeichen), ohne Groß-/Kleinschreibung; keine Platzhalter, kein Wortanfang, keine Überlappung |
| Auslösen | Eingabetaste oder „Weiter“: erster Treffer, danach jeweils der nächste, nach dem letzten wieder der erste |
| Anzeige | aktueller Treffer gelb hinterlegt (schwarze Schrift, auch im Dunkelmodus lesbar) und in den sichtbaren Bereich gescrollt; daneben „2 von 5“ bzw. „Kein Treffer“ |
| Geänderte Eingabe | Suche beginnt neu, Markierung und Zähler verschwinden |

### Umsetzung

| Datei | Inhalt |
|---|---|
| `RawSourceSearch.swift` (neu, Services) | Fundstellen als `NSRange` (`matches(of:in:)`) und nächster Index mit Neubeginn (`nextIndex(after:count:)`) |
| `RawSourceView` | Suchleiste, Zustand (Eingabe, Fundstellen, aktueller Treffer); Textansicht (UITextView/NSTextView) hinterlegt den Treffer über die `textStorage` und scrollt dorthin, ein Koordinator merkt sich den vorigen Treffer zum Lösen |

`NSRange` statt `Range<String.Index>`, weil die native Textansicht damit markiert und scrollt; die Tests prüfen das auch hinter Umlauten und Emoji (UTF-16).

---

## 2. MW-31: Absenderbild in der Mailansicht

**Anforderung:** Der Kreis der Liste (Absender, in Gesendet der Empfänger) auch in der geöffneten Mail, neben den Absender-/Empfängerdaten – Vorbild Apple Mail.

### Entscheidungen

| Frage | Entscheidung |
|---|---|
| Position | links neben Von/An/Kopie/Antwort an und Datum; Betreff bleibt darüber |
| Inhalt | dieselbe Reihenfolge wie die Liste: Kontaktbild, Logo der Domain, Initialen |
| Gesendet / Entwürfe | erster Empfänger (wie in der Liste) |
| Spam, Spamverdacht, unbekannte Einstufung | leerer Kreis, kein Logo-Abruf – dieselbe Regel wie in der Liste (`SpamClassifier.allowsSenderImage`) |
| Bis zur Prüfung beim Öffnen | leerer Kreis (kein Springen der Anordnung) |
| Später geladenes Logo | erscheint ohne erneutes Öffnen (beobachteter Logo-Cache) |

### Umsetzung

| Datei | Inhalt |
|---|---|
| `MessageRowParty` | `make(from:recipients:showsRecipients:)` – Ermittlung aus Absender und Empfängern, auch ohne Listeneintrag; die bisherige Funktion ruft sie auf |
| `SpamFilterService` | `allowsSenderImage(of:scoreLimit:)` – liest die aktuellen Listen; nicht lesbar → kein Bild |
| `MessageDetailHeader` | Parameter `avatar`; Kreis (`SenderAvatarView`) links neben Personen und Datumszeile |
| `MessageDetailView` | `showsRecipients`, Prüfung beim Öffnen, Inhalt des Kreises aus `ContactImageDirectory` und `SenderIconCache` |
| `InboxView` (`MessageDetailLoader`), `ServerMessageLoader` | geben `showsRecipients` der Liste weiter |

---

## 3. MW-33 + MW-34: App-Icon

### Entwürfe

Grundlage war das bisherige Icon (Umschlag mit Zahnrad-Lasche, Verlauf Türkis → Blau, weißer Grund). Der Umschlag wurde freigestellt und nur umgefärbt, damit die Form pixelgleich bleibt.

| Entwurf | Hintergrund | Umschlag |
|---|---|---|
| Hell A | Nebelblau `#DFE5F5` | bisheriger Verlauf |
| **Hell B (gewählt)** | Nebelblau `#DFE5F5` | Button-Blau, Verlauf `#5B8AF0` → `#2A56C9`, Linien weiß |
| Dunkel 1 | Nachtblau (Verlauf um `#121827`) | bisheriger Verlauf |
| Dunkel 2 | Graphit | Mailwerk-Blau |
| **Dunkel 3 (gewählt)** | Nachtblau `#121827` | „negativ“: hell (`#E6EBF8` → `#B9C6E6`), Linien Nachtblau |

Die Farben sind die der App (AppTheme: Nebelblau/Nachtblau; AccentColor: Button-Blau). Entwürfe und Übersicht liegen unter `AppIcons/v0.1.20_Entwuerfe/`.

### Weg zum Dunkelmodus auf allen Geräten

1. **Asset-Katalog (zuerst):** `AppIcon.appiconset` mit hellem 1024er-Icon und einer Variante „Dark“ für iOS. Ergebnis: iPhone/iPad richtig, **Mac nur hell** – der Asset-Katalog kennt für macOS keine Darstellung „Dark“.
2. **Icon Composer (endgültig):** Seit macOS 26 gibt es ein dunkles App-Icon auf dem Mac nur über eine `.icon`-Datei aus Apples Icon Composer. Eine Datei gilt für iPhone, iPad und Mac in Hell, Dunkel und Getönt. Da das Mindestziel 26.5 ist, ist keine Rücksicht auf ältere Systeme nötig.

### Aufbau `Mailwerk/AppIcon.icon`

| Teil | Inhalt |
|---|---|
| Hintergrund | einfarbige Füllung je Darstellung: hell `#DFE5F5`, dunkel `#121827` (`fill-specializations`) |
| Ebene `umschlag_hell` | Umschlag aus Entwurf B, transparenter Grund; sichtbar nur hell |
| Ebene `umschlag_dunkel` | Umschlag aus Entwurf 3, transparenter Grund; sichtbar nur dunkel |
| Glas | Transparenz 30 %, neutraler Schatten (Standard von Icon Composer, bewusst belassen) |

Die Ebenen (1024 px, freigestellt) liegen auch unter `AppIcons/v0.1.20_IconComposer/`.

### Korrekturen an der ersten Fassung der `.icon`-Datei

| Befund | Folge | Korrektur |
|---|---|---|
| Ebenen fest ein-/ausgeblendet (`hidden`) | auch Hell hätte den dunklen Umschlag gezeigt | Sichtbarkeit je Darstellung (`hidden-specializations`) |
| Datei im obersten Projektordner | gehörte nicht zum App-Ziel | nach `Mailwerk/` verschoben (synchronisierter Ordner) |
| `AppIcon.appiconset` mit gleichem Namen | zwei Icons namens „AppIcon“ | Asset-Katalog-Icon entfernt; `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` bleibt |
| automatische Füllung an der hellen Ebene | Bild hätte umgefärbt werden können | entfernt |

**Hinweis Farbraum:** Icon Composer speichert die Hex-Werte als Display P3, die App verwendet sRGB. Das Nebelblau im Icon kann daher minimal kräftiger wirken; bewusst belassen.

### Prüfen

- **Icon Composer:** unten zwischen Default und Dark umschalten (iOS und macOS).
- **iPhone/iPad:** Home-Bildschirm lange drücken → Bearbeiten → Anpassen → Hell/Dunkel.
- **Mac:** Systemeinstellungen → Erscheinungsbild → **Symbol- und Widget-Stil** → Dunkel. Diese Einstellung ist **getrennt** vom Erscheinungsbild „Dunkel“ der Fenster. Hängt das alte Icon im Dock: `killall Dock`.

Stolperstein beim Test: Apps mit ohnehin dunklem Icon (z. B. Firefox, Obsidian) wirken im Dock „dunkel“, obwohl der Symbol-Stil noch auf Standard steht. Maßgeblich sind Apple-Apps wie Safari oder Fotos.

---

## 4. Bug: TestFlight-App heißt „Mailwerk Dev“

**Symptom:** Auf dem iPhone hießen beide Apps „Mailwerk Dev“ – die aus Xcode installierte Dev-App und die TestFlight-App. Auf dem iPad, wo nie aus Xcode installiert wurde, hieß die TestFlight-App ebenfalls „Mailwerk Dev“.

**Ursache (belegt):** Mit dem v0.1.19-Commit `d571edb` wurde im Ziel Mailwerk auch in der **Release**-Konfiguration `INFOPLIST_KEY_CFBundleDisplayName = "Mailwerk Dev"` gesetzt (vorher `Mailwerk`). TestFlight-Builds sind Release-Builds. Typischer Auslöser: Anzeigename unter General → Display Name geändert, während alle Konfigurationen gleichzeitig bearbeitet werden. Die Share-Erweiterungen waren nicht betroffen.

**Folge:** Nur der Name war falsch. Bundle-IDs (`de.sieber-bw.Mailwerk` bzw. `.dev`), Daten und App-Gruppen blieben getrennt.

**Lösung:** Release wieder `Mailwerk`, Debug bleibt `Mailwerk Dev`. Mit dem TestFlight-Build 0.1.20 heißt die App auf allen Geräten wieder richtig; eine Neuinstallation ist nicht nötig.

**Rückfall beim ersten Upload von 0.1.20:** Beim Archivieren stand im lokalen Projekt erneut `"Mailwerk Dev"` für Release (in Xcode als nicht committete Änderung an `project.pbxproj` sichtbar). Xcode hatte die Projektdatei mit dem alten Wert zurückgeschrieben – wahrscheinlich, weil das Projekt beim Branchwechsel geöffnet war und Xcode den alten Stand im Speicher hielt.

**Vorbeugung (umgesetzt):** Der Name steht nicht mehr direkt in den Zielen, sondern wie das Bundle-Suffix in einer eigenen Projekteinstellung: `MAILWERK_DISPLAY_NAME` (Debug „Mailwerk Dev“, Release „Mailwerk“); die Erweiterungen verwenden `INFOPLIST_KEY_CFBundleDisplayName = "$(MAILWERK_DISPLAY_NAME)"`. Im Ziel Mailwerk schrieb Xcode selbst diesen Verweis erneut als festen Wert „Mailwerk Dev“ in beide Konfigurationen zurück (belegt per `git diff`; Auslöser vermutlich das Feld General → Display Name). Dort steht der Name deshalb als `CFBundleDisplayName = $(MAILWERK_DISPLAY_NAME)` in `Mailwerk/Info.plist`, ohne Build-Einstellung. Vor jedem Archivieren Xcode beenden, Branch wechseln bzw. holen, dann erst öffnen; in Source Control prüfen, dass `project.pbxproj` keine unerwarteten Änderungen hat.

---

## Geänderte Dateien (gesamte Version)

**Neu:**
- `Mailwerk/Services/RawSourceSearch.swift`
- `Mailwerk/AppIcon.icon` (`icon.json`, `Assets/umschlag_hell.png`, `Assets/umschlag_dunkel.png`)
- `AppIcons/v0.1.20_Entwuerfe/` (fünf Entwürfe, Übersicht, kleine Größe), `AppIcons/v0.1.20_IconComposer/` (Ebenen)
- Tests: `RawSourceSearchTests`

**Geändert:**
- `RawSourceView`, `MessageDetailView`, `MessageDetailHeader`, `InboxView`, `ServerMessageLoader`
- `MessageRowParty`, `SpamFilterService`
- Tests: `MessageRowPartyTests`
- Projekt: `MARKETING_VERSION` 0.1.20 (drei Ziele), Anzeigename Release `Mailwerk`

**Entfernt:**
- `Mailwerk/Assets.xcassets/AppIcon.appiconset` (ersetzt durch `AppIcon.icon`)

---

## Beobachtungen und Erkenntnisse

- **Cloud-Sitzung:** Ohne Xcode in der Cloud wird weder gebaut noch getestet – jede Lieferung erst lokal bauen (⇧⌘K, ⌘B, ⌘U). Neue Dateien erscheinen dank synchronisierter Ordner ohne Projektänderung im Ziel.
- **Grüne Haken in Xcode** fehlen nach Branchwechsel oft, obwohl „Test Succeeded“ – der Index hinkt nach. Maßgeblich ist der Report Navigator (⌘9) mit der Anzahl der Tests.
- **Dunkles App-Icon auf dem Mac** nur über Icon Composer (`.icon`), nicht über den Asset-Katalog.
- **Symbol-Stil ≠ Erscheinungsbild:** Auf iPhone und Mac werden dunkle Icons getrennt vom Dunkelmodus eingeschaltet.
- **Anzeigename je Konfiguration** prüfen, bevor ein TestFlight-Build hochgeladen wird.

---

## Gesamtstand des Projekts (Stand 18.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS und macOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`. Lokaler Projektordner auf dem Entwicklungs-Mac.
- Version **0.1.20**, **705 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkTests, MailwerkUITests.
- **Verteilung:** TestFlight (zwei Testpersonen), Upload mit „App Store Connect“. „Mailwerk Dev“ per Xcode auf iPhone und Mac. Auf dem Mac ist die produktive App noch nicht installiert.

### Funktionsumfang (bis v0.1.20)
- Unified Inbox mehrerer IMAP/SMTP-Postfächer, Abruf je Postfach ein-/ausschaltbar (je Gerät), Farben je Postfach, Absenderbilder (Kontakte, Favicons) in Liste **und Mailansicht**.
- Sammelansichten: Alle Eingänge, Ungelesen (Zähler), Mit Kennzeichnung (Zähler), Spam (alle Spam-Ordner, auch ohne Filter).
- Ordnerleiste mit Ordnerbaum, Ordner anlegen/löschen, Verschieben-Dialog, Offline-Cache (SQLite, WAL, Schema-Stufe 7, Header-Version 3, FTS5-Suchindex), Server-Abgleich, „Ältere laden“.
- Mailansicht: HTML sicher (CSP, externe Inhalte auf Knopf), Dunkelmodus, Zoom, eingebettete Bilder, Originalquelle **mit Suche**, Drucken, Teilen, Mailkopf mit Adressmenü und Absenderbild, Spam-Einschätzung in der Datumszeile.
- Verfassen: Rich-Text-Editor mit Formatierungsleiste, Anhänge, Bilder im Text, Signaturen je Postfach, Entwürfe, Absender-Regeln; `mailto:`-Links von außen (Standard-Postfach).
- Spamfilter (clientseitig): White-/Blacklist über CloudKit, Domains samt Subdomains (genauester Eintrag gewinnt), Spam-Header `X-Spam`, `X-Spam-Flag`, `X-Spam-Status`, Whitelist schlägt Server-Einstufung, Blockieren/Vertrauen je Mail (Adresse, Domain, Hauptdomain), Listen bearbeiten, exportieren, importieren.
- Suche (lokal, Namen, Server), Sortierung, Mehrfachauswahl, Kontextmenü, Rückgängig-Balken, eigene untere Leiste (Liquid Glass).
- Teilen mit Mailwerk (Erweiterungen iOS und Mac).
- Anmeldung: Passwort (manitu, GMX, web.de, Posteo, Gmail mit App-Passwort) und OAuth 2 (Outlook.com).
- **App-Icon** aus Icon Composer: hell Nebelblau mit Button-Blau, dunkel Nachtblau negativ – iPhone, iPad, Mac.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, MemberImportVisibility; iOS/macOS 26.5. Xcode 27.1, macOS 27.0.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage).
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Refresh-Tokens: iCloud-Schlüsselbund; Filterlisten und Signaturen: SwiftData/CloudKit (`iCloud.de.sieber-bw.Mailwerk`, Development und Production); Abruf-Schalter: UserDefaults (je Gerät).
- Test/Produktion: Bundle-Suffix `.dev` für „Mailwerk Dev“ (eigene App-Gruppe, eigener Key-Value-Speicher, CloudKit Development); Anzeigename über `MAILWERK_DISPLAY_NAME` (Debug „Mailwerk Dev“, Release „Mailwerk“).
- App-Icon: `Mailwerk/AppIcon.icon` (Icon Composer), kein `AppIcon.appiconset` mehr.

### Arbeitsregeln (verbindlich)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher abstimmen.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen; klare Anweisungen mit genauem Menüpfad.
- Ursache belegen, nicht raten (Rohdaten, Server-Dialog, Quelltext, Console, Git-Historie).
- **Lokale Sitzung:** Lieferung als ganze Dateien in den Projektordner (Prüfsummen, Tabelle *Datei · Ort · Art*); Git im Projektordner nur lesend; Claude committet nicht, Commit-Text wird mitgeliefert.
- **Cloud-Sitzung (neu seit v0.1.20):** Claude arbeitet auf einem eigenen Branch, committet und pusht dort; geholt wird lokal per `git fetch` / `git switch <branch>` bzw. `git pull`, gebaut und getestet in Xcode; Übernahme nach `main` per Pull Request.
- Projekteinstellungen, die sich nur in Xcode oder Icon Composer ändern lassen, manuell nach Anleitung.
- Inline-Doku: Datei-Header (Zweck, Abgrenzung, Abhängigkeiten), DocC je Funktion, Deutsch, keine Versionsverweise.
- Öffentliche Dokumentation ohne persönliche Bezüge (siehe `CLAUDE.md`); Arbeitsdokumente in `Documentation/Intern/`.
- Keine Sonderlösungen für einzelne Anbieter; Gestaltung mit Apple-Bausteinen, eigene Anordnungen als USP erlaubt.
- Tests dürfen keine Produktivmails verändern – Tests mit den Testpostfächern in „Mailwerk Dev“.
- Arbeitszeit sparen: kleine Änderungen mit dem nächsten Paket gemeinsam testen und committen.

### Offene Punkte
- **Default Mail App:** Antwort von Apple abwarten; danach Capability „Default Mail App“ an `de.sieber-bw.Mailwerk` einrichten, neuen Build hochladen; Test-Postfach für Apple löschen.
- **Mac:** produktive „Mailwerk“ (TestFlight) noch nicht installiert.
- **Azure-Probephase:** nach Ablauf Outlook in „Mailwerk Dev“ neu anmelden; vor App Store Herausgeber-Verifizierung.
- **`mailto:`-Randfall:** bei offener QuickLook-Vorschau oder Rückfrage kann das Fenster ausbleiben – beobachten.
- **Spam:** Prüfung mit neu eingehender GMX/web.de-Mail eines Whitelist-Absenders mit `X-Spam-Flag: YES` steht noch aus.
- **App-Icon:** Wirkung des Glas-Effekts und der P3-Farben im Alltag beobachten; ggf. Glas abschalten.
- **Gmail per OAuth:** nur vorgemerkt.
- **Kopfdaten außerhalb des Zeitfensters nachfüllen (Weg B):** per „Ältere laden“ geholte Mails mit veralteter Header-Version werden nie nachgefüllt.
- **H6:** Verbindungen je Konto wiederverwenden (ggf. mit Push/IDLE); **N14:** Offline-Warteschlange.
- **Ordner abonnieren:** in Mailwerk angelegte Ordner werden nicht abonniert (SwiftMail ohne SUBSCRIBE).
- **DKIM/Authentication-Results** für Logos und Spam-Prüfung.
- **Sporadischer Gmail-Timeout** – beobachten.
- **Suchfeld unten**, sobald iOS es ohne zweiten Suchknopf erlaubt.
- **Teilen:** große Videos ungetestet; HEIC als Original; Mac-Gestaltung vorläufig.
- **Strukturempfehlungen:** Protokolle/Injektion für Tests ohne Server, SwiftLint/SwiftFormat, Lokalisierung.
- Sonstiges: Empfangsdatum statt Kopfdatum nur bei Bedarf; Originalquelle > 5 MB nicht möglich; Logo-Breite einfacher Signatur fest 150 pt; Titel-Mindestbreite iPad/Querformat beobachten.

### Fahrplan
- **Nächste Version (v0.1.21):** noch festzulegen.
- **v0.2.x:** Seitenleiste und Layout für iPad und Mac, Gestaltung der Teilen-Erweiterung auf dem Mac.
- **Später:** H6, Push/IDLE, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung (Default Mail App, Herausgeber-Verifizierung Microsoft, Datenschutzangaben).
