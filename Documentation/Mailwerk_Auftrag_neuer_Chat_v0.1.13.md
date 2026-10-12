# Mailwerk – Auftrag und Übergabe für den neuen Chat (ab v0.1.13)

Stand: 12.10.2026, nach Abschluss von v0.1.12 (Version 0.1.12, **477 Tests**). Dieses Dokument ersetzt den Verlauf des bisherigen Chats. Es enthält Projektstand, Fahrplan, Arbeitsregeln und den Auftrag.

---

## 1. Auftrag

**Erster Schritt im neuen Chat:**
1. Projektordner freigeben lassen und Repo prüfen:
   - Commit „v0.1.12“ (Paket 2) auf `608041c` (v0.1.12a) folgend oder später;
   - **477 Tests**;
   - lokale Dateien = Repo-Stand.
2. Mit Kim den **Inhalt von v0.1.13** genau abstimmen. Kim hat konkrete Vorstellungen: erst seine Beschreibung einholen, dann Leitfragen stellen, dann Umfang und Aufteilung (Pakete bzw. MVPs mit Test- und Commit-Punkt) zur Freigabe vorlegen. Überschriften allein reichen nicht.
3. Erst nach ausdrücklicher Freigabe bauen.

## 2. Fahrplan bis zum Live-Gang (von Kim festgelegt)

| Version | Thema | Stand / Inhalt |
|---|---|---|
| v0.1.10 | Absenderbild in der Mailliste (MW-7) | erledigt |
| v0.1.11 | Mehrere Mails auswählen, Kontextmenü (MW-9) | erledigt |
| v0.1.12 | Mails vollständig und lesbar anzeigen | **erledigt**: Dunkelmodus, Zoom, Originalquelle (MW-5), eingebettete Bilder inkl. Apple-Mail-Folgen |
| **v0.1.13** | **Signaturen und Entwürfe beim Verfassen (MW-2, MW-16)** | Signaturen (HTML, zur Auswahl, teils je Postfach unterschiedlich), „Entwurf speichern“ beim Schließen, Entwurf weiterbearbeiten, Beantwortet-Kennzeichen setzen |
| v0.1.14 | Dateien und Inhalte aus anderen Apps an Mailwerk teilen (MW-15) | Share Extension (eigenes Ziel, App Group, Schlüsselbundgruppe); für Kim wichtig |
| v0.1.15 | Suche über alle Mails (MW-6) | Eingabe am unteren Rand (Bereich freigehalten, im Auswahlmodus belegt die Befehlsleiste ihn); lokaler Suchindex; Umfang lokal/Server offen |
| v0.2.x | Seitenleiste und Layout für iPad und Mac | Kim hat viele eigene Ideen; dort gesammelt (u. a. Auswahlkreise auf dem Mac) |
| später | H6 Verbindungen wiederverwenden, Push/IDLE, N14 Offline-Warteschlange, Ordner abonnieren, Posteo, Threading | nach Live |

Noch offen: was „Live“ genau heißt (TestFlight eigene Geräte oder App Store).

**Hinweise für v0.1.13 aus dem bisherigen Stand:**
- Verfassen: `ComposeView`/`ComposeViewModel` mit `RichTextEditor` (NSAttributedString → `RichTextHTML`).
  - Antworten und Weiterleiten übernehmen eingebettete Bilder des Zitats als Inline-Teile (`OutgoingAttachment.contentID`).
  - Eine HTML-Signatur mit Bildern (z. B. Logo) kann denselben Weg nehmen: Bild als Inline-Teil mit Content-ID, im HTML per `cid:`.
- Gesendet-Kopie: `MailSendService` (Ordner „Gesendet“ per SPECIAL-USE).
- Entwürfe: Sonderordner „Entwürfe“ ist erkannt (Ordnerrolle). In Gesendet/Entwürfen zeigt die Liste den Empfänger (`MessageRowParty`).
- Das Kennzeichen „Beantwortet“ (`\Answered`) wird bisher nur gelesen; `$Forwarded` wird nach dem Weiterleiten gesetzt.

---

## 3. Arbeitsregeln (verbindlich)

- **Nichts bauen ohne OK.** Erst Vorschlag bzw. Antwort auf Fragen, dann auf ausdrückliche Freigabe warten.
- **Schritt für Schritt:** Test- und Handlungsanweisungen einzeln geben und nach jedem Schritt auf Rückmeldung warten.
  - Kim fasst gern mehrere Teile zu einem Paket mit einem Test- und Commit-Punkt zusammen.
  - Riskante Änderungen (Schema, Abruf, Versand) bleiben dabei in einem eigenen Paket, damit sie sich allein zurücknehmen lassen.
- **Klar reden:** Jede Anweisung ohne Vorwissen ausführbar – genauer Menüpfad, genaue Bezeichnung, was danach zu sehen sein soll.
- **Ursache belegen, nicht raten:** Bei Funden zuerst die Ursache belegen, z. B. Rohdaten der Mail (Apple Mail: **Darstellung → E-Mail → Rohdaten**, ⌥⌘U) oder Mailwerks eigene **Originalquelle**. Bei mehreren Fehlversuchen anhalten.
- **Lieferung – Projektordner:**
  - Claude legt Dateien **direkt in Kims Projektordner** `/Users/kim/Dropbox/Dev/GitHub/Mailwerk` (Zugriff über die Desktop-App, Ordnerfreigabe anfragen).
  - **Vorher** prüfen, dass die betroffenen lokalen Dateien dem Repo-Stand bzw. der letzten Lieferung entsprechen (Prüfsummen vergleichen), damit keine lokale Änderung überschrieben wird.
  - **Git im Projektordner nur lesend** (`git log`, `git diff`, `git status`); nie `fetch`, `pull` o. Ä. Das hinterließ einmal eine Sperrdatei, weil Löschen im Ordner nicht erlaubt ist.
  - Ist der Mac nicht erreichbar: Dateien als Download im Chat, später auf Wunsch selbst ablegen.
  - Immer eine Tabelle *Datei · Ort · Art (neu/ersetzt/löschen)*.
  - **Löschen** macht Kim selbst in Xcode.
  - Ganze Dateien, keine Code-Schnipsel, keine Claude-Code-Prompts.
  - **Projekteinstellungen** (Build Settings, Info-Texte, Capabilities) ändert Kim selbst in Xcode nach genauer Anleitung; Claude prüft danach die Projektdatei.
- **Entwicklungsdokumentationen** (OnePager, Übergaben): im Ordner `Documentation/` und zusätzlich **als Download im Chat**.
- **Neue Dateien:** auf **Target Membership** im Dateiinspektor (⌥⌘1) hinweisen (App: `Mailwerk`, Tests: `MailwerkTests`).
- **Commit:**
  - **Claude committet niemals.** Ob ein Stand commit-reif ist und der Commit selbst bleiben immer Kims Aufgabe, in Xcode (**Integrate → Commit…**, Push).
  - Commits je abgeschlossenem Paket; nie ein nicht lauffähiger Stand.
  - Nach dem Push prüft Claude das Repo.
- **Funde** notieren und bewusst einplanen. Inhaltsverlust oder Fehler im Kern der laufenden Version werden in der Version behoben, nicht vertagt.
- **Keine Sonderlösungen** für Einzelfälle oder Übergangseffekte (alle Installationen sind Testinstallationen).
- **SwiftMail wird nicht geforkt oder erweitert**; keine eigenen IMAP-Wege für Randfunktionen.
- **Tests dürfen keine Produktivmails verändern.** Testordner „Test Mailwerk“ im Webmail, Mails hineinkopieren. Antworten nur an sich selbst. Testmails mit Bildern: Apple Mail (Foto in den Text) und Spark (`cid:`).
- **Testaufwand gering halten:** nur die nötigsten Tests je Gerät.
- **Formulare:** Felder mit klarer, fester Beschriftung und angedrucktem Beispiel (`LabeledInputField`).

---

## 4. Test- und Dokumentationsstandard

**Tests:**
- Automatische Tests auf **Simulator** oder **My Mac**, nie auf dem iPhone.
- **Erwartete Testzahl** bei jeder Lieferung nennen.
  - Ändert sich die Schema-Version, **alle** Tests mit festen Versionszahlen anpassen.
  - Suche nach `user_version`, `userVersion` und Zahlenvergleichen, nicht nur nach `"5"`.
- **Vorprüfung unter Linux (Claude):** Reine Logik (ohne SwiftUI/UIKit) lässt sich vor der Lieferung mit Swift 6.2 unter Linux übersetzen und testen, auch gegen SwiftMail 1.15.0. Das ersetzt nicht den Build in Xcode.
- Änderungen an Abruf oder Abgleich immer mit dem größten Postfach (Kim.Sieber@ordinum.com, rund 8.800 Mails) und einer **frischen Installation** im Simulator testen (App durch langes Drücken entfernen, neu starten).
- Neue Funktionen kurz auch auf dem **Mac** prüfen (Gestaltung iPad/Mac erst v0.2.x).
- Protokoll: Xcode-Konsole (Kategorien Abruf, Aktionen, Spam, Versand, Cache, Ansicht) oder App **Konsole** auf dem Mac.

**Inline-Dokumentation** (in jeder neuen oder geänderten Datei vollständig):
- Datei-Header mit **Zweck**, **Abgrenzung** und **Abhängigkeiten**.
- DocC-Kopf je Funktion: Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`. Gespeicherte Eigenschaften und Typen mit einer Zeile.
- Testfunktionen und Testhilfen: eine Zeile `///`.
- Deutsch, **keine Versionsverweise im Code**.

**OnePager je Version:** `Documentation/Mailwerk_v0.1.xx_Entwicklungsdokumentation.md` – Zusammenfassung mit Entscheidungen, Problem/Lösung je Paket, geänderte Dateien, Testverfahren mit Testzahl, Beobachtungen, nächste Schritte. Vorlage: v0.1.12.

---

## 5. Projektstand

**Projekt:**
- Mailwerk, Mail-Client in Swift/SwiftUI für iOS und macOS.
- Repo `github.com/KimSieber/Mailwerk`, Branch `main`, Bundle `de.sieber-bw.Mailwerk`.
- Drei IMAP-Postfächer bei manitu.
- `MARKETING_VERSION` 0.1.12, **477 Tests**.

**Technik:**
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, Approachable Concurrency (nonisolated async = `nonsending`), MemberImportVisibility; Deployment Target iOS/macOS 26.5.
  - Jede Datei braucht ihren eigenen `import`.
  - Reine Logik ohne Oberfläche als `nonisolated enum` (z. B. `InlineImages`, `RawMessageFormatter`, `MailAppearance`).
  - Arbeit neben dem Main-Actor: `@concurrent` oder `Task.detached` mit synchroner Funktion.
- Xcode-Projekt mit synchronisierten Ordnern; Swift Testing (`@Test`, `#expect`).
- **SwiftMail 1.15.0** (wird nicht geforkt). Keine weiteren Pakete; neue nur nach Rückfrage.
  - Genutzt u. a.: `fetchStructure`, `fetchPart` (`BODY.PEEK`), `fetchRawMessage` (festes Zeitlimit 10 s), `examineMailbox`, `Attachment(contentID:isInline:)`.
  - Nicht vorhanden: Teilabruf der ganzen Mail (`BODY[]<0.n>`), `BODY[HEADER]`, `BODY[n.MIME]`, SUBSCRIBE.
- Mail-Cache: System-SQLite `MessageStore`, WAL und Transaktionen, **Schema-Stufe 6** (Anhang-Tabelle mit `contentID`, `isInline`), Header-Version 2, Ordner `Cache` ohne Backup, Sync-Zustand je Ordner.
- Postfächer im iCloud-Key-Value-Speicher, Passwörter im iCloud-Schlüsselbund, Filterlisten über SwiftData/CloudKit.

**Anzeige einer Mail (seit v0.1.12):**
- `MessageDetailView` mit `MessageDetailHeader`, `MessageAttachmentList` und gemeinsamem Menü `MessageMenuItems` (dazu Teilen, Drucken, Anlagen lokal löschen, ganz unten „Originalquelle“, ⌥⌘U).
- `HTMLMailView`:
  - CSP: externe Inhalte nur nach Freigabe, `data:` immer erlaubt.
  - Dunkelmodus über `MailAppearance` (Mails mit eigenen Farben hell, weiße Fläche mit 8 px Innenrand).
  - Zoom immer möglich.
  - JavaScript aus der Mail aus.
- Eingebettete Bilder:
  - `MessageContentPlan` (`inlineImages`, `layout` single/htmlSequence/textSequence, `contentID(for:)` mit Ersatz `teil-<Abschnitt>@mailwerk`);
  - `InlineImages` (Verweise, sichtbare Anhangliste, `cid:` → `data:`);
  - `InlineImageLoader` (Nachladen beim Öffnen und beim Senden).
- Originalquelle: `RawMessageService` (EXAMINE, `fetchRawMessage`, Grenze 5 MB, offline), `RawMessageFormatter`, `RawSourceView`.
- Druck und Teilen: `MailPrintFormatter` (mit Bildern), `MailPrinter`.

**Mailliste (seit v0.1.10/0.1.11):**
- `MessageRow` (drei Zeilen), `SenderAvatarView` (Kontaktbild → Logo → Initialen; leer bei Spam), Farbstreifen 4/8 pt.
- Kontextmenü per langem Drücken mit „Auswählen“; Auswahlmodus mit `SelectionActionBar` (Kennzeichnung, Gelesen, Verschieben, Löschen).
- 5-Sekunden-Rückgängig für Kennzeichnung und Gelesen.

**Weitere Bausteine:** `MailAccount` (`emailAddress`, `loginName`, `senderAddress`), `MailSession`, `MessageActions`, `FetchCoordinator`, `Dialogs` (`AlertItem`, `ConfirmationRequest`), `ReplyBuilder`, `SpamClassifier`, `ConnectionErrorClassifier`, `NetworkMonitor`, `LabeledInputField`, `Log` (Zahlen, Ordner, Fehler öffentlich; Adressen, Postfachnamen, Domains privat).

---

## 6. Liste offener Punkte

- **DKIM / Authentication-Results:** später prüfen, für Logos und ggf. Spam-Prüfung.
- **H6:** Verbindungen je Konto wiederverwenden (ggf. mit Push-Stufe).
- **N14 „Warteschlange offline“:** Aktionen ohne Netz merken und später ausführen.
- **Ordner abonnieren:** In Mailwerk angelegte Ordner werden nicht abonniert (SwiftMail ohne SUBSCRIBE).
- **Vorschau (`preview`)** wird weiter gespeichert, aber nicht mehr angezeigt – klären, ob sie entfällt (Schema, Tests) oder für die Suche (v0.1.15) bleibt.
- **Strukturempfehlungen:** Protokolle/Injektion für Tests ohne Server, SwiftLint/SwiftFormat, Lokalisierung.
- **Empfangsdatum** statt Kopfdatum (robuster gegen gefälschte Daten im Spam) – nur bei Bedarf.
- **Inline-Foto ohne Verweis bei einer Mail mit einem einzigen HTML-Teil** (Foto ans Ende einer formatierten Apple-Mail) steht in der Anhangliste statt im Text – beobachten.
- **Originalquelle großer Mails** (über 5 MB): nicht möglich, solange SwiftMail keinen Teilabruf der ganzen Mail bietet; Webmail genügt.

**Erledigt mit v0.1.12** (aus der früheren Liste): `cid:`-Bilder, Dunkelmodus-Lesbarkeit, Zoomen.

---

## 7. Bekannte Besonderheiten der Umgebung

- **Simulator:**
  - behält Postfächer und Passwörter (iCloud-Speicher des Simulators), solange er nicht neu aufgesetzt wird;
  - kein CloudKit-Abgleich der Filterlisten mit echten Geräten;
  - zeigt private Protokollwerte im Klartext;
  - hat nur Beispielkontakte;
  - Tastatur: **I/O → Keyboard → Toggle Software Keyboard** (⌘K);
  - Hell/Dunkel: **Features → Toggle Appearance** (⇧⌘A).
- **Netzstatus:** meldet ein fehlendes Netz direkt nach dem Flugmodus manchmal noch nicht. Verbindungsfehler deshalb zusätzlich über `ConnectionErrorClassifier` als „offline“ behandeln.
- **Compiler-Absturz (Swift 6.2):** „Command SwiftCompile failed with a nonzero exit code“ ohne weitere Meldung = Compiler abgestürzt.
  - Ursache im **Report Navigator (⌘9)** → letzter Build → Zeile „Compile …“ aufklappen; die Datei ohne `.dia` ist die abgestürzte.
  - Bekannte Auslöser: `async`-Form von Objective-C-Delegate-Methoden in `nonisolated` Typen; gespeicherte async-Closures ohne feste Isolation.
- **Xcode + Kabel + VPN:** Mit NordVPN bricht die Debug-Verbindung zum iPhone ab; VPN am Mac aus.
- **Git auf macOS:** Reine Groß-/Kleinschreibungs-Änderungen an Dateinamen erfasst Git nicht – über Zwischennamen in zwei Commits.
- **SwiftMail:**
  - baut abgerissene Verbindungen still neu auf, ohne den Ordner neu auszuwählen (abgefangen);
  - `deleteMailbox` löscht samt Inhalt (Vorprüfung in `FolderDeletion`);
  - liefert je Mail nur den ersten Text- und HTML-Teil (in `MessageContentPlan` für Folgen gelöst).
- **Apple Mail** schickt Fotos im Text als Folge von Teilen ohne Content-ID; **Spark** und Outlook nutzen `cid:`.
- **Postfächer:** im August 2026 per IMAPSYNC umgezogen; Sequenznummern sind kein Datumsindikator.
- **HTML-Mails** können fehlerhaft aufgebaut sein. Jede Verarbeitung von Mail-HTML muss tolerant sein und darf nicht an Tags ausschneiden; Ersetzungen nur per Textsuche.
