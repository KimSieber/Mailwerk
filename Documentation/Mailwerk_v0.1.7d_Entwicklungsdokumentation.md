# Mailwerk – Entwicklungsdokumentation v0.1.7d

2026-09-29 · Ordnerauswahl, Mailanzeige im Ordner, Stand und Offline-Betrieb

---

## Zusammenfassung

Version 0.1.7d macht die Ordner aus v0.1.7a auswählbar. Ein Tipp auf einen Ordner in der Leiste zeigt sofort dessen Mails aus dem Cache und ruft ihn im Hintergrund vom Server ab. Der gewählte Ordner ist in der Leiste hinterlegt und trägt – wie im Titel – den Farbpunkt seines Postfachs. Reine Container (`\Noselect`) bleiben grau und nicht wählbar.

Jede Ansicht zeigt in einer zweiten Titelzeile ihren **Stand**: „Aktualisiert: vor 5 Minuten". Der Stand wird dauerhaft gespeichert, ist also auch offline und nach einem Neustart bekannt. Sammelansichten („Alle Eingänge", „Mit Kennzeichnung") zeigen den ältesten Stand ihrer Posteingänge.

Die App arbeitet jetzt **offline**: Ohne Netz wird kein Abruf versucht und keine Fehlermeldung gezeigt; der Titel meldet orange „Offline · Stand: …". Kommt das Netz zurück, ruft die App die aktuelle Ansicht selbst ab. Beim App-Start und bei Pull-to-Refresh in „Alle Eingänge" werden neben den Posteingängen auch die Spam-Ordner aller Postfächer abgerufen.

---

## Projektstruktur (Änderungen gegenüber v0.1.7c)

```
Mailwerk/
├── Models/
│   ├── MailboxSelection.swift        # + .folder(accountID:path:displayName:)
│   └── SyncState.swift               # NEU – Stand einer Ansicht (.never | .at(Date)), ältester Stand
├── Services/
│   ├── MessageStore.swift            # + folderMessages, Tabelle folder_sync, recordSync/lastSync
│   ├── MailFetchService.swift        # Stand nach erfolgreichem Abruf vermerken, isConnectionError
│   ├── ConnectionErrorClassifier.swift # NEU – Verbindungsfehler (URL, POSIX, NIO) erkennen
│   └── NetworkMonitor.swift          # NEU – Netzstatus über NWPathMonitor
├── ViewModels/
│   └── InboxViewModel.swift          # Ordnerabruf, Spam-Ordner mit abrufen, Stand, Offline-Logik
├── Views/
│   ├── InboxView.swift               # zweizeiliger Titel mit Stand/Farbpunkt, Reconnect-Abruf
│   └── Folders/
│       └── FolderSidebarView.swift   # Ordner wählbar, Hinterlegung mit Farbpunkt
MailwerkTests/
├── SyncStateTests.swift              # NEU
└── MessageStoreSyncTests.swift       # NEU
```

Datenbank: neue Tabelle `folder_sync (accountID, folder, lastSyncAt)`, wird beim ersten Start automatisch angelegt.

---

## Getroffene Entscheidungen (v0.1.7d)

| Entscheidung | Begründung |
|---|---|
| Cache sofort zeigen, im Hintergrund abrufen | Kein Warten beim Ordnerwechsel; Verfahren wie Apple Mail |
| Posteingang + Spam-Ordner bei Start und Refresh von „Alle Eingänge" | In beiden Ordnern wird am meisten gearbeitet; übrige Ordner nur bei Bedarf, spart Speicher |
| Spam-Aktionen in allen Ordnern | Abgelegte Mails können sich später als Spam erweisen; eigene Prüfordner möglich |
| Farbpunkt des Postfachs am gewählten Ordner (Leiste und Titel) | Wiedererkennung mit dem Punkt am Postfach in der Leiste |
| Stand als zweite Titelzeile | Liste behält vollen Platz; unterer Rand bleibt frei für die geplante Suche |
| Stand in eigener Tabelle `folder_sync` | Auch leere Ordner haben einen Stand; überlebt Neustarts, offline verfügbar |
| Sammelansichten zeigen den ältesten Stand | Ansicht ist nur so aktuell wie das am längsten nicht abgerufene Postfach |
| Verbindungsfehler still im Titel (orange), andere Fehler per Alert | Offline ist ein normaler Zustand; falsches Passwort u. ä. muss gemeldet werden |
| „Server nicht erreichbar" wie offline behandelt | Im Fehlermoment nicht zuverlässig von „Netz weg" unterscheidbar; für den Nutzer gleiche Bedeutung |
| Automatischer Abruf bei zurückkehrendem Netz | Offline arbeiten ohne manuelles Nachladen |

---

## Behobene Fehler im Verlauf

| Fehler | Ursache | Lösung |
|---|---|---|
| Toolbar doppelt in Ordnern mit Mails | Zeitstempel stand als zweites View *neben* der List; Modifier einer `Group` wirken auf jedes Kind einzeln | Jeder Zweig der Group liefert genau ein View; Kommentar an der Group als Schutz |
| Kein Stand bei leeren Ordnern / offline | Stand nur im Speicher bzw. aus Nachrichten abgeleitet | Tabelle `folder_sync` |
| Warnung „captured var 'self'" im NetworkMonitor | Schwache Referenz im parallel laufenden Task gelesen | Task erhält eigene `[weak self]`-Kopie |

---

## Tests

| Testdatei | Tests | Inhalt |
|---|---|---|
| `SyncStateTests.swift` | 10 | Ältester Stand, „nie abgerufen", Einordnung von Verbindungsfehlern |
| `MessageStoreSyncTests.swift` | 5 | Stand speichern, überschreiben, je Ordner/Postfach getrennt, nach Neuöffnen erhalten |

Manuell geprüft: Ordnerwechsel, leere Ordner, Pull-to-Refresh, Flugmodus an/aus, App-Neustart offline, Spam-Ordner-Abruf, Toolbar in allen Ansichten.

---

## Noch nicht implementiert (geplant für v0.1.7e ff.)

- Ordnerliste in der Leiste offline verfügbar (Speicherung der Ordnerliste)
- Ungelesen-Zähler in der Leiste
- Ordnerbaum im Verschieben-Dialog
- Ordner anlegen und löschen (TD-10)
- Feste Seitenleiste für Mac und iPad im Querformat
- Stand-Anzeige auf dem Mac (Titel steht dort in der Fensterleiste)
- Suche am unteren Bildschirmrand

---

## Abhängigkeiten / Xcode-Konfiguration

Neu genutzt: Apples `Network`-Framework (automatisch verlinkt). Sonst unverändert.
