# Mailwerk – Konzept: Sync-Zustand je Ordner

Stand: 2026-10-06 · freigegeben · Umsetzung in v0.1.9b (Schritt b3)

---

## 1. Ziel

Zwei Probleme mit einem gemeinsamen Mechanismus lösen:

1. **Lücke aus a1b:** Eine Mail, die außerhalb von Mailwerk in einen Ordner kommt (Webmail, iPad, Filterregel des Servers) und ein altes Eingangsdatum hat, erscheint nie. Der Abruf sucht nur nach Datum (letzte 30 Tage), „Ältere laden" nur vor dem Fensterbeginn.
2. **H2 aus dem Review:** Mailwerk prüft UIDVALIDITY nicht. Ändert der Server die UID-Vergabe eines Ordners (Umzug, Wiederherstellung, Neuaufbau), zeigen gecachte UIDs auf falsche Mails. Markieren, Löschen oder Verschieben träfe dann die falsche Nachricht.

Nicht-Ziel: eine neue Abruflogik. Zeitfenster, „Ältere laden" und Abgleich bleiben, wie sie sind. Ergänzt wird nur, was fehlt.

---

## 2. Grundlage

Das Vorgehen folgt dem etablierten Muster für IMAP-Clients mit lokalem Cache (beschrieben in RFC 4549, „Synchronization Operations for Disconnected IMAP4 Clients"):

- **UIDVALIDITY:** Kennzahl eines Ordners. Solange sie gleich bleibt, sind UIDs stabil. Ändert sie sich, ist der lokale Stand dieses Ordners ungültig.
- **UIDNEXT:** die UID, die die nächste im Ordner ankommende Mail erhalten wird. UIDs werden aufsteigend in der Reihenfolge des **Ankommens im Ordner** vergeben, nicht nach Datum. Eine hineinkopierte oder verschobene Mail bekommt immer eine neue UID ≥ dem bisherigen UIDNEXT.

Daraus folgt: **Alles, was seit dem letzten Abruf im Ordner angekommen ist, hat eine UID ≥ dem damals gespeicherten UIDNEXT.** Das gilt unabhängig vom Datum der Mail und ist durch die Zahl der Neuankünfte begrenzt, nie durch die Größe des Ordners.

Beide Werte liefert der Server bei jedem `SELECT`; SwiftMail stellt sie als `selection.uidValidity` und `selection.uidNext` bereit.

---

## 3. Datenmodell

Die bestehende Tabelle `folder_sync` (je Postfach und Ordner, wird nur nach erfolgreichem Abruf geschrieben, beim Löschen von Ordner oder Postfach mit entfernt) erhält zwei Spalten:

| Spalte | Typ | Bedeutung |
|---|---|---|
| `uidValidity` | INTEGER, NULL erlaubt | UIDVALIDITY beim letzten erfolgreichen Abruf |
| `uidNext` | INTEGER, NULL erlaubt | ab dieser UID beginnen die noch nicht gesehenen Mails |

Migration: Schema-Stufe 2 (`PRAGMA user_version = 2`), zwei `ALTER TABLE`. Bestehende Zeilen haben danach NULL; das gilt als „noch kein Zustand" (siehe Fall A).

---

## 4. Ablauf eines Abrufs (je Ordner)

```
SELECT  →  Server: uidValidity, uidNext
        │
        ├─ kein gespeicherter Zustand ........ Fall A
        ├─ uidValidity ≠ gespeichert ......... Fall B: Ordner-Cache verwerfen, dann wie A
        └─ uidValidity = gespeichert ......... Fall C
        │
Datumssuche (30 Tage, im Posteingang plus gekennzeichnete) und speichern – wie bisher
        │
Abgleich (unverändert: Gelöschtes entfernen, Flags übernehmen; liefert alle UIDs)
        │
nur Fall C: Neuankünfte ab gespeichertem uidNext laden (aus den UIDs des Abgleichs)
        │
Zustand speichern: uidValidity, uidNext  (nur wenn alles erfolgreich war)
```

Die Entscheidung A/B/C ist reine Logik ohne IMAP und Datenbank (`SyncStatePlanner`, `nonisolated`) und wird vollständig durch Unit-Tests abgedeckt.

**Neuankünfte laden (Fall C):** Der Abgleich holt ohnehin alle UIDs des Ordners (`UID FETCH 1:* (FLAGS)`). Daraus werden die UIDs im Bereich `gespeicherter uidNext ..< uidNext des Servers` genommen; eine zusätzliche Server-Abfrage ist nicht nötig. Die obere Grenze schließt Mails aus, die erst nach dem SELECT eintrafen – sie gehören zum nächsten Abruf. Bereits gecachte UIDs (Datumssuche, Verschieben in Mailwerk) fallen heraus.

**Obergrenze:** Die Grenze gilt **nur für Neuankünfte, die die Datumssuche nicht ohnehin findet**, also für alt datierte Mails, die außerhalb von Mailwerk in einen Ordner kommen. Erstabruf, „Ältere laden" und neue Mails mit aktuellem Datum sind davon nicht betroffen. Je Abruf und Ordner werden höchstens **200** solcher Mails geladen, aufsteigend. Der gespeicherte `uidNext` rückt dann nur bis hinter die zuletzt geladene UID vor; der Rest folgt bei den nächsten Abrufen, ohne Dialog, mit Konsoleneintrag.

**Paketierung der Kopfdaten:** Unabhängig vom Sync-Zustand werden die Kopfdaten in `cacheMessages` in Paketen zu **100** Mails abgefragt. Innerhalb eines Abrufs kommen alle Mails; es entstehen nur mehrere kleine Anfragen statt einer großen. Das sichert auch Erstabruf und „Ältere laden" gegen Timeouts bei sehr vollen Zeiträumen ab.

---

## 5. Fälle

| # | Situation | Verhalten | Ergebnis |
|---|---|---|---|
| 1 | Erster Abruf eines Ordners / frische Installation | Fall A: 30 Tage + gekennzeichnete wie bisher; Zustand merken | keine Historie, kein Timeout |
| 2 | Neue Mail kommt an | Fall C: SEARCH (Datum) findet sie, Neuankünfte ebenso; doppelt wird erkannt | wie bisher |
| 3 | Alt datierte Mail im Webmail in den Ordner kopiert/verschoben | Fall C: neue UID ≥ gespeichertem uidNext → wird geladen | **Lücke aus a1b geschlossen** |
| 4 | Wie 3, danach trifft noch eine neue Mail ein | beide UIDs ≥ gespeichertem uidNext → beide geladen | kein Verlust (Schwachstelle der „höchsten gecachten UID") |
| 5 | Mail in Mailwerk verschoben (auch Spamfilter) | Zielordner: UID schon im Cache → nur Flags | wie bisher |
| 6 | Mail anderswo aus dem Ordner entfernt | Abgleich entfernt sie | wie bisher |
| 7 | „Ältere laden" | unverändert | wie bisher |
| 8 | UIDVALIDITY geändert (Umzug, Wiederherstellung) | Fall B: Mails, Stand und Zeitfenster **nur dieses Ordners** verwerfen, neu abrufen; Log-Eintrag | kein Markieren/Löschen falscher Mails |
| 9 | 3.000 alte Mails auf einmal hineinverschoben | je Abruf 200 Mails, Rest bei Folgeabrufen | kein Timeout |
| 10 | Abruf bricht mittendrin ab | Zustand wird nicht gespeichert → nächster Abruf wiederholt ab altem Stand | nichts geht verloren |
| 11 | Größtes Postfach (8.780 Mails), bestehender Cache | Neuankünfte = Zahl der seit dem letzten Abruf angekommenen Mails | Laufzeit wie bisher |

---

## 6. Betroffene Dateien (Umsetzung b3)

- `MessageStore.swift`: Migrationsstufe 2; `recordSync` speichert zusätzlich `uidValidity`/`uidNext`; `syncState` und `cachedUIDs` zum Lesen.
- `Services/Sync/SyncStatePlanner.swift` (neu): Entscheidung A/B/C, Bereich der Neuankünfte inkl. Obergrenze; enthält den Typ `FolderSyncState`.
- `MailFetchService.swift`: Werte aus `selectMailbox` übernehmen, Neuankünfte laden, Zustand nach Erfolg speichern; `reconcile` liefert den Server-Stand zurück; Paketierung der Kopfdaten.
- Tests: `SyncStatePlannerTests.swift` (neu), Erweiterung von `MessageStoreSyncTests.swift` (Migration 2, Zustand speichern/lesen, Fall B räumt nur einen Ordner ab).

Nicht betroffen: Zeitfenster, „Ältere laden", Abgleich, Oberfläche.

---

## 7. Tests

**Automatisch:** alle Fälle A/B/C, Obergrenze und Fortschritt, Migration einer Datenbank der Stufe 1, Fall B räumt nur den betroffenen Ordner ab.

**Manuell:**
1. Testordner: alt datierte Mail hineinkopieren → erscheint (Fall 3).
2. Testordner: alt datierte Mail hineinkopieren, dann eine neue Mail an dich selbst in denselben Ordner → beide erscheinen (Fall 4).
3. Größtes Postfach auf Mac und Simulator: kein Timeout, Laufzeit wie bisher (Fall 11).
4. Frische Installation im Simulator: alle Postfächer ohne Timeout (Fall 1).
5. Fall 8 lässt sich am echten Server nicht auslösen; er ist durch Unit-Tests abgedeckt.

---

## 8. Ausblick (nicht Teil von b3)

Mit CONDSTORE/QRESYNC könnte auch der Flag-Abgleich auf Änderungen seit dem letzten Abruf beschränkt werden, statt jedes Mal den ganzen Ordner zu lesen. SwiftMail unterstützt das; ob manitu es anbietet, wäre vorher zu prüfen. Das ist eine Performance-Frage für später, keine Korrektheitsfrage.

---

## 9. Entscheidungen (getroffen)

1. **Obergrenze:** 200 Neuankünfte je Abruf und Ordner, nur für Mails, die die Datumssuche nicht findet.
2. **Paketgröße der Kopfdaten-Abfrage:** 100.
3. **Fall B (UIDVALIDITY geändert):** Ordner-Cache ohne Rückfrage verwerfen und neu abrufen, mit Log-Eintrag.
4. **Datumssuche (SEARCH SINCE):** bleibt erhalten.
