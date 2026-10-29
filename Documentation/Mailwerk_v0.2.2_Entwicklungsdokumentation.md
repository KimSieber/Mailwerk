# Mailwerk – Entwicklungsdokumentation v0.2.2

2026-10-24 · „Sprachen“: Übersetzung fremdsprachiger Mails mit Apples on-device-Übersetzung – dazu Erreichbarkeit je Postfach statt einer falschen „Keine Verbindung“-Meldung, Untertitel auf dem Mac und Erklärungen der Postfach-Zeichen

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen.

---

## Zusammenfassung

v0.2.2 bietet für Mails in fremder Sprache einen Knopf „‹Sprache› übersetzen“. Übersetzt werden Betreff und Text, nur für die Anzeige. Im zweiten Teil wurde ein gemeldeter Fehler behoben: Die Titelzeile meldete immer wieder „Keine Verbindung“, obwohl das Netz da war. Ursache war, dass ein einzelner gescheiterter Abruf die ganze Ansicht markierte; jetzt gilt die Erreichbarkeit je Postfach und ist am Postfach selbst sichtbar.

| Stufe | Inhalt |
|---|---|
| **a** | Übersetzung: Spracherkennung, Hinweis mit Knopf, Übersetzung von Betreff und Text, „Original anzeigen“; Erkennung bei Weiterleitungen und Newslettern abgesichert |
| **b** | Erreichbarkeit je Postfach (gelbes Warnzeichen, Titelzeile, Watch); Untertitel auf dem Mac; Kreisel im Aktualisieren-Knopf (Mac); Erklärung aller Postfach-Zeichen per Tooltip bzw. Sprechblase |

| Bereich | Ergebnis |
|---|---|
| Fremdsprachige Mail | Hinweis „‹Sprache› übersetzen“ unter einem eventuellen Hinweis auf externe Inhalte |
| Übersetzung | Betreff und Text auf Deutsch, Text als reiner Text; „Original anzeigen“ zurück; nichts gespeichert |
| Sprachen | alle, die Apples Übersetzung nach Deutsch kennt; sonst kein Hinweis |
| Postfach nicht erreichbar | gelbes Warndreieck in Ordnerleiste und Postfachliste; Titelzeile nennt das Postfach |
| Watch | je nicht erreichbarem Postfach eine Zeile |
| Mac | Stand und Verbindungshinweis als Untertitel des Fensters; Kreisel im Aktualisieren-Knopf |
| Postfach-Zeichen (rot, gelb, orange) | Mac/Trackpad: Tooltip; iPhone/iPad: Tipp öffnet Sprechblase mit Erklärung |

Tests: 759 → **781** Testfunktionen (`@Test`, 22 neu), alle grün. Version **0.2.2 (Build 1)**. Gebaut und getestet auf iPhone (echtes Gerät) und Mac. iPad und Watch sind erst über TestFlight prüfbar (Abschnitt 8).

| Commit | Inhalt |
|---|---|
| `604f644` | v0.2.2a – Übersetzung fremdsprachiger Mails |
| (dieser) | v0.2.2b – Erreichbarkeit je Postfach, Mac-Untertitel, Erklärung der Zeichen, Doku |

---

## 1. Anforderungen und Entscheidungen

### 1.1 Übersetzung

| Thema | Entscheidung |
|---|---|
| Auslöser | Text der Mail (nicht der Betreff) überwiegend nicht deutsch |
| Bedienung | schmaler Hinweis mit Knopf „‹Sprache› übersetzen“, gestaltet wie „Externe Inhalte blockiert“ |
| Umfang | Betreff **und** Text |
| Rückweg | „Original anzeigen“; erneutes Umschalten ohne neue Übersetzung |
| Speicherung | keine – nur Anzeige, ein Mailwechsel verwirft die Übersetzung |
| Formatierung | zweitrangig; der übersetzte Text erscheint als reiner Text |
| Dienst | **Apples on-device-Übersetzung** (Translation-Framework), kostenlos, ohne Konto, ohne Einrichtung |
| Zweiter Dienst | zurückgestellt (siehe unten) |

**Verworfene Wege:**

| Weg | Grund |
|---|---|
| DeepL mit einem zentralen Schlüssel | Die App geht in den App Store; alle Nutzer hingen an einem einzigen Kontingent und an dessen Kosten |
| DeepL mit eigenem Schlüssel je Nutzer | Es gibt keinen dauerhaft kostenlosen API-Zugang mehr, nur kostenpflichtige Tarife |
| Zweiter Dienst jetzt vorbereiten | bewusst nicht: Die Wahl eines zweiten Dienstes (für Sprachen, die Apple nicht übersetzt, z. B. Isländisch) folgt nach eigener Marktrecherche als eigenes Thema; im Code gibt es dafür keine Vorbereitung |

### 1.2 Erreichbarkeit der Postfächer

| Thema | Entscheidung |
|---|---|
| Gültigkeit | je Postfach, nicht je Ansicht |
| Was zählt | Abruf des Posteingangs bzw. eines Ordners; **nicht** der Spamfilter und nicht ein allein gescheiterter Spam-Ordner |
| Ende | beim nächsten erfolgreichen Abruf des Postfachs; gilt nur für die laufende Sitzung |
| Ohne Netz | keine Markierung; die Titelzeile zeigt „Offline“ |
| Hinweis am Postfach | gelbes Warndreieck in Ordnerleiste und Postfachliste |
| Titelzeile | „Keine Verbindung“ nur, wenn alle Postfächer der Ansicht scheiterten; sonst Name bzw. Anzahl |
| Watch | je Postfach eine Zeile – Transparenz auch dort |
| Abrufe im Hintergrund (Watch) | keine Sonderbehandlung: Scheitert ein Postfach, ist der Hinweis wahr |
| Erklärung der Zeichen | Mac: Tooltip (Standard); iOS: Tipp öffnet Sprechblase (Popover, Apples übliche Form auf Touch-Geräten); gilt für alle drei Zeichen |

---

## 2. Übersetzung (v0.2.2a)

### 2.1 Ablauf

1. Beim Öffnen der Mail erkennt `MessageLanguage` die Sprache des Texts (`NLLanguageRecognizer`) und prüft mit `LanguageAvailability`, ob Apple das Sprachpaar nach Deutsch übersetzt. Die Prüfung braucht kein Netz, auch wenn das Sprachmodell noch nicht geladen ist. Läuft einmal je Anzeige, parallel zur Entscheidung über externe Inhalte.
2. Deutsch, zu wenig Text (unter 20 Zeichen) oder ein nicht unterstütztes Sprachpaar ergeben keinen Hinweis.
3. Ein Tipp auf den Knopf setzt `translationConfiguration`; SwiftUI startet darauf `.translationTask` mit einer `TranslationSession`. Betreff und Text gehen in **einer** Anfrage (`translations(from:)`), damit ein nötiger Download des Sprachmodells nur einmal anfällt.
4. Der übersetzte Betreff ersetzt im Kopf das Original; der Text erscheint als reiner Text statt des HTML. Der Hinweis auf externe Inhalte entfällt dabei (die Übersetzung hat kein HTML).
5. Scheitert die Übersetzung: „Übersetzung fehlgeschlagen“ mit „Erneut versuchen“, das Original bleibt stehen.

Zustand des Hinweises (`TranslationNoticeState`): Angebot, wird übersetzt, übersetzt (mit „Original anzeigen“), fehlgeschlagen.

### 2.2 Absicherung der Erkennung

Beim Test fielen zwei Fälle auf, in denen die Erkennung danebenlag:

| Fall | Ursache | Lösung |
|---|---|---|
| Selbst weitergeleitete englische Mail: kein Hinweis | Eigene Signatur und Kopfblock der Weiterleitung (Von/Datum/Betreff/An, deutsch) zählten mit. Zusätzlich kommen Mails mit CRLF-Zeilenenden; in Swift ist „\r\n“ **ein** Zeichen, `split(separator: "\n")` trennt daran nicht | Text wird auf LF vereinheitlicht; steht die Trennzeile `ReplyBuilder.forwardSeparator` im Text, zählen nur die Zeilen nach dem Kopfblock (Labels zeilenweise übersprungen, ohne Annahme einer Leerzeile – der Textteil einer formatiert verfassten Mail hat keine) |
| Deutscher Newsletter: „Polnisch übersetzen“ | Im Textteil standen über hundertmal `&zwnj;` als reiner Text (Füllzeichen der Vorschauzeile); die Erkennung hielt das wiederholte „zwnj“ für Polnisch. Der eigentliche Inhalt fehlte im Textteil | Vor der Erkennung fallen HTML-Entitäten, Links, Mailadressen und unsichtbare Zeichen weg |

Weiterleitungen anderer Mail-Programme haben andere Trennzeilen und werden nicht gesondert behandelt; dort zählt wie bisher der ganze Text.

### 2.3 Protokoll

Je geöffneter Mail eine Zeile ohne Mailinhalt, z. B. `🌐 Spracherkennung: Textteil ja, HTML ja; Text 2814, Trennzeile ja, bewertet 1932, Hypothesen en 0.97 de 0.02`, danach erkannte Sprache und Übersetzbarkeit. Grundlage für spätere Fehlerberichte („kein Knopf“, „falsche Sprache“).

---

## 3. Erreichbarkeit je Postfach (v0.2.2b)

### 3.1 Fehlerbild und Ursache

Gemeldet: In der Titelzeile stand immer wieder „Keine Verbindung“, obwohl das Netz da war und ein Abruf trotzdem lud. Nicht reproduzierbar, gehäuft bei und nach Abrufen.

Ursache im Quelltext belegt: „Keine Verbindung“ kam nicht aus der Netzprüfung (`NetworkMonitor`, die zeigt „Offline“), sondern aus `InboxViewModel.connectionFailed`. Diese Kennung galt für die ganze Ansicht und wurde gesetzt, sobald **ein einziger** Schritt eines **einzigen** Postfachs an der Verbindung scheiterte – etwa eine Zeitüberschreitung bei der Anmeldung oder der Spamfilter. Zurückgesetzt wurde sie erst beim Start des nächsten Abrufs. Zusätzlich ruft die Watch-Anbindung auch im Hintergrund ab; ein dort gescheiterter Abruf blieb beim nächsten Öffnen der App stehen.

### 3.2 Lösung

- `AccountFetchState` (neu, wie `OAuthSignInState`) hält die nicht erreichbaren Postfächer der Sitzung. `InboxViewModel.updateReachability` setzt bzw. löscht nach jedem Abruf eines Postfachs: Erfolg löscht, ein Verbindungsfehler setzt, andere Fehler ändern nichts, ohne Netz wird nichts gesetzt.
- Es zählt der Posteingang (bzw. der abgerufene Ordner). Ist der Posteingang aktuell und nur der Spam-Ordner gescheitert, gilt das Postfach als erreichbar.
- `connectionFailed` entfällt. `classify` hat keine Nebenwirkung mehr; Verbindungsfehler werden nur protokolliert.
- Titelzeile (`AccountFetchState.titleStatus`): ohne Netz „Offline“; alle Postfächer der Ansicht nicht erreichbar „Keine Verbindung“; eines „‹Name› nicht erreichbar“; mehrere „‹Anzahl› Postfächer nicht erreichbar“. Postfächer der Ansicht: in Sammelansichten die mit eingeschaltetem Abruf, bei einem Ordner dessen Postfach (`InboxViewModel.viewAccounts`).
- Watch (`AccountFetchState.watchProblems`): je nicht erreichbarem Postfach „‹Name›: keine Verbindung zum Mailserver“. Die Watch zeigt jetzt alle Hinweise statt nur des ersten; das Übertragungsformat bleibt unverändert (es führte schon eine Liste).

### 3.3 Zeichen am Postfach

`AccountStatusBadges` stellt die Zeichen in fester Reihenfolge zusammen – in Ordnerleiste und Postfachliste gleich:

| Zeichen | Bedeutung |
|---|---|
| rot, Ausrufezeichen im Kreis | Anmeldung abgelaufen (`SignInRequiredBadge`) |
| gelb, Warndreieck (neu) | Postfach nicht erreichbar (`FetchFailedBadge`) |
| orange, Pause im Kreis | Abruf ausgeschaltet (`FetchPausedBadge`) |

Erklärung:
- **Mac, iPad mit Zeiger:** Tooltip am Zeichen; zusätzlich ein Tooltip mit allen zutreffenden Hinweisen für die ganze Zeile, weil die Zeilen Knöpfe sind.
- **iPhone/iPad per Finger:** Ein Tipp auf das Zeichen öffnet eine kleine Sprechblase (Popover mit `presentationCompactAdaptation(.popover)`, auf dem iPhone kein Blatt) mit Titel und Erklärung. Der Tipp auf das Zeichen geht vor (`highPriorityGesture`): Das Postfach klappt nicht auf, die Bearbeitung öffnet sich nicht. Die Tippfläche ist je Seite 8 Punkt größer als das Zeichen.
- **VoiceOver:** Der Postfachkopf der Ordnerleiste las die Zeichen bisher nicht vor, weil er eine eigene Beschreibung hatte. Die zutreffenden Hinweise stehen jetzt darin.

Die Hinweistexte stehen an einer Stelle (`AccountStatusBadges.signInText` usw.), die drei Zeichen verwenden sie.

### 3.4 Mac

- **Untertitel:** Auf dem Mac war die zweite Titelzeile bisher leer (sie gibt es nur auf iPhone/iPad). Jetzt stehen Stand und Verbindungshinweis als Untertitel des Fensters (`navigationSubtitle`), wie bei Apple Mail. Eine gemeinsame Textregel (`InboxTitle.statusText`) für beide Plattformen; ein minütlicher Takt hält „vor 5 Minuten“ aktuell.
- **Kreisel:** Der Kreisel war ein eigenes Element der Symbolleiste, das nur beim Laden Inhalt hatte. Unter dem gemeinsamen Glas-Hintergrund der Knöpfe wurde er beim Erscheinen abgeschnitten. Jetzt zeigt der Aktualisieren-Knopf selbst den Kreisel statt des Pfeils, in einem Rahmen fester Größe. Er bleibt dabei bedienbar (gesperrt würde der Kreisel ausgegraut), löst aber keinen zweiten Abruf aus.

---

## 4. Dateien

**Neu:**

| Datei | Inhalt |
|---|---|
| `Mailwerk/Services/MessageLanguage.swift` | Spracherkennung, Bereinigung, Kopfblock von Weiterleitungen, Übersetzbarkeit, deutsche Sprachnamen, Diagnose |
| `Mailwerk/Services/AccountFetchState.swift` | nicht erreichbare Postfächer, Regel der Titelzeile, Hinweise für die Watch |
| `Mailwerk/Views/AccountStatusBadges.swift` | Zeichen eines Postfachs in fester Reihenfolge, Hinweistexte, Sprechblase (iOS), Tooltip der Zeile |
| `Mailwerk/Views/FetchFailedBadge.swift` | gelbes Warndreieck „Postfach nicht erreichbar“ |

**Geändert:**

| Datei | Änderung |
|---|---|
| `MessageDetailView` | Spracherkennung beim Öffnen, `.translationTask`, Anzeige der Übersetzung, Protokoll |
| `MessageDetailHeader` | `TranslationNotice`, `TranslationNoticeState`, übersetzter Betreff |
| `ReplyBuilder` | `forwardSeparator` intern und `nonisolated` (für `MessageLanguage`) |
| `InboxViewModel` | Erreichbarkeit je Postfach (`updateReachability`, `viewAccounts`), `connectionFailed` entfernt |
| `InboxView` | Titelzeile nach `AccountFetchState`, gemeinsame Textregel, Untertitel und Kreisel im Knopf (Mac) |
| `FolderSidebarView`, `AccountListView` | Zeichen über `AccountStatusBadges`, Tooltip der Zeile, VoiceOver |
| `SignInRequiredBadge`, `FetchPausedBadge` | Hinweistexte aus `AccountStatusBadges` |
| `WatchBridge` | Hinweise je Postfach |
| `WatchStore`, `WatchRootView` | alle Hinweise statt nur des ersten |
| Projekt | `MARKETING_VERSION` 0.2.2 |

**Tests:** neu `MessageLanguageTests` (11), `AccountFetchStateTests` (11).

Neue Dateien in `Mailwerk/` werden über die synchronisierten Ordner automatisch eingebunden (App und Teilen-Erweiterungen; nicht Watch).

---

## 5. Tests

| Punkt | Ergebnis |
|---|---|
| Bau iPhone, Mac; 781 Tests | erfolgreich |
| Englische Mail: Hinweis, Übersetzung von Betreff und Text, „Original anzeigen“, erneut übersetzen ohne Wartezeit | erfolgreich (echtes iPhone) |
| Selbst weitergeleitete englische Mail mit deutscher Signatur | erfolgreich |
| Deutscher Newsletter mit `&zwnj;`-Füllzeichen: kein Hinweis | erfolgreich |
| Deutsche Mail, sehr kurze Mail: kein Hinweis | erfolgreich |
| Mailwechsel verwirft die Übersetzung | erfolgreich |
| HTML-Mail mit externen Bildern: beide Hinweise untereinander | erfolgreich |
| Postfach mit falschem IMAP-Port: gelbes Zeichen in Ordnerleiste und Postfachliste, Titel „‹Name› nicht erreichbar“, übrige Postfächer laden | erfolgreich |
| Port zurück, Abruf: Zeichen und Hinweis verschwinden | erfolgreich |
| Mac: Untertitel mit Stand und Hinweis; Kreisel im Knopf, nichts abgeschnitten; Tooltips aller Zeichen | erfolgreich |
| iPhone: Tipp auf die Zeichen öffnet die Sprechblase, ohne aufzuklappen bzw. die Bearbeitung zu öffnen | erfolgreich |
| Erste Übersetzung einer Sprache ohne Netz (Download des Modells) | nicht prüfbar – keine ungeladene Sprache verfügbar |
| iPad, Watch | erst über TestFlight (Abschnitt 8) |

---

## 6. Beobachtungen und Erkenntnisse

- **Translation-Framework im Simulator:** `LanguageAvailability` meldet dort keine Sprachpaare – Übersetzung nur auf echten Geräten prüfbar.
- **CRLF in Swift:** `"\r\n"` ist ein einziges `Character`; `split(separator: "\n")` und die Suche nach `"\n\n"` greifen bei Mailtexten nicht. Vor zeilenweiser Verarbeitung auf LF vereinheitlichen. Tests mit Swift-Literalen enthalten nur LF und zeigen den Fehler nicht – Testtexte mit `joined(separator: "\r\n")` bauen.
- **Textteil von Newslettern:** oft unvollständig (Hauptinhalt fehlt) und voller Füllzeichen und Links. Für Auswertungen des Textteils Entitäten und Links entfernen.
- **Textteil selbst verfasster Mails:** entsteht aus dem Editor (`RichTextHTML.plainText`), nicht aus `ReplyBuilder.forwardText` – Absätze mit einfachem Zeilenumbruch, nicht mit Leerzeile.
- **Fehlerkennungen je Ansicht:** Ein Zustand, der an mehreren Postfächern hängt, gehört an das Postfach; eine Kennung für die ganze Ansicht macht aus einem Teilfehler einen Gesamtfehler.
- **Symbolleiste unter macOS 26:** Elemente, die nur zeitweise Inhalt haben, werden unter dem gemeinsamen Glas-Hintergrund nicht sauber eingepasst; Inhalte in festen Rahmen tauschen statt Elemente ein- und ausblenden.
- **Nebenläufigkeit:** Bei `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` sind auch statische Konstanten an den Main Actor gebunden; aus `nonisolated`-Code heraus brauchen sie `nonisolated static let`.

---

## 7. Hinweise für den Betrieb

- Die Übersetzung lädt beim ersten Mal je Sprache das Sprachmodell; iOS fragt dafür ggf. nach. Danach funktioniert sie ohne Netz.
- Das gelbe Zeichen ist kein Fehler der App, sondern ein Befund des letzten Abrufs. Erscheint es häufig ohne erkennbaren Grund, Konsole sichern: `📴 ‹Postfach›: nicht erreichbar` und die Zeile davor mit der Fehlerursache.

---

## 8. Abnahme über TestFlight (offen)

| Nr. | Gerät | Prüfung | Erwartung |
|---|---|---|---|
| 1 | iPad mit Trackpad | Zeiger über die Zeichen und die Postfachzeile | Tooltips wie auf dem Mac |
| 2 | iPad per Finger | Tipp auf ein Zeichen in der festen Ordnerleiste | Sprechblase, Postfach klappt nicht auf |
| 3 | Watch | Aktualisieren bei einem nicht erreichbaren Postfach | Zeile „‹Name›: keine Verbindung zum Mailserver“ |
| 4 | Watch | Aktualisieren ohne Netz am iPhone | „iPhone ohne Internet“ |
| 5 | iPhone | Übersetzung einer noch nicht geladenen Sprache ohne Netz, dann mit Netz | erst „Übersetzung fehlgeschlagen“, dann Übersetzung |

---

## Gesamtstand des Projekts (Stand 24.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS, macOS und watchOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`. Lokaler Projektordner auf dem Entwicklungs-Mac.
- Version **0.2.2**, **781 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkWatch Watch App, MailwerkWatchWidgetExtension, MailwerkTests, MailwerkUITests.
- **Verteilung:** TestFlight (zwei Testpersonen); 0.2.2 noch hochzuladen. „Mailwerk Dev“ per Xcode auf iPhone, iPad-Simulator und Mac.

### Funktionsumfang (bis v0.2.2)
- Unified Inbox mehrerer IMAP/SMTP-Postfächer, Abruf je Postfach ein-/ausschaltbar (je Gerät), Farben je Postfach, Absenderbilder (Kontakte, Favicons).
- Sammelansichten: Alle Eingänge, Ungelesen, Mit Kennzeichnung, Spam. Jeder Abruf holt je Postfach Posteingang und Spam-Ordner über eine Verbindung.
- **Erreichbarkeit je Postfach:** gelbes Zeichen am Postfach, Hinweis in Titelzeile bzw. Mac-Untertitel und auf der Watch; Erklärung aller Postfach-Zeichen per Tooltip bzw. Sprechblase.
- Ordnerleiste mit Ordnerbaum, Ordner anlegen/löschen, Verschieben-Dialog, Offline-Cache (SQLite, FTS5-Suchindex), Server-Abgleich, „Ältere laden“.
- **iPad:** Spaltenlayout (Liste + Mail, im Querformat wahlweise mit fester Ordnerleiste), Vollbild, vorige/nächste Mail, Pfeiltasten, Menüleiste mit Kürzeln, Ziehen auf Ordner.
- Mailansicht: HTML sicher (CSP, externe Inhalte auf Knopf), Dunkelmodus, Zoom, eingebettete Bilder, Originalquelle mit Suche, Drucken, Teilen; Anhänge ohne Endung bekommen die passende; **Übersetzung fremdsprachiger Mails** (Apple on-device).
- Verfassen: Rich-Text-Editor, Anhänge, Bilder im Text, Signaturen, Entwürfe, Absender-Regeln; `mailto:`-Links von außen.
- Spamfilter (clientseitig): White-/Blacklist über CloudKit, Domains samt Subdomains, Spam-Header, Blockieren/Vertrauen je Mail, Listen bearbeiten/exportieren/importieren.
- Suche (lokal, Namen, Server), Sortierung, Mehrfachauswahl, Kontextmenü, Rückgängig-Balken, eigene untere Leiste.
- Teilen mit Mailwerk (Erweiterungen iOS und Mac). Anmeldung per Passwort und OAuth 2 (Outlook.com).
- **Apple Watch:** vier Sammelansichten, lesen, gelesen/ungelesen, Kennzeichen, Spam/Vertrauen, Komplikation, Handoff; Abruf über das iPhone; Hinweise je Postfach.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus; iOS/macOS/watchOS 26.5. Xcode 27.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage). Apple-Frameworks für die Übersetzung: NaturalLanguage, Translation.
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Tokens: iCloud-Schlüsselbund; Filterlisten und Signaturen: SwiftData/CloudKit; Abruf-Schalter und Spalten-Einstellung: UserDefaults (je Gerät).
- Test/Produktion: Bundle-Suffix `.dev` für „Mailwerk Dev“.

### Arbeitsregeln (verbindlich)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher abstimmen.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen; klare Anweisungen mit genauem Menüpfad.
- Ursache belegen, nicht raten (Rohdaten, Konsole, Quelltext, Git-Historie).
- **Lokale Sitzung:** Lieferung als ganze Dateien direkt in den Projektordner, mit Liste der Zielordner; Git nur lesend; Claude committet nicht. Commit-Text erst zum Abschluss einer Stufe nach erfolgreicher Abnahme, nicht für Zwischenschritte.
- Versionen werden nicht mit bekannten Fehlern abgeschlossen.
- Projekteinstellungen, die sich nur in Xcode ändern lassen, manuell nach Anleitung.
- Inline-Doku: Datei-Header (Zweck, Abgrenzung, Abhängigkeiten), DocC je Funktion, Deutsch, keine Versionsverweise.
- Öffentliche Dokumentation ohne persönliche Bezüge (siehe `CLAUDE.md`); Arbeitsdokumente in `Documentation/Intern/`.
- Keine Sonderlösungen für einzelne Anbieter; Gestaltung mit Apple-Bausteinen; keine veralteten APIs (keine Warnungen).
- Tests dürfen keine Produktivmails verändern – Tests mit den Testpostfächern in „Mailwerk Dev“.

### Offene Punkte
- **Übersetzung:** zweiter Dienst für Sprachen ohne Apple-Unterstützung (z. B. Isländisch) – Marktrecherche offen; Weiterleitungen anderer Mail-Programme werden bei der Erkennung nicht gesondert behandelt; erste Übersetzung ohne Netz ungeprüft.
- **iPad/Watch:** Abnahme über TestFlight (Abschnitt 8 und v0.2.1, Abschnitt 7); Server-Treffer der Suche öffnen im Spaltenlayout per Push in der schmalen Listenspalte; Hervorhebung beim Ziehen erst ab iOS 27.
- **Watch:** Aktualisieren in der Praxis beobachten (v0.2.1, Abschnitt 4.2); eingebettete Bilder, Mitteilungen.
- **Mac:** Spaltenlayout und Menübefehle (eigene Version); größere HTML-Mails öffnen sich teils nicht (v0.2.0); produktive „Mailwerk“ noch nicht installiert.
- **H6 (Rest):** Ordnerliste lädt über eine eigene Verbindung und kann bei Gmail noch in die Zeitüberschreitung laufen („Erneut versuchen“); übrige Aktionen ohne Verbindungswiederverwendung; ggf. mit Push/IDLE.
- **Default Mail App:** Antrag abgelehnt (fehlender Zugang zum Testen); neu beantragen mit TestFlight-Link.
- **MailwerkUITests:** Ordner fehlt auf der Platte – aufräumen oder neu anlegen.
- **Azure-Probephase:** nach Ablauf Outlook neu anmelden; vor App Store Herausgeber-Verifizierung.
- Weitere: `mailto:`-Randfall, Spam-Prüfung Whitelist mit `X-Spam-Flag: YES`, Gmail per OAuth, Kopfdaten außerhalb des Zeitfensters (Weg B), N14 Offline-Warteschlange, Ordner abonnieren, DKIM/Authentication-Results, Suchfeld unten, Teilen (große Videos, HEIC), Strukturempfehlungen.

### Fahrplan
- **Nächste Version v0.2.3 „Performance-Optimierung“:** lange Ladezeiten, Hänger während des Ladens, ruckelige Bedienung; Prüfbericht als Grundlage; begrenzt paralleler Abruf der Postfächer als eigenes Paket.
- **Danach:** TestFlight mit Abnahme iPad und Watch; Mac-Fassung (Spaltenlayout, Menübefehle, „größere HTML-Mails“).
- **Später:** zweiter Übersetzungsdienst, H6, Push/IDLE, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung.
