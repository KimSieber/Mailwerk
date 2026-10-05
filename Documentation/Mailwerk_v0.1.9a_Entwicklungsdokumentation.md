# Mailwerk – Entwicklungsdokumentation v0.1.9a

2026-10-05 · Sicherheit und Datenkorrektheit (Code-Review Teil 1), Rücknahme von a1b

---

## Zusammenfassung

v0.1.9a ist der erste Teil des Code-Reviews (v0.1.9). Er behebt die vier kritischen Befunde K1 bis K4 und legt den Dokumentationsstandard für alle folgenden Teilversionen fest.

Ein zusätzlich eingebauter Laufzeitfund (a1b, Nachladen fehlender Mails im Abgleich) führte bei großen Postfächern zu einem Timeout und wurde vollständig zurückgenommen. Die zugrunde liegende Lücke ist bekannt und fest für v0.1.9b eingeplant.

Stand nach v0.1.9a: a1, a2 und a3 sind enthalten; Abruf und Abgleich arbeiten im Code wieder exakt wie in v0.1.8e.

---

## Auslöser

Ein externes Code-Review auf v0.1.8c (in Claude Cloud mit einem anderen Modell) lieferte Befunde in vier Kategorien: Kritisch (K), Hoch (H), Mittel (M) und Niedrig (N). Der Bericht wurde gegen den Stand v0.1.8e geprüft. H3 und H5 waren bereits erledigt. Einige Bewertungen wurden korrigiert, insbesondere M10 und K5, weil das Review die Projekteinstellung `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` übersehen hatte.

v0.1.9 ist in fünf Teilversionen aufgeteilt: a (Sicherheit und Datenkorrektheit), b (robuster Store), c (Performance), d (Struktur und Aufräumen), e (Inline-Dokumentation für die übrigen Dateien).

---

## Umgesetzte Befunde

### a1 – Ordner bei Markierung und Anhang-Download (K1)

**Problem:** `MailSendService.markOriginal` und `AttachmentManager.downloadAttachment` wählten immer `INBOX`. Eine Antwort auf eine Mail im Spam- oder einem Benutzerordner setzte `\Answered` auf eine fremde Mail im Posteingang mit gleicher UID. Dasselbe galt für den Anhang-Download, auch beim Weiterleiten. Der Fehler bestand seit den Ordneransichten in v0.1.7d.

**Lösung:** `OutgoingMail.Origin` enthält das Pflichtfeld `folder`. Der Bezug auf die Originalmail entsteht an einer einzigen Stelle, dem Initializer `Origin(composeKind:original:)`; die private Funktion `origin()` im `ComposeViewModel` entfällt. `markOriginal` wählt `origin.folder`, `downloadAttachment` wählt `message.folder`.

**Hinweis:** Antworten, die vor v0.1.9a aus Spam oder Benutzerordnern verschickt wurden, können eine fremde Mail im Posteingang als beantwortet markiert haben. Das ist nachträglich nicht sicher zuzuordnen, aber harmlos (nur ein Flag).

### a2 – Keychain (K2)

**Problem:** `savePassword` löschte den Eintrag und legte ihn neu an. `deletePassword` fehlte das Attribut `kSecAttrSynchronizable`; der synchronisierte Eintrag wurde beim Entfernen eines Postfachs daher nicht gefunden und blieb im iCloud-Schlüsselbund liegen.

**Lösung:** `savePassword` versucht zuerst `SecItemUpdate` und legt nur bei `errSecItemNotFound` neu an. Alle Zugriffe nutzen eine gemeinsame `baseQuery(for:)` mit `kSecAttrSynchronizable = true`.

**Zur Einordnung:** Die Passwörter sind generische Schlüsselbund-Einträge. Sie synchronisieren über iCloud, erscheinen aber nicht in der Passwörter-App auf dem iPhone, sondern nur in der Schlüsselbundverwaltung am Mac (Suche nach `de.sieber-bw.Mailwerk.mailaccount`).

### a3 – Dateinamen und Druck (K3, K4)

**Problem K3:** `writeTempFile` übernahm den Dateinamen aus dem MIME-Header ungeprüft. Ein Name wie `../../Library/Caches/payload` hätte außerhalb des Temp-Verzeichnisses geschrieben werden können.

**Lösung K3:** `sanitizedFilename(_:)` nimmt nur den letzten Pfadbestandteil (auch bei Backslash-Pfaden), entfernt führende Punkte und fällt bei leerem Ergebnis auf „Anhang" zurück. Zusätzlich leert `cleanupTempFiles()` beim App-Start den Ordner `Mailwerk-Attachments` (Aufruf in `MailwerkApp.init`).

**Problem K4:** Der Druck-WebView (`MailPrinter`) lief ohne eigene Konfiguration und konnte JavaScript aus der Mail ausführen.

**Lösung K4:** `MailPrinter` nutzt eine `WKWebViewConfiguration` mit `allowsContentJavaScript = false`. Bilder und Stylesheets werden weiterhin geladen, damit der Ausdruck vollständig ist. Eine erste Fassung, die auch Remote-Bilder blockierte, wurde verworfen, weil der HTML-Druck damit seinen Zweck verliert.

---

## Zurückgenommen: a1b – Nachladen fehlender Mails im Abgleich

### Ausgangslage

Beim Test von a1 fiel auf: Eine im Webmail in einen Ordner kopierte Mail mit altem Eingangsdatum erscheint in Mailwerk nicht. Der Abruf sucht nur in den letzten 30 Tagen (`SEARCH SINCE`, bezogen auf das Eingangsdatum), „Ältere laden" nur vor dem gespeicherten Fensterbeginn, und der Abgleich entfernt nur und gleicht Flags ab. Die Lücke besteht seit v0.1.8b (dauerhaft gespeichertes Zeitfenster).

### Was eingebaut war

Der Abgleich bildete die Differenz „UIDs auf dem Server minus UIDs im Cache" und lud diese Mails nach. Getestet wurde nur im kleinen Testordner; dort funktionierte es.

### Fehler

Bei großen Postfächern umfasst diese Differenz die gesamte nicht gecachte Historie, im größten Postfach rund 8.600 Mails. `fetchMessageInfosBulk` lief nach 10 Sekunden in einen Timeout. Mailwerk meldet einen Timeout als „keine Verbindung" nur still im Titel, deshalb fiel der Fehler erst beim Test von b1+b2 auf.

Zwei schnelle Nachbesserungen (Untergrenze über die niedrigste gecachte UID) scheiterten: Der Cache enthält auch ältere gekennzeichnete und per „Ältere laden" geholte Mails mit sehr niedrigen UIDs.

### Nachweis der Ursache

- Im Log erschien `Davon bereits im Cache` zweimal: Der zweite Aufruf kam aus dem Nachladen im Abgleich.
- `missingUIDs` war im Code von v0.1.9a vorhanden.
- Gegenprobe: v0.1.8e lief mit derselben Datenbank ohne Timeout.

### Rücknahme

`ServerReconciliation.swift`, `MailFetchService.swift` und `ServerReconciliationTests.swift` sind im Code (ohne Kommentare) identisch mit v0.1.8e. Erhalten blieb die neue Inline-Doku; die Lücke ist in den Datei-Headern als bekannte Einschränkung vermerkt. Die Rücknahme ist ein eigener Commit nach vorne, es wurde kein Stand zurückgesetzt.

### Geplante Lösung (v0.1.9b, direkt nach b1+b2)

Konzept „Sync-Zustand je Ordner" nach dem Muster aus RFC 4549: je Ordner UIDVALIDITY und die höchste gesehene UID speichern. Neu im Ordner ist, was oberhalb dieser UID liegt, unabhängig vom Datum, denn eine hineinkopierte Mail bekommt immer eine neue, höhere UID. Das Konzept wird vor der Umsetzung schriftlich vorgelegt und geprüft, zusammen mit UIDVALIDITY (H2).

### Konsequenzen für das Vorgehen

- Funde während des Reviews werden notiert und bewusst eingeplant, nicht nebenbei gepatcht.
- Änderungen an Abruf und Abgleich werden immer auch mit dem größten Postfach getestet, zusätzlich mit einer frischen Installation im Simulator.
- Bei mehreren Fehlversuchen: anhalten und die Ursache belegen, statt weiter nachzubessern.

---

## Geänderte Dateien (Stand nach v0.1.9a)

```
Mailwerk/
├── MailwerkApp.swift                     # cleanupTempFiles beim Start (K3)
├── Services/
│   ├── AttachmentManager.swift           # Ordner beim Download (K1), sanitizedFilename, cleanupTempFiles (K3)
│   ├── KeychainService.swift             # Update statt Löschen+Neuanlegen, baseQuery (K2)
│   ├── MailFetchService.swift            # nur Inline-Doku; Code wie v0.1.8e
│   ├── MailSendService.swift             # Origin mit Ordner, Markierung im richtigen Ordner (K1)
│   └── Sync/
│       └── ServerReconciliation.swift    # nur Inline-Doku; Code wie v0.1.8e
├── ViewModels/
│   └── ComposeViewModel.swift            # Origin(composeKind:original:) statt origin() (K1)
└── Views/
    └── MailPrinter.swift                 # JavaScript aus der Mail gesperrt (K4)
MailwerkTests/
├── AttachmentSanitizeTests.swift         # neu, 9 Tests (K3)
├── OutgoingMailOriginTests.swift         # neu, 5 Tests (K1)
└── ServerReconciliationTests.swift       # nur Kurzdoku; Tests wie v0.1.8e
```

Datenbank: keine Änderung. Commits: `7be6eaa` (a1, a1b), `f77b912` (a2, a3), Rücknahme a1b.

---

## Inline-Dokumentation

Standard ab v0.1.9a:

- **Datei-Header:** Zweck, Abgrenzung, Abhängigkeiten.
- **Funktionen:** DocC-kompatibler Kopf mit Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`.
- **Testfunktionen:** eine Zeile `///` mit Zuordnung und Zweck.
- **Sprache:** Deutsch, keine Versionsverweise im Code.

Alle elf oben genannten Dateien folgen diesem Standard. Die übrigen Dateien folgen in v0.1.9e.

---

## Testverfahren

**Automatisch:** alle Tests grün, ohne Warnungen. Gegenüber v0.1.8e (121 Tests) kommen 14 neue hinzu (5 Origin, 9 Dateinamen), also 135.

**Manuell (Simulator und Mac), nach der Rücknahme von a1b:**

| Test | Inhalt | Ergebnis |
|---|---|---|
| T1 | Build und Tests | in Ordnung |
| T2 | Abruf aller drei Postfächer inkl. des größten; Abgleich ohne Nachladen | in Ordnung, kein Timeout |
| T3 | Frische Installation im Simulator, alle Postfächer abrufen | in Ordnung, kein Timeout |
| T4 | Antworten/Weiterleiten aus „Test Mailwerk", Anhang über 5 MB | Markierung in Mailwerk und Webmail korrekt |
| T5 | Passwort ändern | erfolgreich, ein Eintrag je Postfach |
| T6 | Druck einer HTML-Mail mit Bildern, Anhang öffnen und teilen | funktioniert |

---

## Abhängigkeiten / Xcode-Konfiguration

- **SwiftMail:** Mindestversion von 1.11.0 auf **1.13.0** angehoben (Paket neu eingebunden, im Commit `7be6eaa`). Paket-Updates sollen künftig in einem eigenen Commit erfolgen, damit sich Verhaltensänderungen klar zuordnen lassen.
- `MARKETING_VERSION` = 0.1.9a.

---

## Nächste Schritte

- **v0.1.9b:**
  1. b1+b2 neu liefern (Transaktions-Wrapper mit Rollback, Prüfung der SQLite-Ergebnisse, `user_version`, WAL, Mail und Anhänge atomar speichern), Test inkl. größtem Postfach.
  2. Konzept „Sync-Zustand je Ordner" (UIDVALIDITY und höchste gesehene UID) vorlegen und prüfen.
  3. Umsetzung des Konzepts: schließt die Lücke aus a1b und setzt H2 um.
  4. b4: Wiederherstellung statt `fatalError` bei beschädigter Datenbank, Backup-Ausschluss der Cache-Datei.
- **v0.1.9c:** Performance.
- **v0.1.9d:** Struktur und Aufräumen.
- **v0.1.9e:** Inline-Dokumentation der übrigen Dateien.
