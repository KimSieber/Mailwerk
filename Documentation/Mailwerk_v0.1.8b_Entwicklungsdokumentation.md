# Mailwerk – Entwicklungsdokumentation v0.1.8b

2026-09-30 · Konsolidierung: Simulator online, breite HTML-Mails, dauerhafter Cache, Ordner offline

---

## Zusammenfassung

v0.1.8b ist eine Konsolidierungsrunde mit vier Punkten:

1. **Simulator online:** Der Simulator zeigte fälschlich „Offline“, dadurch fielen Abruf und Nachladen dort aus. Jetzt wird er richtig erkannt. Echte Geräte verhalten sich unverändert.
2. **Breite HTML-Mails:** Mails, die breiter als der Bildschirm sind, werden auf Bildschirmbreite verkleinert statt rechts abgeschnitten. Auslöser war der DHL-Einlieferungsbeleg.
3. **Dauerhafter Cache:** Mails werden nicht mehr nach Alter gelöscht. Nachgeladene ältere Mails bleiben dauerhaft im Cache, auch nach einem Neustart. Der Abruf holt zusätzlich **alle gekennzeichneten Mails** des Posteingangs, unabhängig vom Alter.
4. **Ordner offline:** Die Ordnerstruktur wird je Postfach gespeichert und ist damit offline verfügbar. Scheitert das Neuladen, bleibt der Baum stehen.

---

## Geänderte Dateien

```
Mailwerk/
├── MailwerkApp.swift                 # Zurücksetzen der Zeitfenster beim Start entfernt
├── Models/
│   ├── MailFolder.swift              # MailFolder, SpecialUse, FolderListing: Codable
│   └── SyncWindow.swift              # cleanupCutoff entfernt, Kommentare
├── Services/
│   ├── NetworkMonitor.swift          # Simulator-Regel, Diagnosezeile (DEBUG)
│   ├── MailFetchService.swift        # + Suche FLAGGED im Posteingang, Aufräumen entfernt
│   ├── MessageStore.swift            # + Tabelle folder_listing; resetWindows,
│   │                                 #   deleteMessagesOlderThan entfernt
│   ├── MailActionService.swift       # fetchFolderTree speichert die Ordnerliste
│   └── Folders/
│       ├── FolderCatalog.swift       # gespeicherter Baum zuerst, Baum bleibt bei Fehler
│       └── FolderTreeBuilder.swift   # + build(listing:configuredSpamFolder:)
├── ViewModels/InboxViewModel.swift   # Kommentar
└── Views/
    ├── HTMLMailView.swift            # Verkleinern auf Bildschirmbreite
    └── InboxView.swift               # Katalog mit gespeichertem Baum
MailwerkTests/
├── FolderCatalogTests.swift          # + 4 Tests gespeicherter Baum, 1 Test umgedreht
├── MessageStoreFolderTests.swift     # + Ordnerliste speichern/laden; Alters-Test entfernt
└── SyncWindowTests.swift             # + Neustart-Test; Tests für Entferntes gestrichen
```

Datenbank: neue Tabelle `folder_listing (accountID PK, json, savedAt)`. Sie wird automatisch angelegt, eine Migration ist nicht nötig.

---

## Entscheidungen

| Entscheidung | Begründung |
|---|---|
| Im Simulator gilt jeder verbundene Pfad als online (`#if targetEnvironment(simulator)`) | Der Simulator meldet nur einen Tunnel des Macs (`utun`, Typ „other“), nie WLAN. Watch und Bluetooth gibt es dort nicht |
| Die Regel „WLAN, Mobilfunk, Kabel“ bleibt auf echten Geräten | Auf dem iPhone mit VPN bestätigt: Beim Abschalten des WLAN bleibt der Pfad über `utun` verbunden. Nur die Regel erkennt dann „offline“ |
| Für watchOS braucht es eine eigene Bewertung | Die Watch geht legitim über das iPhone per Bluetooth ins Netz. Der Hinweis steht im Code |
| Breite Mails per CSS-`zoom` am body verkleinern | Die Seite wird tatsächlich so breit wie der Bildschirm. Wirkt allgemein, unabhängig von der Ursache der Überbreite |
| Kein Vollbild-Umweg zum Zoomen | Zu kompliziert. Zoomen wird ein eigenes späteres Thema |
| Nichts mehr nach Alter löschen (Entscheidung aus v0.1.7e revidiert) | Verlorene gekennzeichnete und nachgeladene Mails waren ärgerlich. Die App-Größe ist unkritisch |
| Alle gekennzeichneten Mails des Posteingangs abrufen | „Mit Kennzeichnung“ ist vollständig, auch für sehr alte Mails. Die Treffermenge ist klein |
| Rohe Ordnerliste speichern, nicht den fertigen Baum | Änderungen am Aufbau des Baums und an der Spam-Einstellung wirken sofort |
| Scheitert das Neuladen, bleibt der Baum ohne Hinweis stehen | Konsistent mit der Mail-Liste. Der Offline-Zustand steht bereits im Titel |

---

## Erkenntnisse

| Thema | Erkenntnis |
|---|---|
| Netzpfad im Simulator | `satisfied · utun4 (other)`. Netzwechsel zur Laufzeit meldet der Simulator nicht zuverlässig. Für einen Offline-Test: WLAN am Mac aus, dann die App neu starten |
| DHL-Mail | Die Sprachleiste ist ein Karussell nur aus CSS mit `display: table` und erzwingt so eine Mindestbreite von ~590 px. `max-width` hilft gegen die Mindestbreite von Tabellen nicht. Eingegrenzt durch Nachstellen und Ausblenden einzelner Elemente |
| Zoomen in Mails | Bisher ein Zufallseffekt: Nur Mails mit eigener Viewport-Angabe sind zoombar (Vermutung), Textmails nie. Als eigenes Thema vermerkt |
| Konsolenmeldungen von iOS | `PointerUI …` und `cannot add handler …` stammen vom System und sind folgenlos |

---

## Tests

Insgesamt laufen 105 Tests ohne Warnungen, mit echtem SQLite.

Manuell geprüft:
- Simulator online und offline (nach Neustart), iPhone unverändert, auch mit VPN.
- DHL-Mail vollständig. Andere HTML-Mails und Textmails unverändert.
- Alle gekennzeichneten Mails sofort vorhanden. Eine 2019 im Webmail gekennzeichnete Mail erscheint nach dem Abruf.
- Nachgeladene Mails überstehen einen Neustart.
- Ordner offline nach Neustart im Flugmodus. Neuladen offline behält den Baum. Anlegen und Löschen aktualisieren den gespeicherten Baum.

Nicht geprüft: ein neues Postfach ohne gespeicherte Liste im Offline-Zustand. Das folgt, sobald weitere Postfächer dazukommen.

---

## Bekannte Einschränkungen und nächste Schritte

- Für ältere Mails im Cache werden Gelesen- und Kennzeichnungsstatus vom Server nicht abgeglichen. Ausnahme sind gekennzeichnete Mails des Posteingangs. Anderswo gelöschte oder verschobene Mails bleiben im Cache → **v0.1.8d Server-Abgleich**.
- Gespeicherte Ordnerliste und Mails eines gelöschten Postfachs bleiben im Cache → **v0.1.8d**.
- Zoomen in Mails → eigenes Thema, z. B. zusammen mit der Detailansicht für iPad und Mac.
- Nächster Schritt: **v0.1.8c Verschieben-Dialog mit Ordnerbaum**.

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.8a.
