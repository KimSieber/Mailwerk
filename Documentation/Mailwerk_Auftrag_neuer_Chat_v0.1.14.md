# Mailwerk – Auftrag und Übergabe für den neuen Chat (ab v0.1.14)

Stand: 13.10.2026, nach Abschluss von v0.1.13 (Version 0.1.13, **528 Tests**). Dieses Dokument ersetzt den Verlauf des bisherigen Chats. Es enthält Projektstand, Fahrplan, Arbeitsregeln und den Auftrag.

---

## 1. Auftrag

**Erster Schritt im neuen Chat:**
1. Projektordner freigeben lassen und Repo prüfen:
   - Commit „v0.1.13“ (Paket c) auf `405af3f` (v0.1.13b) folgend oder später;
   - **528 Tests**;
   - lokale Dateien = Repo-Stand (`git status` leer).
2. Mit Kim den **Inhalt von v0.1.14 (Fehler-Patch-Version)** genau abstimmen: erst seine Fehlerliste einholen, je Fund die Ursache belegen (nicht raten), dann Umfang und Aufteilung (Pakete mit Test- und Commit-Punkt) zur Freigabe vorlegen.
   - Kim fragen, ob **c2 „Entwurf weiterbearbeiten“** (siehe Abschnitt 6) in v0.1.14 aufgenommen wird. Empfehlung: ja – gesicherte Entwürfe lassen sich in Mailwerk bisher nicht weiterbearbeiten.
3. Erst nach ausdrücklicher Freigabe bauen.

## 2. Fahrplan bis zum Live-Gang (von Kim festgelegt, ab v0.1.14 um eins verschoben)

| Version | Thema | Stand / Inhalt |
|---|---|---|
| v0.1.10 | Absenderbild in der Mailliste (MW-7) | erledigt |
| v0.1.11 | Mehrere Mails auswählen, Kontextmenü (MW-9) | erledigt |
| v0.1.12 | Mails vollständig und lesbar anzeigen | erledigt |
| v0.1.13 | Signaturen (MW-2), Abruf je Postfach, Entwurf sichern (MW-16 Teil 1) | **erledigt** (a `c63552f`, b `405af3f`, c dieser Commit) |
| **v0.1.14** | **Fehler-Patch-Version** | Inhalt mit Kim abstimmen; Kandidat: c2 „Entwurf weiterbearbeiten“ |
| v0.1.15 | Dateien und Inhalte aus anderen Apps an Mailwerk teilen (MW-15) | Share Extension (eigenes Ziel, App Group, Schlüsselbundgruppe); für Kim wichtig |
| v0.1.16 | Suche über alle Mails (MW-6) | Eingabe am unteren Rand (Bereich freigehalten, im Auswahlmodus belegt die Befehlsleiste ihn); lokaler Suchindex; Umfang lokal/Server offen |
| v0.2.x | Seitenleiste und Layout für iPad und Mac | Kim hat viele eigene Ideen (u. a. Auswahlkreise auf dem Mac) |
| später | H6 Verbindungen wiederverwenden, Push/IDLE, N14 Offline-Warteschlange, Ordner abonnieren, Posteo, Threading | nach Live |

Noch offen: was „Live“ genau heißt (TestFlight eigene Geräte oder App Store). Vor TestFlight/App Store: CloudKit-Schema nach Production übertragen.

---

## 3. Arbeitsregeln (verbindlich)

- **Nichts bauen ohne OK.** Erst Vorschlag bzw. Antwort auf Fragen, dann auf ausdrückliche Freigabe warten.
- **Inhalt jeder Version vorher abstimmen:** Kims Beschreibung einholen, Leitfragen mit Empfehlung stellen, Umfang und Aufteilung zur Freigabe vorlegen.
- **Schritt für Schritt:** Test- und Handlungsanweisungen einzeln geben und nach jedem Schritt auf Rückmeldung warten.
  - Kim fasst gern mehrere Teile zu einem Paket mit einem Test- und Commit-Punkt zusammen.
  - Riskante Änderungen (Schema, Abruf, Versand) bleiben in einem eigenen Paket, damit sie sich allein zurücknehmen lassen.
  - Zwischenrufe Kims (neue Wünsche während einer Version) werden als eigenes Paket eingeplant, nicht nebenbei eingebaut.
- **Klar reden:** Jede Anweisung ohne Vorwissen ausführbar – genauer Menüpfad, genaue Bezeichnung, was danach zu sehen sein soll.
- **Ursache belegen, nicht raten:** Bei Funden zuerst die Ursache belegen, z. B. Rohdaten der Mail (Apple Mail: **Darstellung → E-Mail → Rohdaten**, ⌥⌘U), Mailwerks **Originalquelle**, Prüfsummen, Protokoll. Bei mehreren Fehlversuchen anhalten.
- **Lieferung – Projektordner:**
  - Claude legt Dateien **direkt in Kims Projektordner** `/Users/kim/Dropbox/Dev/GitHub/Mailwerk` (Zugriff über die Desktop-App, Ordnerfreigabe anfragen).
  - **Vorher** prüfen, dass die betroffenen lokalen Dateien dem Repo-Stand bzw. der letzten Lieferung entsprechen (`git status`, Prüfsummen).
  - **Für jede Lieferung einen frischen Zwischenpfad** (z. B. `outputs/c1/…`, Korrektur `outputs/c1fix1/…`) verwenden – das Ablege-Werkzeug schrieb bei wiederholtem gleichem Pfad teils den alten Inhalt und meldete trotzdem „geschrieben“.
  - **Nach jedem Ablegen die Prüfsummen auf dem Mac kontrollieren.**
  - **Git im Projektordner nur lesend** (`git log`, `git diff`, `git status`); nie `fetch`, `pull` o. Ä. (Sperrdatei, Löschen im Ordner nicht erlaubt). Das Repo prüft Claude in einem eigenen Klon in seiner Umgebung.
  - Ist der Mac nicht erreichbar: Dateien als Download im Chat.
  - Immer eine Tabelle *Datei · Ort · Art (neu/ersetzt/löschen)*.
  - **Löschen** macht Kim selbst in Xcode.
  - Ganze Dateien, keine Code-Schnipsel, keine Claude-Code-Prompts.
  - **Projekteinstellungen** (Build Settings, Version, Info-Texte, Capabilities) ändert Kim selbst in Xcode nach genauer Anleitung; Claude prüft danach die Projektdatei. `MARKETING_VERSION` nur aus Zahlen mit Punkten (z. B. `0.1.14`), Buchstaben nur im Commit-Text.
- **Entwicklungsdokumentationen** (OnePager, Übergaben): im Ordner `Documentation/` und zusätzlich **als Download im Chat**.
- **Neue Dateien:** auf **Target Membership** im Dateiinspektor (⌥⌘1) hinweisen (App: `Mailwerk`, Tests: `MailwerkTests`). Neue Unterordner in synchronisierten Ordnern werden automatisch übernommen.
- **Commit:**
  - **Claude committet niemals.** Ob ein Stand commit-reif ist und der Commit selbst bleiben immer Kims Aufgabe, in Xcode (**Integrate → Commit…**, Push).
  - Commits je abgeschlossenem Paket; nie ein nicht lauffähiger Stand, möglichst ohne Warnungen.
  - Nach dem Push prüft Claude das Repo.
- **Funde** notieren und bewusst einplanen. Inhaltsverlust oder Fehler im Kern der laufenden Version werden in der Version behoben, nicht vertagt.
- **Keine Sonderlösungen** für Einzelfälle oder Übergangseffekte (alle Installationen sind Testinstallationen).
- **SwiftMail wird nicht geforkt oder erweitert**; keine eigenen IMAP-Wege für Randfunktionen.
- **Tests dürfen keine Produktivmails verändern.** Testordner „Test Mailwerk“ im Webmail, Mails hineinkopieren. Antworten nur an sich selbst. Testmails mit Bildern: Apple Mail (Foto in den Text) und Spark (`cid:`).
- **Testaufwand gering halten:** nur die nötigsten Tests je Gerät.
- **Formulare:** Felder mit klarer, fester Beschriftung und angedrucktem Beispiel (`LabeledInputField`).
- **Rückfragen** einheitlich als `alert` über `Dialogs` (`AlertItem`, `ConfirmationRequest`, optional dritter Knopf `secondary`).

---

## 4. Test- und Dokumentationsstandard

**Tests:**
- Automatische Tests auf **Simulator** oder **My Mac**, nie auf dem iPhone.
- **Erwartete Testzahl** bei jeder Lieferung nennen.
  - Ändert sich die Schema-Version, **alle** Tests mit festen Versionszahlen anpassen (Suche nach `user_version`, `userVersion` und Zahlenvergleichen).
- **Vorprüfung unter Linux (Claude):** Swift 6.2 (`/opt/swift`, ggf. neu laden von download.swift.org), eigenes SwiftPM-Paket mit `defaultIsolation(MainActor.self)`, Swift-5-Modus, symbolisch verlinkten Quell- und Testdateien. Reine Logik (ohne SwiftUI/UIKit) vor jeder Lieferung übersetzen und testen; das ersetzt nicht den Build in Xcode.
- **Isolation (Swift 6.2, Standard MainActor):** Standardwerte von Parametern werden außerhalb des Main-Actors ausgewertet (kein `= MainActorTyp()` als Standardwert). Eigene `init` reiner Datentypen, die auch außerhalb des Main-Actors gebraucht werden, als `nonisolated` kennzeichnen; Initialisierer nicht als Funktionsverweis weitergeben (`.map(Typ.init)` → Warnung).
- Änderungen an Abruf oder Abgleich immer mit dem größten Postfach (Kim.Sieber@ordinum.com, rund 8.800 Mails) und einer **frischen Installation** im Simulator testen.
- Neue Funktionen kurz auch auf dem **Mac** prüfen (Gestaltung iPad/Mac erst v0.2.x).
- Protokoll: Xcode-Konsole (Kategorien Abruf, Aktionen, Spam, Versand, Cache, Ansicht) oder App **Konsole** auf dem Mac.

**Inline-Dokumentation** (in jeder neuen oder geänderten Datei vollständig):
- Datei-Header mit **Zweck**, **Abgrenzung** und **Abhängigkeiten**.
- DocC-Kopf je Funktion: Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`. Gespeicherte Eigenschaften und Typen mit einer Zeile.
- Testfunktionen und Testhilfen: eine Zeile `///`.
- Deutsch, **keine Versionsverweise im Code**.

**OnePager je Version:** `Documentation/Mailwerk_v0.1.xx_Entwicklungsdokumentation.md` – Zusammenfassung mit Entscheidungen, Problem/Lösung je Paket, geänderte Dateien, Testverfahren mit Testzahl, Beobachtungen, nächste Schritte. Vorlage: v0.1.13.

---

## 5. Projektstand

**Projekt:**
- Mailwerk, Mail-Client in Swift/SwiftUI für iOS und macOS.
- Repo `github.com/KimSieber/Mailwerk`, Branch `main`, Bundle `de.sieber-bw.Mailwerk`.
- Drei IMAP-Postfächer bei manitu, dazu ein Posteo-Postfach (für den Krisenfall, derzeit meist mit Abruf aus).
- `MARKETING_VERSION` 0.1.13, **528 Tests**.

**Technik:**
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, Approachable Concurrency, MemberImportVisibility; Deployment Target iOS/macOS 26.5.
  - Jede Datei braucht ihren eigenen `import`.
  - Reine Logik ohne Oberfläche als `nonisolated enum`/`struct` (z. B. `HTMLRichTextParser`, `DraftFormat`, `FetchSelection`, `SignatureRules`).
  - Arbeit neben dem Main-Actor: `@concurrent` oder `Task.detached` mit synchroner Funktion.
- Xcode-Projekt mit synchronisierten Ordnern; Swift Testing (`@Test`, `#expect`).
- **SwiftMail 1.15.0** (wird nicht geforkt). Keine weiteren Pakete; neue nur nach Rückfrage.
  - Genutzt u. a.: `fetchStructure`, `fetchPart` (`BODY.PEEK`), `fetchRawMessage` (10 s), `examineMailbox`, `append(email:to:flags:)` (liefert UID bei UIDPLUS), `store`, `expunge(messages:)` (UID EXPUNGE), `createMailbox`, `Attachment(contentID:isInline:)`.
  - Nicht vorhanden: Teilabruf der ganzen Mail, `BODY[HEADER]`, `BODY[n.MIME]`, SUBSCRIBE.
- Mail-Cache: System-SQLite `MessageStore`, WAL und Transaktionen, **Schema-Stufe 6**, Ordner `Cache` ohne Backup, Sync-Zustand je Ordner.
- Postfächer im iCloud-Key-Value-Speicher, Passwörter im iCloud-Schlüsselbund; **Filterlisten und Signaturen** über SwiftData/CloudKit (`FilterEntry`, `AccountSignature`, Container `iCloud.de.sieber-bw.Mailwerk`, Schema bisher nur Development); **Abruf-Schalter je Gerät** in `UserDefaults` (`mailwerk.fetchPausedAccounts`).

**Verfassen (seit v0.1.13):**
- `ComposeView`/`ComposeViewModel` mit `RichTextEditor` (Fett, Kursiv, Unterstrichen, Größe, Farbe, Link, Listen, Bilder).
  - HTML-Rückweg: `HTMLRichTextParser` (fehlertolerant, `isLossless`) → `RichTextImport`. Eigenes Editor-HTML kommt unverändert zurück.
  - Bilder im Text: `MailImageAttachment` (Daten, MIME, Content-ID, Breite, Platzhalter), `EditorImageData` (ImageIO), `EditorImages.normalize`; Versand als Inline-Teil (`RichTextHTML.images(in:)`).
  - Links: `LinkInput`, `RichTextController.setLink`.
- **Signaturen:** `SignatureStore` (über `.environment`), `SignatureEditorView` (Einfach/HTML, Logo), `SignatureEditing` (Umwandlung, Einsetzen mit Attribut `.mailwerkSignature`, `split`), `HTMLSignatureBlock` + `SignatureBlockView` (bearbeitbarer HTML-Block, Logo `data:` → `cid:`), `CodeTextEditor`.
- **Entwürfe:** `DraftFormat` (Marken `<!--mailwerk-entwurf:…-->`, Datenblock), `DraftService` (APPEND mit `\Draft`/`\Seen`, Ordner suchen/anlegen), Rückfrage „Nachricht schließen?“ mit drittem Knopf.
- Gesendet-Kopie und Markieren des Originals (`\Answered`, `$Forwarded`): `MailSendService`.

**Abruf:**
- `InboxViewModel` (Runde über `AccountStore.fetchingAccounts`), `FetchCoordinator`, `FetchSelection`, `FolderCatalog` (ausgeschaltete Postfächer nur aus dem Cache), Kennzeichen `FetchPausedBadge`.

**Anzeige einer Mail und Liste:** wie seit v0.1.12 (`MessageDetailView`, `HTMLMailView` mit CSP und Dunkelmodus, eingebettete Bilder, Originalquelle; `MessageRow`, `SenderAvatarView`, Kontextmenü, Auswahlmodus, 5-Sekunden-Rückgängig).

---

## 6. Liste offener Punkte

- **c2 „Entwurf weiterbearbeiten“ (MW-16 Teil 2)** – Konzept steht und ist mit Kim abgestimmt:
  - Tipp auf eine Mail im Ordner „Entwürfe“ öffnet das Verfassen-Fenster statt der Leseansicht.
  - Wiederherstellen aus `DraftFormat.parse`: Absender (Postfach des Entwurfs), An/Cc aus dem Cache, Bcc aus dem Datenblock, Betreff, Text vor/nach der Signatur (`RichTextImport`, Bilder über `cid:` aus den Anhängen des Entwurfs, fehlende nachladen), Signatur (einfach: markiert einsetzen; HTML: als Block), Zitat getrennt und unverändert, Anhänge (fehlende nachladen), Bezug zur Originalmail und Threading.
  - Senden oder erneut sichern entfernt die alte Fassung endgültig (`store \Deleted` + `expunge(messages:)` im Entwürfe-Ordner, nicht über den Papierkorb) und aus dem Cache.
  - Gesendeter Antwort-Entwurf setzt „Beantwortet“ am Original (`OutgoingMail.Origin` aus dem Datenblock).
  - Fremde Entwürfe (ohne Datenblock): ganzer Inhalt vereinfacht in den Editor.
- **DKIM / Authentication-Results:** später prüfen, für Logos und ggf. Spam-Prüfung.
- **H6:** Verbindungen je Konto wiederverwenden (ggf. mit Push-Stufe).
- **N14 „Warteschlange offline“:** Aktionen ohne Netz merken und später ausführen (auch Entwurf sichern offline).
- **Ordner abonnieren:** In Mailwerk angelegte Ordner (auch ein neu angelegter „Drafts“) werden nicht abonniert (SwiftMail ohne SUBSCRIBE).
- **Vorschau (`preview`)** wird weiter gespeichert, aber nicht angezeigt – klären, ob sie entfällt oder für die Suche (v0.1.16) bleibt.
- **Strukturempfehlungen:** Protokolle/Injektion für Tests ohne Server, SwiftLint/SwiftFormat, Lokalisierung.
- **Empfangsdatum** statt Kopfdatum – nur bei Bedarf.
- **Inline-Foto ohne Verweis bei einer Mail mit einem einzigen HTML-Teil** steht in der Anhangliste statt im Text – beobachten.
- **Originalquelle großer Mails** (über 5 MB): nicht möglich ohne Teilabruf in SwiftMail.
- **Logo-Breite einer einfachen Signatur** fest 150 pt (änderbar nur über Art HTML) – bei Bedarf Feld ergänzen.
- **CloudKit-Schema** vor TestFlight/App Store nach Production übertragen.

---

## 7. Bekannte Besonderheiten der Umgebung

- **Simulator:**
  - behält Postfächer und Passwörter (iCloud-Speicher des Simulators), solange er nicht neu aufgesetzt wird;
  - kein CloudKit-Abgleich mit echten Geräten (Signaturen/Filterlisten nur iPhone ↔ Mac prüfbar);
  - zeigt private Protokollwerte im Klartext;
  - hat nur Beispielkontakte;
  - Tastatur: **I/O → Keyboard → Toggle Software Keyboard** (⌘K);
  - Hell/Dunkel: **Features → Toggle Appearance** (⇧⌘A);
  - **Hängende Sondertaste:** Tippen markiert alles, Pfeiltasten springen wortweise, Rückschritt löscht ganze Zeilen (auch in Safari) → Simulator neu starten; kein Fehler in Mailwerk.
- **Netzstatus:** meldet ein fehlendes Netz direkt nach dem Flugmodus manchmal noch nicht; Verbindungsfehler zusätzlich über `ConnectionErrorClassifier` als „offline“ behandeln.
- **Compiler-Absturz (Swift 6.2):** „Command SwiftCompile failed with a nonzero exit code“ ohne Meldung = Compiler abgestürzt. Ursache im **Report Navigator (⌘9)**. Bekannte Auslöser: `async`-Form von Objective-C-Delegate-Methoden (deshalb Rückruf-Form, z. B. in `SignatureBlockView`); gespeicherte async-Closures ohne feste Isolation.
- **Xcode + Kabel + VPN:** Mit NordVPN bricht die Debug-Verbindung zum iPhone ab; VPN am Mac aus.
- **Git auf macOS:** Reine Groß-/Kleinschreibungs-Änderungen an Dateinamen erfasst Git nicht – über Zwischennamen in zwei Commits.
- **SwiftMail:**
  - baut abgerissene Verbindungen still neu auf, ohne den Ordner neu auszuwählen (abgefangen);
  - `deleteMailbox` löscht samt Inhalt (Vorprüfung in `FolderDeletion`);
  - liefert je Mail nur den ersten Text- und HTML-Teil (in `MessageContentPlan` gelöst).
- **WKWebView:** JavaScript der Mail/Signatur ist aus; Skripte der App laufen in eigener Welt (`WKContentWorld.defaultClient`) bzw. per `evaluateJavaScript`.
- **Apple Mail** schickt Fotos im Text als Folge von Teilen ohne Content-ID; **Spark** und Outlook nutzen `cid:`.
- **Postfächer:** im August 2026 per IMAPSYNC umgezogen; Sequenznummern sind kein Datumsindikator.
- **HTML-Mails** können fehlerhaft aufgebaut sein. Jede Verarbeitung von Mail-HTML muss tolerant sein und darf nicht an Tags ausschneiden; Ersetzungen nur per Textsuche (so auch Logo-Platzhalter und Entwurfs-Marken).
