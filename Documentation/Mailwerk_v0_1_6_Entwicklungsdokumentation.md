# Mailwerk – Entwicklungsdokumentation v0.1.6

2026-09-27 · Fehlerbehebung iCloud-Abgleich der Filterlisten

---

## Zusammenfassung

Version 0.1.6 war als Ordnerverwaltung geplant. Der erste Umsetzungsversuch wurde verworfen und auf v0.1.5 (Commit `37c6452`) zurückgesetzt. Die Version ist stattdessen der Klärung eines vermeintlichen Fehlers gewidmet: Whitelist- und Blacklist-Einträge schienen nicht zwischen den Geräten abzugleichen. Die Ordnerverwaltung rückt auf v0.1.7.

**Ergebnis:** Der Abgleich war nie defekt. Der iOS-Simulator empfängt CloudKit-Änderungen nicht zuverlässig. Zwischen echten Geräten (iPhone und Mac) gleichen die Listen in beide Richtungen ab, einschließlich Löschungen.

Um einen zweiten echten Testpartner zu haben, wurde Mailwerk erstmals auf dem Mac gebaut und gestartet. Dafür waren einige Plattform-Korrekturen nötig. Zusätzlich aktualisiert sich eine geöffnete Filterliste jetzt selbst, wenn Änderungen von einem anderen Gerät eintreffen.

---

## Änderungen

| Datei | Art | Inhalt |
|---|---|---|
| `Views/PlatformInputModifiers.swift` | neu | `.plainTextInput()`, `.emailInput()`, `.numberInput()` – Großschreibung und Tastaturtyp nur außerhalb von macOS |
| `Views/PlatformSheetSize.swift` | neu | `.macSheetFrame(.form / .list / .composer)` – Mindestgröße für Sheets auf macOS |
| `Services/Spam/FilterListCloudEvents.swift` | neu | Meldet ein erfolgreich abgeschlossenes Herunterladen aus iCloud; kapselt Core Data |
| `Views/AddAccountView.swift`, `EditAccountView.swift` | geändert | Eingabe-Modifier, `.macSheetFrame(.form)` |
| `Views/AccountListView.swift`, `SpamSettingsView.swift` | geändert | `.macSheetFrame(.list)` |
| `Views/ComposeView.swift` | geändert | `.macSheetFrame(.composer)` |
| `Views/MessageDetailView.swift` | geändert | Ordnerauswahl mit `.macSheetFrame(.list)` |
| `Views/FilterListView.swift` | geändert | `.emailInput()`, Neuladen bei `FilterListCloudEvents.remoteChangesImported` |
| `Views/InboxView.swift` | geändert | Platz der Ladeanzeige: `.topBarLeading`, auf macOS `.automatic` |
| `Views/HTMLMailView.swift` | geändert | `isOpaque` / `backgroundColor` nur noch im iOS-Zweig |
| `project.pbxproj` | geändert | App Sandbox → Outgoing Connections (Client) = Yes |

---

## Erkenntnisse

| Erkenntnis | Bedeutung |
|---|---|
| **Der Simulator empfängt CloudKit-Änderungen nicht zuverlässig** | Abgleich über SwiftData/CloudKit künftig nur mit echten Geräten testen (iPhone, Mac). |
| **iCloud stellt Änderungen verzögert und unregelmäßig zu** | Stille Push-Meldungen werden gebündelt und gedrosselt; Sekunden bis mehrere Minuten sind normal. Ein App-Start erzwingt immer einen Abgleich. SwiftData bietet keinen Weg, das Herunterladen gezielt anzustoßen. |
| **Auf dem Mac gleichen Postfächer, Passwörter und Spam-Einstellungen ab** | Key-Value-Speicher und iCloud-Schlüsselbund funktionieren dort ohne Nacharbeit. |
| **Sandbox-Einstellungen liegen in den Build Settings, nicht in den Entitlements** | Das Projekt steuert die App Sandbox über `ENABLE_APP_SANDBOX` bzw. `ENABLE_OUTGOING_NETWORK_CONNECTIONS`; `Mailwerk.entitlements` bleibt davon unberührt. |
| **macOS-Sheets richten sich nach dem Inhalt** | `List` und `Form` melden keine Höhe; ohne Mindestgröße schrumpft das Sheet auf Titel- und Symbolleiste. |

---

## Entscheidungen

| Entscheidung | Begründung |
|---|---|
| **Plattformunterschiede als Modifier bündeln statt `#if` je Feld** | Eine Stelle für alle Unterschiede; neue Felder brechen den Mac-Build nicht versehentlich. |
| **Alle Sheets mit `.macSheetFrame` versehen, nicht nur die betroffenen** | Jedes Sheet wäre auf dem Mac gleich leer gewesen; keine halbe Korrektur. |
| **Neuladen nur nach erfolgreich beendetem Herunterladen** | Erst dann stehen neue Einträge im Speicher; Starts, Hochladen und Fehlschläge lösen nichts aus. |
| **Kein dauerhafter Diagnose-Code** | Der vorbereitete `CloudSyncMonitor` wurde nicht eingebaut, weil die Ursache ohne ihn feststand. |

---

## Tests

Manuell geprüft zwischen iPhone und Mac, beide in iCloud mit derselben Apple-ID angemeldet:

- Eintrag auf dem Mac angelegt: erscheint bei geöffneter Liste von selbst auf dem iPhone.
- Eintrag auf dem iPhone angelegt bzw. gelöscht: erscheint bzw. verschwindet von selbst auf dem Mac, mit schwankender Verzögerung.
- Builds für iPhone und Mac ohne Fehler; Abruf aller drei Postfächer auf dem Mac erfolgreich.

---

## Bekannte Technical Debts (neu bzw. geändert)

Die übrigen Punkte aus v0.1.5 gelten unverändert weiter.

| # | Bereich | Beschreibung | Priorität | Status |
|---|---|---|---|---|
| TD-16 | macOS-Mailansicht | `HTMLMailView` setzt auf macOS `drawsBackground` per KVC, einer nicht öffentlichen Eigenschaft von WebKit. Entfällt sie in einer künftigen macOS-Version, stürzt die App beim Öffnen einer Mail ab. | Niedrig | Offen (neu in v0.1.6) |
| TD-S8 | Abgleich-Verzögerung | Wird ein Absender auf einem Gerät blockiert, kann ein anderes Gerät eine neue Mail dieses Absenders innerhalb der Verzögerung noch mit der alten Liste prüfen. Sie trägt danach `$MailwerkChecked` und bleibt im Posteingang. | Niedrig | Bekannte Einschränkung – Kurzes Zeitfenster; die gerade blockierte Mail wird sofort verschoben |

---

## Xcode-Konfiguration (Änderungen)

| Einstellung | Wert |
|---|---|
| **App Sandbox (Build Setting)** | Outgoing Connections (Client) = Yes |
| **MARKETING_VERSION** | 0.1.6 |

---

## Hinweise für v0.1.7

1. **v0.1.7 ist die Ordnerverwaltung** (ehemals v0.1.6); die Hinweise aus der v0.1.5-Doku gelten weiter.
2. **Neue Sheets** mit `.macSheetFrame(…)` versehen, **neue Eingabefelder** über die Eingabe-Modifier einrichten.
3. **Neue Oberflächen auch auf dem Mac prüfen**, da er jetzt baut und als Testgerät dient.
