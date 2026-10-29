# Mailwerk – Entwicklungsdokumentation v0.1.16

2026-10-15 · Suche über alle Mails (Jira MW-6) und Sortierung, Bedienung am unteren Bildschirmrand

---

## Zusammenfassung

Anforderung: Das iPhone wird überwiegend mit einer Hand bedient. Die wichtigsten Knöpfe und Eingabefelder gehören deshalb an den unteren Rand. Dort sollen drei Knöpfe stehen: Sortieren, Suche, Neue Mail. Die Suche soll Text, Betreff und Anhangnamen durchsuchen und Personen vorschlagen.

**Entscheidungen (abgestimmt):**

| Frage | Entscheidung |
|---|---|
| Gestaltung der Leiste | **iOS-26-Standard** (Liquid Glass) statt eines größeren Mittelknopfs wie im Vorbild. Ein Eigenbau bleibt als möglicher USP für später offen. Die drei Knöpfe stehen als **Gruppe mittig**. |
| Sortierfelder | Von, Betreff, Datum, Größe; dazu aufsteigend/absteigend. In Gesendet/Entwürfen heißt „Von“ **„An“** und sortiert nach der angezeigten Person (Empfänger). |
| Geltung der Sortierung | **Nur für den gezeigten Ordner.** Ein Ordnerwechsel und das vollständige Beenden der App setzen sie auf **Datum absteigend** zurück. Keine Speicherung. Mail öffnen, Abruf, Antworten und App-Wechsel lassen sie bestehen. |
| Erkennbarkeit | Weicht die Sortierung ab, wird der Knopf **blau** (blau getönter Glaskreis). |
| Suchbereich | **Immer die gezeigte Ansicht**: „Alle Eingänge“ = alle Posteingänge mit eingeschaltetem Abruf, Ordner = nur dieser, „Mit Kennzeichnung“ = gekennzeichnete Mails (dort keine Serversuche). Kein Umschalter. |
| Suchregel | **Teilzeichenfolge** (findet „Stromrechnung“ mit „rechnung“), **ab 3 Zeichen, Leerzeichen zählen mit** („IS␣“ für Kürzel), Groß-/Kleinschreibung zählt nicht. Treffer an Wortenden („Preis␣“) bewusst in Kauf genommen. |
| Felder | Betreff, Personen (Von, An, Cc), Text, **Dateinamen** der Anhänge (nicht deren Inhalt). |
| Namensvorschläge | **Ab dem 1. Zeichen** aus den Adressen der Mails der Ansicht (nicht aus dem Adressbuch). **Alphabetisch**, Name fett, Adresse grau. Je Adresse ein Vorschlag. Gewählt wird die Person zur **Marke**: Mails von und an diese Adresse, ohne Mindestlänge. |
| Server oder Cache? | Erst sofort **lokal**, darunter Knopf **„Auf dem Server weitersuchen“**. |
| Servertreffer | **Nur Kopfdaten**, eigener Abschnitt „Auf dem Server“, ohne Doppelte. **Erst beim Antippen** wird die Mail geladen und in den Cache übernommen. Vor dem Öffnen keine Aktionen. **Höchstens 100 Treffer je Ordner.** |
| Offline | Nur Cache-Suche, der Server-Knopf ist grau (kein Zusatztext; „Offline“ steht im Titel). |
| Mac | **Funktional immer mit** (nicht auseinanderlaufen). Gestaltung und Bedienung folgen mit v0.2.x. |
| Vorschau (`preview`) | **Entfällt.** Der Suchindex ersetzt sie. |

**Umsetzung in drei Commits:**

| Paket | Inhalt | Commit |
|---|---|---|
| **a+b** | Untere Leiste, Sortiermenü, Suchindex (Schema-Stufe 7) | `fb32701` |
| **Fix** | Abgleich entfernt anderswo gelöschte neueste Mails (Zwischenruf) | `3e7faf3` |
| **c+d** | Lokale Suche, Namensvorschläge, Serversuche; Knopfgruppe, Leiste während der Suche | (folgt) |

Tests: 551 → **584** (33 neue, 3 entfallen), alle grün. `MARKETING_VERSION` 0.1.16 in allen drei Zielen.

---

## Paket a+b – Untere Leiste, Sortieren, Suchindex

### Untere Leiste

- **iPhone/iPad:** `ToolbarItem(placement: .bottomBar)`. Sortieren und Neue Mail sitzen in der unteren Leiste („Neue Mail“ ist von oben nach unten gewandert), dazwischen ab Paket c+d die Suche.
- **Auswahlmodus:** Die Befehlsleiste ersetzt die untere Leiste wie bisher.
- **Mac:** dieselben Knöpfe in der oberen Symbolleiste.
- **Rückgängig-Hinweis:** Er sitzt jetzt als Überlagerung des Inhalts und hält den sicheren Bereich ein, liegt also über der unteren Leiste statt auf ihr.

### Sortierung (`MessageSort`)

- Reine Logik:
  - Feld und Richtung.
  - „Von“ über `MessageRowParty` (in Gesendet/Entwürfen der erste Empfänger).
  - Texte wie im Finder verglichen (`localizedStandardCompare`, Zahlen nach Wert).
  - Bei Gleichstand gilt das Datum (neueste zuerst), dann die Cache-ID. So ist die Reihenfolge immer eindeutig.
- `InboxViewModel.sort`:
  - Die Liste wird sofort umsortiert.
  - `selection.didSet` setzt die Sortierung auf `.standard` zurück.
  - `loadFromCache` sortiert nur bei abweichender Sortierung, denn der Cache liefert bereits Datum absteigend.
- `sortsByRecipients` setzt die Ansicht, weil sie die Ordnerrolle kennt.
- **Hervorhebung:**
  - Zuerst `buttonStyle(.glassProminent)` – in der Leiste kaum sichtbar, vermutlich vom gemeinsamen Glashintergrund überdeckt.
  - Jetzt: blau getönter Glaskreis (`glassEffect(.regular.tint(.blue))`) mit weißem Symbol. Der gemeinsame Hintergrund der Leiste ist für diesen Knopf ausgeblendet (`sharedBackgroundVisibility(.hidden)`).
  - Der „flüssige“ Glaseffekt fehlt dabei – das Thema ist für die nächste Design-Optimierung vorgemerkt.

### Suchindex (Schema-Stufe 7)

**Problem:** Eine Suche mit `LIKE` über Text und HTML von rund 9.000 Mails wäre langsam. Für reine HTML-Mails würde sie außerdem in Tags und Stilangaben treffen.

**Lösung:** FTS5-Tabelle `message_search` mit Verfahren **„trigram“**. Sie liefert Teilzeichenfolgen ab 3 Zeichen und faltet Groß-/Kleinschreibung auch bei Umlauten.

- Spalten: `subject`, `people`, `body`, `attachments`. Die Zeilennummer ist die der Nachricht.
- **Schreiben:** `writeSearchEntry` liest Betreff, Von, An, Cc, Text/HTML und die Namen echter Anhänge (ohne eingebettete Bilder) und schreibt den Eintrag neu. Es läuft in derselben Transaktion bei:
  - `saveMessage`,
  - `saveMessageWithAttachments` (nach den Anhängen),
  - `updateHeaders` (An/Cc).
- **Löschen:** Ein Trigger `message_search_delete` (AFTER DELETE ON message) löscht den Eintrag. **Verschieben** behält die Zeilennummer und damit den Eintrag.
- **Aufbereitung (`SearchText`):**
  - Der Textteil hat Vorrang. Fehlt er, wird das HTML tolerant aufbereitet: Kopf, Stil, Skript und Kommentare fallen weg, Blockenden werden zu Leerzeichen, Tags fallen weg, Entitäten werden aufgelöst. Höchstens 50.000 Zeichen.
  - Personen: eine Zeile je Adresse, `Name <adresse>`, Adresse klein. So trifft eine gewählte Person über `<adresse>` genau diese Adresse und nicht `ruben@…` für `ben@…`.
  - Alles in NFC, damit ein zerlegtes „ä“ (Mac) gefunden wird.
- **Nachtragen (`SearchIndexBuilder`):**
  - Fehlende Einträge (Bestand nach dem Update oder ein gescheitertes Schreiben) werden beim App-Start in Paketen zu 50 mit 30 ms Pause nachgetragen, die neuesten zuerst.
  - Das läuft auf dem Main-Actor; die Pausen halten die Oberfläche bedienbar.
- **Sicherheit:** Fehlt die Tabelle (SQLite ohne FTS5), wird nicht indiziert. Das Speichern von Mails scheitert nie am Index, und der Trigger wird nur mit Tabelle angelegt.
- **Migration 6 → 7:** Tabelle und Trigger anlegen, Spalte `preview` entfernen (`DROP COLUMN`). Stufe 3 legt die Vorschau nicht mehr an.
- `MessageListItem`: `preview` → **`sizeBytes`** (für „Größe“).

---

## Fix – Abgleich entfernt anderswo gelöschte neueste Mails

**Fund (Test):** Auf dem iPhone gelöschte Testmails erschienen auf dem Mac weiter im Eingang (und im Papierkorb).

**Ursache (im Code belegt):**
- Der Abgleich (`ServerReconciliation.plan`) entfernte nur gecachte Mails mit UID ≤ `keepUIDsAbove`.
- Diese Grenze war die **höchste UID, die der Server noch meldet**. Sie sollte Mails schützen, die während des Abrufs eintreffen.
- Waren die gelöschten Mails die neuesten (höchste UIDs), lag die Grenze darunter. Die gelöschten Mails galten als „neu eingetroffen“ und blieben, bis eine neue Mail ankam.
- Das iPhone war nicht betroffen, weil es selbst gelöscht und seinen Cache dabei bereinigt hatte.

**Lösung:**
- Grenze = **UIDNEXT − 1** aus der Auswahl des Ordners (`removalLimit`). Jede Mail darunter gab es bei der Auswahl schon.
- Später eintreffende Mails bekommen eine UID ab UIDNEXT und bleiben geschützt.
- Ohne UIDNEXT (0) gilt wie bisher die höchste UID.
- `MailFetchService.reconcile` bekommt `uidNext` aus dem SELECT, den der Abruf ohnehin ausführt.

---

## Paket c+d – Suche

### Ablauf

```
Suchknopf (untere Leiste) ─▶ searchable (Suchfeld über der Tastatur)
   ├─ Eingabe/Marke ─▶ SearchViewModel.queryChanged
   │     └─ MessageStore.searchMessageIDs(scope, MATCH) ─▶ matchingIDs
   │            └─ InboxViewModel.searchFilter ─▶ visibleMessages (Liste)
   ├─ Vorschläge: participantAddresses(scope) ─▶ SearchPerson.collect/suggestions
   └─ „Auf dem Server weitersuchen“ ─▶ MailFetchService.searchOnServer (je Postfach)
         └─ Antippen ─▶ ServerMessageLoader ─▶ MailFetchService.loadMessage ─▶ Cache
```

### Lokale Suche

- `SearchText.matchExpression`:
  - Die Eingabe wird unverändert (samt Leerzeichen) zur FTS5-**Phrase**, innere Anführungszeichen werden verdoppelt. Sonderzeichen gelten damit als Text.
  - Eine Marke wird zu `people : "<adresse>"`.
  - Beides zusammen wird mit `AND` verknüpft.
- Die lokale Suche liefert **nur Cache-IDs**. Die Liste filtert ihre eigenen Einträge (`InboxViewModel.searchFilter` → `visibleMessages`). Damit gelten Sortierung, Wischen, Kontextmenü und Auswahl unverändert auch für Treffer.
- „Alle auswählen“ und die Sammelaktionen arbeiten mit `visibleMessages`, also nur mit den Treffern.
- Nach jedem `loadFromCache` (Zähler `cacheGeneration`) läuft die Suche erneut, damit neue, gelöschte und geladene Mails berücksichtigt sind.
- Wechselt die Ansicht, wird die Suche beendet (`SearchScope` geändert).

### Namensvorschläge

- `MessageStore.participantAddresses(in:)`: Von, An und Cc der Ansicht ohne Doppelte. Gleiche JSON-Listen werden nur einmal entschlüsselt.
- `SearchPerson.collect`:
  - Adressen zerlegen, gleiche Adressen ohne Groß-/Kleinschreibung zusammenfassen, der erste bekannte Name gilt.
  - Alphabetisch sortieren.
- `suggestions`: trifft Name oder Adresse (ohne Groß-/Kleinschreibung und Akzente), höchstens 12 Vorschläge.
- Darstellung über `searchSuggestions` mit `searchCompletion(person)`. Eine zweite Marke ersetzt die erste; der getippte Name wird beim Wählen gelöscht.

### Serversuche

- `MailFetchService.searchOnServer`:
  - Ordner nur lesend auswählen (**EXAMINE**).
  - Suche mit **TEXT** (Kopf und Inhalt, damit auch Betreff und Anhangnamen) bzw. FROM/TO/CC für die Marke.
  - Treffer im Cache entfallen.
  - Kopfdaten für die **300 höchsten UIDs** holen (in Paketen zu 100, BODY.PEEK – nichts wird als gelesen markiert), nach Datum ordnen und die neuesten **100** liefern. Dass UIDs nichts über das Datum sagen, zeigt der IMAPSYNC-Umzug.
  - Gespeichert wird nichts.
- `SearchViewModel.searchServer`:
  - Nacheinander je Postfach. Ein nicht erreichbares Postfach wird gezählt („Nicht alle Postfächer erreichbar – erneut versuchen“).
  - Die Treffer stehen gemeinsam nach Datum.
  - Eine geänderte Eingabe verwirft das Ergebnis.
- Anzeige: Abschnitt „Auf dem Server“ mit Knopf, Ladeanzeige, Treffern bzw. „Keine weiteren Treffer auf dem Server“ und „Weitere Treffer – Suche verfeinern“.
- **Öffnen (`ServerMessageLoader`):**
  - `MailFetchService.loadMessage` lädt die Mail auf dem gewohnten Weg (`cacheMessages`) und zeigt sie in `MessageDetailView`.
  - Erst beim Zurückkehren wird der Treffer aus dem Abschnitt genommen und die Liste neu geladen. Er ist dann ein lokaler Treffer.
  - Ohne Netz oder bei Fehler erscheint ein Hinweis mit „Erneut versuchen“.

### Korrekturen aus dem Funktionstest

| Fund | Ursache | Lösung |
|---|---|---|
| Während einer Suche fehlten oben Ordner-Knopf, Titel und Einstellungen bzw. „Alle auswählen“ und „Fertig“ | iOS blendet die obere Leiste aus, solange die Suche aktiv ist | `searchPresentationToolbarBehavior(.avoidHidingContent)`. Zusätzlich bleibt das Suchfeld im Auswahlmodus unten (`DefaultToolbarItem` auch im Auswahlzweig). |
| Server-Knopf offline nicht grau, kleiner Zusatztext schlecht lesbar | Ein deaktivierter Knopf in der Liste wird nur schwarz statt blau | Farbe ausdrücklich grau, Zusatztext entfernt |
| Drei Einzelknöpfe „verloren“ verteilt | Flexible Abstandhalter zwischen den Knöpfen | Abstandhalter nur außen; die Knöpfe stehen als Gruppe mittig |

---

## Geänderte Dateien (gesamte Version)

```
Mailwerk.xcodeproj/project.pbxproj          # Version 0.1.16 (drei Ziele)
Mailwerk/
├── Models/
│   ├── MessageListItem.swift               # preview → sizeBytes
│   ├── MessageSort.swift                   # neu: Sortierung
│   ├── SearchScope.swift                   # neu: Suchbereich je Ansicht
│   └── SearchPerson.swift                  # neu: Namensvorschläge
├── Services/
│   ├── MessageStore.swift                  # Schema 7, Suchindex, Suche, Adressen
│   ├── MailFetchService.swift              # reconcile mit UIDNEXT, searchOnServer, loadMessage
│   ├── Search/
│   │   ├── SearchText.swift                # neu: Aufbereitung, Suchausdruck
│   │   └── SearchIndexBuilder.swift        # neu: Index nachtragen
│   └── Sync/
│       └── ServerReconciliation.swift      # removalLimit (UIDNEXT)
├── ViewModels/
│   ├── InboxViewModel.swift                # sort, searchFilter, visibleMessages, cacheGeneration
│   └── SearchViewModel.swift               # neu: Suche
└── Views/
    ├── InboxView.swift                     # untere Leiste, Sortiermenü, searchable, Abschnitt „Auf dem Server“
    └── ServerMessageLoader.swift           # neu: Servertreffer öffnen
MailwerkTests/
├── MessageSortTests.swift                  # neu, 6 Tests
├── SearchTextTests.swift                   # neu, 9 Tests
├── MessageStoreSearchIndexTests.swift      # neu, 9 Tests
├── MessageStoreSearchTests.swift           # neu, 5 Tests
├── SearchPersonTests.swift                 # neu, 4 Tests
├── ServerReconciliationTests.swift         # +3 Tests (UIDNEXT)
├── MessageStoreListTests.swift             # Vorschau-Tests entfallen (−3), Migration angepasst
├── MessageStoreSyncTests.swift             # Schema-Version 7
├── MessageStoreTransactionTests.swift      # Schema-Version 7
├── MessageRowPartyTests.swift              # sizeBytes
└── MessageSelectionTests.swift             # sizeBytes
```

---

## Testverfahren

**Automatisch:** **584 Tests** (Simulator), alle grün. Vorab unter Linux (Swift 6.2, SwiftMail 1.15.0 im SwiftPM-Paket):
- übersetzt und getestet: Ablage samt Suchindex (FTS5 „trigram“), `SearchText`, `MessageSort`, `SearchPerson`, `SearchScope`, `ServerReconciliation`;
- nur übersetzt: `MailFetchService`, `SearchViewModel`;
- Platzhalter für `os.Logger`, Schlüsselbund und `AccountStore`.

**Manuell:**

| Nr. | Test | Ergebnis |
|---|---|---|
| 1 | Sortieren nach allen Feldern und Richtungen, Zurücksetzen beim Ordnerwechsel, Gesendet „An“ | ✔ |
| 2 | Sortierknopf blau bei abweichender Sortierung | ✔ |
| 3 | Fix: Testmail an sich selbst, auf iPhone gelöscht → auf dem Mac nach Abruf weg | ✔ |
| 4 | Freitextsuche, Suche nach Person (Marke) | ✔ |
| 5 | Auf dem Server weitersuchen, Treffer öffnen (geladen, danach lokal) | ✔ |
| 6 | Offline: lokale Suche geht, Server-Knopf grau | ✔ |
| 7 | „Mit Kennzeichnung“: kein Server-Knopf | ✔ |
| 8 | Auswahl während der Suche: „Alle auswählen“ und „Fertig“ sichtbar, nur Treffer ausgewählt | ✔ (nach Korrektur) |
| 9 | Obere Leiste bleibt während der Suche | ✔ (nach Korrektur) |
| 10 | Mac: Build, Run, Suche inkl. Server nachladen | ✔ |

---

## Beobachtungen

- **Fehlende Absenderbilder bei Mails vor etwa 10.09.2026 (Testinstallation):**
  - Ein Bild erscheint nur, wenn die Spam-Einstufung des Servers bekannt ist. Ist sie unbekannt, wird vorsichtshalber kein Bild gezeigt, auch nicht bei Whitelist.
  - Die Einstufung speichert Mailwerk seit v0.1.9e1b (Schema-Stufe 4, 11.10.2026). Ältere Einträge werden beim Abruf ihres Ordners nachgefüllt – aber **nur Mails im 30-Tage-Fenster der Datumssuche**. Am 11.10. reichte es bis etwa 10.09. zurück.
  - Mails, die vorher per „Ältere laden“ geholt worden waren, blieben ohne Einstufung und damit ohne Bild.
  - Heute geladene Mails (auch per „Ältere laden“) sind nicht betroffen.
  - **Entscheidung: Weg A** – App neu installieren, der Cache baut sich neu auf. Es ist ein Übergangseffekt der Testinstallation, keine Sonderlösung.
  - Weg B steht unter „Offene Punkte“.
- **Erster Start nach dem Update:** Der Suchindex wird im Hintergrund nachgetragen (Protokoll „🔎 Suchindex nachgetragen: n Mails“). Bis dahin findet die Suche ältere Mails noch nicht.
- **Glaseffekt des blauen Sortierknopfs** ist nicht „flüssig“ wie die übrigen Knöpfe – für die nächste Design-Optimierung vorgemerkt.
- **Serversuche mit TEXT** kann je nach Server auch Treffer im Inhalt von Anhängen liefern; bewusst in Kauf genommen (Obermenge).
- **Servertreffer haben vor dem Öffnen keine Büroklammer**, denn Anhänge sind erst nach dem Laden der Struktur bekannt.

## Offene Punkte (neu)

- **Kopfdaten außerhalb des Zeitfensters nachfüllen (Weg B):** Das Nachfüllen bei einer höheren Header-Version (`messageIDsNeedingHeaders`) erfasst nur Mails im 30-Tage-Fenster. Es sollte alle Mails des Ordners mit veralteter Version erfassen, sonst wiederholt sich der Effekt bei jeder künftigen Erhöhung. Das ist eine Änderung am Abruf, also ein eigenes Paket.
- **Liquid-Glass-Effekt** des hervorgehobenen Sortierknopfs.

## Nächste Schritte

- Inhalt der nächsten Version festlegen (siehe Übergabe v0.1.17).
