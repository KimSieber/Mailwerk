# Mailwerk – Entwicklungsdokumentation v0.1.13a

2026-10-13 · Signaturen (Jira MW-2): HTML zurück in den Editor, Links und Bilder im Editor, Signatur-Pflege je Postfach mit iCloud-Abgleich, Signatur beim Verfassen

---

## Zusammenfassung

v0.1.13a ist das erste Paket von v0.1.13. Es wurde in drei Abschnitten (a1–a3) mit je einem Testpunkt umgesetzt und wird gemeinsam committet. Schema und Abruf des Mail-Caches bleiben unberührt; neu im iCloud-Speicher (SwiftData/CloudKit) ist das Datenmodell `AccountSignature`.

- **a1 – Editor:** HTML lässt sich fehlertolerant zurück in den Editor holen; neuer Knopf „Link“; Bilder im Editor (eingefügte Fotos) gehen als eingebettete Bilder (`cid:`) mit.
- **a2 – Pflege:** In „Postfach bearbeiten“ gibt es die Zeile „Signatur“ mit eigener Pflege-Seite: Art „Einfach“ (Editor) oder „HTML“ (Code/Vorschau), Logo, iCloud-Abgleich über alle Geräte.
- **a3 – Verfassen:** Die Signatur des Absende-Postfachs wird bei neuen Mails, Antworten und Weiterleitungen eingesetzt und beim Wechsel des Postfachs ausgetauscht.

**Entschieden:**
- **Eine Signatur je Postfach.** Gleiche Signatur für mehrere Postfächer wird von Hand kopiert.
- **Zwei Arten, je Signatur genau eine:**
  - *Einfach* – im Editor gestaltet: Schriftgröße, Farbe, fett, kursiv, unterstrichen, Link (Web und `mailto:`), Logo.
  - *HTML* – als Code eingefügt, z. B. für Tabellen mit Spaltenbreiten und Ausrichtung; oben rechts Umschalter Code/Vorschau.
  - Wechsel Einfach → HTML übernimmt den erzeugten Code; HTML → Einfach fragt nach, wenn Gestaltung wegfiele.
- **Logo:** ein Bild je Signatur, auf der Pflege-Seite hochgeladen (Fotos oder Dateien), höchstens 600 px. Im HTML als Platzhalter `<img src="logo">`, Breite optional mit `width`, sonst 150 pt. Im Editor über den Knopf mit dem Bild-Symbol an der Schreibmarke.
- **Ort beim Verfassen:** unter dem eigenen Text, bei Antworten und Weiterleitungen über dem Zitat; eine Leerzeile davor, keine Trennzeile („-- “).
- **Bearbeitbar beim Verfassen:** Die einfache Signatur steht im Mailtext und ist frei änderbar. Die HTML-Signatur erscheint als eigener Block darunter: Text änderbar und löschbar, Gestaltung bleibt; ✕ entfernt den ganzen Block.
- **Wechsel des Absende-Postfachs:** Die Signatur des neuen Postfachs wird immer eingesetzt – auch wenn die vorige geändert oder gelöscht wurde (erneutes Löschen ist ein Fingertipp).
- **Kein Schalter „Ohne Signatur“.** Löschen im Text bzw. ✕ genügt.
- **iCloud:** Signaturen werden nur einmal gepflegt und auf allen Geräten abgeglichen.
- **Pflege-Ort:** „Postfach bearbeiten“ → „Signatur“.

Tests: 477 → 501 (a1) → 511 (a2) → **519**, alle grün.

---

## a1 – Editor: HTML-Rückweg, Links, Bilder

**Problem:** Der Editor konnte nur nach HTML umwandeln, nicht zurück. Gespeichertes HTML (Signatur, später Entwurf) ließ sich also nicht wieder bearbeiten. Links ließen sich nicht setzen, Bilder im Text gingen beim Senden verloren.

**Lösung:**
- **`HTMLRichTextParser` (neu, ohne Oberfläche):** liest beliebiges HTML fehlertolerant in Zeilen mit Textabschnitten und Bildern.
  - Bildet ab, was der Editor kann: Absätze, Zeilenumbrüche, fett, kursiv, unterstrichen, Schriftgröße (px, pt, em, %, Schlüsselwörter, `<font size>`), Farbe (`#rgb`, `#rrggbb`, `rgb()`, gängige Namen), Links, Listen, Bilder mit Breite.
  - Links nur mit `http:`, `https:`, `mailto:`; `javascript:` u. Ä. fallen weg.
  - Nicht geschlossene oder falsch verschachtelte Tags werden hingenommen; Kommentare, `head`, `script`, `style`, `title` werden nie Text.
  - `isLossless` meldet, ob Gestaltung wegfiel (Tabellen, fremde Styles, verschachtelte Listen …).
- **`RichTextImport` (neu):** setzt die Zeilen in Editor-Text um, mit genau den Attributen, die der Editor selbst setzt. Eigenes Editor-HTML kommt nach Hin- und Rückweg unverändert heraus. Bildquellen: `data:` direkt, sonst über eine Zuordnung (Logo-Platzhalter, später `cid:`).
- **`LinkInput` (neu):** prüft die Eingabe im Link-Dialog: `www.…` → `https://…`, `name@…` → `mailto:…`, fremde Schemata abgelehnt.
- **`FormattingToolbar`:** Knopf „Link“ mit Eingabedialog (vorbelegt, „Link entfernen“, Hinweis bei ungültiger Adresse).
- **`RichTextController`:** `setLink(_:)` (Markierung, ganzer Link an der Marke oder Einfügen als verlinkter Text, je ein Rückgängig-Schritt), `insertImage(_:)`.
- **`EditorImage` (neu):** `MailImageAttachment` hält Bilddaten, MIME-Typ, Content-ID, Anzeigebreite und Platzhalter; `EditorImageData` verkleinert über ImageIO (HEIC → JPEG, Transparenz → PNG); `EditorImages.normalize` macht vom System eingefügte Bilder versendbar.
- **`RichTextHTML`:** Bilder als `<img src="cid:…" width height>`, `images(in:)` liefert die Inline-Teile, im Nur-Text entfallen Bilder.
- **macOS:** Der Editor nimmt Bilder an (`importsGraphics`).

---

## a2 – Signatur-Pflege

**Lösung:**
- **Speicher:**
  - `AccountSignature` (neu, SwiftData) im bestehenden iCloud-Speicher neben den Filterlisten. Logo als externe Datei (in CloudKit eigenes Asset).
  - CloudKit kennt keine eindeutigen Schlüssel: Beim Lesen gilt je Postfach der neueste Datensatz, beim Speichern werden Doppelte entfernt (`SignatureRules.byAccount`).
  - `SignatureStore` (neu, `@Observable`) hält den Stand für die Oberfläche, liest bei übernommenen iCloud-Änderungen neu (`FilterListCloudEvents`) und wird über `.environment` an alle Ansichten gereicht. Variante im Speicher für Tests.
  - Beide Arten werden als HTML gespeichert, das Logo als Platzhalter. Eine leere Signatur entfernt die gespeicherte.
  - Wird ein Postfach entfernt, wird seine Signatur mit gelöscht (`AccountListView`).
- **`SignatureEditorView` (neu):** Auswahl Einfach | HTML, Editor mit Formatierungsleiste und Logo-Knopf bzw. Code/Vorschau, Bereich Logo (Wählen, Ersetzen, Entfernen), „Signatur entfernen“, Sichern/Abbrechen. Weitere Bilder im Editor entfallen beim Sichern nach Hinweis.
- **`CodeTextEditor` (neu):** Code-Feld ohne typografische Anführungszeichen, Striche und Autokorrektur – SwiftUIs `TextEditor` hätte `"` durch „“ ersetzt und das HTML unbrauchbar gemacht.
- **`SignatureEditing` (neu):** Umwandlung HTML ↔ Editor mit Logo-Platzhalter, Logo tauschen/entfernen.
- **`EditAccountView`:** Abschnitt „Signatur“ mit Zeile „Keine / Einfach / HTML“.
- **`MailwerkApp`, `ContentView`:** Schema um `AccountSignature` erweitert, `SignatureStore` in `AppObjects`.

---

## a3 – Signatur beim Verfassen

**Lösung:**
- **Einfache Signatur:** `SignatureEditing.markedSignature` setzt den Signaturtext mit dem Attribut `.mailwerkSignature` in den Mailtext (leerer Text: zwei Leerzeilen, dann Signatur; sonst nach einer Leerzeile). `replacingSignature` findet den markierten Bereich beim Wechsel wieder – auch wenn darin getippt wurde – und ersetzt ihn.
- **HTML-Signatur:**
  - `HTMLSignatureBlock` (neu, ohne Oberfläche): Anzeige mit Logo als `data:`, Versand mit `cid:` (Textsuche nach genau dieser `data:`-Adresse), Logo als Inline-Teil nur, wenn es noch im Block steht, Nur-Text-Fassung.
  - `SignatureBlockView` (neu): WKWebView, Inhalt per `contenteditable` bearbeitbar. JavaScript der Signatur ist aus; ein Skript der App in eigener „Welt“ macht den Inhalt bearbeitbar und meldet HTML und Höhe. Keine Navigation. ✕ entfernt den Block.
- **`ComposeViewModel`:** `attachSignatures` beim Erscheinen des Fensters (danach gilt der Text samt Signatur als Ausgangszustand, eine unveränderte Signatur zählt nicht als Eingabe), `accountDidChange` beim Wechsel, Zusammenbau von HTML- und Textteil mit Signatur, Inline-Teile von Editor-Bildern und Signatur-Logo.
- **`ComposeView`:** Block unter dem Editor; mit HTML-Signatur ist der Editor anfangs niedriger, damit der Block direkt am Text anschließt.
- **„Beantwortet“ (`\Answered`):** setzte Mailwerk bereits seit v0.1.4 nach dem Senden einer Antwort (`MailSendService.markOriginal`); im Test bestätigt.

---

## Geänderte Dateien

```
Mailwerk/
├── ContentView.swift                     # SignatureStore in AppObjects, .environment          (a2)
├── MailwerkApp.swift                     # Schema + AccountSignature                           (a2)
├── Services/
│   ├── EditorImage.swift                 # neu                                                 (a1)
│   ├── HTMLRichTextParser.swift          # neu                                                 (a1)
│   ├── LinkInput.swift                   # neu                                                 (a1)
│   ├── RichTextHTML.swift                # Bilder, images(in:), Bildquelle                     (a1, a2)
│   ├── RichTextImport.swift              # neu                                                 (a1)
│   └── Signatures/
│       ├── AccountSignature.swift        # neu                                                 (a2)
│       ├── HTMLSignatureBlock.swift      # neu                                                 (a3)
│       ├── SignatureEditing.swift        # neu (a2), Einsetzen beim Verfassen                  (a3)
│       ├── SignatureRules.swift          # neu (a2), Nur-Text                                  (a3)
│       └── SignatureStore.swift          # neu                                                 (a2)
├── ViewModels/
│   └── ComposeViewModel.swift            # Bilder als Inline-Teile (a1), Signatur              (a3)
└── Views/
    ├── AccountListView.swift             # Signatur beim Entfernen löschen                     (a2)
    ├── CodeTextEditor.swift              # neu                                                 (a2)
    ├── ComposeView.swift                 # Signatur einsetzen, HTML-Block                      (a3)
    ├── EditAccountView.swift             # Abschnitt „Signatur“                                (a2)
    ├── FormattingToolbar.swift           # Knopf „Link“                                        (a1)
    ├── RichTextEditor.swift              # Links, Bilder einsetzen, Bilder normalisieren       (a1, a2)
    ├── SignatureBlockView.swift          # neu                                                 (a3)
    └── SignatureEditorView.swift         # neu                                                 (a2)
Mailwerk.xcodeproj/project.pbxproj        # Version 0.1.13 (manuell)
MailwerkTests/
├── HTMLRichTextParserTests.swift         # neu, 12 Tests                                       (a1)
├── HTMLSignatureBlockTests.swift         # neu, 3 Tests                                        (a3)
├── LinkInputTests.swift                  # neu, 5 Tests                                        (a1)
├── RichTextImportTests.swift             # neu, 7 Tests                                        (a1)
├── SignatureComposeTests.swift           # neu, 4 Tests                                        (a3)
├── SignatureRulesTests.swift             # neu, 5 Tests                                        (a2, a3)
└── SignatureStoreTests.swift             # neu, 6 Tests                                        (a2)
```

---

## Testverfahren

**Automatisch:** 519 Tests (Simulator), alle grün. Vor jeder Lieferung zusätzlich unter Linux mit Swift 6.2 geprüft: Parser, Link-Prüfung, Signatur-Regeln, HTML-Signatur-Block (25 Tests).

**Manuell (Simulator, iPhone, Mac), Mails nur an sich selbst:**
- **a1:** Link auf markiertem Text, Link als eingefügte Mailadresse (danach ohne Link weitergetippt), ungültige Eingabe mit Hinweis, Foto eingefügt; Empfang und Gesendet-Kopie mit funktionierenden Links und Bild im Text.
- **a2:** HTML-Signatur mit Logo und Vorschau, Sichern und Wiederöffnen, Wechsel HTML → Einfach mit Rückfrage, einfache Signatur mit Formaten und Logo, Wechsel Einfach → HTML. Anlegen auf dem Mac. iCloud-Abgleich iPhone ↔ Mac in beide Richtungen.
- **a3:** neue Mail, Antwort und Weiterleitung aus verschiedenen Postfächern; beim Empfänger Signatur und Logo korrekt, auch offline und bei Spamverdacht. Signatur beim Verfassen geändert (einfach und HTML), Wechsel des Postfachs setzt die neue Signatur, auch nach Löschen.

---

## Beobachtungen

- **Simulator:** Während des Tests hing im Simulator eine Sondertaste (⌘/⌥) fest – Tippen markierte alles, Pfeiltasten sprangen wortweise, Rückschritt löschte ganze Zeilen, auch in Safari. Ein Neustart des Simulators behob es; kein Fehler in Mailwerk.
- **Ablage in den Projektordner (Werkzeug von Claude):** Wird dieselbe Datei mehrmals über denselben Zwischenpfad abgelegt, schrieb das Werkzeug teilweise den früheren Inhalt erneut und meldete trotzdem „geschrieben“. Abhilfe: für jede Korrektur ein frischer Zwischenpfad und Prüfsummenvergleich auf dem Mac nach jedem Ablegen.
- **CloudKit-Schema:** Der Datensatztyp für `AccountSignature` ist bisher nur in der Development-Umgebung angelegt. Vor dem App-Store-Gang das Schema im CloudKit-Dashboard nach Production übertragen (gilt auch für die Filterlisten).
- Die Logo-Breite einer einfachen Signatur ist fest 150 pt (bzw. die beim Einlesen gefundene Breite); ändern lässt sie sich nur über die Art HTML (`width`).
- Bilder, die beim Kopieren innerhalb des Editors weitergereicht werden, erhalten eine neue Content-ID; eine eigene Breite geht dabei auf die Standardbreite zurück.

## Nächste Schritte

- **Abruf je Postfach ein-/ausschalten** (nachträglicher Wunsch, in v0.1.13 nach den Signaturen): Inhalt vorab abstimmen (Leitfragen: Bedeutung von „aus“, Sichtbarkeit der Mails, Senden, je Gerät oder iCloud, Ort des Schalters, Reihenfolge vor/nach den Entwürfen).
- **Entwürfe (MW-16):** „Entwurf speichern“ beim Schließen, Entwurf weiterbearbeiten (nutzt den HTML-Rückweg aus a1), Beantwortet-Kennzeichen für gesendete Antwort-Entwürfe. Inhalt zuerst abstimmen.
