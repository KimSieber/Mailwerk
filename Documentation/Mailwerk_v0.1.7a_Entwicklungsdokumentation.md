# Mailwerk – Entwicklungsdokumentation v0.1.7a

2026-09-28 · Ordnerstruktur anzeigen

---

## Zusammenfassung

Version 0.1.7a bringt die **Ordnerleiste**: Ein Button oben links schiebt eine Seitenleiste von links über die Mail-Liste. Oben steht „Alle Eingänge" (schließt die Leiste), darunter folgen die Postfächer mit ihrem jeweiligen Ordnerbaum. Ordner sind in dieser Version noch nicht auswählbar – nur die Struktur wird gelesen und angezeigt.

Die Ordner werden beim ersten Öffnen der Leiste per IMAP LIST abgerufen (alle Postfächer parallel) und für die App-Sitzung im Speicher gehalten. Pull-to-Refresh lädt sie neu. Sonderordner (Posteingang, Gesendet, Entwürfe, Spam, Papierkorb, Archiv) werden über SPECIAL-USE und gebräuchliche Namen erkannt, mit einheitlichen deutschen Anzeigenamen versehen und in fester Reihenfolge vor den übrigen Ordnern sortiert. Unterordner sind immer sichtbar und durch Einrückung erkennbar. Reine Container (`\Noselect`) erscheinen abgeschwächt.

`MailFolder` wurde aus `MailActionService.swift` in eine eigene Datei ausgelagert und um `isSelectable` erweitert. Der bestehende Verschieben-Dialog ist unverändert.

---

## Projektstruktur (Änderungen gegenüber v0.1.6)

```
Mailwerk/
├── Models/
│   ├── MailFolder.swift              # NEU – ausgelagert, + isSelectable, + FolderListing
│   └── FolderNode.swift              # NEU – Baumknoten, Rollen, Anzeigenamen, Symbole
├── Services/
│   ├── MailActionService.swift       # MailFolder entfernt, + fetchFolderTree/fetchFolderListing, + isSelectable/includeInbox
│   └── Folders/                      # NEU – Ordner-Untergruppe
│       ├── FolderTreeBuilder.swift   # NEU – Baum aus flacher Liste, Namespace, Rollen, Kollisionen
│       └── FolderCatalog.swift       # NEU – Lade-/Fehlerzustand je Postfach
├── Views/
│   ├── InboxView.swift               # + Ordner-Button, Titel „Alle Eingänge", SideDrawer
│   └── Folders/                      # NEU
│       ├── SideDrawer.swift          # NEU – Einfahrleiste mit Abdunklung
│       └── FolderSidebarView.swift   # NEU – Ordnerbaum je Postfach
```

---

## Getroffene Entscheidungen (v0.1.7a)

| Entscheidung | Begründung |
|---|---|
| Fokus iPhone; Mac/iPad-Leiste später | Eine Einfahrleiste genügt für den Einstieg; `NavigationSplitView`-Umbau würde den Rahmen sprengen |
| Namespace-Präfix entfernen (NAMESPACE-Auskunft) | Server legt Ordner unter „INBOX." ab; ohne Entfernung stünden alle als Unterordner des Posteingangs |
| Rollen: SPECIAL-USE → SpamFolderResolver → Namen | Dreistufig, damit Anzeige und Spamfilter denselben Ordner als Spam erkennen |
| Einheitliche deutsche Anzeigenamen je Rolle | Drafts → Entwürfe, Sent → Gesendet, Junk → Spam, Trash → Papierkorb; „Spam" wie im Spamfilter |
| Bei Namensgleichheit beide Servernamen behalten | Verhindert zwei identische Einträge in der Liste |
| Unterordner immer sichtbar, nur Postfächer aufklappbar | Einfacher als verschachtelte Disclosure Groups; Hierarchie durch Einrückung erkennbar |
| Aufklappzustand nur bis App-Neustart | Neustart beginnt bei „Alle Eingänge" mit eingeklappten Ordnern – wirkt aufgeräumt |
| Ordner nur im Speicher, kein Cache | Offline-Speicherung folgt mit 7b, sobald Ordner auswählbar sind |
| `Loader` als `@MainActor`-Closure | Swift-6.2-Compiler-Fehler: ohne feste Isolation kamen Parameter unter Approachable Concurrency beschädigt an |

---

## Tests

| Testdatei | Tests | Inhalt |
|---|---|---|
| `FolderTreeBuilderTests.swift` | 28 | Namespace, Ebenen, Rollen, Sortierung, Namensgleichheit, Anzeigenamen |
| `FolderCatalogTests.swift` | 11 | Zustände, Fehler, Neuladen, Abbruch, Bereinigung |
| `FolderNodeTests.swift` | 4 | Eingerückte Liste, Starttiefe, Rollensymbole |

---

## Noch nicht implementiert (geplant für v0.1.7b ff.)

- Ordner auswählen und deren Mails anzeigen (TD-14, TD-S1)
- Spam- und Gesendet-Ordner automatisch abrufen
- Ungelesen-Zähler in der Leiste
- Offline-Speicherung der Ordnerliste
- Ordnerbaum im Verschieben-Dialog
- Ordner anlegen und löschen (TD-10)
- Feste Seitenleiste für Mac und iPad im Querformat

---

## Abhängigkeiten

Unverändert gegenüber v0.1.5/v0.1.6.

## Xcode-Konfiguration

Unverändert; `MARKETING_VERSION` wird auf `0.1.7` gesetzt.
