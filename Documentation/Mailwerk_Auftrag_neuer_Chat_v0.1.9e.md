# Mailwerk – Auftrag und Übergabe für den neuen Chat (ab v0.1.9e1)

Stand: 11.10.2026, nach Abschluss von v0.1.9e2 (Commit `1ec520f`). Dieses Dokument ersetzt den Verlauf des bisherigen Chats. Es enthält Projektstand, Arbeitsregeln und den Auftrag.

---

## 1. Auftrag

Abschluss des Code-Reviews v0.1.9. Die offenen Stufen in dieser Reihenfolge, **jede mit eigener Entwicklungsdoku (OnePager) und eigenem Commit**:

| Stufe | Inhalt |
|---|---|
| **e1 – M5** | Externe Inhalte (Bilder, Tracking-Pixel) in HTML-Mails nicht automatisch laden, mit Knopf „Externe Inhalte laden“. Beim Antworten/Weiterleiten das HTML-Zitat sicher übernehmen statt per Regex zu bereinigen (`ReplyBuilder.sanitizedBodyContent`). |
| **e3 – weitere Funde** | siehe Abschnitt 5 |
| **f – Inline-Doku** | Dokumentationsstandard auf alle übrigen Dateien (61 Dateien, siehe Abschnitt 6), in zwei bis drei Lieferungen mit Build und Test |
| **Abschluss v0.1.9** | Diskussion M6 (eigenes Feld für die Absenderadresse). Kim möchte den Befund **erst erklärt** bekommen, dann entscheidet er. |

**Vorgehen für e1:**
1. Zuerst den Ist-Stand belegen: `HTMLMailView` (wie wird HTML geladen, welche WebView-Einstellungen gelten seit K4) und `ReplyBuilder.sanitizedBodyContent` (was wird heute entfernt, wo wird das Zitat verwendet).
2. Vorschlag mit Schritten vorlegen: Mechanismus zum Blockieren (CSP-Meta oder `WKContentRuleList`), Bedienung „Externe Inhalte laden“ (je Mail, nur für diese Anzeige), Umgang mit `cid:`-Bildern und `data:`-URLs, sicheres Zitat (Parser oder Textteil). Dabei mit offenen Fragen an Kim arbeiten (z. B. ob „Externe Inhalte laden“ je Absender gemerkt werden soll).
3. Auf Kims OK warten, erst dann bauen.

Hinweise aus dem Review (`Documentation/v0.1.8d - Code-Review-Mailwerk.md`, M5): CSP-Vorschlag `default-src 'none'; img-src data: cid:; style-src 'unsafe-inline'` oder `WKContentRuleList`; für das Zitat einen echten Parser (z. B. SwiftSoup) oder nur den Textteil. **Neue Pakete nur nach Rückfrage.** SwiftMail wird nicht geforkt.

---

## 2. Arbeitsregeln (verbindlich)

- **Nichts bauen ohne OK.** Erst Vorschlag bzw. Antwort auf Fragen, dann auf ausdrückliche Freigabe warten. Fragen zuerst beantworten, nicht gleich handeln.
- **Schritt für Schritt:** Test- und Handlungsanweisungen einzeln geben und nach jedem Schritt auf Rückmeldung warten.
- **Klar reden:** Jede Anweisung muss ohne Vorwissen ausführbar sein – genauer Menüpfad, genaue Bezeichnung, was danach zu sehen sein soll. Keine Begriffe wie „App-Umschalter“ ohne Erklärung, keine Menüpunkte, deren Existenz nicht sicher ist. Im Zweifel den einfachsten Weg nennen (z. B. App im Simulator durch Hochwischen beenden).
- **Lieferung:** immer **komplette Dateien** als Download, dazu eine Tabelle *Datei · Zielordner · Art (neu/ersetzen/löschen)*. Keine Code-Schnipsel, keine Claude-Code-Prompts. Zu löschende Dateien in der Tabelle ausdrücklich als „löschen“ markieren und im Text erklären, dass sie nicht mitgeliefert werden.
- **Neue Dateien:** bei jeder neuen Datei ausdrücklich darauf hinweisen, in welchen Ordner sie gehört, und dass im Dateiinspektor (View → Inspectors → File, ⌥⌘1) unter **Target Membership** nur das richtige Ziel angehakt ist (App: `Mailwerk`, Tests: `MailwerkTests`). In e2 landeten zweimal Dateien im falschen Ziel.
- **Commit** macht Kim selbst in Xcode (und pusht), jeweils am Ende einer Stufe. **Nie einen nicht lauffähigen Stand committen** – ein im Test gefundener Fehler wird vor dem Commit behoben, nicht als Fund verschoben. Danach prüft Claude das Repo.
- **Xcode-Bezeichnungen exakt** (z. B. **Product → Clean Build Folder**). Paketversion wird unter Package Dependencies direkt in der Zeile geändert (kein „Done“-Knopf). Der Projektnavigator ist die linke Dateiliste (⌘1). Das Simulator-Menü heißt **Device → Reset All Content and Settings**; einen Menüpunkt „App Switcher“ gibt es dort nicht.
- **Keine Sonderlösungen** für Einzelfälle; bei mehreren Fehlversuchen anhalten und die Ursache belegen statt weiter nachzubessern.
- **Funde** während der Arbeit notieren und bewusst einplanen, nicht nebenbei patchen.
- **Tests dürfen keine Produktivmails verändern.** Testordner „Test Mailwerk“ im Webmail, Mails hineinkopieren.
- **Testaufwand gering halten:** nur die nötigsten Tests je Gerät.

---

## 3. Test- und Dokumentationsstandard

**Tests:**
- Automatische Tests auf **Simulator oder My Mac**, nie auf dem iPhone.
- **Änderungen an Abruf oder Abgleich** immer mit dem größten Postfach (Kim.Sieber@ordinum.com, rund 8.800 Mails) und einer frischen Installation im Simulator testen.
- Neue Funktionen auch auf dem **Mac** prüfen.
- Erwartete Testzahl bei jeder Lieferung nennen.
- Der Simulator hat keine Bildschirmtastatur, solange die Mac-Tastatur genutzt wird; einblenden mit **I/O → Keyboard → Toggle Software Keyboard** (⌘K).
- Protokoll lesen: Xcode-Konsole (mit „Metadata“ für Kategorie), oder App **Konsole** auf dem Mac (Gerät links wählen, Menü **Aktion → Infomeldungen einschließen**, Suchfeld mit **einem** Begriff aus dem Meldungstext, z. B. „Abgleich“).

**Inline-Dokumentation** (in jeder gelieferten Datei vollständig):
- Datei-Header mit Zweck, Abgrenzung und Abhängigkeiten.
- DocC-Kopf je Funktion: Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`.
- Testfunktionen: eine Zeile `///`.
- Deutsch, **keine Versionsverweise im Code**.

**OnePager je Stufe:** `Mailwerk_v0.1.9xx_Entwicklungsdokumentation.md` im Ordner `Documentation/`. Inhalt: Zusammenfassung, Problem/Lösung je Schritt, geänderte Dateien, Testverfahren mit Testzahl, Beobachtungen, nächste Schritte (Vorlage: v0.1.9d2, v0.1.9e2).

---

## 4. Projektstand

**Projekt:** Mailwerk, Mail-Client in Swift/SwiftUI für iOS und macOS. Repo `github.com/KimSieber/Mailwerk`, Branch `main`. Bundle `de.sieber-bw.Mailwerk`. Drei IMAP-Postfächer bei manitu. `MARKETING_VERSION` 0.1.9e2b.

**Technik:**
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, Approachable Concurrency, MemberImportVisibility; Deployment Target iOS/macOS 26.5.
  - Statische Werte, die als Standardparameter oder Startwert einer Eigenschaft dienen, müssen `nonisolated` sein (z. B. `MailFolder.inboxPath`, `FetchRequest.supersedes`).
  - Jede Datei, die Member eines Moduls nutzt, braucht den eigenen `import` (z. B. `import os` für `Log`).
- Xcode-Projekt mit synchronisierten Ordnern: Neue Dateien im Ordner gehören automatisch zum Ziel des Ordners.
- Swift Testing (`@Test`, `#expect`).
- **SwiftMail 1.15.0** (Mindestversion). Wird nicht geforkt; Paket-Updates in eigenem Commit.
- Mail-Cache: System-SQLite `MessageStore` (WAL, Transaktionen, Schema-Stufe 3, Ordner `Cache` ohne Backup).
- Postfächer im iCloud-Key-Value-Speicher, Passwörter im iCloud-Schlüsselbund, Filterlisten über SwiftData/CloudKit.

**Wichtige Bausteine (Stand e2):**
- `MailSession` (Zugangsdaten, `withIMAP`), `MessageActions` (Aktionen auf Server und Cache), `Dialogs` (`AlertItem`, `ConfirmationRequest`, `.alertItem`, `.confirmationRequest`).
- `FetchCoordinator` (Abrufe nacheinander, gleiche Anforderung schließt sich an).
- `MessageContentPlan` (nur Struktur + Text/HTML laden, Anhänge einzeln).
- `MailFolder.inboxPath/isInbox`, `SyncWindow` (Fenster, Kalender), `FlagState`, `FolderKey`, `UserFacingError`.
- `MailPrintFormatter` (HTML für Druck und Teilen); Teilen über `ShareLink` in `MessageDetailView`.
- `Log` (os.Logger): Kategorien Abruf, Aktionen, Spam, Versand, Cache, Ansicht; Zahlen/Ordner/Fehler öffentlich, Postfachnamen/Adressen/Message-IDs privat.
- `HTMLMailView`: CSS `body { display: flow-root !important; }` gegen abgeschnittene Mails (Margin-Collapsing).

**Commits v0.1.9 seit d1:**

| Stufe | Inhalt | Commit |
|---|---|---|
| d1a–e | Antwortansicht wie Apple Mail, Abrufe abgestimmt, M9, neue Postfächer, flow-root | `b5e7bfe`, `55001e1`, `006fe6e`, `c883dd8`, `b1e5df9`, `295fa5e` |
| d2a/b | MailSession, refresh zerlegt; MessageActions, Dialogs | `6f50177`, `da15147` |
| d4a/b | SwiftMail 1.15.0; Ordner löschen über `deleteMailbox` | `2b28033`, `a99f1a9` |
| e2a/b | Aufräumen nach Review; os.Logger | `87984ec`, `1ec520f` |

Die OnePager für d4 und e2 liegen als `Mailwerk_v0.1.9d4_…` und `Mailwerk_v0.1.9e2_…` vor (von Kim ins Repo unter `Documentation/` zu legen, falls noch nicht geschehen).

**Tests:** 360, alle grün.

---

## 5. Review-Befunde: Stand und Funde für e3

| Stand | Befunde |
|---|---|
| Erledigt | K1–K5, H1–H5, M1, M2, M4, M7, M8, M9; N1, N2, N4–N12, N15–N20, N23–N26; N21/N22 entfallen mit d4 |
| Bewusst nicht umgesetzt (begründet in Doku e2) | N3 (benannte SQL-Parameter), N19 Teil „Größe schätzen“ |
| Offen | M5 (e1), N13 (zu entscheiden), M6 (Abschluss) |
| Verschoben | H6 (Verbindungen wiederverwenden), N14 Teil „Warteschlange offline“, Strukturempfehlungen (Protokolle/Injektion, SwiftLint, Lokalisierung) |

**Funde für e3:**
1. `FolderTreeBuilder.resolveNameCollisions` rät beim Zurückholen des Servernamens „.“ als Trennzeichen (bei Servern mit „/“ falsch; `components(separatedBy: ".").last` ist nie `nil`, der „/“-Zweig greift nie).
2. `Models/InboxMessage.swift` wird nirgends verwendet → toter Code, entfernen.
3. Port-Felder in `AddAccountView` ohne `.numberInput()` (in `EditAccountView` vorhanden).
4. N13: `MessageDetailView` rund 780 Zeilen – Kim entscheidet, ob die Aufteilung (Kopfbereich, Anhangliste, Menü) in v0.1.9 gehört.
5. Beobachtung „Löschen per Menü reagiert manchmal nicht“: zurückgestellt, nur bei erneutem Auftreten aufnehmen.

---

## 6. Stufe f – Dateien ohne vollständigen Kopf

**App (39):** `Models/` AccountColor, CachedMessage, InboxMessage (entfällt mit e3), MailAccount, MailAddress, MailboxSelection, SyncState · `Services/` ConnectionErrorClassifier, ContactSuggestionService, MailLink, MailServerFactory, RecipientInput, ReplyBuilder, RichTextHTML, `Folders/`MailboxNameCodec · `Services/Spam/` FilterAddress, FilterEntry, FilterListCloudEvents, FilterListExporter, FilterListInput, FilterListRepository, FilterListRules, SpamFilterPlanner, SpamHeaderParser, SpamKeyword, SpamSettings, Spamclassifier, SwiftDataFilterListRepository · `ViewModels/` AddAccountViewModel · `Views/` AttachmentRow, ColorPickerGrid, FlowLayout, FormattingToolbar, PlatformInputModifiers, PlatformSheetSize, RecipientField, SpamSettingsView, `Folders/`FolderLabel, `Folders/`SideDrawer.

**Tests (22):** FilterAddress, FilterListExporter, FilterListInput, FilterListRepository, FolderCatalog, FolderCreationPlanner, FolderNode, FolderTreeBuilder, MailLink, MailboxNameCodec, Mailwerk, MessageStoreFolder, RecipientInput, ReplyBuilder, RichTextHTML, SpamClassifier, SpamFilterPlanner, SpamFolderResolver, SpamHeaderParser, SpamKeyword, SyncState (jeweils `…Tests.swift`).

**Mit Versionsangaben im Code (6):** `Views/Folders/FolderLabel.swift`, `Views/Folders/SideDrawer.swift`, `MailwerkTests/SyncWindowTests.swift`, `FolderCatalogTests.swift`, `MessageStoreFolderTests.swift`, `FolderTreeBuilderTests.swift`.

Hinweis: Dateien, die in e1/e3 ohnehin geändert werden (z. B. `ReplyBuilder`, `HTMLMailView`), dort gleich vollständig dokumentieren. Datei `Spamclassifier.swift` hat einen klein geschriebenen Namensteil (Typ heißt `SpamClassifier`) – Umbenennen in f mit Kim abstimmen.

---

## 7. Bekannte Besonderheiten der Umgebung

- **Xcode + Kabel + VPN:** Mit NordVPN bricht die Debug-Verbindung zum iPhone ab; für die Installation VPN am Mac aus.
- **Simulator:**
  - kein CloudKit-Abgleich der Filterlisten, kein iCloud-Schlüsselbund;
  - zeigt im Protokoll private Werte immer im Klartext (Datenschutz-Einstufung dort nicht prüfbar);
  - Tastatur nimmt gelegentlich nur ein Zeichen an → Simulator neu starten.
- **SwiftMail:** baut abgerissene Verbindungen still neu auf, ohne den Ordner neu auszuwählen (abgefangen); `deleteMailbox` löscht samt Inhalt (Vorprüfung in `FolderDeletion`).
- **Postfächer:** im August 2026 per IMAPSYNC umgezogen; Sequenznummern sind kein Datumsindikator.

---

## 8. Erster Schritt im neuen Chat

1. Repo prüfen: Commit `1ec520f` (oder später, falls Kim die OnePager committet hat), 360 Tests, keine `print`-Aufrufe.
2. Für **e1** den Ist-Stand in `HTMLMailView` und `ReplyBuilder` lesen und Kim einen Vorschlag mit Schritten und offenen Fragen vorlegen.
3. Auf Kims OK warten.
