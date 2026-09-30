# Mailwerk – Entwicklungsdokumentation v0.1.8d

2026-09-30 · Server-Abgleich des Caches, Postfach entfernen

---

## Zusammenfassung

**Der Server ist führend, Mailwerk folgt ihm.** Das gilt für Änderungen aus dem Webmail ebenso wie für weitere Mailwerk-Installationen auf iPad oder Mac – für den Abgleich sind beide dasselbe.

Nach jedem Abruf eines Ordners gleicht Mailwerk seinen Cache mit dem Server ab: Mails, die es dort nicht mehr gibt, verschwinden; geänderte Flags (gelesen, gekennzeichnet, beantwortet, weitergeleitet) werden übernommen. Abgeglichen werden beim Abruf nur Posteingang und Spam, jeder andere Ordner beim Öffnen.

Wird ein Postfach in Mailwerk entfernt, wird sein gesamter Cache gelöscht – und davor **muss bestätigt werden**, auch beim Wischen.

---

## Geänderte Dateien

```
Mailwerk/
├── Services/
│   ├── Sync/ServerReconciliation.swift   # NEU – Vergleichslogik (Ordner Sync ist neu)
│   ├── MailFetchService.swift            # + reconcile(), Messung (DEBUG, abgeschaltet)
│   ├── MessageStore.swift                # + cachedFlagStates, cachedFlaggedStates,
│   │                                     #   apply(plan), deleteAccount
│   └── AccountStore.swift                # removeAccount räumt den Cache ab
└── Views/AccountListView.swift           # Rückfrage vor dem Entfernen (alert)
MailwerkTests/
├── ServerReconciliationTests.swift       # NEU – 16 Tests
└── MessageStoreFolderTests.swift         # + Postfach-Cache vollständig abräumen
```

Datenbank: keine Schemaänderung.

---

## Wie der Abgleich arbeitet

Statt für jede Mail die Flags zu holen, genügen vier kurze Suchen, die nur UID-Listen liefern: alle, ungelesen, gekennzeichnet, beantwortet. Dazu `$Forwarded`, das übersprungen wird, wenn der Server das Schlüsselwort ablehnt. Aus dem Vergleich mit dem Cache ergibt sich, was zu entfernen und welche Flags zu ändern sind. Alle Änderungen laufen in einer Transaktion; schlägt eine Suche fehl, wird nichts geändert.

Drei Schutzmaßnahmen:

- **Neu eingetroffene Mails** werden nie als gelöscht behandelt: UIDs oberhalb der höchsten vom Server gemeldeten UID bleiben unangetastet. IMAP vergibt UIDs aufsteigend.
- **Ein geleerter Ordner** leert auch den Cache – dort greift die Grenze bewusst nicht.
- **`$Forwarded`** bleibt unverändert, wenn der Server es nicht meldet, statt fälschlich gelöscht zu werden.

---

## Entscheidungen

| Entscheidung | Begründung |
|---|---|
| Der Server ist führend, Clients folgen | Mehrere Installationen (iPhone, iPad, Mac) dürfen sich nicht gegenseitig überschreiben |
| Beim Abruf nur Posteingang und Spam, andere Ordner beim Öffnen | Die Ladezeit wächst sonst mit der Zahl der Ordner |
| Vier UID-Suchen statt Flags je Mail | Datensparsam und unabhängig von der Ordnergröße |
| ESEARCH statt einfachem SEARCH | Fasst Bereiche zusammen („1:8780“); das einfache SEARCH scheitert ab etwa 1000 UIDs |
| Verschwundene Mails nur aus dem Cache entfernen, nicht in den Papierkorb umhängen | IMAP sagt nicht, wohin eine Mail ging, und im Zielordner hat sie eine neue UID. Im Papierkorb erscheint sie beim Öffnen – wie beim Verschieben in Mailwerk |
| Außerhalb des geladenen Zeitraums nur Kennzeichnungen korrigieren, nie löschen | Für diesen Bereich liegt keine vollständige UID-Liste vor. Lieber eine Mail zu viel im Cache als eine zu Unrecht gelöschte |
| Cache eines Postfachs löschen, wenn es entfernt wird | Ohne Postfach hat sein Cache keinen Zweck |
| Rückfrage vor dem Entfernen als Hinweisdialog (`alert`) | Ein `confirmationDialog` erscheint am Listeneintrag als Sprechblase und blendet „Abbrechen“ aus – für eine nicht umkehrbare Aktion zu wenig deutlich |

---

## Messergebnisse (manitu, 2026-09-30)

**Antwortgrenze:** NIOIMAP begrenzt eine Antwortzeile fest auf 8 KB, unabhängig vom Puffer der Verbindung (1 MB). Eine Suchantwort ist genau eine Zeile.

| Ordner | UIDs | ESEARCH | einfaches SEARCH |
|---|---|---|---|
| Junk | 69 … 992 | 160–240 ms | 220–350 ms |
| INBOX | 5954 | 238 ms | abgebrochen |
| INBOX | 8780 | 233 ms | abgebrochen |

Damit ist auch der Fund aus v0.1.7e erklärt. Ein solcher Fehler **reißt außerdem die Verbindung ab**: Der folgende LOGOUT scheiterte, was als „Fehler beim Abrufen“ sichtbar wurde. Die Messung steht deshalb auf `false` (`measuresFullFolderSearch`).

**Laufzeit des Abgleichs:** rund 1,1–1,3 s je Ordner, praktisch unabhängig von der Datenmenge (0 UIDs dauern wie 165). Bestimmend ist die Zahl der Anfragen: fünf Suchen zu je etwa 220 ms.

---

## Tests

Insgesamt 124 Tests ohne Warnungen, mit echtem SQLite. Neu: 16 Tests zur Vergleichslogik und einer zum vollständigen Abräumen eines Postfachs.

Manuell am iPhone geprüft: anderswo gelesen, anderswo gelöscht (erscheint im Papierkorb beim Öffnen), Kennzeichnung einer Mail von 2019 entfernt, Verhalten offline. Für das Entfernen eines Postfachs wurde ein Testpostfach angelegt, befüllt, entfernt und wieder eingerichtet – ohne Reste aus dem alten Cache. Rückfrage mit Abbrechen und Entfernen geprüft.

---

## Bekannte Einschränkungen und nächste Schritte

- Außerhalb des geladenen Zeitraums wird nicht gelöscht (siehe oben).
- Restrisiko: ESEARCH ist nur kompakt, solange die Treffer zusammenhängen. Eine weit verstreute Menge könnte die 8-KB-Grenze erreichen. Lösungsweg wäre, die Antwort in Teilbereiche zu zerlegen.
- **v0.1.8e:** Abgleich beschleunigen (eine Abfrage statt fünf, etwa 250 ms statt 1,2 s je Ordner) und auf den ganzen Ordner ausweiten – laut Messung mit ESEARCH machbar.
- **v0.1.9:** Code-Review mit Korrekturen, darunter die Frage, ob Rückfragen einheitlich gestaltet werden.
- **v0.1.10:** Kontextmenü für Mails per langem Drücken, inklusive Mehrfachauswahl.

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.8c.
