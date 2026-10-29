# Mailwerk – Entwicklungsdokumentation v0.1.10

2026-10-11 · Absenderbild in der Mailliste (Jira MW-7) und schlankere Listenzeile

---

## Zusammenfassung

Jede Zeile der Mailliste zeigt links einen runden Kreis mit dem Bild der Person: Kontaktbild aus dem Adressbuch, sonst das Logo (Favicon) der Absenderdomain, sonst Initialen. Die Zeile ist auf drei Zeilen verschlankt, ungelesene Mails sind am breiten Farbstreifen sofort erkennbar.

**Entschieden:**
- Neuer Fahrplan bis zum Live-Gang: v0.1.10 Absenderbild, v0.1.11 Mehrfachauswahl und Kontextmenü (MW-9), v0.1.12 Mailanzeige vervollständigen (`cid:`-Bilder, Dunkelmodus, Zoom, zuletzt Originaltext MW-5), v0.1.13 Signaturen und Entwürfe (MW-2, MW-16), v0.1.14 Teilen an Mailwerk (MW-15), v0.1.15 Suche (MW-6). Seitenleiste iPad/Mac komplett nach v0.2.x.
- **Zeile:** (1) Kennzeichen links, Datum rechts, klein und grau; (2) Name fett bei ungelesen, Adresse klein und grau dahinter (wird zuerst gekürzt); (3) Betreff. Die Vorschauzeile entfällt.
- **Datum:** heute nur Uhrzeit (`17:06`), sonst Wochentag, Datum mit vierstelliger Jahreszahl und Uhrzeit (`Mo, 28.09.2026 17:06`). Gezeigt wird weiterhin das Kopfdatum der Mail (keine Änderung am Speicher).
- **Farbstreifen:** gelesen 4 pt, ungelesen 8 pt; Postfach ohne Farbe: gelesen kein Streifen, ungelesen hellgrau 8 pt.
- **Gesendet und Entwürfe:** Bild, Name und Adresse des ersten Empfängers, bei mehreren „+n“.
- **Bildquelle:** Adressbuch zuerst (auch bei Unternehmen), dann Logo der Domain, dann Initialen. Freemail-Anbieter bekommen kein Logo. Kleine Logos werden unscharf gezeigt – lieber unscharf als Initialen.
- **Spam:** Kein Bild (leerer Kreis), wenn der Spamfilter die Mail nicht behalten würde – dieselbe Regel wie der Filterlauf. Unbekannte Spam-Angabe = kein Bild.
- **Logos:** Laden im Hintergrund, Speichern je Domain; ohne Treffer nach 30 Tagen erneut, Treffer nach 90 Tagen auffrischen. Logo auf weißem Kreis.
- **Kontakte-Berechtigung:** Abfrage beim ersten Anzeigen der Liste; ohne Berechtigung Logos bzw. Initialen.
- DKIM-Prüfung bewusst später (auch für die Spam-Prüfung zu betrachten).

Tests: 388 → **431**, alle grün.

---

## MVP a – Neue Listenzeile

**Problem:** Die Zeile zeigte Absender, Datum, Betreff und Vorschau. Die Vorschau (meist die Anrede) kostete Platz; ungelesene Mails waren schwer zu erkennen.

**Lösung:**
- `MessageRow` (neu, aus `InboxView` herausgelöst) mit drei Zeilen, Farbstreifen in reserviertem 8-pt-Platz (die Zeile springt beim Lesen nicht).
- `MessageRowParty` (neu): gezeigte Person (Absender bzw. erster Empfänger), Texte der Namenszeile, Initialen, feste Farbe je Adresse (FNV-1a statt `hashValue`).
- `ListDateFormatter` (neu): festes Datumsformat mit zwischengespeicherten Formatierern.
- `SenderAvatarView` (neu): Kreis mit Initialen oder leer.
- `MessageListItem` und Listenabfrage im `MessageStore` liefern zusätzlich Empfänger und Spam-Angabe (vorhandene Spalten, kein Schemaumbau).
- `SpamClassifier.allowsSenderImage` (neu): Bild nur, wenn `classify` „behalten“ ergibt. `InboxViewModel` hält dafür eine Kopie der Filterlisten und liest sie bei jedem Laden der Liste, nach dem Schließen der Spam-Einstellungen und nach iCloud-Änderungen neu.
- Rolle des gezeigten Ordners (Gesendet/Entwürfe) aus dem Ordnerbaum (`[FolderNode].node(withPath:)`).

## MVP b – Kontaktbilder

**Lösung:**
- `ContactImageDirectory` (neu): liest einmal im Hintergrund alle Kontakte mit Bild und hält die Vorschaubilder je Adresse nur im Speicher. Änderungen am Adressbuch (`CNContactStoreDidChange`) bauen die Zuordnung neu auf; die Liste zeigt neue Bilder ohne Neustart.
- Berechtigung über `ContactSuggestionService` (gemeinsam mit den Adressvorschlägen), angefragt beim ersten Anzeigen der Liste.
- Text der Systemabfrage im Projekt (Debug und Release) erweitert: „… und zeigt in der Mailliste die Bilder deiner Kontakte …“.

## MVP c – Logos (Favicons)

**c1 – Grundlagen:**
- `SenderDomain` (neu): Domain aus der Adresse, gekürzt auf die Hauptdomain (`mailing.beispiel-shop.de` → `beispiel-shop.de`; zweiteilige Länderendungen wie `co.uk` berücksichtigt), Freemail-Liste. Umlaut-Domains bleiben ohne Logo.
- `SenderIconRecord` (neu): Logo bzw. erfolgloser Versuch mit Prüfzeitpunkt, Regel 30/90 Tage.
- `MessageStore`: **Schema-Stufe 5**, Tabelle `sender_icon (domain, image, checkedAt)`. Gehört keinem Postfach und bleibt beim Entfernen eines Postfachs erhalten.

**c2 – Laden und Anzeigen:**
- `SenderIconFetcher` (neu): `apple-touch-icon.png`, dann Icon-Angaben der Startseite (größte zuerst, ohne SVG), dann `favicon.ico`. Nur HTTPS (auch Weiterleitungen), keine Cookies, kein Cache, kein Dienst Dritter, 200 KB je Bild, 512 KB Startseite. Gespeichert wird ein neu erzeugtes PNG ≤ 120 px, nie das Original. „Nicht erreichbar“ wird nicht gespeichert und beim nächsten Start erneut versucht.
- `SenderIconCache` (neu): Warteschlange mit höchstens drei gleichzeitigen Abrufen, jede Domain einmal je Sitzung, offline kein Abruf. Ergibt ein Auffrischen „kein Logo“, bleibt ein vorhandenes Logo stehen.
- `DecodedImage` (neu): gemeinsame Umwandlung von Bilddaten in ein SwiftUI-Bild für Kontaktbilder und Logos.
- Spam-Zeilen fragen gar nicht erst nach Bildern – sie lösen also keinen Abruf aus.

**Compiler-Absturz (Swift 6.2):** Die Weiterleitungsprüfung als `async`-Delegate-Methode in einem `nonisolated` Typ brachte den Compiler zum Absturz (ohne Fehlermeldung, nur „SwiftCompile failed“; die fehlende `.dia`-Datei im aufgeklappten Protokoll zeigte die Datei). Lösung: eigener Typ `SenderIconRedirectGuard` mit Completion-Handler. Bei „SwiftCompile failed“ ohne Meldung immer den aufgeklappten Compile-Eintrag lesen – der in der Übersicht genannte Dateiname kann eine andere Datei derselben Übersetzungsgruppe sein.

---

## Geänderte Dateien

```
Mailwerk/
├── Models/
│   ├── MessageListItem.swift          # Empfänger, Spam-Angabe
│   ├── MessageRowParty.swift          # neu
│   ├── SenderDomain.swift             # neu
│   ├── SenderIconRecord.swift         # neu
│   └── FolderNode.swift               # node(withPath:)
├── Services/
│   ├── ListDateFormatter.swift        # neu
│   ├── ContactImageDirectory.swift    # neu
│   ├── ContactSuggestionService.swift # nur Dateikopf
│   ├── SenderIconFetcher.swift        # neu
│   ├── SenderIconCache.swift          # neu
│   ├── MessageStore.swift             # Listenspalten, Schema 5, sender_icon
│   └── Spam/
│       ├── SpamClassifier.swift       # allowsSenderImage
│       └── SpamFilterService.swift    # currentLists()
├── ViewModels/InboxViewModel.swift    # Filterlisten für Absenderbilder
└── Views/
    ├── MessageRow.swift               # neu (ersetzt InboxRow)
    ├── SenderAvatarView.swift         # neu
    ├── DecodedImage.swift             # neu
    └── InboxView.swift                # MessageRow, Bilder, Start der Kontaktbilder
Mailwerk.xcodeproj/project.pbxproj     # Text der Kontakte-Abfrage, Version 0.1.10
MailwerkTests/
├── MessageRowPartyTests.swift         # neu, 9 Tests
├── ListDateFormatterTests.swift       # neu, 4 Tests
├── ContactImageDirectoryTests.swift   # neu, 3 Tests
├── SenderDomainTests.swift            # neu, 5 Tests
├── SenderIconStoreTests.swift         # neu, 6 Tests
├── SenderIconFetcherTests.swift       # neu, 8 Tests
├── SpamClassifierTests.swift          # +4 Tests
├── MessageStoreListTests.swift        # +2 Tests, Schema 5
├── FolderNodeTests.swift              # +2 Tests
├── MessageStoreTransactionTests.swift # Schema 5
└── MessageStoreSyncTests.swift        # Schema 5
```

---

## Testverfahren

**Automatisch:** 431 Tests (Simulator), alle grün.

**Manuell (Simulator, Mac kurz):**
- „Alle Eingänge“: drei Zeilen, Kennzeichen links, Datumsformate, Streifen 4/8 pt, Wechsel gelesen/ungelesen ohne seitliches Springen.
- Spam-Ordner: leerer Kreis. Gesendet: Empfänger mit „+n“.
- Kontakt mit Foto im Simulator angelegt: Foto erscheint; Foto eines zweiten Kontakts bei laufender App ergänzt: erscheint ohne Neustart.
- Logos erscheinen nach kurzer Zeit; beim zweiten Start sofort; offline aus dem Cache.
- Migration Schema 4 → 5 mit bestehendem Cache: Liste unverändert.
- Mac: Zeile sieht ordentlich aus (Gestaltung iPad/Mac folgt in v0.2.x).

---

## Beobachtungen

- Der Simulator behält Postfächer und Passwörter (iCloud-Speicher des Simulators), solange er nicht neu aufgesetzt wird.
- Die Vorschau (`preview`) wird weiter gespeichert, aber nicht mehr angezeigt.
- Bei ungelesenen Mails ist nur der Name fett, der Betreff nicht (nach erstem Test so belassen).

## Nächste Schritte

- v0.1.11: Mehrere Mails markieren und per langem Drücken bearbeiten (MW-9), vorher `MessageDetailView` aufteilen (N13). Inhalt zuerst abstimmen.
- Merkliste: DKIM-/Authentication-Results-Prüfung (Logos und Spam-Prüfung).
