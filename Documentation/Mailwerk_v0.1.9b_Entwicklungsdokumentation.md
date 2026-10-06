# Mailwerk – Entwicklungsdokumentation v0.1.9b

2026-10-06 · Robuster Store und Sync-Zustand je Ordner (Code-Review Teil 2)

---

## Zusammenfassung

v0.1.9b macht die lokale Ablage robust und schließt die Lücke aus a1b sauber:

- **b1+b2:** Schreibvorgänge werden geprüft und laufen in echten Transaktionen mit Rollback; Mail und Anhänge werden gemeinsam gespeichert; WAL-Modus; Schema-Version über `PRAGMA user_version` (Review-Befunde H1, H4, M8).
- **b3:** Sync-Zustand je Ordner (UIDVALIDITY und UIDNEXT). Mails, die außerhalb von Mailwerk in einen Ordner kommen, erscheinen unabhängig von ihrem Datum; bei geänderter UIDVALIDITY wird der Ordner-Cache neu aufgebaut (Review-Befund H2). Die Kopfdaten-Abfrage ist paketiert.
- **b4:** Kein Absturz mehr beim Öffnen der Datenbank. Eine beschädigte Datei wird gelöscht und neu angelegt, mit Meldung. Die Ablage liegt in einem vom Backup ausgeschlossenen Ordner.
- **Mac:** Sandbox-Freigaben für Drucken, Sichern als PDF und Kontakte ergänzt; Absturz beim Mac-Druck behoben.

---

## b1+b2 – Schreibsicherheit

**Problem:** Das Ergebnis von `sqlite3_step` wurde nirgends geprüft. Transaktionen wurden auch nach einem Fehler committet, und `relocateMessage` hatte kein Rollback. Beim Abruf wurde die Mail vor den Anhängen gespeichert; brach ein Anhang-Download ab, blieb die Mail ohne Anhänge im Cache.

**Lösung:**
- Alle Schreibzugriffe laufen über `execute(_:context:bind:)`, das bei jedem Ergebnis außer `SQLITE_DONE` einen `StoreError` wirft.
- `transaction { … }` committet nur bei vollständigem Erfolg, sonst `ROLLBACK`. Das gilt für Abgleich, Verschieben, Löschen von Ordner und Postfach, Migration und das Speichern von Mail mit Anhängen.
- Die öffentliche Schnittstelle wirft nicht; Fehler werden protokolliert (`🗄️ Schreiben fehlgeschlagen …`). Aufrufer mussten nicht angepasst werden.
- Neu: `saveMessageWithAttachments(…)` (gibt Erfolg als `Bool` zurück). Entfallen: das ungenutzte `saveMessages`.
- Ist ein einzelner Anhang nicht ladbar, wird nur sein Eintrag ohne Daten gespeichert. Die Mail bleibt sichtbar, der Anhang lässt sich per Antippen nachladen.
- WAL-Modus; Schema-Version über `PRAGMA user_version` mit Migrationsstufen.
- Fremdschlüssel werden per `defer` sicher wieder eingeschaltet.

Alle SQL-Befehle sind inhaltlich unverändert (geprüft); neu sind nur die PRAGMAs.

---

## b3 – Sync-Zustand je Ordner

Grundlage ist das Konzept `Mailwerk_Konzept_Sync-Zustand_je_Ordner.md` (freigegeben).

**Prinzip (nach RFC 4549):** UIDs werden in der Reihenfolge des Ankommens im Ordner vergeben, nicht nach Datum. Alles, was seit dem letzten Abruf angekommen ist, hat eine UID ≥ dem damals gespeicherten UIDNEXT. UIDVALIDITY zeigt, ob die UIDs eines Ordners noch gültig sind.

**Ablauf je Abruf:**
1. SELECT liefert UIDVALIDITY und UIDNEXT; der `SyncStatePlanner` entscheidet:
   - kein Zustand → erster Abruf (nur Zustand anlegen),
   - UIDVALIDITY geändert → Ordner-Cache verwerfen, neu aufbauen,
   - sonst → zusätzlich Neuankünfte laden.
2. Datumssuche (30 Tage) wie bisher.
3. Abgleich wie bisher; er liefert jetzt die UIDs des Ordners zurück.
4. Neuankünfte aus diesen UIDs ermitteln (keine zusätzliche Server-Abfrage), höchstens **200** je Abruf und Ordner. Die Grenze gilt nur für Mails, die die Datumssuche nicht findet; der Rest folgt bei den nächsten Abrufen.
5. Zustand speichern – erst nach vollständigem Erfolg.

**Paketierung:** Die Kopfdaten werden in Paketen zu **100** Mails abgefragt. Das sichert auch Erstabruf und „Ältere laden" gegen Timeouts bei sehr vollen Zeiträumen.

**Datenbank:** Schema-Stufe 2, Spalten `uidValidity` und `uidNext` in `folder_sync`.

**Einmaliges Übergangsverhalten:** Mails, die vor dem Update auf b3 in einen bereits geladenen Zeitraum kopiert wurden, werden nicht nachgeladen; der erste Abruf legt den Zustand nur an. Das betrifft nur Testinstallationen; echte Installationen beginnen frisch. Bewusst keine Sonderlösung.

---

## b4 – Öffnen ohne Absturz, Backup-Ausschluss

**Problem:** Beim Öffnen der Datenbank führte jeder Fehler zu `fatalError`. Der Cache (rund 12.000 Mails samt Anhängen) landete im iCloud-Geräte-Backup, obwohl er jederzeit vom Server neu geladen werden kann.

**Lösung:**
- Nach dem Öffnen prüft ein erster Lesezugriff die Datei (SQLite öffnet auch defekte Dateien zunächst ohne Fehler).
- **Beschädigt** (`SQLITE_CORRUPT`, `SQLITE_NOTADB`): Datenbank samt `-wal` und `-shm` endgültig löschen, neu anlegen, Meldung „Lokaler Mail-Speicher neu angelegt".
- **Anderer Fehler** (z. B. Speicher voll): nichts löschen, in dieser Sitzung im Arbeitsspeicher arbeiten, Meldung „Lokaler Mail-Speicher nicht verfügbar".
- Die Meldung zeigt `MailwerkApp` einmal beim Start.
- **Neuer Speicherort:** Unterordner `Cache` im Application-Support-Verzeichnis (Mac: im Container der App), als Ganzes vom Backup ausgeschlossen. Der bisherige Cache wurde nicht übernommen; die alte Datei bleibt auf Testinstallationen liegen, bis die App gelöscht wird.

---

## Mac: Sandbox-Freigaben und Druck

Beim Regressionslauf auf dem Mac fielen fehlende Sandbox-Freigaben auf. Sie standen seit Anlage des Projekts unverändert und wurden nie mit den später hinzugekommenen Funktionen abgeglichen. Unter iOS gibt es diese Einschränkungen nicht.

| Freigabe | Stand | Gebraucht für |
|---|---|---|
| Outgoing Connections | an | IMAP, SMTP |
| Incoming Connections | aus | – |
| Printing | **neu an** | Drucken |
| User Selected File | **neu Read/Write** (vorher Read Only) | PDF sichern, Anhang sichern, Filterlisten-Export |
| Contacts | **neu an** | Adressvorschläge beim Verfassen |
| Kamera, Mikrofon, Ort, Kalender, Bluetooth, USB | aus | – |

**Regel:** Neue Funktionen werden gegen diese Tabelle geprüft und auch auf dem Mac getestet.

**Druckcode (`MailPrinter`, nur Mac-Teil):** Die Größe der Druckansicht wird vor dem Seitenumbruch gesetzt (sonst Abbruch in `WKPrintingView`), die Seite wird eingerichtet (Breite an die Seite anpassen, 1,25 cm Rand), und aufgeräumt wird erst nach dem Schließen des Druckdialogs. Dieser Code lief bisher nie, weil die Sandbox den Druck vorher abgelehnt hatte.

---

## Geänderte Dateien

```
Mailwerk/
├── MailwerkApp.swift                       # Starthinweis des Mail-Speichers (b4)
├── Services/
│   ├── MailFetchService.swift              # atomares Speichern (b2), Sync-Zustand, Paketierung (b3)
│   ├── MessageStore.swift                  # Transaktionen, WAL, user_version (b1/b2),
│   │                                       # Stufe 2 + Zustand (b3), Wiederherstellung, Speicherort (b4)
│   └── Sync/
│       └── SyncStatePlanner.swift          # neu: Entscheidung und Neuankünfte (b3)
└── Views/
    └── MailPrinter.swift                   # Mac-Druck
Mailwerk.xcodeproj/project.pbxproj          # Sandbox: Printing, User Selected File R/W, Contacts
MailwerkTests/
├── MessageStoreTransactionTests.swift      # neu, 6 Tests (b1/b2)
├── MessageStoreSyncTests.swift             # erweitert, +7 Tests (b3)
├── SyncStatePlannerTests.swift             # neu, 15 Tests (b3)
└── MessageStoreRecoveryTests.swift         # neu, 7 Tests (b4)
Documentation/
├── Mailwerk_Konzept_Sync-Zustand_je_Ordner.md   # neu
├── Mailwerk_v0.1.9a_Entwicklungsdokumentation.md # Testanzahl korrigiert
└── Mailwerk_v0.1.9b_Entwicklungsdokumentation.md # neu
```

Alle geänderten Code-Dateien folgen dem Dokumentationsstandard aus v0.1.9a.

---

## Testverfahren

**Automatisch:** alle Tests grün. Zählung: 302 (v0.1.9a) + 6 (b1/b2, von Xcode mit 308 bestätigt) + 22 (b3) + 7 (b4) = **337**.

**Manuell (Mac, Simulator, nur Testmails bzw. Ordner „Test Mailwerk"):**

| Bereich | Ergebnis |
|---|---|
| Abruf aller drei Postfächer inkl. des größten, frische Installation | ohne Timeout |
| Alt datierte Mail in „Test Mailwerk" kopiert | erscheint (`🆕 Neuankünfte: 1 geladen`) |
| Kopierte Mail und danach neue Mail im selben Ordner | beide erscheinen |
| Verschieben in Mailwerk | Mail erscheint genau einmal |
| Neuer Speicherort, Neustart | Ablage in `…/Application Support/Cache`, Daten bleiben erhalten |
| Regressionslauf (Senden, Antworten, Weiterleiten, Anhänge, Verschieben, Löschen, Spam, Ordner anlegen/löschen, Passwort) | in Ordnung |
| Druck und „Als PDF sichern" auf dem Mac | in Ordnung nach Sandbox-Freigaben und Druckkorrektur |
| Kontaktvorschläge auf dem Mac | in Ordnung nach Freigabe |

Defekte Datenbank, UIDVALIDITY-Wechsel und mehr als 200 Neuankünfte sind am echten Server nicht sinnvoll auszulösen; sie sind durch Unit-Tests abgedeckt.

---

## Beobachtungen (nicht durch v0.1.9b verursacht)

- **Löschen per Menü:** Beim ersten Versuch wurde das Löschen nicht ausgeführt; im Log stand ein Hinweis auf ein bereits geschlossenes Kontextmenü. Vermutlich wird die Rückfrage geöffnet, während sich das Menü noch schließt. Nicht reproduziert. → in **d2** (Rückfragen vereinheitlichen) aufgenommen.
- **Simulator-Tastatur:** Nach einem Zeichen keine weitere Eingabe, auch in Safari. Ursache im Simulator (Device Hub); nach Neustart behoben.
- **Konsolenmeldungen:** WebKit-, Simulator- und CloudKit-Meldungen (z. B. „Could not resolve UID for user mobile", Hintergrundaufträge des Filterlisten-Abgleichs) stammen nicht von Mailwerk und sind harmlos.

---

## Abhängigkeiten / Xcode-Konfiguration

- SwiftMail unverändert (≥ 1.13.0).
- Sandbox-Freigaben siehe oben.
- Datenbank: Schema-Stufe 2, neuer Speicherort `Cache`.

---

## Nächste Schritte

- **v0.1.9c – Performance:** Listenmodell ohne Bodies, Preview-Spalte, Index; Zähler speichern; HTML nur bei Änderung neu laden; Laufzeitmessung; große Mails nur mit Struktur und Text-Parts laden.
- **v0.1.9d – Struktur und Aufräumen:** gemeinsamer Zugang zu Zugangsdaten und Verbindung; `refresh()` zerlegen; Aktionen ins ViewModel, einheitlicher Fehlerkanal und **einheitliche Rückfragen** (inkl. Beobachtung „Löschen per Menü"); `os.Logger`; toter Code.
- **v0.1.9e – Inline-Dokumentation** der übrigen Dateien.
