# Mailwerk – Entwicklungsdokumentation v0.1.12

2026-10-12 · Mails vollständig und lesbar anzeigen – Teil 1: Dunkelmodus, Zoom, Originalquelle (Jira MW-5)

---

## Zusammenfassung

v0.1.12 kommt in zwei Paketen. **Paket 1** (dieses Dokument) ändert nur die Anzeige und holt die Originalquelle bei Bedarf vom Server. Schema und Cache bleiben unberührt.
- Im Dunkelmodus bleiben HTML-Mails mit eigenen Farben hell, wie in Apple Mail.
- Jede HTML-Mail lässt sich per Geste zoomen.
- Die Mailansicht hat ganz unten im Menü den Eintrag „Originalquelle“.

**Paket 2** (eingebettete `cid:`-Bilder: Laden, Anzeige, Drucken/Teilen, Antworten/Weiterleiten) folgt mit eigenem Commit, weil es Schema, Abruf und Versand ändert.

**Entschieden (Kim):**
- **Dunkelmodus wie Apple Mail:** Eine Mail mit eigener Hintergrund- *oder* Schriftfarbe wird hell dargestellt. Mails ohne eigene Farben und Textmails folgen dem Dunkelmodus.
- **Zoom:** Jede HTML-Mail lässt sich per Geste zoomen. Der Zoom gilt nur für die geöffnete Mail; es gibt keine Schriftgrößen-Einstellung. Textmails bleiben unverändert, sie folgen der Textgröße des Systems.
- **Originalquelle:**
  - Ort: eigener Abschnitt ganz unten im Menü der Mailansicht, nicht im Kontextmenü der Liste, kein Schalter in den Einstellungen.
  - Inhalt: Kopfzeilen und Text-/HTML-Teile vollständig; Anlagen werden ausgelassen.
  - Kodierung: Base64-Text wird dekodiert, Quoted-Printable bleibt wie übertragen.
  - Grenzen: Mails über 5 MB und fehlendes Netz zeigen einen Hinweis statt der Quelle.
  - Speicherung: keine.
- **5-MB-Grenze bleibt:** Ein Teilabruf „nur die ersten 10.000 Zeichen“ (`BODY.PEEK[]<0.10000>`) wäre ideal, ist mit SwiftMail 1.15.0 aber nicht möglich. Ein eigener IMAP-Weg oder eine höhere Grenze sind nicht zielführend. Für große Mails bleibt das Webmail.

Tests: 446 → **462**, alle grün.

---

## Dunkelmodus

**Problem:** Das Grundgerüst färbte die Schrift im Dunkelmodus hell. Mails mit eigenem weißem Hintergrund, aber ohne eigene Schriftfarbe, erschienen hellgrau auf Weiß (z. B. Sunweb). Umgekehrt wurde dunkle Schrift auf dunklem App-Hintergrund unlesbar.

**Lösung:**
- **`MailAppearance` (neu):** Eine einfache Textsuche entscheidet, ob eine Mail eigene Farben mitbringt. Sie verändert das HTML nicht.
  - Als eigene Farbe zählen: `bgcolor=`, `background=`, `<font … color=`, `<body … text=` sowie die CSS-Eigenschaften `color:`, `background:` und `background-color:`.
  - `border-color` u. Ä. zählen nicht.
  - Ein Fehlalarm stellt die Mail nur hell dar.
- **`HTMLMailView.colorStyle(usesOwnColors:)`:**
  - Mails mit eigenen Farben bekommen im Dunkelmodus eine weiße Fläche mit 8 px Innenrand und das Kennzeichen `color-scheme: light`.
  - Mails ohne eigene Farben bekommen wie bisher helle Schrift.
  - Im Hellmodus ändert sich nichts.

## Zoom

**Problem:** Das Grundgerüst setzte `maximum-scale=1`. Zoombar waren nur Mails mit eigener Viewport-Angabe (meist Newsletter), persönliche HTML-Mails nie.

**Lösung:** Die Grenze im Grundgerüst entfällt. Auf iOS gilt zusätzlich `ignoresViewportScaleLimits`, auf macOS `allowsMagnification` (Trackpad). Damit zoomen auch Mails, die Zoomen in ihrem Viewport verbieten.

## Originalquelle (MW-5)

**Lösung:**
- **`RawMessageService` (neu):**
  - Holt die Mail im Original über `fetchRawMessage` (`BODY.PEEK[]`). Der Ordner wird dafür nur zum Lesen geöffnet (`examineMailbox`), am Server ändert sich nichts, auch nicht der Gelesen-Status.
  - Das Aufbereiten läuft neben der Oberfläche.
  - `availability(sizeBytes:isOnline:)` prüft vorab das Netz und die 5-MB-Grenze.
- **`RawMessageFormatter` (neu):** Ein toleranter eigener MIME-Durchlauf.
  - Kopfzeilen, Grenzen, Präambel und Epilog bleiben unverändert.
  - Base64-Text wird im Zeichensatz des Teils dekodiert und mit `[Base64 dekodiert]` gekennzeichnet.
  - Anlagen und Inline-Bilder werden durch `[Anlage ausgelassen: Name, Größe]` ersetzt; Namen nach RFC 2047/2231 werden dekodiert.
  - Eingebettete Mails (`message/rfc822`, z. B. in Unzustellbarkeitsberichten) werden nach denselben Regeln aufgelöst. Zustellberichte gelten als Text.
  - Zeilen werden als UTF-8 gelesen, sonst als ISO-8859-1.
- **`RawSourceView` (neu):**
  - Blatt mit nativer Textansicht in Festbreitenschrift, auswählbar.
  - Knöpfe „Kopieren“ (mit kurzem Häkchen) und „Teilen“ als `.txt`.
  - Hinweise „Nur mit Internetverbindung verfügbar“ bzw. „Mail zu groß“ (mit Begründung und Größe).
- **Menü:** `MessageMenuLabels.source`; in `MessageDetailView` als eigener Abschnitt unter „Mail löschen“.
- **⌥⌘U:** liegt auf einem unsichtbaren Knopf. Die Einträge eines Menüs in der Symbolleiste entstehen erst beim Öffnen, ein Kürzel daran wirkte nur bei offenem Menü.

**Fund im Test (T17):** Direkt nach dem Einschalten des Flugmodus meldete der Netzstatus noch „online“. Der Verbindungsfehler erschien dann roh („NIOPosix.NIOConnectionError-Fehler 1“). Jetzt erkennt `ConnectionErrorClassifier` Verbindungsfehler, und sie zeigen denselben Hinweis wie fehlendes Netz.

---

## Geänderte Dateien

```
Mailwerk/
├── Services/
│   ├── MailAppearance.swift        # neu
│   ├── RawMessageFormatter.swift   # neu
│   └── RawMessageService.swift     # neu
└── Views/
    ├── HTMLMailView.swift          # Farbregeln, Zoom
    ├── MessageDetailView.swift     # Eintrag „Originalquelle“, ⌥⌘U, Blatt
    ├── MessageMenu.swift           # MessageMenuLabels.source
    └── RawSourceView.swift         # neu
Mailwerk.xcodeproj/project.pbxproj  # Version 0.1.12 (Kim)
MailwerkTests/
├── MailAppearanceTests.swift       # neu, 6 Tests
├── RawSourceTests.swift            # neu, 9 Tests
└── MessageMenuTests.swift          # +1 Test
```

---

## Testverfahren

**Automatisch:** 462 Tests (Simulator), alle grün. Die Aufbereitung der Quelle und die Farberkennung wurden vor der Lieferung zusätzlich mit einem Swift-Compiler unter Linux gegengeprüft.

**Manuell (Simulator, iPhone, Mac), keine Mail verändert:**
- **Dunkelmodus:** Newsletter und Outlook-Mail hell und lesbar, schlichte Mail und Textmail dunkel; im Hellmodus unverändert.
- **Zoom:** bisher starre Mail zoomt, Newsletter wie bisher, nach erneutem Öffnen wieder normale Größe.
- **Originalquelle:**
  - Eintrag nur in der Mailansicht.
  - Kopfzeilen und Inhalt vollständig, Anlage ausgelassen, Base64 dekodiert.
  - Kopieren und Teilen funktionieren.
  - Große Mail zeigt den Hinweis, Flugmodus den Hinweis ohne Verbindung.
- **Mac:** ⌥⌘U, Trackpad-Zoom, Dunkelmodus.

---

## Beobachtungen

- Dass die Quelle nichts am Server verändert, ist durch `EXAMINE` und `BODY.PEEK` im Code gesichert; am Gerät lässt sich das kaum sichtbar prüfen.
- SwiftMail bricht `fetchRawMessage` nach festen 10 Sekunden ab, gerechnet ab dem Senden. Bei sehr langsamer Verbindung kann das auch unter 5 MB vorkommen; dann erscheint die Fehlermeldung im Blatt.
- Beim ersten Git-Befehl von Claude im Projektordner blieb eine leere Sperrdatei zurück. Sie ist umbenannt in `.git/stale-maintenance-lock-claude` und kann gelöscht werden. In Kims Ordner nutzt Claude Git seitdem nur lesend.

## Nächste Schritte

- **Paket 2 – eingebettete Bilder (`cid:`):**
  - Laden und Speichern (Schema-Stufe 6), Nachladen beim Öffnen.
  - Anzeige, Drucken, Teilen.
  - Antworten und Weiterleiten.
  - Testreihenfolge: c1 mit größtem Postfach und frischer Installation, dann c2, dann c3.
- Merkliste unverändert: DKIM/Authentication-Results, H6, N14 Offline-Warteschlange, Ordner abonnieren, Vorschau-Spalte klären.
