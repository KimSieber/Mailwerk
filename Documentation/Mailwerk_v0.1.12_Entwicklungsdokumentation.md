# Mailwerk – Entwicklungsdokumentation v0.1.12

2026-10-12 · Mails vollständig und lesbar anzeigen: Dunkelmodus, Zoom, Originalquelle (Jira MW-5), eingebettete Bilder

---

## Zusammenfassung

v0.1.12 wurde in zwei Paketen mit je einem Test- und Commit-Punkt umgesetzt:
- **Paket 1** (Commit `608041c`, „v0.1.12a“) ändert nur die Anzeige und holt die Originalquelle bei Bedarf vom Server. Schema und Cache bleiben unberührt.
  - Im Dunkelmodus bleiben HTML-Mails mit eigenen Farben hell, wie in Apple Mail.
  - Jede HTML-Mail lässt sich per Geste zoomen.
  - Die Mailansicht hat ganz unten im Menü den Eintrag „Originalquelle“.
- **Paket 2** (dieser Commit) betrifft Schema, Abruf und Versand.
  - Eingebettete Bilder werden geladen, gespeichert und im Text angezeigt.
  - Drucken und Teilen enthalten sie, Antworten und Weiterleiten senden sie mit.
  - Mails aus Apple Mail mit Fotos zwischen Textteilen erscheinen vollständig.

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
- **Eingebettete Bilder:**
  - Sie werden immer angezeigt, auch bei Spam und bei gesperrten externen Inhalten. Sie sind Inhalt der Mail und brauchen keinen Netzabruf.
  - Laden: mit dem Text bei Mails bis 5 MB; fehlen sie beim Öffnen, lädt Mailwerk sie im Hintergrund nach; offline bleiben sie still leer.
  - Drucken und Teilen folgen der Anzeige.
  - Antworten **und** Weiterleiten senden die Bilder des Zitats mit.

Tests: 446 → 462 (Paket 1) → **477**, alle grün.

---

## Paket 1

### Dunkelmodus

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

### Zoom

**Problem:** Das Grundgerüst setzte `maximum-scale=1`. Zoombar waren nur Mails mit eigener Viewport-Angabe (meist Newsletter), persönliche HTML-Mails nie.

**Lösung:** Die Grenze im Grundgerüst entfällt. Auf iOS gilt zusätzlich `ignoresViewportScaleLimits`, auf macOS `allowsMagnification` (Trackpad). Damit zoomen auch Mails, die Zoomen in ihrem Viewport verbieten.

### Originalquelle (MW-5)

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

## Paket 2 – Eingebettete Bilder

**Problem:**
- `MessageContentPlan` lud eingebettete Bilder bewusst nicht. `cid:`-Bilder erschienen deshalb als fehlendes Bild, auch im Druck, in der geteilten Datei und im Zitat beim Antworten.
- Fotos, die Apple Mail ohne Verweis „inline“ mitschickt, ordnete SwiftMail weder als Anhang noch als Text ein. Sie gingen still verloren.

**Lösung:**
- **Ablage (Schema-Stufe 6):**
  - Die Anhang-Tabelle hat neue Spalten `contentID` und `isInline`; `CachedAttachment` die gleichnamigen Felder (mit Standardwerten) und `with(data:)`.
  - Eingebettete Bilder liegen in derselben Tabelle wie Anhänge. Damit gilt derselbe Lösch- und Bereinigungsweg, und es gibt keinen zweiten Speicher.
- **`MessageContentPlan.inlineImages`:** alle Bildteile der Mail selbst, die keine Anhänge sind und nicht zu einer weitergeleiteten Mail gehören.
- **Abruf (`MailFetchService`):** Bilder werden wie Anhänge bis 5 MB mitgeladen, sonst nur als Eintrag gespeichert.
- **`InlineImages` (neu, ohne Oberfläche):**
  - findet die per `cid:` angesprochenen Content-IDs (vereinheitlicht: ohne Klammern, Prozent-Kodierung aufgelöst, Groß-/Kleinschreibung egal);
  - liefert die **sichtbare Anhangliste**: echte Anhänge und nicht angesprochene Inline-Bilder;
  - ersetzt `cid:`-Verweise per Textsuche durch `data:`-Adressen, nur für `image/*`. Die CSP erlaubt `data:`-Bilder schon immer.
- **`InlineImageLoader` (neu):**
  - Lädt beim Öffnen angesprochene, noch fehlende Bilder nach: Struktur holen, nur fehlende Teile laden, `EXAMINE` und `BODY.PEEK`.
  - Für alle eingebetteten Bilder legt er Einträge an. Das gilt auch für Mails, die vor dieser Version geladen wurden; das ist dieselbe allgemeine Regel und keine Sonderlösung für den Übergang.
- **Mailansicht:**
  - Das HTML wird einmal je Änderung der Anhänge mit Bildern aufgelöst (`resolvedHTML`), nicht bei jedem Neuzeichnen.
  - Anhänge und Bilder werden vor der Entscheidung über externe Inhalte gelesen, damit die Mail gleich mit Bildern erscheint.
  - „Anlagen lokal löschen“ betrifft nur sichtbare Anhänge.
- **Drucken und Teilen:** `MailPrintFormatter` setzt die Bilder ein; die geteilte Datei ist in sich geschlossen.
- **Antworten und Weiterleiten:**
  - `ComposeViewModel` merkt die vom Zitat angesprochenen Bilder vor und sendet sie als Inline-Teile mit derselben Content-ID. `OutgoingAttachment.contentID` führt zu SwiftMails `multipart/related`.
  - Fehlende Bilder werden beim Senden nachgeladen. Scheitert das, fragt das Fenster „Bild nicht geladen – ohne dieses Bild senden?“.
  - Die Zitat-Vorschau zeigt die Bilder. Beim Weiterleiten erscheinen sie nicht als zusätzliche Anhänge.
- **`AttachmentManager`:** findet einen Teil über seine Abschnittsnummer (Teil der Kennung), sonst wie bisher über Dateiname und Typ. Das gilt für Anhänge und Bilder.

**Fund im Test – Apple Mail „Text – Bild – Text“:**
- Eine Testmail aus Apple Mail (Foto mitten im Text) zeigte nur den ersten Absatz, das Foto stand in der Anhangliste, der Text danach fehlte.
- Die Rohdaten belegten den Aufbau: `multipart/mixed` aus `text/plain` – `image/jpeg` (inline, ohne Content-ID) – `text/plain`, ganz ohne HTML.
- SwiftMail liefert nur den ersten Text- bzw. HTML-Teil. Der Fehler bestand also schon vor v0.1.12; vorher fehlte sogar das Bild ganz.
- **Lösung (`MessageContentPlan.layout`):**
  - `htmlSequence`: Mehrere HTML-Teile werden aneinandergehängt, Bilder zwischen ihnen an ihrer Stelle eingesetzt. Bilder, die das HTML schon per `cid:` anspricht, werden nicht verdoppelt.
  - `textSequence`: Kein HTML, aber mehrere Textteile oder eingebettete Bilder. Aus den Textteilen (maskiert, `white-space: pre-wrap`) und den Bildern wird in ihrer Reihenfolge ein HTML gebaut. Der Textteil sind dann alle Textteile.
  - `single`: wie bisher; gewöhnliche Mails mit je einem Text- und HTML-Teil bleiben unverändert.
  - Bilder ohne Content-ID werden über eine aus ihrer Abschnittsnummer gebildete angesprochen (`teil-2@mailwerk`, `MessageContentPlan.contentID(for:)`). Danach laufen Anzeige, Nachladen, Druck, Teilen, Antworten und Weiterleiten über denselben Weg wie bei `cid:`-Bildern.

---

## Geänderte Dateien

```
Mailwerk/
├── Models/
│   └── CachedMessage.swift          # CachedAttachment: contentID, isInline, with(data:)   (P2)
├── Services/
│   ├── AttachmentManager.swift      # Teil über Abschnittsnummer                          (P2)
│   ├── InlineImageLoader.swift      # neu                                                 (P2)
│   ├── InlineImages.swift           # neu                                                 (P2)
│   ├── MailAppearance.swift         # neu                                                 (P1)
│   ├── MailFetchService.swift       # Bilder mitladen                                     (P2)
│   ├── MailPrintFormatter.swift     # Bilder in Druck und Teilen                          (P2)
│   ├── MailSendService.swift        # Inline-Teile mit Content-ID                         (P2)
│   ├── MessageContentPlan.swift     # inlineImages, layout, contentID(for:)               (P2)
│   ├── MessageStore.swift           # Schema-Stufe 6                                      (P2)
│   ├── RawMessageFormatter.swift    # neu                                                 (P1)
│   └── RawMessageService.swift      # neu                                                 (P1)
├── ViewModels/
│   └── ComposeViewModel.swift       # Bilder beim Antworten/Weiterleiten                  (P2)
└── Views/
    ├── ComposeView.swift            # Zitat-Vorschau mit Bildern, „Bild nicht geladen“    (P2)
    ├── HTMLMailView.swift           # Farbregeln, Zoom                                    (P1)
    ├── MessageDetailView.swift      # Originalquelle (P1); Bilder, sichtbare Anhänge (P2)
    ├── MessageMenu.swift            # MessageMenuLabels.source                            (P1)
    └── RawSourceView.swift          # neu                                                 (P1)
Mailwerk.xcodeproj/project.pbxproj   # Version 0.1.12 (Kim)
MailwerkTests/
├── InlineImagesTests.swift          # neu, 6 Tests                                        (P2)
├── MailAppearanceTests.swift        # neu, 6 Tests                                        (P1)
├── MailPrintFormatterTests.swift    # +1                                                  (P2)
├── MessageContentPlanTests.swift    # +6 (Bilder, Folgen aus Apple Mail)                  (P2)
├── MessageMenuTests.swift           # +1                                                  (P1)
├── MessageStoreListTests.swift      # Schema-Version 6                                    (P2)
├── MessageStoreSyncTests.swift      # Schema-Version 6                                    (P2)
├── MessageStoreTransactionTests.swift # +2 (Bilder, Migration 5 → 6)                       (P2)
└── RawSourceTests.swift             # neu, 9 Tests                                        (P1)
```

---

## Testverfahren

**Automatisch:** 477 Tests (Simulator), alle grün. Vor der Lieferung zusätzlich mit Swift unter Linux gegengeprüft: die Aufbereitung der Originalquelle, die Farberkennung, die Regeln für eingebettete Bilder und die Tests des Inhaltsplans (gegen das echte SwiftMail 1.15.0).

**Manuell (Simulator, iPhone, Mac), keine Produktivmail verändert:**
- **Dunkelmodus:** Newsletter und Outlook-Mail hell und lesbar, schlichte Mail und Textmail dunkel; im Hellmodus unverändert.
- **Zoom:** bisher starre Mail zoomt, Newsletter wie bisher, nach erneutem Öffnen wieder normale Größe.
- **Originalquelle:**
  - Eintrag nur in der Mailansicht.
  - Kopfzeilen und Inhalt vollständig, Anlage ausgelassen, Base64 dekodiert.
  - Kopieren und Teilen funktionieren.
  - Große Mail zeigt den Hinweis, Flugmodus den Hinweis ohne Verbindung.
- **Eingebettete Bilder** mit zwei Testmails an sich selbst (Spark mit `cid:`-Bild, Apple Mail „Text – Bild – Text“, 5,9 MB):
  - Bild im Text, keine Anhangliste; bei der großen Mail nach dem Öffnen nachgeladen.
  - Offline aus dem Cache.
  - Drucken und Teilen mit Bild.
  - Antworten und Weiterleiten kommen mit Bild an.
- **Abruf:** größtes Postfach mit frischer Installation im Simulator.
- **Mac:** ⌥⌘U, Trackpad-Zoom, Dunkelmodus.

---

## Beobachtungen

- Dass Originalquelle und Nachladen nichts am Server verändern, ist durch `EXAMINE` und `BODY.PEEK` im Code gesichert; am Gerät lässt sich das kaum sichtbar prüfen.
- SwiftMail bricht `fetchRawMessage` nach festen 10 Sekunden ab, gerechnet ab dem Senden. Bei sehr langsamer Verbindung kann das auch unter 5 MB vorkommen; dann erscheint die Fehlermeldung im Blatt.
- Bereits geladene Mails im Aufbau „Text – Bild – Text“ bleiben im Cache unvollständig, bis sie neu geladen werden (z. B. frische Installation). Bewusst keine Übergangslösung, alle Installationen sind Testinstallationen.
- Inline-Fotos ohne Verweis in einer Mail mit einem einzigen HTML-Teil (z. B. Foto ans Ende einer formatierten Apple-Mail gehängt) stehen weiterhin in der Anhangliste, nicht im Text.
- Beim ersten Git-Befehl von Claude im Projektordner blieb eine leere Sperrdatei zurück. Sie ist umbenannt in `.git/stale-maintenance-lock-claude` und kann gelöscht werden. In Kims Ordner nutzt Claude Git seitdem nur lesend.

## Nächste Schritte

- **v0.1.13 – Signaturen und Entwürfe beim Verfassen** (MW-2, MW-16). Inhalt zuerst mit Kim abstimmen.
- Fahrplan, Merkliste und Arbeitsregeln: siehe `Mailwerk_Auftrag_neuer_Chat_v0.1.13.md`.
