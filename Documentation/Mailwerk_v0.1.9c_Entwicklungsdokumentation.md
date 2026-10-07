# Mailwerk – Entwicklungsdokumentation v0.1.9c

2026-10-07 · Performance der Liste, robuster Abruf bei Verbindungsabbruch (Code-Review Teil 3)

---

## Zusammenfassung

v0.1.9c macht die Nachrichtenliste deutlich schneller und den Abruf robust gegen abreißende Verbindungen:

- **c1:** Laufzeitmessung in Debug-Builds (`⏱`-Zeilen) als Grundlage.
- **c2:** Die Liste lädt keine Mailtexte mehr, sondern nur Kopfdaten und eine Vorschau von 200 Zeichen. Die vollständige Mail wird erst beim Öffnen gelesen. Neuer Index für die Sortierung nach Datum (Review-Befund K5).
- **c2b (neuer Fund):** Nach einem Verbindungsabbruch scheiterte der Rest einer Abrufrunde, und bei „Ältere laden“ konnten dauerhaft Lücken entstehen. Beides ist behoben.
- **c3:** Das ViewModel der Liste entsteht nur noch einmal; der HTML-Inhalt einer Mail wird nur bei Änderung neu geladen (Review-Befund M4).
- **Mac:** eigener Refresh-Knopf (⌘R).

Ergebnis: Die Liste lädt rund **10-mal schneller** und liest über **200-mal weniger Daten**.

| Gerät | Mails | vorher (c1) | nachher |
|---|---|---|---|
| Simulator / Mac | ~314 | 22–56 ms, 11 MB Mailtext | 2–6 ms, 42 KB Vorschau |
| iPhone | 612 | 70–104 ms, 24 MB Mailtext | 4–20 ms, 79 KB Vorschau |
| iPhone | 798 | – | 16–27 ms, 107 KB Vorschau |
| Mail öffnen | – | – | 0–7 ms, auch bei 173 KB |

---

## c1 – Messung

In Debug-Builds gibt `InboxViewModel.loadFromCache()` je Aufruf eine Zeile aus:
`⏱ Liste aus Cache #n: X Mails, Y ms, Vorschautexte Z KB, Ansichtsabfragen seither: Q`.

Erkenntnisse:
- Die Ladezeit wuchs linear mit der Zahl der Mails (rund 40 KB und 0,15 ms je Mail), weil jede Mail mit ihrem ganzen Text gelesen wurde.
- Die Ansicht fragt zwischen zwei Ladevorgängen nur 0–6-mal die Datenbank ab → **M3: gemessen, kein Handlungsbedarf.**
- Das ViewModel wurde doppelt angelegt (`#1` erschien zweimal) → c3.

---

## c2 – Liste ohne Mailinhalte (K5)

**Problem:** Jede Aktualisierung der Liste las Text und HTML aller angezeigten Mails, im Mittel rund 40 KB je Mail. Bei 612 Mails waren das 24 MB bei jedem Neuladen, auf dem Main-Thread.

**Lösung:**
- Neuer Typ `MessageListItem`: alle Felder einer Listenzeile (Kopfdaten, Kennzeichen, Anhang ja/nein, Vorschau), aber kein Mailinhalt. Weil es ein eigener Typ ist, verhindert der Compiler, dass eine Stelle versehentlich mit einem Listeneintrag statt der vollständigen Mail arbeitet, etwa beim Antworten.
- `allMessages`, `folderMessages` und `flaggedInboxMessages` liefern `[MessageListItem]`. `message(id:)` liefert weiter die vollständige `CachedMessage`.
- Beim Öffnen lädt `MessageDetailLoader` die vollständige Mail aus dem Cache. Ist sie inzwischen gelöscht oder verschoben, erscheint „Nachricht nicht mehr vorhanden“.
- **Datenbank, Schema-Stufe 3:**
  - neue Spalte `preview`, gebildet beim Speichern aus den ersten 200 Zeichen des Textteils;
  - neuer Index `idx_message_account_folder_date` auf (Konto, Ordner, Datum absteigend), damit die Sortierung ohne Zwischentabelle läuft;
  - der alte Index `idx_message_account_folder` entfällt.
  - Die Migration trägt die Vorschau für vorhandene Mails einmalig nach.
- Die Liste ist in eigene Teile ausgelagert (`messageList`, `messageRow(for:)`). Im großen `body` überschritt der Ausdruck die Prüfzeit des Compilers.

**Nicht umgesetzt (bewusst):** Laden im Hintergrund und Entprellen (K5, Punkt 5). Nach c2 dauert das Laden 2–27 ms, das rechtfertigt den Umbau nicht.

---

## c2b – Abruf bei Verbindungsabbruch (neuer Fund)

**Auslöser:** Auf dem iPhone (Hotel-WLAN mit VPN, per Kabel an Xcode) brach „Ältere laden“ mit vielen Meldungen `No mailbox selected` ab.

**Ursache (im Quellcode von SwiftMail belegt):** Reißt eine Verbindung ab, baut SwiftMail sie beim nächsten Befehl still neu auf und meldet sich neu an. Den zuvor ausgewählten Ordner wählt es aber nicht erneut aus. Ab dann scheitert jeder weitere Befehl der Runde.

**Folgen vorher:**
- Der Rest der Abrufrunde schlug fehl, mit Fehlermeldung. Die Datenbank blieb heil, der nächste Abruf funktionierte wieder.
- Bei „Ältere laden“ rückte der Fensterbeginn trotzdem zurück. Übersprungene Mails dieses Zeitraums wurden nie mehr geladen.
- Dasselbe galt für Neuankünfte: UIDNEXT rückte vor, auch wenn eine Mail fehlte.

**Lösung:**
1. Das Laden einer neuen Mail steckt in der eigenen Funktion `storeNewMessage`. Schlägt es fehl, wählt `cacheMessages` den Ordner neu aus und versucht die Mail genau einmal erneut:
   - klappt es, lief nur die Verbindung neu, und der Abruf geht normal weiter;
   - scheitert die Mail erneut, ist sie selbst defekt, wird übersprungen und als fehlgeschlagen gezählt;
   - scheitert schon die neue Auswahl, ist die Verbindung tot, und die Runde bricht sauber ab.
2. **Fensterbeginn** (`SyncWindow.startAfterLoading`) und **UIDNEXT** (`SyncStatePlanner.uidNextAfterLoading`) rücken nur vor, wenn alle Mails eines Schritts gespeichert wurden. Sonst versucht der nächste Abruf bzw. Tipp denselben Bereich erneut.
3. Bleibt bei „Ältere laden“ etwas offen, erscheint der Hinweis „n ältere Nachrichten konnten nicht geladen werden. Bitte „Ältere laden“ erneut tippen.“

`cacheMessages` liefert jetzt gespeicherte und fehlgeschlagene Mails (`CacheResult`); `OlderFetchResult.loaded` enthält zusätzlich `failed`.

**Einfrieren und Konsolenabbrüche:** Ohne Kabel lief die App einwandfrei. Die Ursache war die Debug-Verbindung zu Xcode (Kabel, VPN auf Mac und iPhone), nicht Mailwerk.

---

## c3 – Einmal anlegen, nur bei Änderung laden

**ViewModel doppelt:** SwiftUI wertet `body` von App und Ansichten mehrfach aus. Was dort oder im `init` einer Ansicht entsteht, entsteht jedes Mal neu und wird sofort wieder verworfen. Betroffen waren:
- das ViewModel samt Laden der Liste;
- der Ordnerkatalog;
- der Postfach-Speicher;
- die Spam-Einstellungen;
- der Filterlisten-Zugriff.

**Lösung:** `AppObjects` (in `ContentView.swift`) legt alle langlebigen Objekte genau einmal in `MailwerkApp.init` an und reicht sie herunter. `InboxView` erhält ViewModel und Ordnerkatalog von außen (`@Bindable`). Den Ordnerkatalog legt `InboxView.makeFolderCatalog` an.

Hinweis Mac: Ein zweites Fenster (⌘N) zeigt nun dieselbe Ansicht wie das erste.

**HTML (M4):** `updateUIView`/`updateNSView` luden die Mail bei jeder Aktualisierung neu, auch wenn sie nur ihre eigene Höhe gemeldet hatte. Jetzt merkt sich der Coordinator das zuletzt geladene HTML und lädt nur bei Änderung (`⏱ HTML geladen: n KB`, einmal je geöffneter Mail).

---

## Mac: Refresh-Knopf

Auf dem Mac ist Herunterziehen keine übliche Bedienung. Bisher erzeugte macOS aus `.refreshable` selbst einen Knopf; durch das Auslagern der Liste entfiel er. Jetzt gibt es einen eigenen Knopf „Aktualisieren“ (⌘R), gesperrt während eines Abrufs. `.refreshable` gilt nur noch für iPhone/iPad.

---

## Geänderte Dateien

```
Mailwerk/
├── MailwerkApp.swift                       # AppObjects einmalig anlegen (c3)
├── ContentView.swift                       # AppObjects, Weiterreichen (c3)
├── Models/
│   ├── MessageListItem.swift               # neu: Listeneintrag ohne Mailinhalt (c2)
│   └── SyncWindow.swift                    # startAfterLoading, OlderFetchResult.failed (c2b)
├── Services/
│   ├── MailFetchService.swift              # Ordner neu wählen + Wiederholung, CacheResult (c2b)
│   ├── MessageStore.swift                  # Stufe 3: preview, Index, Listenabfragen (c2)
│   └── Sync/
│       └── SyncStatePlanner.swift          # uidNextAfterLoading (c2b)
├── ViewModels/
│   └── InboxViewModel.swift                # Messung (c1), MessageListItem (c2), Hinweis bei Fehlern (c2b)
└── Views/
    ├── InboxView.swift                     # MessageDetailLoader, Liste ausgelagert (c2),
    │                                       # Refresh-Knopf Mac, ViewModel von außen (c3)
    └── HTMLMailView.swift                  # nur bei Änderung laden (c3)
MailwerkTests/
├── MessageStoreListTests.swift             # neu, 7 Tests (c2)
├── LoadCompletenessTests.swift             # neu, 4 Tests (c2b)
├── MessageStoreSyncTests.swift             # Schema-Stufe 3
└── MessageStoreTransactionTests.swift      # Schema-Stufe 3
Documentation/
└── Mailwerk_v0.1.9c_Entwicklungsdokumentation.md   # neu
```

Alle geänderten Code-Dateien folgen dem Dokumentationsstandard aus v0.1.9a.

---

## Testverfahren

**Automatisch:** alle Tests grün. Zählung: 337 (v0.1.9b) + 7 (c2) + 4 (c2b) = **348**.

**Manuell:**

| Bereich | Gerät | Ergebnis |
|---|---|---|
| Messung vorher/nachher (Start, Refresh, „Ältere laden“, Mails öffnen) | Simulator, Mac, iPhone | siehe Tabelle oben |
| Vorschau in der Liste wie vorher | alle | in Ordnung |
| Antworten/Weiterleiten mit Zitat, Wischaktionen, Rückgängig in „Gekennzeichnet“ | Simulator | in Ordnung |
| Abbruchtest: VPN zweimal aus/ein während „Ältere laden“ und Refresh | iPhone ohne Kabel | keine Fehler, Mails erscheinen |
| Refresh-Knopf und ⌘R | Mac | in Ordnung |
| `#1` nur einmal, `HTML geladen` einmal je Mail | Simulator | in Ordnung |
| Filterlisten nach c3 | Mac | vorhanden |
| Frische Installation, größtes Postfach | iPhone (c2), Simulator (c3, nach Zurücksetzen) | in Ordnung, 0 Fehler |

---

## Fehler während der Entwicklung

- **Compiler-Zeitüberschreitung** in `InboxView.body` nach Einführung von `MessageListItem` → Liste in eigene Teile ausgelagert.
- **Falscher Platzhalter** beim Bilden der Vorschau (`?16` = HTML statt `?15` = Text). Die neuen Tests haben den Fehler sofort gefunden. Die Migration war nicht betroffen.

---

## Beobachtungen (nicht durch v0.1.9c verursacht)

- **Debuggen per Kabel mit VPN:** Ist auf Mac und iPhone NordVPN aktiv, bricht die Verbindung zwischen Xcode und iPhone ab: „Connection interrupted“, „Failed to create directory on device“, Konsole stoppt, App scheint eingefroren. Abhilfe: VPN am Mac für die Installation aus, danach **Product → Stop** und ohne Kabel testen.
- **Simulator und CloudKit:** Die Filterlisten gleichen im Simulator nicht ab (bekannt seit v0.1.6). iCloud Drive und Passwörter lassen sich dort nicht einschalten. Für Tests im Simulator Einträge von Hand anlegen; den Abgleich nur auf Mac/iPhone testen.
- **Simulator zurücksetzen:** Menü **Device → Reset All Content and Settings**. Danach Apple-Account neu anmelden und Passwörter von Hand eingeben.
- **Erster Start auf frischem Gerät:** „Refresh gestartet für 0 Konten“. Die Postfächer kommen aus iCloud erst kurz nach dem Start an → in d1.
- **Zitat in der Antwortansicht** auf 400 Punkte begrenzt und nicht scrollbar (seit v0.1.7e) → in d1.
- **Simulator-Tastatur** nimmt nur ein Zeichen an → Simulator neu starten.

---

## Abhängigkeiten / Xcode-Konfiguration

- Datenbank: Schema-Stufe 3 (Migration automatisch beim ersten Start).
- SwiftMail unverändert (≥ 1.13.0). Version 1.14.0 (06.10.2026) bietet `deleteMailbox` öffentlich an; der eigene Weg zum Löschen von Ordnern kann damit später zurückgebaut werden (eigener Commit).
- `MARKETING_VERSION` = 0.1.9c.

---

## Nächste Schritte

Jede Stufe mit eigener Doku und eigenem Commit:

- **v0.1.9d1 – Verhalten:**
  - überlappende Abrufe verhindern (R1);
  - Zitat in der Antwortansicht vollständig lesbar;
  - Abruf starten, sobald die Postfächer aus iCloud eintreffen;
  - überflüssiges letztes Neuladen im Refresh;
  - große Mails über 5 MB ohne Anhang-Daten laden (M9, vorher SwiftMail-API prüfen).
- **v0.1.9d2 – Struktur:** M1, M2, M7 samt einheitlicher Rückfragen (inkl. „Löschen per Menü“).
- **v0.1.9d3 – Aufräumen:** `os.Logger` (N24), toter Code.
- **v0.1.9e1 – M5:** externe Inhalte blockieren, sicheres Zitieren von HTML.
- **v0.1.9e2 – N-Befunde:** Aufräumarbeiten.
- **v0.1.9e3 – weitere Funde.**
- **v0.1.9f – Inline-Dokumentation** der übrigen Dateien.
- **Abschluss v0.1.9:** Diskussion M6 (eigenes Feld für die Absenderadresse).
- **Später:** H6 (Verbindungen wiederverwenden), ggf. mit der Push-Stufe → Technical-Debt-Liste.
