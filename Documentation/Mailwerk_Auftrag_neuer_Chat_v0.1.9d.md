# Mailwerk – Auftrag und Übergabe für den neuen Chat (ab v0.1.9d1)

Stand: 07.10.2026, nach Abschluss von v0.1.9c. Dieses Dokument ersetzt den Verlauf des bisherigen Chats. Es enthält Projektstand, Arbeitsregeln und den Auftrag.

---

## 1. Auftrag

Fortsetzung des Code-Reviews v0.1.9 mit **v0.1.9d1**. Danach folgen die weiteren Stufen in dieser Reihenfolge, **jede mit eigener Entwicklungsdoku (OnePager) und eigenem Commit**:

| Stufe | Inhalt |
|---|---|
| **d1 – Verhalten** | R1: überlappende Abrufe verhindern · Zitat in der Antwortansicht vollständig lesbar · erster Abruf, sobald Postfächer aus iCloud eintreffen · überflüssiges letztes Neuladen im Refresh · **M9:** große Mails > 5 MB ohne Anhang-Daten laden |
| **d2 – Struktur** | M1: Zugangsdaten/Verbindungsaufbau an einer Stelle · M2: `refresh()` zerlegen · M7: Aktionen ins ViewModel, ein Fehlerkanal, **einheitliche Rückfragen** (inkl. Beobachtung „Löschen per Menü reagiert manchmal nicht“) |
| **d3 – Aufräumen** | N24: `os.Logger` statt `print` (64 Aufrufe) · toter Code (Review Abschnitt 5) |
| **e1 – M5** | Externe Inhalte (Bilder, Tracking-Pixel) blockieren, mit „Externe Inhalte laden“; sicheres Zitieren von HTML beim Antworten (kein Regex-Sanitizing) |
| **e2 – N-Befunde** | Aufräumarbeiten N1–N23, N25, N26 (soweit sinnvoll) |
| **e3 – weitere Funde** | was sich bis dahin ergibt |
| **f – Inline-Doku** | Dokumentationsstandard auf alle übrigen Dateien |
| **Abschluss v0.1.9** | Diskussion M6 (eigenes Feld für die Absenderadresse); Kim möchte den Befund erst erklärt bekommen |

**Vorgehen für d1:** Zuerst Vorschlag mit Schritten vorlegen, auf OK warten, erst dann bauen. Bei **M9** vorher im Quellcode von SwiftMail prüfen, ob sich nur Struktur und Text-/HTML-Teile einer Mail holen lassen. M9 ändert den Abruf, also gelten die Testregeln für Abruf-Änderungen (siehe 3).

---

## 2. Arbeitsregeln (verbindlich)

- **Nichts bauen ohne OK.** Erst Vorschlag bzw. Antwort auf Fragen, dann auf ausdrückliche Freigabe warten. Fragen zuerst beantworten, nicht gleich handeln.
- **Schritt für Schritt:** Test- und Handlungsanweisungen einzeln geben und nach jedem Schritt auf Rückmeldung warten. Nicht mehrere Baustellen gleichzeitig öffnen.
- **Lieferung:** immer **komplette Dateien** als Download, dazu eine Tabelle *Datei · Zielordner · Art (neu/ersetzen)*. Keine Code-Schnipsel zum Einfügen, keine Claude-Code-Prompts.
- **Commit** macht Kim selbst in Xcode (und pusht), jeweils am Ende einer Stufe. Danach prüft Claude das Repo.
- **Xcode-Bezeichnungen exakt angeben** (Menüpfade, z. B. **Product → Clean Build Folder**). Xcode verwendet „Integrate“ und „Switch to …“. Das Simulator-Menü heißt **Device → Reset All Content and Settings**.
- **Keine Sonderlösungen** für Einzelfälle; bei mehreren Fehlversuchen anhalten und die Ursache belegen statt weiter nachzubessern.
- **Funde** während der Arbeit notieren und bewusst einplanen, nicht nebenbei patchen.
- **Tests dürfen keine Produktivmails verändern.** Testordner „Test Mailwerk“ im Webmail, Mails hineinkopieren.
- **Testaufwand gering halten:** Die verschiedenen Geräte kosten Kim die meiste Zeit. Nur die nötigsten Tests je Gerät vorsehen.

---

## 3. Test- und Dokumentationsstandard

**Tests:**
- Automatische Tests auf **Simulator oder My Mac**, nie auf dem iPhone. Dort startet Xcode die echte Installation mit, und die Geräteverbindung ist störanfällig.
- **Änderungen an Abruf oder Abgleich** immer mit dem größten Postfach (Kim.Sieber@ordinum.com, rund 8.780 Mails) und einer frischen Installation im Simulator testen.
- iPhone-Tests von Netzwerkverhalten **ohne Kabel**: per Kabel installieren, **Product → Stop**, Kabel ab, App vom Home-Bildschirm starten.
- Neue Funktionen auch auf dem **Mac** prüfen (Sandbox-Freigaben siehe Doku v0.1.9b).

**Inline-Dokumentation** (in jeder gelieferten Datei vollständig):
- Datei-Header mit Zweck, Abgrenzung und Abhängigkeiten.
- DocC-Kopf je Funktion: Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`.
- Testfunktionen: eine Zeile `///`.
- Deutsch, **keine Versionsverweise im Code**.

**OnePager je Stufe:** `Mailwerk_v0.1.9xx_Entwicklungsdokumentation.md` im Ordner `Documentation/`. Inhalt: Zusammenfassung, Problem/Lösung je Schritt, geänderte Dateien, Testverfahren mit Testzahl, Beobachtungen, nächste Schritte (Vorlage: v0.1.9b, v0.1.9c).

---

## 4. Projektstand

**Projekt:** Mailwerk, Mail-Client in Swift/SwiftUI für iOS und macOS. Repo `github.com/KimSieber/Mailwerk`, Branch `main`. Bundle `de.sieber-bw.Mailwerk`. Drei IMAP-Postfächer bei manitu.

**Technik:**
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Deployment Target iOS/macOS 26.5.
- Swift Testing (`@Test`, `#expect`).
- SwiftMail (Cocoanetics) ≥ 1.13.0 für IMAP/SMTP. Wird nicht geforkt; Paket-Updates in eigenem Commit.
- Mail-Cache: System-SQLite `MessageStore` (WAL, Transaktionen mit Rollback, Schema-Stufe **3**, Ordner `Cache` ohne Backup).
- Postfächer im iCloud-Key-Value-Speicher, Passwörter im iCloud-Schlüsselbund, Filterlisten über SwiftData/CloudKit.

**Erledigte Stufen von v0.1.9:**

| Stufe | Inhalt | Commit |
|---|---|---|
| a | K1–K4 (Ordner bei Markierung/Anhang, Keychain, Dateinamen, WebView-Sicherheit); a1b zurückgenommen | `f77b912`, `fa005a2`, `cfd1bdb` |
| b | Transaktionen, atomares Speichern, WAL, `user_version` (H1, H4, M8); Sync-Zustand je Ordner mit UIDVALIDITY/UIDNEXT (H2); Wiederherstellung statt `fatalError`; Mac-Sandbox | `de2022e` |
| c | Liste ohne Mailinhalte, Vorschau, Index (K5); robuster Abruf bei Verbindungsabbruch; ViewModel einmal anlegen; HTML nur bei Änderung (M4); Refresh-Knopf Mac | *von Kim nach diesem Dokument* |

**Tests:** 348, alle grün.

**Wichtige Bausteine aus c, die d betreffen:**
- `MessageListItem`: Listeneintrag ohne Mailinhalt; die vollständige Mail lädt `MessageDetailLoader` (in `InboxView.swift`) beim Öffnen.
- `AppObjects` (in `ContentView.swift`): alle langlebigen Objekte, einmal in `MailwerkApp.init` angelegt.
- `MailFetchService.cacheMessages` → `storeNewMessage`: bei Fehler Ordner neu auswählen und die Mail einmal wiederholen. Fensterbeginn und UIDNEXT rücken nur bei vollständigem Laden vor.
- Debug-Messung: `⏱ Liste aus Cache …`, `⏱ Mail geöffnet …`, `⏱ HTML geladen …`.

---

## 5. Review-Befunde: Stand

Bericht: `Documentation/v0.1.8d - Code-Review-Mailwerk.md`.

| Stand | Befunde |
|---|---|
| Erledigt | K1–K5, H1–H5, M4, M8 |
| Geprüft, kein Handlungsbedarf | M3 (gemessen), M10 (MainActor; Transaktionen mit b), K5 Teil 5 (Laden im Hintergrund; nach c2 nur 2–27 ms) |
| Geplant | M9 (d1), M1, M2, M7 (d2), N24, toter Code (d3), M5 (e1), N-Befunde (e2), Dokumentation (f), M6 (Diskussion am Schluss) |
| Verschoben | H6 (Verbindungen wiederverwenden), ggf. mit der Push-Stufe → Technical-Debt-Liste; Strukturempfehlungen (Protokolle/Injektion, SwiftLint, Lokalisierung) |

---

## 6. Bekannte Besonderheiten der Umgebung

- **Xcode + Kabel + VPN:** Mit NordVPN auf Mac und iPhone bricht die Debug-Verbindung ab: „Connection interrupted“, „Failed to create directory on device“, Konsole stoppt, App scheint eingefroren. Für die Installation VPN am Mac aus; Netzwerk-Tests ohne Kabel.
- **Simulator:**
  - kein CloudKit-Abgleich der Filterlisten (dort Testeinträge von Hand anlegen);
  - kein iCloud-Schlüsselbund (Passwörter von Hand eingeben);
  - Tastatur nimmt gelegentlich nur ein Zeichen an → Simulator neu starten.
- **SwiftMail-Verhalten:** baut abgerissene Verbindungen still neu auf, ohne den Ordner neu auszuwählen (abgefangen in c2b).
- **SwiftMail 1.14.0** (06.10.2026) bietet `deleteMailbox`/`renameMailbox` öffentlich an. Der eigene IMAP-Weg zum Löschen von Ordnern (`FolderDeletion`, `IMAPLineConnection`) kann zurückgebaut werden; als eigener Commit einplanen.
- **Postfächer:** Im August 2026 per IMAPSYNC umgezogen; Sequenznummern sind kein Datumsindikator.

---

## 7. Erster Schritt im neuen Chat

1. Repo auf den Commit von v0.1.9c prüfen: alle Dateien wie geliefert, 348 Tests, `MARKETING_VERSION` 0.1.9c.
2. Vorschlag für **d1** vorlegen: Reihenfolge der fünf Punkte, je Punkt kurz Problem, Lösungsansatz und Test. Für M9 vorher die SwiftMail-API prüfen.
3. Auf Kims OK warten.
