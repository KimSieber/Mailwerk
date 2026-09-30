# Mailwerk – Entwicklungsdokumentation v0.1.7b

2026-09-28 · Kennzeichen-Sicht

---

## Zusammenfassung

Version 0.1.7b führt das **Auswahlmodell** ein und nutzt es für die erste alternative Ansicht: „Mit Kennzeichnung" zeigt alle gekennzeichneten Nachrichten aus den Posteingängen. Die Auswahl erfolgt über die Seitenleiste aus v0.1.7a.

`MailboxSelection` ist ein Enum mit zwei Fällen: `.allInboxes` (bisheriges Verhalten) und `.flagged`. Das Modell steuert Titel, Symbol und Cache-Abfrage. In v0.1.7c kommt `.folder(accountID:path:)` für einzelne Ordner dazu.

Entflaggen in der Kennzeichen-Sicht zeigt einen „Rückgängig"-Hinweis am unteren Rand. Der Hinweis verschwindet nach 5 Sekunden oder auf Tipp; „Rückgängig" setzt das Kennzeichen auf dem Server und im Cache wieder. In „Alle Eingänge" verhält sich Entflaggen wie bisher.

---

## Projektstruktur (Änderungen gegenüber v0.1.7a)

```
Mailwerk/
├── Models/
│   └── MailboxSelection.swift        # NEU – .allInboxes | .flagged, Titel, Symbol
├── ViewModels/
│   └── InboxViewModel.swift          # + selection, undoUnflag, flaggedCount
├── Services/
│   └── MessageStore.swift            # + flaggedInboxMessages, flaggedInboxCount
├── Views/
│   ├── InboxView.swift               # + dynamischer Titel, Rückgängig-Banner, Auswahl-Anbindung
│   └── Folders/
│       └── FolderSidebarView.swift   # + Kennzeichen-Zeile mit Zähler, Auswahl-Binding
```

---

## Getroffene Entscheidungen (v0.1.7b)

| Entscheidung | Begründung |
|---|---|
| Nur Mails aus INBOX, nicht aus anderen Ordnern | Gekennzeichnete Mails in Spam oder Papierkorb sind keine aktiven Merker; andere Ordner werden noch nicht synchronisiert |
| „Rückgängig"-Hinweis statt stiller Verzögerung | Mail verschwindet sofort (reaktionsschnell), Aktion ist trotzdem korrigierbar; Apples Muster bei Löschen/Archivieren |
| 5 Sekunden Timeout | Lang genug zum Reagieren, kurz genug zum Nicht-Stören; bei schnellem Mehrfach-Entflaggen ersetzt jeder neue Hinweis den vorigen |
| Zähler als Badge in der Leiste | Gibt auf einen Blick die Anzahl; kein eigener Abruf nötig, kommt aus dem Cache |
| `MailboxSelection` als Enum statt String | Typsicher, erweiterbar, Titel und Symbol direkt am Wert |

---

## Tests

Keine neuen Unit-Tests in dieser Version. Die Logik liegt in `MessageStore` (SQL-Abfragen) und `InboxViewModel` (Zustandswechsel), beides wird über die bestehenden Integrationstests und manuell abgedeckt. Bestehende Tests bleiben unverändert grün.

Manuell geprüft: Ansichtswechsel, Entflaggen mit Rückgängig, Timeout, Pull-to-Refresh in beiden Ansichten, leere Kennzeichen-Sicht, Zähler-Aktualisierung.

---

## Noch nicht implementiert (geplant für v0.1.7c ff.)

- Ordnerinhalte laden und anzeigen (`.folder(accountID:path:)`)
- Spam- und Gesendet-Ordner automatisch abrufen (TD-14, TD-S1)
- Ungelesen-Zähler in der Leiste
- Offline-Speicherung der Ordnerliste
- Ordnerbaum im Verschieben-Dialog
- Ordner anlegen und löschen (TD-10)

---

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.7a.
