# Mailwerk – Entwicklungsdokumentation v0.1.9d2

2026-10-10 · Struktur: Verbindung und Zugangsdaten, Abruf, Aktionen, Meldungen und Rückfragen (Code-Review Teil 5)

---

## Zusammenfassung

v0.1.9d2 bereinigt die Struktur dort, wo dieselbe Logik mehrfach stand. Die Stufe besteht aus zwei Schritten mit je eigenem Commit:

- **d2a (M1 + M2):**
  - Zugangsdaten und IMAP-Verbindung liegen an einer Stelle (`MailSession`).
  - `refresh()` ist in überschaubare Teile zerlegt.
  - Offene Rückfragen „Spam-Ordner anlegen?“ gehen nicht mehr verloren.
- **d2b (M7 + Rückfragen):**
  - Aktionen an Mails laufen über einen gemeinsamen Weg (`MessageActions`).
  - Jede Ansicht hat **einen** Meldungs- und **einen** Rückfragekanal.
  - Alle Rückfragen erscheinen einheitlich mittig.

**Entschieden (Kim):**
- Postfächer werden **nicht** parallel abgerufen. Das gehört zu H6 und bringt zu viel Komplexität ohne gesicherten Gewinn.
- Alle Rückfragen erscheinen als `alert`.
- d2 läuft in zwei Schritten statt vier.

Tests: 361 → **365**, alle grün.

---

## d2a – Verbindung und Zugangsdaten an einer Stelle (M1)

**Problem:**
- Die Folge „Postfach suchen → Passwort lesen → verbinden → anmelden → Aktion → abmelden, bei Fehler trennen“ stand an **9 Stellen**: `MailActionService`, `MailSendService`, `SpamFilterService` (2×), `MailFetchService` (2×), `AttachmentManager` und `InboxViewModel`.
- „Postfach nicht gefunden“ und „kein Passwort“ gab es in **fünf** eigenen Fehlerarten.

**Lösung – `MailSession` (neu):**
- `accountStore.credentials(for:)` liefert `MailCredentials` (Postfach + Passwort) oder einen gemeinsamen Fehler `MailCredentialError`, entweder „Postfach nicht gefunden“ oder „Kein Passwort gespeichert“. Ein Lesefehler des Schlüsselbunds wird unverändert weitergegeben.
- `MailSession.withIMAP(credentials) { server in … }` verbindet, meldet an, führt aus und meldet ab; bei Fehlern wird die Verbindung getrennt.
  - Ein Ergebnis gilt erst, wenn auch das Abmelden geklappt hat. Der Abruf speichert seinen Sync-Stand deshalb weiterhin erst danach.
- Alle 9 Stellen nutzen diesen Weg. Entfallen sind:
  - die eigenen Verbindungshelfer `withIMAPConnection`, `withIMAP`, `withConnection` sowie zwei handgeschriebene Abläufe;
  - die Fehlerfälle `accountNotFound` und `noPassword` in `ActionError`, `SendError`, `FilterError` und `AttachmentError`, dazu `MissingPasswordError`.
- **Unverändert eigenständig:** SMTP und der eigene Weg zum Löschen von Ordnern bauen ihre Verbindung weiter selbst auf, nutzen aber dieselben Zugangsdaten.

## d2a – `refresh()` zerlegt (M2)

**Problem:**
- `refresh()` war rund 100 Zeilen lang und bis zu 6 Ebenen tief verschachtelt.
- Fehler wurden an drei Stellen unterschiedlich behandelt.
- Die Schwelle des Spamfilters wurde per Eigenschaft gesetzt.
- **Fehler:** `pendingSpamFolders = []` verwarf bei jedem Abruf Rückfragen, die noch nicht beantwortet waren.
- (Den Doppelabruf eines gewählten Ordners aus dem Review gab es seit d1b nicht mehr.)

**Lösung:**
- **`performRefresh`:** ruft die Postfächer nacheinander ab, lädt die Liste nach jedem Postfach und bricht bei Netzverlust ab.
- **`refreshAccount`:** erst der Spamfilter, dann der Posteingang, dann der Spam-Ordner. Scheitert der Posteingang, entfällt der Spam-Ordner. Die Funktion liefert die Meldungstexte zurück.
- **`runSpamFilter`:**
  - Je Postfach steht höchstens eine Rückfrage in der Warteschlange.
  - Offene Rückfragen bleiben bestehen. Hat das Postfach inzwischen einen Spam-Ordner, entfällt seine Rückfrage.
  - Die Schwelle wird als Parameter übergeben: `SpamFilterService.run(for:scoreLimit:)`.
- **`refreshSpamFolder`:** liest den Spam-Ordner frisch aus dem Postfach. Hat der Filter ihn gerade erst gefunden, wird er in derselben Runde schon abgerufen.

**Nebenbei:** `MailActionService` und `SpamFilterService` sind vollständig nachdokumentiert.

**Warnung aus d1b behoben:** `FetchRequest.supersedes` ist jetzt `nonisolated`.
- Der Startwert einer Eigenschaft wird außerhalb des Main-Actors ausgewertet, die Regel gehörte aber durch `SWIFT_DEFAULT_ACTOR_ISOLATION` zum Main-Actor.
- Gleiche Lösung wie bei `MailFetchService.inboxFolder`.

---

## d2b – Aktionen an Mails an einer Stelle (M7)

**Problem:**
- Gelesen, Kennzeichnen, Löschen und Verschieben standen doppelt in `InboxView` (Wischaktionen) und `MessageDetailView` (Menü), jeweils als Folge Server → Cache → Liste.
- Rückgängig-Zeitgeber und Zeilensperre lagen in der View.

**Lösung:**
- **`MessageActions` (neu):** `setRead`, `setFlagged`, `delete` und `move` ändern Server und Cache gemeinsam. Das Ziel ist `MessageActions.Target` (Cache-ID, Postfach, Ordner, UID) und lässt sich aus Listeneintrag oder vollständiger Mail bilden.
- **`InboxViewModel`:** übernimmt die Wischaktionen (`toggleRead`, `toggleFlag`), das „Rückgängig“ samt 5-Sekunden-Zeitgeber (`undo`, `dismissUndoUnflag`) und die Zeilensperre (`processingMessageIDs`).
- **`InboxView`:** enthält nur noch Darstellung.

## d2b – Ein Meldungs- und ein Rückfragekanal je Ansicht

**Problem:**
- Es gab 7 getrennte Meldungszustände und 9 Rückfragen in zwei Bauarten (`confirmationDialog` und `alert`).
- `MessageDetailView` hängte **drei** `confirmationDialog` und zwei `alert` an dieselbe Ansicht und öffnete sie aus einem Menü heraus. Diese Bauweise gilt in SwiftUI als unzuverlässig und war der Verdacht hinter der alten Beobachtung „Löschen per Menü reagiert manchmal nicht“.

**Lösung – `Dialogs.swift` (neu):**
- `AlertItem`: Meldung mit „OK“ und optionaler Aktion danach.
- `ConfirmationRequest`: Rückfrage mit Bestätigen und Abbrechen. Die Kennung kann fest sein, damit eine Rückfrage aus einer Warteschlange nicht flackert.
- Modifier `.alertItem(…)` und `.confirmationRequest(…)`, beide als mittiger `alert`.

**Umgestellt:**

| Ansicht | Rückfragen | Meldungen |
|---|---|---|
| `InboxView` / `InboxViewModel` | Spam-Ordner anlegen | Abruf, Wischaktionen, Rückgängig, Ältere laden |
| `MessageDetailView` | Mail löschen, Anlagen lokal löschen, Blockieren/Vertrauen | Aktionen, Listeneintrag, Vorschau, Download |
| `ComposeView` | Entwurf verwerfen | Versandfehler, Hinweise nach dem Versand, Datei/Foto anhängen |
| `AccountListView` | Postfach entfernen | Entfernen fehlgeschlagen |
| `FolderSidebarView` | Ordner löschen | Anlegen/Löschen fehlgeschlagen |

- Beide Knöpfe von „Spam-Ordner anlegen?“ nehmen die Anfrage sofort aus der Warteschlange, damit sie während des Anlegens nicht erneut aufblitzt.
- Fehler beim Anhängen von Dateien oder Fotos tragen eigene Titel statt „Versand fehlgeschlagen“.
- `MessageDetailView`, `AccountListView` und `FolderSidebarView` sind vollständig nachdokumentiert, die Versionskommentare entfernt.

**Bewusst unverändert:**
- Der Eingabedialog „Neuer Ordner“ mit Textfeld.
- Die Einzelmeldungen in `AddAccountView`, `EditAccountView`, `FilterListView` und `FolderMoveSheet`. Sie haben nur eine Meldung und keinen Konflikt mehrerer Dialoge und werden in e2 angeglichen.

---

## Geänderte Dateien

```
Mailwerk/
├── Services/
│   ├── MailSession.swift                   # neu: Zugangsdaten, IMAP-Verbindung (d2a)
│   ├── MailFetchService.swift              # über MailSession (d2a)
│   ├── MailActionService.swift             # über MailSession, dokumentiert (d2a)
│   ├── MailSendService.swift               # über MailSession (d2a)
│   ├── AttachmentManager.swift             # über MailSession (d2a)
│   ├── Spam/SpamFilterService.swift        # über MailSession, run(for:scoreLimit:), dokumentiert (d2a)
│   └── Sync/FetchCoordinator.swift         # supersedes nonisolated (d2a)
├── ViewModels/
│   ├── MessageActions.swift                # neu: Aktionen an Mails (d2b)
│   └── InboxViewModel.swift                # refresh zerlegt (d2a); Wischaktionen, alert (d2b)
└── Views/
    ├── Dialogs.swift                       # neu: AlertItem, ConfirmationRequest (d2b)
    ├── InboxView.swift                     # nur Darstellung, je ein Kanal (d2b)
    ├── MessageDetailView.swift             # je ein Kanal, MessageActions, dokumentiert (d2b)
    ├── ComposeView.swift                   # je ein Kanal (d2b)
    ├── AccountListView.swift               # je ein Kanal, dokumentiert (d2b)
    └── Folders/FolderSidebarView.swift     # je ein Kanal, dokumentiert (d2b)
MailwerkTests/
└── MailSessionTests.swift                  # neu, 4 Tests (d2a)
Documentation/
└── Mailwerk_v0.1.9d2_Entwicklungsdokumentation.md   # neu
```

---

## Testverfahren

**Automatisch:** 361 (v0.1.9d1) + 4 (d2a) = **365**, alle grün. d2b ändert Ansichten und ruft Dienste auf, die ohne Server nicht testbar sind; neue Tests gibt es dort keine.

**Manuell (Simulator, nur Mails in „Test Mailwerk“):**

| Schritt | Bereich | Ergebnis |
|---|---|---|
| d2a | Abruf „Alle Eingänge“ mit Spamfilter und Spam-Ordnern | 0 Fehler, 547 Nachrichten |
| d2a | Wischen (gelesen, kennzeichnen), Verschieben hin und zurück, Löschen | in Ordnung |
| d2a | Anlagen lokal löschen und neu laden | in Ordnung |
| d2a | Antworten an sich selbst: Gesendet-Kopie, Original beantwortet | in Ordnung |
| d2a | Blockieren, Vertrauen (abgelehnt, solange auf Blacklist), nach Entfernen zurück in den Posteingang | in Ordnung |
| d2b | Wischaktionen, Rückgängig (Tipp und 5 s), alle Rückfragen, mehrfaches Löschen über das Menü | in Ordnung |
| d2b | Mail löschen mit Rückfrage | Mac: in Ordnung |

Spam-Aktionen lassen sich im Simulator gefahrlos testen: Dort gleichen die Filterlisten nicht mit iCloud ab, die echten Listen bleiben unberührt.

---

## Beobachtungen

- **„Löschen per Menü reagiert manchmal nicht“:** Die Beobachtung ist alt (frühere Version) und ließ sich nicht mehr nachstellen. Zurückgestellt als Beobachtung. Die verdächtige Bauweise (mehrere Dialoge an einer Ansicht, geöffnet aus dem Menü) gibt es seit d2b nicht mehr; mehrfaches Löschen über das Menü lief fehlerfrei.
- **Testanweisungen:** Herunterziehen in einem Ordner ruft nur diesen Ordner ab (`refreshFolder`), nicht alle Posteingänge. Tests für `refresh()` laufen in „Alle Eingänge“.

---

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.9d1. `MARKETING_VERSION` je Schritt von Kim gesetzt.

---

## Commits

| Schritt | Commit |
|---|---|
| d2a | `6f50177` |
| d2b + Doku | *von Kim nach diesem Dokument* |

---

## Nächste Schritte

- **v0.1.9d3 – Aufräumen:** `os.Logger` statt `print` (N24), toter Code (Review Abschnitt 5).
- **v0.1.9e1 – M5:** externe Inhalte blockieren, sicheres Zitieren von HTML.
- **v0.1.9e2 – N-Befunde**, dazu die übrigen Einzelmeldungen auf `AlertItem` angleichen.
- **v0.1.9e3 – weitere Funde**, **f – Inline-Dokumentation**.
- **Abschluss v0.1.9:** Diskussion M6.
- **Eigener Commit:** Rückbau des eigenen Ordner-Löschwegs auf SwiftMails `deleteMailbox` (ab 1.14.0).
- **Später:** H6 (Verbindungen wiederverwenden), ggf. mit der Push-Stufe.
