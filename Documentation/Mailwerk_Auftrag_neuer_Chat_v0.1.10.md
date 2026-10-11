# Mailwerk – Auftrag und Übergabe für den neuen Chat (ab v0.1.10)

Stand: 11.10.2026, nach Abschluss von v0.1.9 (Commit `e043466`, Version 0.1.9g). Dieses Dokument ersetzt den Verlauf des bisherigen Chats. Es enthält Projektstand, Arbeitsregeln und den Auftrag.

---

## 1. Auftrag

Das Code-Review v0.1.9 ist abgeschlossen. Jetzt folgen **funktionale Erweiterungen auf dem Weg zum ersten Live-Gang**.

**Erster Schritt im neuen Chat:**
1. Repo prüfen: Commit `e043466` (oder später), 388 Tests.
2. Mit Kim den **Fahrplan bis zur ersten Live-Version** festlegen: welche Funktionen dafür nötig sind und in welcher Reihenfolge (je Version ein Thema, aufgeteilt in kleine MVPs a, b, c …). Kim entscheidet, Claude schlägt vor und zeigt Abhängigkeiten.
3. Danach mit der ersten Version beginnen.

**Bisher vorgemerkt** (Reihenfolge und Umfang mit Kim bestätigen):

| Thema | Stand |
|---|---|
| **v0.1.10 – Kontextmenü für Mails** per langem Drücken, inkl. Mehrfachauswahl | geplant seit v0.1.8d; Kontextmenü auch für Ordner nur per langem Drücken (kein Drei-Punkte-Symbol) |
| Signaturen | HTML-Signaturen zur Auswahl, teils je Postfach unterschiedlich |
| Suche | Eingabe am unteren Bildschirmrand; dieser Bereich ist dafür freigehalten |
| Seitenleiste für iPad und Mac | Mac feste Leiste, iPad je nach Hoch-/Querformat; Mac-Tests der Ordnerleiste stehen bis dahin zurück |
| Push / IDLE | spätere Stufe (0.4.x); Push derzeit nicht gewünscht |

Dazu kommen die offenen Punkte aus Abschnitt 5, soweit sie für den Live-Gang nötig sind.

---

## 2. Arbeitsregeln (verbindlich)

- **Nichts bauen ohne OK.** Erst Vorschlag bzw. Antwort auf Fragen, dann auf ausdrückliche Freigabe warten. Fragen zuerst beantworten, nicht gleich handeln.
- **Schritt für Schritt:** Test- und Handlungsanweisungen einzeln geben und nach jedem Schritt auf Rückmeldung warten. Große Umsetzungen in 3–4 Abschnitte mit eigenem Testpunkt teilen.
- **Klar reden:** Jede Anweisung muss ohne Vorwissen ausführbar sein – genauer Menüpfad, genaue Bezeichnung, was danach zu sehen sein soll.
- **Lieferung – Projektordner:**
  - Claude legt Dateien **direkt in Kims Projektordner** `/Users/kim/Dropbox/Dev/GitHub/Mailwerk` (Zugriff über die Desktop-App, Kim gibt den Ordner frei).
  - **Vorher** per Prüfsumme sicherstellen, dass die lokalen Fassungen dem Repo-Stand bzw. der letzten Lieferung entsprechen. So wird keine lokale Änderung überschrieben.
  - Dazu immer eine Tabelle *Datei · Ort · Art (neu/ersetzt/löschen)*.
  - **Löschen** macht Kim selbst in Xcode (Delete → Move to Trash).
  - Ganze Dateien, keine Code-Schnipsel, keine Claude-Code-Prompts.
- **Entwicklungsdokumentationen** (OnePager, Übergaben): zusätzlich **als Download im Chat**; Kim legt sie selbst in den Projektkontext.
- **Neue Dateien:** auf die Prüfung von **Target Membership** im Dateiinspektor (⌥⌘1) hinweisen (App: `Mailwerk`, Tests: `MailwerkTests`).
- **Commit:**
  - **Claude committet niemals.** Ob ein Stand commit-reif ist und der Commit selbst bleiben immer Kims Aufgabe, in Xcode (**Integrate → Commit…**, Push to remote).
  - Nie einen nicht lauffähigen Stand committen; ein im Test gefundener Fehler wird vorher behoben.
  - Nach dem Push prüft Claude das Repo.
- **Funde** während der Arbeit notieren und bewusst einplanen, nicht nebenbei patchen.
- **Keine Sonderlösungen** für Einzelfälle oder einmalige Übergangseffekte (alle Installationen sind Testinstallationen aus Xcode). Bei mehreren Fehlversuchen anhalten und die Ursache belegen.
- **Tests dürfen keine Produktivmails verändern.** Testordner „Test Mailwerk“ im Webmail, Mails hineinkopieren. Antworten nur an sich selbst (An auf Kim.Sieber@ordinum.com ändern).
- **Testaufwand gering halten:** nur die nötigsten Tests je Gerät.
- **Formulare:** Felder mit klarer, fester Beschriftung und angedrucktem Beispiel (`LabeledInputField`).

---

## 3. Test- und Dokumentationsstandard

**Tests:**
- Automatische Tests auf **Simulator** oder **My Mac**, nie auf dem iPhone.
- **Änderungen an Abruf oder Abgleich** immer mit dem größten Postfach (Kim.Sieber@ordinum.com, rund 8.800 Mails) und einer **frischen Installation** im Simulator testen. Das heißt: App durch langes Drücken auf das Symbol entfernen, dann neu starten.
- Neue Funktionen auch auf dem **Mac** prüfen.
- Erwartete Testzahl bei jeder Lieferung nennen.
- Simulator-Tastatur: **I/O → Keyboard → Toggle Software Keyboard** (⌘K).
- Protokoll: Xcode-Konsole (Kategorien Abruf, Aktionen, Spam, Versand, Cache, Ansicht) oder App **Konsole** auf dem Mac.

**Inline-Dokumentation** (in jeder neuen oder geänderten Datei vollständig):
- Datei-Header mit **Zweck**, **Abgrenzung** und **Abhängigkeiten**.
- DocC-Kopf je Funktion: Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`. Gespeicherte Eigenschaften und Typen mit einer Zeile.
- Testfunktionen und Testhilfen: eine Zeile `///`.
- Deutsch, **keine Versionsverweise im Code**.
- Seit v0.1.9f sind **alle** Dateien auf diesem Stand.

**OnePager je Stufe:** `Mailwerk_v0.1.xx_Entwicklungsdokumentation.md` im Ordner `Documentation/`. Inhalt: Zusammenfassung mit Entscheidungen, Problem/Lösung je Schritt, geänderte Dateien, Testverfahren mit Testzahl, Beobachtungen, nächste Schritte. Vorlagen: v0.1.9e1, v0.1.9g.

---

## 4. Projektstand

**Projekt:** Mailwerk, Mail-Client in Swift/SwiftUI für iOS und macOS. Repo `github.com/KimSieber/Mailwerk`, Branch `main`. Bundle `de.sieber-bw.Mailwerk`. Drei IMAP-Postfächer bei manitu. `MARKETING_VERSION` 0.1.9g. 87 App-Dateien, 39 Testdateien, 388 Tests.

**Technik:**
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, Approachable Concurrency, MemberImportVisibility; Deployment Target iOS/macOS 26.5.
  - Statische Werte als Standardparameter müssen `nonisolated` sein.
  - Jede Datei braucht ihren eigenen `import` (z. B. `import os` für `Log`).
- Xcode-Projekt mit synchronisierten Ordnern; Swift Testing (`@Test`, `#expect`).
- **SwiftMail 1.15.0** (wird nicht geforkt; Paket-Updates in eigenem Commit). Keine weiteren Pakete; neue Pakete nur nach Rückfrage.
- Mail-Cache: System-SQLite `MessageStore`.
  - WAL und Transaktionen, **Schema-Stufe 4** (Spam-Angabe je Mail), **Header-Version 2**.
  - Ordner `Cache` ohne Backup; Sync-Zustand je Ordner (UIDVALIDITY/UIDNEXT).
- Postfächer im iCloud-Key-Value-Speicher, Passwörter im iCloud-Schlüsselbund, Filterlisten über SwiftData/CloudKit.

**Wichtige Bausteine:**
- **Postfach:** `MailAccount` mit `emailAddress` (Pflicht im Formular), `username` (tatsächlicher Anmeldename) und `senderAddress`.
  - `MailAccount.loginName`: Benutzername leer = Anmeldung mit der Adresse.
  - Beim Bearbeiten erscheint der Benutzername nur, wenn er von der Adresse abweicht.
- **Verbindungen und Aktionen:** `MailSession` (Zugangsdaten, `withIMAP`), `MessageActions`, `FetchCoordinator`, `MessageContentPlan`, `Dialogs` (`AlertItem`, `ConfirmationRequest`).
- **Anzeige von HTML-Mails:**
  - `HTMLMailView`: JavaScript aus, Navigation gesperrt, CSP aus `RemoteContentPolicy`.
  - Externe Inhalte sind gesperrt; Knopf „Laden“ je Anzeige.
  - Whitelist-Absender laden sofort (`SpamClassifier.trustsSender`, Score-Obergrenze, unbekannte Spam-Angabe = nicht vertraut).
  - Drucken und Teilen folgen der Anzeige.
- **Zitat:** `ReplyBuilder.withoutDocumentWrapper` entfernt nur die Hüllen-Tags, sonst unverändert.
- **Spamfilter:** `SpamClassifier` mit gemeinsamem Listenabgleich `listMatch` für Filterlauf und Anzeige.
- **Formulare:** `LabeledInputField` (Beschriftung + Feld mit Beispiel).
- **Protokoll:** `Log` (os.Logger) mit Kategorien. Zahlen, Ordner und Fehler öffentlich; Postfachnamen, Adressen und Message-IDs privat.

**Commits v0.1.9 seit e1:**

| Stufe | Inhalt | Commit |
|---|---|---|
| e1a | Externe Inhalte sperren (CSP), Knopf „Laden“ | `2785a45` |
| e1b | Whitelist lädt sofort, Spam-Angabe im Cache; Dateiname SpamClassifier | `7ed8661`, `bc0c15e`, `d014020` |
| e1c | Zitat unverändert (nur Hüllen-Tags) | `e549633` |
| e3 | Funde aus e2 | `52b0ed1` |
| f | Inline-Doku für alle übrigen Dateien | `c7e99e5` |
| g | Eigene E-Mail-Adresse je Postfach (M6) – Abschluss v0.1.9 | `e043466` |

OnePager: `Documentation/Mailwerk_v0.1.9e1_…`, `…e3_…`, `…f_…`, `…g_…`.

---

## 5. Liste offener Punkte (bewusst nicht in v0.1.9)

- **H6:** Verbindungen je Konto wiederverwenden; heute baut jede Aktion eine neue TLS-Verbindung auf. Ggf. mit der Push-Stufe.
- **N14 Teil „Warteschlange offline“:** Aktionen ohne Netz merken und später ausführen.
- **N13:** `MessageDetailView` (rund 800 Zeilen) in Kopfbereich, Anhangliste und Menü aufteilen. Passt gut zum Kontextmenü (v0.1.10).
- **`cid:`-Bilder:** Eingebettete Bilder werden nicht gespeichert und erscheinen als fehlendes Bild.
- **Dunkelmodus:** HTML-Mails mit eigenem weißem Hintergrund, aber ohne Textfarbe erscheinen hellgrau auf weiß (z. B. Sunweb auf dem Mac). Lösung wie Apple Mail oder HTML-Mails immer als helle Karte.
- **Zoomen in Mails:** einheitlich lösen, Gestenkonflikt vorher analysieren.
- **Ordner abonnieren:** In Mailwerk angelegte Ordner werden nicht abonniert (SwiftMail hat kein SUBSCRIBE).
- **Strukturempfehlungen:** Protokolle/Injektion für Tests ohne Server, SwiftLint/SwiftFormat, Lokalisierung.
- **Beobachtung „Löschen per Menü reagiert manchmal nicht“:** nur bei erneutem Auftreten aufnehmen.

---

## 6. Bekannte Besonderheiten der Umgebung

- **Xcode + Kabel + VPN:** Mit NordVPN bricht die Debug-Verbindung zum iPhone ab; für die Installation VPN am Mac aus.
- **Simulator:** kein CloudKit-Abgleich der Filterlisten, kein iCloud-Schlüsselbund; zeigt private Protokollwerte im Klartext; Tastatur nimmt gelegentlich nur ein Zeichen an (Simulator neu starten).
- **Git auf macOS:** Reine Groß-/Kleinschreibungs-Änderungen an Dateinamen erfasst Git nicht. Umbenennen über einen Zwischennamen in zwei Commits.
- **SwiftMail:** baut abgerissene Verbindungen still neu auf, ohne den Ordner neu auszuwählen (abgefangen); `deleteMailbox` löscht samt Inhalt (Vorprüfung in `FolderDeletion`).
- **Postfächer:** im August 2026 per IMAPSYNC umgezogen; Sequenznummern sind kein Datumsindikator.
- **Bestehende Installationen:** Mails, die vor Schema-Stufe 4 im Cache lagen, haben keine Spam-Angabe und zeigen auch bei Whitelist-Absendern den Knopf „Laden“. Gewollt; echte Installationen beginnen frisch.
- **HTML-Mails** können fehlerhaft aufgebaut sein (z. B. ein zweites Dokument mittendrin). Jede Verarbeitung von Mail-HTML muss tolerant sein wie ein Browser und darf nicht an Tags ausschneiden.
