# Mailwerk – Entwicklungsdokumentation v0.1.19

2026-10-18 · „Spam und Optik“ (Teil 1): App-Icon in App Store Connect, Mailwerk als Standard-Mail-App (mailto:), Domain-Einträge samt Subdomains, Hauptdomain im Spam-Menü, Spam-Einschätzung in Liste und Mailansicht, `X-Spam-Flag`, Whitelist schlägt die Server-Einstufung

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen.

---

## Zusammenfassung

v0.1.19 war als Sammelversion „Spam und Optik“ mit neun Jira-Vorgängen geplant. Umgesetzt bzw. erledigt wurden fünf; die übrigen gehen in die nächste Version.

| Jira | Inhalt | Ergebnis | Commit |
|---|---|---|---|
| MW-39 | App Store Connect: App-Icon fehlt | kein Code – erledigt durch Upload mit „App Store Connect“ statt „TestFlight Internal Only“ | – |
| MW-38 | Mailwerk unter Standard-Apps nicht auswählbar | `mailto:`-Schema + Annahme von Links; Antrag bei Apple gestellt | `d571edb` |
| MW-32 + MW-28 | Domain-Einträge samt Subdomains; Hauptdomain im Spam-Menü | umgesetzt (gemeinsam) | `40d70a9` |
| MW-30 | Anzeige der Spam-Einschätzung | umgesetzt, mit Regeländerungen (`X-Spam-Flag`, Whitelist) | `f2391ca` |
| MW-27 | Schieberegler Score mit automatischem Verschieben | **verworfen** (siehe Abschnitt 5) | – |
| MW-31, MW-33, MW-34 | Icon in Mailansicht, App-Icon Nebelblau, App-Icon Dunkelmodus | → nächste Version | – |

Tests: 651 → **698** Testfunktionen (`@Test`, 47 neu), alle grün. `MARKETING_VERSION` 0.1.19 in allen drei Zielen.

---

## 1. MW-39: App-Icon in App Store Connect

**Symptom:** In der App-Übersicht von App Store Connect stand Mailwerk ohne Icon (Platzhalter-Raster), MySmartGarden und GymGuard mit Icon.

**Prüfung Repo:** Icon korrekt eingerichtet – `AppIcon.appiconset` mit 1024×1024 für iOS (deckend) und allen Mac-Größen, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Im Dialog „Build hinzufügen“ zeigten die Builds das Icon bereits.

**Ursache (belegt):** App Store Connect zeigt das Icon des Builds, der der App-Store-Version zugeordnet ist. Die Version „1.0 In Vorbereitung“ hatte keinen Build. Die vorhandenen Builds waren mit **„TestFlight Internal Only“** hochgeladen – solche Builds sind dauerhaft nur für interne Tests nutzbar und lassen sich keiner App-Store-Version zuordnen (auch nach Anpassen der Versionsnummer nicht).

**Lösung:** Upload künftig immer mit **„App Store Connect“** (Product → Archive → Distribute App). Der Build läuft genauso für interne TestFlight-Tester, ist aber auch extern und für den App Store nutzbar. Mit dem Upload von 0.1.19 erscheint das Icon in App Store Connect.

---

## 2. MW-38: Mailwerk als Standard-Mail-App

### Voraussetzungen (Apple, belegt)

Die Auswahl unter *Einstellungen → Apps → Standard-Apps → E-Mail* verlangt die verwaltete Berechtigung `com.apple.developer.mail-client`. Sie wird **nicht** unter „Capability Requests“ beantragt (dort gibt es nur „Default Web Browser“), sondern über ein eigenes Formular:

- Formular: `https://developer.apple.com/contact/request/default-mail-client` (Rolle Account Holder)
- Bedingungen: `mailto:` in der Info.plist; Senden an jeden gültigen Empfänger; beim Aufruf eines `mailto:`-Links ein Verfassen-Fenster mit vorbelegtem Empfänger; Empfang von jedem Absender (vom Nutzer gesteuerte Filter erlaubt – der Spamfilter ist zulässig).
- Gilt für iOS/iPadOS je App-ID (`de.sieber-bw.Mailwerk`, nicht `.dev`). Auf dem Mac keine Berechtigung nötig – Auswahl in Apple Mail → Einstellungen → Allgemein → Standard-E-Mail-Programm (im Finder-Dialog erscheint die Dev-Version als „Mailwerk.app“).

**Antrag:** nach erfolgreichem Test gestellt. Dafür ein eigenes Test-Postfach (50 MB, ohne Portalrechte) angelegt; es wird nach Apples finaler Antwort gelöscht. Nach der Freigabe muss die Capability „Default Mail App“ an der App-ID eingerichtet und ein neuer Build hochgeladen werden.

### Entscheidungen

| Frage | Entscheidung |
|---|---|
| Absender bei Link von außen | Immer das **Standard-Postfach**; ohne Standard-Postfach bleibt der Absender leer |
| Fenster bereits offen (z. B. angefangene Mail) | Link wird **vorgemerkt**, Verfassen-Fenster öffnet nach dem Schließen; bei mehreren Links gilt nur der letzte |
| Noch kein Postfach eingerichtet | Alert „Kein Postfach eingerichtet“; Link wird verworfen |

### Umsetzung

| Datei | Inhalt |
|---|---|
| `Info.plist` (App) | `CFBundleURLTypes` mit Schema `mailto`, Rolle Editor |
| `ExternalMailtoRouter.swift` (neu, Services) | Wartender Link (nur der letzte), Zähler offener Fenster, Abholen mit Ergebnis „Verfassen“ bzw. „kein Postfach“ |
| `ExternalMailtoPresenter.swift` (neu, Views) | Modifier `countsAsOpenWindow()` für jedes Blatt; Verfassen-Fenster bzw. Alert, 500 ms nach dem Schließen des letzten Blatts (sonst übergeht SwiftUI das neue Blatt) |
| `MailwerkApp` | `onOpenURL` → Router; `handlesExternalEvents` (Mac: Link im vorhandenen Fenster) |
| `ContentView` | Verfassen-Fenster für Links von außen an der Wurzel (hält InboxView frei) |
| `InboxView`, `MessageDetailView`, `AccountListView` | Alle Blätter melden sich als offen |

`MailtoLink` und die Vorbelegung im Verfassen-Fenster (An, Cc, Bcc, Betreff, Text) gab es schon und blieben unverändert.

**Randfall (bewusst akzeptiert):** Ist gerade die QuickLook-Vorschau oder eine Rückfrage offen, kann das Fenster für den Link ausbleiben – Link erneut antippen.

**Test:** `xcrun simctl openurl booted "mailto:…"` im Simulator (Vorbelegung, Warten auf offenes Fenster), Mac mit Mailwerk Dev als Standard-Mail-Programm.

**Nebenbefund:** Die Warnung „CFBundleShortVersionString of an app extension (0.1.19) must match … parent app (0.1.18)“ – Version war nur in MailwerkShare angehoben; in den Zielen Mailwerk und MailwerkShareMac nachgezogen.

---

## 3. MW-32 + MW-28: Domains samt Subdomains, Hauptdomain im Menü

### Entscheidungen

| Frage | Entscheidung |
|---|---|
| Wirkung eines Domain-Eintrags | `apple.com` trifft `x@apple.com`, `x@mail.apple.com`, `x@a.mail.apple.com` – **nicht** `x@badapple.com` (Vergleich an der Punkt-Grenze) |
| Wirkung auf bestehende Listen | Bewusst: alle vorhandenen Domain-Einträge gelten ab sofort auch für Subdomains |
| Verschachtelte Einträge (`mail.apple.com` und `apple.com`) | redundant, unschädlich, keine Prüfung |
| Vorrang | **Der genaueste Eintrag gewinnt:** Adresse vor längster Domain vor kürzerer Domain; je Stufe Whitelist vor Blacklist. Beispiel Whitelist `apple.com` + Blacklist `news.apple.com` → Mails von `news.apple.com` sind Spam, übrige Apple-Mails nicht |
| Konfliktprüfung | Unverändert nur gleicher Wert auf der anderen Liste |
| Schreibweise in Liste, Menü, Export | `*apple.com` – `*` steht für „Punkt oder @ davor“ (wie im manitu-Portal: `*apple.com` schließt Subdomains ein, `*@apple.com` dort nur die exakte Domain) |
| Eingabe (manuell, Bearbeiten, Import) | `apple.com`, `*apple.com`, `*.apple.com`, `*@apple.com`, `@apple.com` – alle als Domain samt Subdomains (ältere Exporte bleiben lesbar) |
| Länderendungen (`com`, `co.uk`, `com.au` …) | wie TLD behandelt, **nie** als Domain eintragbar oder im Menü angeboten |
| Spam-Menü | Abschnitte `x@mail.apple.com`, `*mail.apple.com` und – **nur bei Subdomain** – `*apple.com`, je mit Blockieren/Vertrauen |
| Export | Domains als `*apple.com` (ohne `@`) |

### Umsetzung

- **`FilterDomain.swift` (neu):** alle Domain-Regeln an einer Stelle – Schreibweise, Länderendungen, Normalisieren der Listeneingabe (`listable`), Kandidaten für den Abgleich (`matchCandidates`, bis zur Hauptdomain), Hauptdomain für das Menü, Listenwert aus dem Menü (`entryValue`). Hauptdomain über die bestehende Kürzung der Absenderbilder (`SenderDomain`, eine Liste zweiteiliger Endungen).
- **`SpamClassifier`:** Abgleich über die Domain-Kette, genauester Eintrag zuerst. Gilt automatisch für Filter, externe Inhalte und Absenderbilder.
- **`FilterListInput`, `FilterListRules`, `FilterListExporter`, `FilterListImport`, `FilterListEditing`, `FilterListView`:** neue Schreibweisen, Anzeige `*…`, Hilfetexte.
- **`MessageMenu` (`SpamMenuSection`), `MessageActionDialogs`, `SpamFilterService`:** dritter Abschnitt, Rückfragen in Listenschreibweise („… dieser Domain und ihrer Subdomains“).

### Sicherheit

- **Platzhalter nur in der Listeneingabe:** `FilterAddress.normalizedDomain` (prüft auch Absender-Domains) akzeptiert weiterhin nur `*@`/`@`. Ein gefälschter Absender `x@*apple.com` wird nicht zu `apple.com` und kann keine Whitelist umgehen (Test).
- **Menü → Liste:** Der Dienst trägt einen Wert aus dem Menü nur ein, wenn er zum Absender passt (Adresse, Domain oder übergeordnete Domain bis zur Hauptdomain).

**Test-Fund:** Der alte Test `exactDomainMatch` erwartete „Subdomain trifft nicht“ – auf „ähnliche Domains treffen nicht“ (`evil-firma.de`, `firma.de.evil.com`) reduziert.

---

## 4. MW-30: Spam-Einschätzung anzeigen – mit Regeländerungen

### Befund: Spam-Kopfzeilen der Anbieter (Stichprobe über „Originalquelle“)

| Anbieter | Kopfzeile | Score |
|---|---|---|
| manitu (fremde Absender) | `X-Spam-Status: Yes/No, score=…` | ja |
| manitu (Absender von manitu-Domains) | keine | – |
| GMX, web.de | `X-Spam-Flag: YES/NO` | nein |
| Gmail | keine | – |
| Outlook | kein eindeutiger Eintrag | – |

`X-Spam-Flag` wurde bisher **nicht** ausgewertet (per Test festgelegt). Groß-/Kleinschreibung des Werts schwankt (yes/Yes/YES), ebenso Leerzeichen.

### Entscheidungen

| Frage | Entscheidung |
|---|---|
| `X-Spam-Flag` | wird ausgewertet, gleichwertig zu `X-Spam` / `X-Spam-Status`: Spam, wenn irgendeine dieser Zeilen mit „Yes“ beginnt; ohne Groß-/Kleinschreibung, Leerzeichen um Wert und `score=` egal |
| **Whitelist gegen Server** | **Whitelist schlägt die Server-Einstufung immer**, auch „Yes“ ohne Score (Anlass: GMX/web.de markieren Mails von einer eigenen Domain als Spam). Nur ein **gelieferter** Score **bei oder über** der Obergrenze übersteuert die Whitelist (Schutz gegen gefälschte Absender) |
| Neubewertung | nur neu eintreffende Mails; keine Neubewertung bei Regeländerungen |
| Anzeige Liste | nur `[SPAM]`, klein und grau **nach den Symbolen** (Kennzeichnung/Anhang bleiben an fester Stelle), Datum rechts unverändert, nie gekürzt |
| Anzeige Mailansicht | rechtsbündig in der Datumszeile (Datum links) |
| Grundlage | Gesamtergebnis wie beim Filter: aktuelle Listen + beim Abruf gespeicherter Server-Befund; die Anzeige folgt Listenänderungen, verschoben wird dadurch nichts |

Anzeigeregel:

| Gesamtergebnis | Score | Liste | Mailansicht |
|---|---|---|---|
| Spam | ja | `[SPAM]` | `[SPAM score=7.2]` |
| Spam | nein | `[SPAM]` | `[SPAM]` |
| kein Spam | ja | – | `[NoSpam score=2.1]` |
| kein Spam durch Whitelist | nein | – | `[NoSpam]` |
| kein Spam, ohne Whitelist | nein | – | – |

`[NoSpam]` erscheint bei **jedem** Whitelist-Treffer, der die Mail behält – auch bei Gmail und bei Mails ohne gespeicherten Befund (Serversuche). „NoSpam“ in gemischter Schreibweise wirkt bewusst nicht wie eine Warnung. Ein Score über der Obergrenze ergibt `[SPAM score=…]`, nicht `[NoSpam]`.

Verlauf: Zunächst stand der Score auch in der Liste (`[score=2.1]`) – nach dem Test zurückgenommen („nur für den Spezialisten“); Mailansicht um „NoSpam“ ergänzt, damit der Score erkennbar zur Spam-Prüfung gehört.

### Umsetzung

| Datei | Inhalt |
|---|---|
| `SpamHeaderParser` | `X-Spam-Flag` in Feldliste und Auswertung |
| `SpamClassifier` | `whitelisted`: ohne Score immer behalten; `isWhitelisted(_:in:)` neu |
| `SpamMark.swift` (neu) | Texte in zwei Darstellungen (`.list`, `.detail`) |
| `MessageStore` | `currentHeadersVersion` 2 → **3**: beim nächsten Abruf eines Ordners wird die Spam-Angabe vorhandener Mails im Zeitfenster nachgefüllt (inkl. `X-Spam-Flag`), ohne zusätzliche Server-Abfrage |
| `InboxViewModel`, `InboxView`, `MessageRow` | Anzeige in der Liste |
| `SpamFilterService` (`spamMark`), `MessageDetailView`, `MessageDetailHeader` | Anzeige in der Mailansicht |

---

## 5. MW-27 verworfen: eigene Score-Schwelle

**Idee:** eigene Schwelle in der App, unabhängig von der Server-Einstufung – Steuerung server- und anbieterübergreifend in die App holen.

**Bewertung (gemeinsam):**
- Ein Score kommt praktisch nur von manitu (fremde Absender). GMX/web.de liefern nur YES/NO, Gmail nichts, Outlook nichts Eindeutiges.
- Scores sind zwischen Systemen nicht vergleichbar (SpamAssassin um 5, rspamd um 6, Ablehnung um 15).
- Sicherheitsrisiko: Ein Absender kann einen eigenen niedrigen Score mitschicken.

**Entscheidung:** Wunsch fallen gelassen („zu sehr Stückwerk“). Mailwerk verlässt sich auf **Black-/Whitelist** und die **Einschätzung des Servers**; die Whitelist hat Vorrang (Abschnitt 4).

### Gesamtregel des Spamfilters (Stand v0.1.19)

Nur Posteingang, nur noch nicht geprüfte Mails, Filter eingeschaltet:

1. Blacklist (genauester Treffer) → Spam-Ordner
2. Whitelist (genauester Treffer) → bleibt, außer ein gelieferter Score ≥ Obergrenze (Standard 15)
3. Server „Yes“ (`X-Spam`, `X-Spam-Flag`, `X-Spam-Status`) → Spam-Ordner
4. sonst bleibt die Mail. Mails im Spam-Ordner holt Mailwerk nie von selbst zurück.

---

## Geänderte Dateien (gesamte Version)

**Neu:**
- `Mailwerk/Services/ExternalMailtoRouter.swift`, `Mailwerk/Views/ExternalMailtoPresenter.swift`
- `Mailwerk/Services/Spam/FilterDomain.swift`, `Mailwerk/Services/Spam/SpamMark.swift`
- Tests: `ExternalMailtoRouterTests`, `FilterDomainTests`, `SpamMarkTests`

**Geändert:**
- `Mailwerk/Info.plist`, `MailwerkApp`, `ContentView`
- `FilterAddress`, `FilterListInput`, `FilterListRules`, `FilterListExporter`, `FilterListImport`, `FilterListEditing`, `SpamClassifier`, `SpamFilterService`, `SpamHeaderParser`
- `MessageStore`, `MailFetchService` (Doku), `CachedMessage` (Doku)
- `InboxViewModel`, `InboxView`, `MessageRow`, `MessageDetailView`, `MessageDetailHeader`, `MessageMenu`, `MessageActionDialogs`, `FilterListView`, `AccountListView`
- Tests: `FilterAddressTests`, `FilterListExporterTests`, `FilterListInputTests`, `MessageMenuTests`, `SpamClassifierTests`, `SpamHeaderParserTests`
- Projekt (manuell in Xcode): `MARKETING_VERSION` 0.1.19 in Mailwerk und MailwerkShareMac

---

## Beobachtungen und Erkenntnisse

- **„TestFlight Internal Only“ sperrt Builds** dauerhaft für App Store und externe Tests. Immer „App Store Connect“ wählen.
- **Default Mail App:** eigenes Antragsformular, nicht „Capability Requests“. Apples Dokumentations-URL „preparing-your-app-to-be-the-default-mail-app“ existiert nicht mehr; maßgeblich ist die Seite der Berechtigung `com.apple.developer.mail-client`.
- **Spam-Kopfzeilen sind nicht einheitlich** (siehe Tabelle Abschnitt 4); ein Score ist die Ausnahme.
- **Platzhalter-Schreibweise:** `*domain` = Domain samt Subdomains, `*@domain` = nur exakt (manitu und andere Blacklists).
- Ablauf bewährt: Dateien direkt in den Projektordner mit Prüfsummen vor und nach dem Ablegen.

---

## Gesamtstand des Projekts (Stand 18.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS und macOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`. Lokaler Projektordner auf dem Entwicklungs-Mac.
- Version **0.1.19**, **698 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkTests, MailwerkUITests.
- **Verteilung:** TestFlight (zwei Testpersonen), ab 0.1.19 mit „App Store Connect“ hochgeladen. „Mailwerk Dev“ per Xcode auf iPhone und Mac. Auf dem Mac ist die produktive App noch nicht installiert.

### Funktionsumfang (bis v0.1.19)
- Unified Inbox mehrerer IMAP/SMTP-Postfächer, Abruf je Postfach ein-/ausschaltbar (je Gerät), Farben je Postfach, Absenderbilder (Kontakte, Favicons).
- Sammelansichten: Alle Eingänge, Ungelesen (Zähler), Mit Kennzeichnung (Zähler), Spam (alle Spam-Ordner, auch ohne Filter).
- Ordnerleiste mit Ordnerbaum, Ordner anlegen/löschen, Verschieben-Dialog, Offline-Cache (SQLite, WAL, Schema-Stufe 7, Header-Version 3, FTS5-Suchindex), Server-Abgleich, „Ältere laden“.
- Mailansicht: HTML sicher (CSP, externe Inhalte auf Knopf), Dunkelmodus, Zoom, eingebettete Bilder, Originalquelle, Drucken, Teilen, Mailkopf mit Adressmenü, **Spam-Einschätzung** in der Datumszeile.
- Verfassen: Rich-Text-Editor mit Formatierungsleiste, Anhänge, Bilder im Text, Signaturen je Postfach, Entwürfe, Absender-Regeln; **`mailto:`-Links von außen** (Standard-Postfach).
- Spamfilter (clientseitig): White-/Blacklist über CloudKit, **Domains samt Subdomains** (genauester Eintrag gewinnt), Spam-Header `X-Spam`, **`X-Spam-Flag`**, `X-Spam-Status`, **Whitelist schlägt Server-Einstufung**, Blockieren/Vertrauen je Mail (Adresse, Domain, **Hauptdomain**), Listen bearbeiten, exportieren (`*domain`), importieren; funktioniert auch ohne eigene IMAP-Schlüsselwörter.
- Suche (lokal, Namen, Server), Sortierung, Mehrfachauswahl, Kontextmenü, Rückgängig-Balken, eigene untere Leiste (Liquid Glass).
- Teilen mit Mailwerk (Erweiterungen iOS und Mac).
- Anmeldung: Passwort (manitu, GMX, web.de, Posteo, Gmail mit App-Passwort) und OAuth 2 (Outlook.com).

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, MemberImportVisibility; iOS/macOS 26.5. Xcode 27.1, macOS 27.0.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage).
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Refresh-Tokens: iCloud-Schlüsselbund; Filterlisten und Signaturen: SwiftData/CloudKit (`iCloud.de.sieber-bw.Mailwerk`, Development und Production); Abruf-Schalter: UserDefaults (je Gerät).
- Test/Produktion: Bundle-Suffix `.dev` für „Mailwerk Dev“ (eigene App-Gruppe, eigener Key-Value-Speicher, CloudKit Development).

### Arbeitsregeln (verbindlich, unverändert)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher mit Leitfragen (einzeln, mit Empfehlung) abstimmen.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen; klare Anweisungen mit genauem Menüpfad.
- Ursache belegen, nicht raten (Rohdaten, Server-Dialog, Quelltext, Console).
- Lieferung als ganze Dateien direkt in den Projektordner (frischer Zwischenpfad, Prüfsummen vor und nach dem Ablegen, Tabelle *Datei · Ort · Art*); Git im Projektordner nur lesend; Projekteinstellungen werden manuell in Xcode nach Anleitung geändert.
- **Claude committet nie** – Commit-Text mitliefern; der Commit erfolgt manuell in Xcode.
- Inline-Doku: Datei-Header (Zweck, Abgrenzung, Abhängigkeiten), DocC je Funktion, Deutsch, keine Versionsverweise.
- Keine Sonderlösungen für einzelne Anbieter; Gestaltung mit Apple-Bausteinen, eigene Anordnungen als USP erlaubt.
- Tests dürfen keine Produktivmails verändern – Tests mit den Testpostfächern in „Mailwerk Dev“.
- Arbeitszeit sparen: kleine Änderungen mit dem nächsten Paket gemeinsam testen und committen.

### Offene Punkte
- **Default Mail App:** Antwort von Apple abwarten; danach Capability „Default Mail App“ an `de.sieber-bw.Mailwerk` einrichten, neuen Build hochladen; Test-Postfach für Apple löschen. Fragt Apple nach der App: externe TestFlight-Gruppe anlegen (Beta-Prüfung).
- **Mac:** produktive „Mailwerk“ (TestFlight) noch nicht installiert.
- **Azure-Probephase:** nach Ablauf Outlook in „Mailwerk Dev“ neu anmelden; bei Problemen Pay-As-You-Go. Vor App Store: Herausgeber-Verifizierung.
- **`mailto:`-Randfall:** bei offener QuickLook-Vorschau oder Rückfrage kann das Fenster ausbleiben – beobachten.
- **Spam:** Prüfung mit neu eingehender GMX/web.de-Mail eines Whitelist-Absenders mit `X-Spam-Flag: YES` steht noch aus (nur mit neuen Mails möglich).
- **Gmail per OAuth:** nur vorgemerkt.
- **Kopfdaten außerhalb des Zeitfensters nachfüllen (Weg B):** per „Ältere laden“ geholte Mails mit veralteter Header-Version werden nie nachgefüllt – betrifft jetzt auch die Spam-Angabe (Header-Version 3).
- **H6:** Verbindungen je Konto wiederverwenden (ggf. mit Push/IDLE); **N14:** Offline-Warteschlange.
- **Ordner abonnieren:** in Mailwerk angelegte Ordner werden nicht abonniert (SwiftMail ohne SUBSCRIBE).
- **DKIM/Authentication-Results** für Logos und Spam-Prüfung.
- **Sporadischer Gmail-Timeout** (IMAP, Spam-Ordner in der Runde) – beobachten.
- **Suchfeld unten**, sobald iOS es ohne zweiten Suchknopf erlaubt.
- **Teilen:** große Videos ungetestet; HEIC als Original; Mac-Gestaltung vorläufig.
- **Strukturempfehlungen:** Protokolle/Injektion für Tests ohne Server, SwiftLint/SwiftFormat, Lokalisierung.
- Sonstiges: Empfangsdatum statt Kopfdatum nur bei Bedarf; Inline-Foto ohne Verweis bei einzelnem HTML-Teil beobachten; Originalquelle > 5 MB nicht möglich; Logo-Breite einfacher Signatur fest 150 pt; Titel-Mindestbreite iPad/Querformat beobachten.

### Fahrplan
- **Nächste Version (v0.1.20):** Rest aus „Spam und Optik“ – **MW-31** (Icon aus der Liste auch in der Mailansicht), **MW-33** (App-Icon: Hintergrund Nebelblau, Test Briefumschlag in Button-Blau), **MW-34** (App-Icon Dunkelmodus); weitere Punkte noch festzulegen.
- **v0.2.x:** Seitenleiste und Layout für iPad und Mac (viele Ideen vorhanden), Gestaltung der Teilen-Erweiterung auf dem Mac.
- **Später:** H6, Push/IDLE, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung (Default Mail App, Herausgeber-Verifizierung Microsoft, Datenschutzangaben).
