# Mailwerk – Auftrag und Übergabe für den neuen Chat (ab v0.1.11)

Stand: 11.10.2026, nach Abschluss von v0.1.10 (Commit `20d4313`, Version 0.1.10). Dieses Dokument ersetzt den Verlauf des bisherigen Chats. Es enthält Projektstand, Fahrplan, Arbeitsregeln und den Auftrag.

---

## 1. Auftrag

**Erster Schritt im neuen Chat:**
1. Projektordner freigeben lassen und Repo prüfen: Commit `20d4313` (oder später), **431 Tests**, lokale Dateien = Repo-Stand.
2. Mit Kim den **Inhalt von v0.1.11** genau abstimmen. Kim hat konkrete Vorstellungen – erst seine Beschreibung einholen, dann Leitfragen, dann Umfang und MVP-Aufteilung zur Freigabe vorlegen. Überschriften allein reichen nicht.
3. Erst nach ausdrücklicher Freigabe bauen.

## 2. Fahrplan bis zum Live-Gang (von Kim festgelegt)

| Version | Thema | Stand / Inhalt |
|---|---|---|
| v0.1.10 | Absenderbild in der Mailliste (MW-7) | **erledigt** |
| **v0.1.11** | **Mehrere Mails markieren und per langem Drücken bearbeiten (MW-9)** | Kontextmenü per langem Drücken, Mehrfachauswahl, Sammelaktionen (löschen, verschieben, kennzeichnen …). Vorher `MessageDetailView` (~800 Zeilen) aufteilen (N13). Kontextmenü auch bei Ordnern nur per langem Drücken, kein Drei-Punkte-Symbol. |
| v0.1.12 | Mails vollständig und lesbar anzeigen | `cid:`-Bilder, Dunkelmodus-Lesbarkeit, Zoomen; als letztes, abtrennbares MVP Originaltext/Header anzeigen (MW-5, niedrige Priorität) |
| v0.1.13 | Signaturen und Entwürfe beim Verfassen (MW-2, MW-16) | Signaturen (HTML, je Postfach), „Entwurf speichern“ beim Schließen, Entwurf weiterbearbeiten, Beantwortet-Kennzeichen setzen |
| v0.1.14 | Dateien und Inhalte aus anderen Apps an Mailwerk teilen (MW-15) | Share Extension (eigenes Ziel, App Group, Schlüsselbundgruppe) – für Kim wichtig |
| v0.1.15 | Suche über alle Mails (MW-6) | Eingabe am unteren Rand (Bereich freigehalten), lokaler Suchindex; Umfang lokal/Server noch offen |
| v0.2.x | Seitenleiste und Layout für iPad und Mac | Kim hat viele Anmerkungen; dort gesammelt |
| später | H6 Verbindungen wiederverwenden, Push/IDLE, N14 Offline-Warteschlange, Ordner abonnieren, Posteo, Threading | nach Live |

Noch offen: was „Live“ genau heißt (TestFlight eigene Geräte oder App Store).

---

## 3. Arbeitsregeln (verbindlich)

- **Nichts bauen ohne OK.** Erst Vorschlag bzw. Antwort auf Fragen, dann auf ausdrückliche Freigabe warten.
- **Schritt für Schritt:** Test- und Handlungsanweisungen einzeln geben und nach jedem Schritt auf Rückmeldung warten. Große Umsetzungen in 3–4 Abschnitte mit eigenem Testpunkt teilen (z. B. a, b, c1, c2).
- **Klar reden:** Jede Anweisung ohne Vorwissen ausführbar – genauer Menüpfad, genaue Bezeichnung, was danach zu sehen sein soll.
- **Lieferung – Projektordner:**
  - Claude legt Dateien **direkt in Kims Projektordner** `/Users/kim/Dropbox/Dev/GitHub/Mailwerk` (Zugriff über die Desktop-App, Ordnerfreigabe anfragen).
  - **Vorher** prüfen, dass die betroffenen lokalen Dateien dem Repo-Stand bzw. der letzten Lieferung entsprechen (`git status`, `git diff`), damit keine lokale Änderung überschrieben wird.
  - Immer eine Tabelle *Datei · Ort · Art (neu/ersetzt/löschen)*.
  - **Löschen** macht Kim selbst in Xcode.
  - Ganze Dateien, keine Code-Schnipsel, keine Claude-Code-Prompts.
  - **Projekteinstellungen** (Build Settings, Info-Texte) ändert Kim selbst in Xcode nach genauer Anleitung; Claude prüft danach die Projektdatei.
- **Entwicklungsdokumentationen** (OnePager, Übergaben): im Ordner `Documentation/` und zusätzlich **als Download im Chat**.
- **Neue Dateien:** auf **Target Membership** im Dateiinspektor (⌥⌘1) hinweisen (App: `Mailwerk`, Tests: `MailwerkTests`).
- **Commit:**
  - **Claude committet niemals.** Ob ein Stand commit-reif ist und der Commit selbst bleiben immer Kims Aufgabe, in Xcode (**Integrate → Commit…**, Push).
  - Commits je abgeschlossenem MVP sind möglich; nie ein nicht lauffähiger Stand.
  - Nach dem Push prüft Claude das Repo.
- **Funde** notieren und bewusst einplanen, nicht nebenbei patchen.
- **Keine Sonderlösungen** für Einzelfälle oder Übergangseffekte (alle Installationen sind Testinstallationen). **Bei mehreren Fehlversuchen anhalten und die Ursache belegen** – nicht raten.
- **Tests dürfen keine Produktivmails verändern.** Testordner „Test Mailwerk“ im Webmail, Mails hineinkopieren. Antworten nur an sich selbst.
- **Testaufwand gering halten:** nur die nötigsten Tests je Gerät.
- **Formulare:** Felder mit klarer, fester Beschriftung und angedrucktem Beispiel (`LabeledInputField`).

---

## 4. Test- und Dokumentationsstandard

**Tests:**
- Automatische Tests auf **Simulator** oder **My Mac**, nie auf dem iPhone.
- Änderungen an Abruf oder Abgleich immer mit dem größten Postfach (Kim.Sieber@ordinum.com, rund 8.800 Mails) und einer **frischen Installation** im Simulator testen (App durch langes Drücken entfernen, neu starten).
- Neue Funktionen kurz auch auf dem **Mac** prüfen (Gestaltung iPad/Mac erst v0.2.x).
- Erwartete Testzahl bei jeder Lieferung nennen.
- Protokoll: Xcode-Konsole (Kategorien Abruf, Aktionen, Spam, Versand, Cache, Ansicht) oder App **Konsole** auf dem Mac.

**Inline-Dokumentation** (in jeder neuen oder geänderten Datei vollständig):
- Datei-Header mit **Zweck**, **Abgrenzung** und **Abhängigkeiten**.
- DocC-Kopf je Funktion: Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`. Gespeicherte Eigenschaften und Typen mit einer Zeile.
- Testfunktionen und Testhilfen: eine Zeile `///`.
- Deutsch, **keine Versionsverweise im Code**.

**OnePager je Version:** `Documentation/Mailwerk_v0.1.xx_Entwicklungsdokumentation.md` – Zusammenfassung mit Entscheidungen, Problem/Lösung je MVP, geänderte Dateien, Testverfahren mit Testzahl, Beobachtungen, nächste Schritte. Vorlage: v0.1.10.

---

## 5. Projektstand

**Projekt:** Mailwerk, Mail-Client in Swift/SwiftUI für iOS und macOS. Repo `github.com/KimSieber/Mailwerk`, Branch `main`. Bundle `de.sieber-bw.Mailwerk`. Drei IMAP-Postfächer bei manitu. `MARKETING_VERSION` 0.1.10. **431 Tests.**

**Technik:**
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, Approachable Concurrency (nonisolated async = `nonsending`), MemberImportVisibility; Deployment Target iOS/macOS 26.5.
  - Jede Datei braucht ihren eigenen `import`.
  - Arbeit, die neben dem Main-Actor laufen soll: `@concurrent` (z. B. `SenderIconFetcher.fetch`) oder `Task.detached` mit synchroner Funktion.
- Xcode-Projekt mit synchronisierten Ordnern; Swift Testing (`@Test`, `#expect`).
- **SwiftMail 1.15.0** (wird nicht geforkt). Keine weiteren Pakete; neue nur nach Rückfrage.
- Mail-Cache: System-SQLite `MessageStore`, WAL und Transaktionen, **Schema-Stufe 5** (Tabelle `sender_icon`), Header-Version 2, Ordner `Cache` ohne Backup, Sync-Zustand je Ordner.
- Postfächer im iCloud-Key-Value-Speicher, Passwörter im iCloud-Schlüsselbund, Filterlisten über SwiftData/CloudKit.

**Mailliste (seit v0.1.10):**
- `MessageRow` (drei Zeilen: Kennzeichen/Datum, Name fett bei ungelesen + Adresse grau, Betreff), Farbstreifen 4/8 pt.
- `MessageRowParty` (Absender bzw. erster Empfänger in Gesendet/Entwürfen), `ListDateFormatter`.
- Kreis `SenderAvatarView`: Kontaktbild (`ContactImageDirectory`, nur im Speicher) → Logo (`SenderIconCache` + `SenderIconFetcher`, je Hauptdomain in `sender_icon`, 30/90 Tage) → Initialen; leer, wenn `SpamClassifier.allowsSenderImage` nein sagt.
- `InboxViewModel` hält eine Kopie der Filterlisten für diese Entscheidung.

**Weitere Bausteine:** `MailAccount` (`emailAddress`, `loginName`, `senderAddress`), `MailSession`, `MessageActions`, `FetchCoordinator`, `MessageContentPlan`, `Dialogs` (`AlertItem`, `ConfirmationRequest`), `HTMLMailView` (CSP, externe Inhalte per Knopf, Whitelist lädt sofort über `trustsSender`), `ReplyBuilder`, `SpamClassifier` (`classify`, `trustsSender`, `allowsSenderImage` – gemeinsamer `listMatch`), `LabeledInputField`, `Log` (Zahlen, Ordner, Fehler öffentlich; Adressen, Postfachnamen, Domains privat).

---

## 6. Liste offener Punkte

- **N13:** `MessageDetailView` aufteilen – Vorarbeit für v0.1.11.
- **DKIM / Authentication-Results:** später prüfen, für Logos und ggf. Spam-Prüfung.
- **H6:** Verbindungen je Konto wiederverwenden (ggf. mit Push-Stufe).
- **N14 „Warteschlange offline“:** Aktionen ohne Netz merken und später ausführen.
- **`cid:`-Bilder, Dunkelmodus, Zoomen** → v0.1.12.
- **Ordner abonnieren:** In Mailwerk angelegte Ordner werden nicht abonniert (SwiftMail ohne SUBSCRIBE).
- **Vorschau (`preview`)** wird weiter gespeichert, aber nicht mehr angezeigt – bei Gelegenheit klären, ob sie entfällt (Schema, Tests) oder für die Suche bleibt.
- **Strukturempfehlungen:** Protokolle/Injektion für Tests ohne Server, SwiftLint/SwiftFormat, Lokalisierung.
- **Empfangsdatum** statt Kopfdatum (robuster gegen gefälschte Daten im Spam) – bewusst nicht umgesetzt, nur bei Bedarf.

---

## 7. Bekannte Besonderheiten der Umgebung

- **Simulator:** behält Postfächer und Passwörter (iCloud-Speicher des Simulators), solange er nicht neu aufgesetzt wird; kein CloudKit-Abgleich der Filterlisten mit echten Geräten; zeigt private Protokollwerte im Klartext; hat nur Beispielkontakte (für Kontaktbilder eigenen Kontakt mit Foto anlegen); Tastatur: **I/O → Keyboard → Toggle Software Keyboard** (⌘K).
- **Compiler-Absturz (Swift 6.2):** „Command SwiftCompile failed with a nonzero exit code“ ohne weitere Meldung = Compiler abgestürzt. Ursache im **Report Navigator (⌘9)** → letzter Build → Zeile „Compile …“ aufklappen (Symbol mit Linien); die Datei ohne `.dia` ist die abgestürzte. Der in der Übersicht genannte Dateiname kann eine andere Datei derselben Übersetzungsgruppe sein. Bekannte Auslöser: `async`-Form von Objective-C-Delegate-Methoden in `nonisolated` Typen; gespeicherte async-Closures ohne feste Isolation (siehe `FolderCatalog`).
- **Xcode + Kabel + VPN:** Mit NordVPN bricht die Debug-Verbindung zum iPhone ab; VPN am Mac aus.
- **Git auf macOS:** Reine Groß-/Kleinschreibungs-Änderungen an Dateinamen erfasst Git nicht – über Zwischennamen in zwei Commits.
- **SwiftMail:** baut abgerissene Verbindungen still neu auf, ohne den Ordner neu auszuwählen (abgefangen); `deleteMailbox` löscht samt Inhalt (Vorprüfung in `FolderDeletion`).
- **Postfächer:** im August 2026 per IMAPSYNC umgezogen; Sequenznummern sind kein Datumsindikator.
- **HTML-Mails** können fehlerhaft aufgebaut sein; jede Verarbeitung von Mail-HTML muss tolerant sein und darf nicht an Tags ausschneiden.
