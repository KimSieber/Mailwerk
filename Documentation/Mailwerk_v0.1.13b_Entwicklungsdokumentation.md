# Mailwerk – Entwicklungsdokumentation v0.1.13b

2026-10-13 · Abruf je Postfach ein-/ausschalten (nur dieses Gerät)

---

## Zusammenfassung

v0.1.13b ist das zweite Paket von v0.1.13. Es kam als Zwischenruf während der Signaturen hinzu und wurde als eigenes Paket mit eigenem Test- und Commit-Punkt umgesetzt, weil es den Abruf betrifft.

**Problem (Kim):** Einige Postfächer werden gerade nicht genutzt, sind nur zum Testen angelegt oder funktionieren (noch) nicht – etwa das Posteo-Postfach für den geschäftlichen Krisenfall. Beim Abruf über „Alle Eingänge“ kosten sie Zeit und unterbrechen mit Fehlermeldungen die Arbeit.

**Lösung:** Je Postfach ein Schalter „Abruf“, standardmäßig an. Ausgeschaltet wird das Postfach nicht mehr über „Alle Eingänge“ abgerufen; Postfach und Mails bleiben erhalten. Öffnet man einen seiner Ordner, wird er trotzdem abgerufen – so lässt sich ein Postfach gezielt abrufen, aber nicht automatisch.

**Entschieden (Kim):**
1. Mails eines ausgeschalteten Postfachs werden in „Alle Eingänge“ (und in „Mit Kennzeichnung“) **ausgeblendet** – sonst stünden veraltete Mails zwischen aktuellen, und „Aktualisiert: …“ stimmte für sie nicht.
2. Auch die übrigen automatischen Abrufe entfallen: Spam-Ordner beim Start, Abruf bei zurückkehrender Verbindung, Neuladen der Ordnerliste. Die Ordnerliste bleibt aus dem Cache sichtbar.
3. Beim Öffnen des **Posteingangs** eines ausgeschalteten Postfachs läuft der Abruf wie in der Runde: Spamfilter, Posteingang, Spam-Ordner. Andere Ordner werden wie bei jedem Postfach einzeln abgerufen.
4. **Senden** bleibt möglich.
5. **Je Gerät:** Der Schalter wird nicht über iCloud abgeglichen – ein Postfach kann z. B. nur am Mac abgerufen werden.
6. **Kennzeichen:** orangefarbener Kreis mit weißem Pause-Zeichen vor dem Postfachnamen (Postfachliste und Seitenleiste). Ein erstes, graues Umriss-Symbol war schlecht erkennbar und wurde nach Kims Vorlage ersetzt.
7. **Schalter** in der Postfachliste je Zeile und in „Postfach bearbeiten“ (Abschnitt „Abruf“); beide wirken sofort.

Tests: 519 → **523**, alle grün.

---

## Umsetzung

- **`FetchSelection` (neu, ohne Oberfläche):** Regeln – welche Postfächer an Runde und Sammelsichten teilnehmen (Reihenfolge bleibt), wann das Öffnen eines Ordners den vollen Abruf auslöst (`folderRefresh`: nur Posteingang eines ausgeschalteten Postfachs), Speicherform der ausgeschalteten Postfächer (sortierte Textliste, Ungültiges wird beim Lesen übergangen).
- **`AccountStore`:** `pausedAccountIDs` in den lokalen Einstellungen (`UserDefaults`, Schlüssel `mailwerk.fetchPausedAccounts`), `isFetchEnabled`, `setFetchEnabled`, `fetchingAccounts`. Beim Entfernen eines Postfachs fällt sein Eintrag weg. Für Tests lassen sich eigene Einstellungen übergeben.
- **`InboxViewModel`:**
  - Runde (`performRefresh`) nur über `fetchingAccounts`; das Protokoll nennt die Zahl der ausgeschalteten Postfächer.
  - Sammelsichten, Kennzeichen-Zähler, Stand („Aktualisiert“) und „Ältere Nachrichten laden“ nur mit eingeschalteten Postfächern.
  - `performRefreshFolder`: beim Posteingang eines ausgeschalteten Postfachs `refreshAccount` (Spamfilter, Posteingang, Spam-Ordner), sonst wie bisher nur der Ordner.
- **`FolderCatalog`:** `loadIfNeeded` und `reload` laden ausgeschaltete Postfächer nicht vom Server; ihr gespeicherter Baum erscheint trotzdem.
- **`InboxView`:** Öffnen eines Ordners eines ausgeschalteten Postfachs lädt auch dessen Ordnerliste (`retry`). Umschalten baut die Sammelsichten sofort neu auf; wird ein Postfach wieder eingeschaltet, folgt gleich ein Abruf.
- **`AccountListView`:** Schalter „Abruf“ je Zeile (Knopf randlos, damit Zeilen-Tipp und Schalter getrennt reagieren), Kennzeichen vor dem Namen.
- **`EditAccountView`:** Abschnitt „Abruf“ mit Schalter und Erklärung („Gilt nur auf diesem Gerät …“).
- **`FolderSidebarView`:** Kennzeichen zwischen Farbpunkt und Name.
- **`FetchPausedBadge` (neu):** gemeinsames Kennzeichen (`pause.circle.fill`, Palette Weiß/Orange).

---

## Geänderte Dateien

```
Mailwerk/
├── Services/
│   ├── AccountStore.swift            # Abruf-Schalter je Gerät, fetchingAccounts
│   ├── Folders/FolderCatalog.swift   # ausgeschaltete Postfächer nur aus dem Cache
│   └── Sync/FetchSelection.swift     # neu
├── ViewModels/
│   └── InboxViewModel.swift          # Runde, Sammelsichten, Posteingang öffnen
└── Views/
    ├── AccountListView.swift         # Schalter je Zeile, Kennzeichen
    ├── EditAccountView.swift         # Abschnitt „Abruf“
    ├── FetchPausedBadge.swift        # neu
    ├── Folders/FolderSidebarView.swift # Kennzeichen, Ordnerliste
    └── InboxView.swift               # Ordnerliste beim Öffnen, Neuaufbau beim Umschalten
Mailwerk.xcodeproj/project.pbxproj    # Version 0.1.13 (Kim; vorher „0.1.13a“, das Apple nicht annimmt)
MailwerkTests/
├── AccountFetchSettingsTests.swift   # neu, 1 Test
└── FetchSelectionTests.swift         # neu, 3 Tests
```

---

## Testverfahren

**Automatisch:** 523 Tests (Simulator), alle grün; die Regeln (`FetchSelection`) zusätzlich unter Linux.

**Manuell (Simulator, iPhone):**
- Ausschalten: Mails des Postfachs verschwinden aus „Alle Eingänge“; Einschalten: Abruf, Mails sind wieder da.
- Pull-to-Refresh: Protokoll „Refresh gestartet für … Konten (1 ausgeschaltet)“, kein „Starte Abruf“ für das ausgeschaltete Postfach, keine Fehlermeldung mehr von ihm.
- Posteingang des ausgeschalteten Postfachs öffnen: wird abgerufen.
- Kennzeichen in Postfachliste und Seitenleiste gut erkennbar (hell und dunkel).
- Anderes Gerät: dasselbe Postfach bleibt eingeschaltet und wird normal abgerufen.

---

## Beobachtungen

- Die Versionsangabe „0.1.13a“ aus dem Commit v0.1.13a ist korrigiert: `MARKETING_VERSION` muss aus Zahlen mit Punkten bestehen (sonst Ablehnung bei TestFlight/App Store); der Buchstabe steht nur im Commit-Text.
- Beim Öffnen eines einzelnen Ordners läuft bei eingeschalteten Postfächern weiterhin kein Spamfilter (unverändert, bewusst).

## Nächste Schritte

- **v0.1.13c – Entwürfe (MW-16):** „Entwurf speichern“ beim Schließen, Entwurf weiterbearbeiten (nutzt den HTML-Rückweg aus v0.1.13a), Beantwortet-Kennzeichen für gesendete Antwort-Entwürfe. Inhalt zuerst mit Kim abstimmen.
