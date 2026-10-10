# Mailwerk – Entwicklungsdokumentation v0.1.9d1

2026-10-08 bis 2026-10-10 · Verhalten: Antwortansicht, Abrufe, Laden großer Mails, HTML-Höhe (Code-Review Teil 4)

---

## Zusammenfassung

v0.1.9d1 korrigiert Verhalten, das im Alltag stört. Die Stufe wurde in fünf Schritten mit je eigenem Commit umgesetzt:

- **d1a:** Die Antwortansicht scrollt als Ganzes, wie in Apple Mail. Das Zitat ist vollständig lesbar. Formatierungen lassen sich einzeln widerrufen.
- **d1b (R1):** Abrufe laufen nacheinander und ohne Doppelungen. `refresh()` ist bereinigt.
- **d1c (M9):** Von einer neuen Mail werden nur die Struktur sowie Text und HTML geladen, Anhänge nur bei Mails bis 5 MB. Kein Teil wird mehr doppelt übertragen.
- **d1d:** Mailwerk ruft ab, sobald Postfächer eintreffen, etwa beim ersten Start aus iCloud.
- **d1e (Fund):** HTML-Mails werden nicht mehr am Ende abgeschnitten.

Tests: 348 → **361**, alle grün.

| Messung M9 (Konsole `📎`) | Größe der Mail | übertragen vorher | übertragen jetzt |
|---|---|---|---|
| Mail mit 3 Anhängen | 6.137 KB | gesamte Mail | Text 7 KB |
| Mail mit 1 Anhang | 6.828 KB | gesamte Mail | Text 43 KB |
| Mail mit 1 Anhang (PDF) | 502 KB | Mail + Anhang ein zweites Mal | Text 0 KB, Anhang 500 KB |

---

## d1a – Antwortansicht scrollt als Ganzes, Formatierung widerrufbar

**Problem:** Das Zitat in der Antwortansicht war auf 400 Punkte begrenzt und nicht scrollbar (seit v0.1.7e). Der Rest einer langen Mail war unerreichbar.

**Abwägung:** Ein eigener Scrollbereich nur für das Zitat wäre der kleinere Eingriff gewesen. Gewählt wurde die saubere Lösung wie in Apple Mail: Die ganze Ansicht scrollt. Dafür musste der Editor umgebaut werden.

**Lösung:**
- **`RichTextEditor`:** Der Editor scrollt nicht mehr selbst, sondern wächst mit seinem Text. Er ist mindestens 160 Punkte hoch.
  - iOS: `GrowingTextView`, ein `UITextView` ohne eigenes Scrollen.
  - macOS: `GrowingNSTextView`, ein `NSTextView` ohne eigene Scroll-Ansicht. Die Höhe wird über TextKit 2 gemessen; `layoutManager` wird bewusst nicht angefasst, weil das auf TextKit 1 zurückschaltet.
  - Die Breite übernimmt der Editor von SwiftUI über `sizeThatFits`. Ohne das würde eine Textansicht ohne Scrollen so breit wie ihre längste Zeile.
  - Die Schreibmarke bleibt sichtbar: Beim Tippen, beim Wachsen und beim Versetzen rückt der Editor sie über die umgebende Scroll-Ansicht ins Bild, auf dem iPhone über der Tastatur.
- **`ComposeView`:**
  - Kopfbereich, Editor und Zitat liegen in einem gemeinsamen `ScrollView`, das Zitat in voller Höhe. Die untere Leiste bleibt stehen.
  - Ein Tipp in die freie Fläche unter dem Inhalt setzt die Marke ans Textende (`RichTextController.focusAtEnd`). Vorher füllte der Editor diese Fläche selbst aus.
  - Auf dem iPhone blendet Wischen nach unten die Tastatur aus.

**Fund beim Test (d1a2):** Mit ⌘Z verschwand die ganze Eingabe statt der Formatierung.
- *Ursache:* Die Formatierung änderte den Textspeicher direkt und umging damit die Rückgängig-Verwaltung. Der Fehler bestand seit v0.1.4.
- *Lösung:* Alle Formatierungen laufen über `performAttributeEdit`:
  - macOS: `shouldChangeText` … `didChangeText`, `NSTextView` vermerkt den Schritt dann selbst.
  - iOS: Der vorherige Zustand wird beim `undoManager` hinterlegt. Wiederherstellt wird nur, wenn der Bereich noch dieselben Zeichen enthält.
  - Jeder Schritt hat einen Namen, z. B. „Widerrufen: Fett“. Wiederholen funktioniert.

---

## d1b – Abrufe nacheinander und ohne Doppelungen (R1)

**Problem:** Start-Abruf, Herunterziehen, „Netz zurück“, Ordnertipp und „Ältere laden“ konnten gleichzeitig laufen. Dann bearbeiteten zwei Verbindungen denselben Ordner und überschrieben sich gegenseitig den Sync-Zustand (UIDNEXT, Fensterbeginn). Außerdem rief `refresh()` einen gewählten Ordner ein zweites Mal ab und lud die Liste zum Schluss überflüssig neu.

**Lösung:**
- **`FetchCoordinator` (neu, generisch, ohne Netz testbar):**
  - Abrufe laufen nacheinander.
  - Dieselbe Anforderung wird angeschlossen statt wiederholt.
  - Ein neuer Ordnerabruf verdrängt einen noch wartenden (`FetchRequest.supersedes`), ein laufender wird nie verdrängt.
  - Bricht der Aufrufer ab, läuft der Abruf trotzdem zu Ende.
- **`InboxViewModel`:**
  - `refresh()`, `refreshFolder()` und `loadOlder()` laufen über den Coordinator.
  - „Ältere laden“ merkt sich die Ordner zum Zeitpunkt des Tippens und zeigt sofort „wird geladen“.
  - Zusätzlicher Ordnerabruf und letztes Neuladen in `refresh()` sind entfallen.
- **Konsole:** `🔁 … angeschlossen`, `⏳ … wartet`, `⏭ … übersprungen`.

---

## d1c – Nur Struktur, Text/HTML und Anhänge bis 5 MB laden (M9)

**Prüfung vorab:** Der Quellcode von SwiftMail 1.13–1.15 wurde gelesen. `fetchMessage` lädt *jeden* Teil einer Mail mit Inhalt, weitergeleitete Mails sogar doppelt (als Ganzes und in Einzelteilen). `fetchStructure`, `fetchPart` und `Message(header:parts:)` sind öffentlich.

**Problem (über den Review-Befund hinaus):**
- Mails über 5 MB wurden komplett geladen und die Anhänge danach verworfen.
- Bei Mails bis 5 MB wurden die Anhänge doppelt geladen.
- Eingebettete Bilder (`cid:`) wurden bei jeder HTML-Mail geladen, aber nie gespeichert.
- Auch das Nachladen eines Anhangs per Tipp lud die ganze Mail und den Anhang danach ein zweites Mal.

**Lösung:**
- **`MessageContentPlan` (neu):**
  - Aus der Struktur bestimmt er die zu ladenden Teile: Text und HTML der Mail selbst, Anhänge nur gelistet, eingebettete Bilder und Teile weitergeleiteter Mails gar nicht.
  - Die Einordnung übernimmt weiterhin SwiftMails `Message`, also dieselbe wie bisher, nur ohne Inhalte.
  - Danach setzt er Text und HTML aus den Rohdaten zusammen; die Dekodierung erledigt SwiftMail wie bisher.
- **`MailFetchService.storeNewMessage`:** Zuerst `fetchStructure`, dann `fetchPart` für Text und HTML, dann die Anhänge einzeln und nur bis zur Schwelle.
- **`AttachmentManager`:** Beim Antippen wird nur die Struktur geladen, danach genau dieser eine Anhang.
- Die Konsolenzeile `📎` nennt jetzt Größe und tatsächlich übertragene Menge.

---

## d1d – Abruf, sobald Postfächer eintreffen

**Problem:** Beim ersten Start sind noch keine Postfächer vorhanden („Refresh gestartet für 0 Konten“). Sie kommen kurz darauf aus iCloud, aber niemand rief ab.

**Lösung:**
- `InboxView` beobachtet die Postfach-IDs. Kommt eines hinzu, zeigt sie die Liste aus dem Cache und ruft alle Posteingänge ab (Entscheidung Kim: alle, nicht nur die neuen). Name oder Farbe ändern löst nichts aus.
- **Folge aus d1b:** Läuft der Start-Abruf mit 0 Postfächern noch, schließt sich der neue Abruf ihm nur an. Deshalb nimmt `performRefresh` während der Runde hinzugekommene Postfächer mit.

---

## d1e – HTML-Mails am Ende abgeschnitten (Fund aus dem d1c-Test)

**Befund:** Bei schlichten HTML-Mails fehlten die letzten ein bis zwei Zeilen. Der Fehler bestand schon vor d1c, der ältere Stand auf dem iPhone zeigte dasselbe.

**Diagnose:** Eine vorübergehende Ausgabe (`📐`) zeigte zu drei Zeitpunkten Breite, Höhe des `body` und Höhe des Dokuments:

| Mail | body (gemessen) | Dokument (tatsächlich) | Differenz |
|---|---|---|---|
| Smyril Line | 344 | 368 | 24 |
| Health Check | 240 | 272 | 32 |
| M365, Headout (Gegenprobe) | gleich | gleich | 0 |

Breite und Höhe blieben über 2 s gleich. Spätes Wachsen und eine andere Breite schieden damit aus.

**Ursache:** „Margin collapsing“. Die Randabstände des ersten und letzten Absatzes ragen über den `body` hinaus. `body.scrollHeight` misst ohne sie, gemeldet wird also zu wenig: 2 × 12 bzw. 2 × 16 Punkte.

**Lösung:** `body { display: flow-root !important; }` im CSS-Rahmen von `HTMLMailView`. Der `body` bildet damit einen eigenen Block, die Abstände zählen zur Höhe. Gemessen wird weiter am `body`, so kann der Rahmen bei Bedarf auch schrumpfen. Das behebt zugleich das Zitat in der Antwortansicht. Die Diagnose ist wieder entfernt.

---

## Geänderte Dateien

```
Mailwerk/
├── Models/ (unverändert)
├── Services/
│   ├── MessageContentPlan.swift            # neu: zu ladende Teile einer Mail (d1c)
│   ├── MailFetchService.swift              # Struktur + Text/HTML + Anhänge einzeln (d1c)
│   ├── AttachmentManager.swift             # Nachladen nur Struktur + ein Teil (d1c)
│   └── Sync/
│       └── FetchCoordinator.swift          # neu: Abrufe nacheinander, FetchRequest (d1b)
├── ViewModels/
│   └── InboxViewModel.swift                # über Coordinator (d1b), neue Postfächer in der Runde (d1d)
└── Views/
    ├── RichTextEditor.swift                # wächst mit Text, Marke im Bild, Widerrufen (d1a)
    ├── ComposeView.swift                   # gemeinsamer Scrollbereich, Zitat voll (d1a)
    ├── InboxView.swift                     # Abruf bei neuen Postfächern (d1d)
    └── HTMLMailView.swift                  # body als eigener Block (d1e)
MailwerkTests/
├── FetchCoordinatorTests.swift             # neu, 7 Tests (d1b)
└── MessageContentPlanTests.swift           # neu, 6 Tests (d1c)
Documentation/
└── Mailwerk_v0.1.9d1_Entwicklungsdokumentation.md   # neu
```

Alle gelieferten Code-Dateien folgen dem Dokumentationsstandard. `RichTextEditor` und `ComposeView` wurden dabei vollständig nachdokumentiert; der doppelte Dateikopf in `ComposeView` ist entfernt.

---

## Testverfahren

**Automatisch:** 348 (v0.1.9c) + 7 (d1b) + 6 (d1c) = **361**, alle grün.

**Manuell:**

| Schritt | Bereich | Gerät | Ergebnis |
|---|---|---|---|
| d1a | Zitat bis zum Ende, Editor wächst, Marke über der Bildschirmtastatur (⌘K), Wischen blendet Tastatur aus | Simulator | in Ordnung |
| d1a | Scrollen über Zitat/Editor, Editor wächst, Tipp unter den Text | Mac | in Ordnung |
| d1a2 | ⌘Z nimmt Farbe, dann Fett, dann Text zurück; ⇧⌘Z stellt wieder her | Mac, Simulator | in Ordnung |
| d1b | Herunterziehen während Start-Abruf → `🔁 angeschlossen`, nur ein Refresh | Simulator | in Ordnung |
| d1b | Ordnertipp während Abruf → `⏳ wartet`, korrekte Anzeige | Simulator | in Ordnung (Verdrängen nur automatisch geprüft) |
| d1c | Kopien in „Test Mailwerk“: > 5 MB (2×), kleiner Anhang, HTML mit Bildern; Anzeige, Nachladen, Vorschau | Simulator | in Ordnung, Werte siehe oben |
| d1c + d1d | Frische Installation (**Device → Reset All Content and Settings**), Abruf startet selbst, größtes Postfach | Simulator | 0 Fehler, 291 Nachrichten |
| d1e | Abgeschnittene Mails vollständig, Gegenprobe unverändert, Zitat vollständig | Simulator | in Ordnung |

---

## Beobachtungen

- **Erster Abruf eines Ordners:** Er lädt nur die letzten 30 Tage. In einen noch nie geöffneten Ordner kopierte, alt datierte Mails erscheinen daher erst über „Ältere laden“. Ab dem zweiten Abruf greift UIDNEXT, und neue Mails erscheinen unabhängig vom Datum. So ist es im Konzept „Sync-Zustand je Ordner“ vorgesehen, keine Änderung.
- **Echtes neues Gerät:** Die Postfächer können aus iCloud vor den Passwörtern eintreffen. Dann kann beim ersten Abruf kurz „kein Passwort gefunden“ erscheinen. Das wird beobachtet und bei Bedarf eingeplant.
- **`decodeImageImp failed`** in der Konsole kommt von WebKit (Bild nicht dekodierbar), nicht von Mailwerk.
- **Mac:** Seit d1a wurde nur d1a auf dem Mac geprüft. d1b bis d1e ändern keine Mac-spezifischen Teile.

---

## Abhängigkeiten / Xcode-Konfiguration

- SwiftMail unverändert (≥ 1.13.0). Genutzt werden jetzt zusätzlich `fetchStructure`, `fetchPart` und `Message(header:parts:)`, öffentlich seit 1.13.0.
- Datenbank unverändert (Schema-Stufe 3).
- `MARKETING_VERSION` je Schritt von Kim gesetzt (0.1.9d1a … 0.1.9d1e).

---

## Commits

| Schritt | Commit |
|---|---|
| d1a | `b5e7bfe`, `55001e1` (Version) |
| d1b | `006fe6e` |
| d1c | `c883dd8` |
| d1d | `b1e5df9` |
| d1e + Doku | *von Kim nach diesem Dokument* |

---

## Nächste Schritte

- **v0.1.9d2 – Struktur:** M1 (Zugangsdaten/Verbindungsaufbau an einer Stelle), M2 (`refresh()` zerlegen), M7 (Aktionen ins ViewModel, ein Fehlerkanal, einheitliche Rückfragen inkl. „Löschen per Menü reagiert manchmal nicht“).
- **v0.1.9d3 – Aufräumen:** `os.Logger` statt `print` (N24), toter Code.
- **v0.1.9e1 – M5:** externe Inhalte blockieren, sicheres Zitieren von HTML.
- **v0.1.9e2 – N-Befunde**, **e3 – weitere Funde**, **f – Inline-Dokumentation**.
- **Abschluss v0.1.9:** Diskussion M6.
- **Eigener Commit:** Rückbau des eigenen Ordner-Löschwegs auf SwiftMails `deleteMailbox` (ab 1.14.0).
- **Später:** H6 (Verbindungen wiederverwenden), ggf. mit der Push-Stufe.
