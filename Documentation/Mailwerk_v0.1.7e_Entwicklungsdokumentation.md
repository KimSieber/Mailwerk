# Mailwerk – Entwicklungsdokumentation v0.1.7e

2026-09-30 · Ältere Mails nachladen, Links in Mails, Keychain-Fehler

---

## Zusammenfassung

Version 0.1.7e schließt v0.1.7 ab. Am Ende jeder Liste („Alle Eingänge" und jeder Ordner) steht jetzt die Zeile **„Ältere Nachrichten laden · bis …"**. Ein bewusster Tipp lädt den nächsten 30-Tage-Zeitraum nach. Leere Zeiträume werden übersprungen. Gibt es auf dem Server nichts Älteres, steht dort „Keine älteren Nachrichten". Nachgeladene Mails bleiben **bis zum nächsten App-Start**, danach gilt wieder das 30-Tage-Fenster.

**Links in HTML-Mails** sind wieder antippbar. `http`, `https` und `tel` öffnen extern, `mailto:` öffnet eine neue Mail in Mailwerk. Skripte aus Mails werden nicht mehr ausgeführt. **Keychain-Lesefehler** werden gemeldet statt still verschluckt.

---

## Projektstruktur (Änderungen gegenüber v0.1.7d)

```
Mailwerk/
├── MailwerkApp.swift                 # Zurücksetzen der Fenster beim App-Start
├── Models/
│   └── SyncWindow.swift              # NEU – Zeitfenster: Standardbeginn, nächster Zeitraum, Aufräumgrenze
├── Services/
│   ├── MailLink.swift                # NEU – Link-Einordnung, mailto-Zerlegung (RFC 6068)
│   ├── MailFetchService.swift        # fetchOlder, hasMessages (abschnittsweise), cacheMessages ausgelagert
│   ├── MessageStore.swift            # Tabelle folder_window, windowStart/setWindowStart/resetWindows
│   └── NetworkMonitor.swift          # online nur über WLAN/Mobilfunk/Kabel
├── ViewModels/
│   ├── InboxViewModel.swift          # loadOlder, Nachlade-Zustand, readPassword
│   └── ComposeViewModel.swift        # Vorbelegung aus mailto
├── Views/
│   ├── InboxView.swift               # Zeile „Ältere Nachrichten laden" (Liste und Leeransicht)
│   ├── HTMLMailView.swift            # Interaktion an, Linkbehandlung, JavaScript aus
│   ├── MessageDetailView.swift       # mailto → neue Mail
│   ├── ComposeView.swift             # Parameter mailto
│   └── EditAccountView.swift         # Keychain-Fehler beim Verbindungstest
MailwerkTests/
├── SyncWindowTests.swift             # NEU
└── MailLinkTests.swift               # NEU
```

Datenbank: neue Tabelle `folder_window (accountID, folder, windowStart)`. Sie wird automatisch angelegt und enthält nur Zeilen, solange nachgeladen wurde.

---

## Getroffene Entscheidungen (v0.1.7e)

| Entscheidung | Begründung |
|---|---|
| Nachladen nur per Button, nicht beim Scrollen | Bewusste Aktion; kein ungewollter Datenverbrauch über Mobilfunk |
| Nachgeladenes bis zum App-Start, dann Standardfenster | Speicher bleibt schlank; Neustart beginnt aufgeräumt |
| Zurücksetzen in `MailwerkApp.init` | Läuft genau einmal pro Start; View-Initialisierer laufen mehrfach |
| Fensterbeginn auf Tagesanfang | IMAP sucht tagesgenau, das Aufräumen vergleicht sekundengenau |
| „Gibt es Älteres?" abschnittsweise über Sequenznummern (1000 je Suche) | SEARCH über den ganzen Ordner sprengt den Antwortpuffer; die Ablagereihenfolge ist nach IMAPSYNC kein Datumsindikator |
| Nachladen nicht in „Mit Kennzeichnung" | Sammelansicht aus den Posteingängen; laden dort ergibt keinen eigenen Sinn |
| Normaler Refresh gleicht nur die letzten 30 Tage ab | Nachgeladenes bekommt keine Flag-Änderungen vom Server; löst der Cache-Abgleich in v0.1.8 |
| `mailto:` öffnet Mailwerk, nicht Apple Mail | Postfächer sollen ausschließlich über Mailwerk bedient werden |
| JavaScript in Mails aus | Sicherheit, wie Apple Mail; die Höhenmessung der App ist nicht betroffen |
| Online nur über WLAN/Mobilfunk/Kabel | Im Flugmodus meldet die Watch-Bluetooth-Verbindung sonst einen Netzpfad |

---

## Behobene Fehler im Verlauf

| Fehler | Ursache | Lösung |
|---|---|---|
| `PayloadTooLargeError` beim Nachladen großer Postfächer | SEARCH BEFORE über den ganzen Ordner lieferte eine riesige Antwortzeile | Abschnittsweise Suche über Sequenznummern, frühes Ende beim ersten Treffer |
| „Keine älteren Nachrichten", obwohl Jahre vorhanden | Nachricht Nr. 1 als älteste angenommen; nach IMAPSYNC stammt sie aus dem August 2026 | Prüfung unabhängig von der Reihenfolge (siehe oben) |
| Nachladen im Flugmodus nicht gesperrt | Watch-Bluetooth wird als Netzpfad gemeldet | Nur Internet-Schnittstellen zählen; Verbindungsfehler zusätzlich an der Zeile angezeigt |
| Links nicht antippbar | WebView-Interaktion in v0.1.7c abgeschaltet – half dem Menü nachweislich nicht | Interaktion wieder an, Navigation gezielt gesteuert |

---

## Tests

| Testdatei | Tests | Inhalt |
|---|---|---|
| `SyncWindowTests.swift` | 10 | Standardbeginn, Zeiträume ohne Lücke, Aufräumgrenze, Fenster speichern/zurücksetzen |
| `MailLinkTests.swift` | 14 | Einordnung der Schemata, mailto mit allen Feldern, Kodierung, `+`-Adressen |

Manuell am iPhone geprüft: Nachladen im großen Posteingang, in „Alle Eingänge", in kleinen und leeren Ordnern bis zum Ende, Flugmodus an/aus, App-Neustart, Swipe-Aktionen an nachgeladenen Mails, Links und mailto.

---

## Bekannte Einschränkungen

- Nachgeladene Mails erhalten keine Flag-Änderungen vom Server (Abgleich nur für 30 Tage).
- Das Aktionsmenü ist bei einzelnen Mails knapp abgeschnitten. Das wird beobachtet.

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.7d.
