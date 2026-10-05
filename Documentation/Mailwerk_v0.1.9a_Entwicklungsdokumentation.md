# Mailwerk – Entwicklungsdokumentation v0.1.9a

2026-10-05 · Sicherheit, Datenkorrektheit und Inline-Dokumentation (Teil 1)

---

## Zusammenfassung

v0.1.9a ist der erste Teil des Code-Reviews (v0.1.9). Er behebt fünf Befunde aus den Kategorien Sicherheit (K1–K4) und Datenkorrektheit (a1b) und legt den Dokumentationsstandard für alle folgenden Versionen fest.

Alle gelieferten Dateien tragen jetzt einen Datei-Header mit Zweck, Abgrenzung und Abhängigkeiten sowie Funktionsköpfe mit Zweck, Verarbeitung und Parametern (DocC-kompatibel, auf Deutsch). Testfunktionen erhalten eine Kurzform mit Zuordnung und Zweck.

---

## Auslöser

Ein externes Code-Review auf v0.1.8c (durchgeführt in Claude Cloud mit einem anderen Modell) lieferte Befunde in vier Kategorien: Kritisch (K), Hoch (H), Mittel (M) und Niedrig (N). Der Review-Bericht wurde gegen den aktuellen Stand v0.1.8e geprüft. Zwei Befunde (H3, H5) waren bereits erledigt, einige Bewertungen wurden korrigiert (insbesondere M10 und K5, weil das Review die Projekteinstellung `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` übersehen hatte).

v0.1.9 wird in fünf Teilversionen aufgeteilt: a (Sicherheit/Datenkorrektheit), b (robuster Store), c (Performance), d (Struktur/Aufräumen), e (Inline-Dokumentation Rest).

---

## Befunde und Maßnahmen in v0.1.9a

### a1 – Ordner bei Markierung und Anhang-Download (K1)

**Problem:** `MailSendService.markOriginal` wählte immer `INBOX`, und `AttachmentManager.downloadAttachment` ebenfalls. Eine Antwort auf eine Mail im Spam-Ordner setzte `\Answered` auf eine fremde Mail im Posteingang (gleiche UID, falscher Ordner). Dasselbe galt für den Anhang-Download bei weitergeleiteten Mails.

**Lösung:** `OutgoingMail.Origin` enthält jetzt ein Pflichtfeld `folder`. Die Erzeugung des Bezugs wurde aus der privaten `origin()`-Methode in `ComposeViewModel` in einen failable Initializer `Origin(composeKind:original:)` auf dem Typ selbst verlagert – eine einzige Stelle, die Postfach, Ordner und UID aus der Originalnachricht übernimmt. `markOriginal` wählt `origin.folder`, `downloadAttachment` wählt `message.folder`.

**Geänderte Dateien:**
- `Mailwerk/Services/MailSendService.swift` – Origin mit Ordner, `markOriginal` nutzt `origin.folder`
- `Mailwerk/Services/AttachmentManager.swift` – `downloadAttachment` nutzt `message.folder`
- `Mailwerk/ViewModels/ComposeViewModel.swift` – `origin()` entfernt, Aufruf durch Initializer ersetzt
- `MailwerkTests/OutgoingMailOriginTests.swift` – 5 neue Tests (Ordner aus Spam, ReplyAll, verschachtelter Ordner, neue Mail, ohne Original)

### a1b – Fehlende Mails im Abgleich nachladen (Laufzeitfund)

**Problem:** Eine im Webmail verschobene oder kopierte Mail mit altem Eingangsdatum (außerhalb der letzten 30 Tage) war in Mailwerk unsichtbar. Der Abgleich (`reconcile`) sah ihre UID auf dem Server, tat aber nichts damit, weil sein Auftrag nur „entfernen und Flags ändern" war.

**Fund:** Beim Test von a1 im Ordner „Test Mailwerk" wurde eine Mail aus 2021 hinein kopiert. Sie erschien nicht in Mailwerk, obwohl die Konsolenausgabe „Abgleich: 2 Mails im Ordner" meldete.

**Lösung:** `ServerReconciliation.Plan` enthält jetzt `missingUIDs` – die Differenz aus Server-UIDs minus Cache-UIDs (gefiltert auf ≤ `keepUIDsAbove`, sortiert aufsteigend). `MailFetchService.reconcile` ruft für diese UIDs `cacheMessages` auf, denselben Weg wie der reguläre Abruf. Keine zusätzliche IMAP-Abfrage nötig, nur ein Mengenvergleich.

**Geänderte Dateien:**
- `Mailwerk/Services/Sync/ServerReconciliation.swift` – `missingUIDs` im Plan, `isEmpty` erweitert
- `Mailwerk/Services/MailFetchService.swift` – `reconcile` lädt fehlende UIDs nach, Log erweitert
- `MailwerkTests/ServerReconciliationTests.swift` – 5 neue Tests, 1 veralteten entfernt, 1 erweitert

### a2 – Keychain-Korrektur (K2)

**Problem:** `savePassword` löschte den bestehenden Eintrag und legte ihn neu an (`SecItemDelete` + `SecItemAdd`). Das erzeugte bei jedem Speichern einen neuen iCloud-Schlüsselbund-Eintrag, der alte blieb als Leiche zurück. Außerdem fehlte in `deletePassword` das Attribut `kSecAttrSynchronizable`, sodass der synchronisierte Eintrag beim Entfernen eines Postfachs nicht gefunden und nicht gelöscht wurde.

**Lösung:** `savePassword` versucht zuerst `SecItemUpdate`; nur bei `errSecItemNotFound` wird `SecItemAdd` aufgerufen. `deletePassword` enthält jetzt `kSecAttrSynchronizable = true`. Die Query-Duplikation ist über eine gemeinsame `baseQuery(for:)` beseitigt.

**Geänderte Datei:**
- `Mailwerk/Services/KeychainService.swift` – Update statt Löschen+Neuanlegen, `baseQuery`, Synchronizable in Delete

### a3 – Dateinamen-Bereinigung und WebView-Sicherheit (K3, K4)

**Problem K3:** `writeTempFile` übernahm den MIME-Dateinamen ungeprüft. Ein manipulierter Name wie `../../Library/Caches/payload` hätte eine Datei außerhalb des Temp-Verzeichnisses ablegen können.

**Lösung:** `sanitizedFilename(_:)` nimmt den letzten Pfadbestandteil, behandelt Backslash-Pfade, entfernt führende Punkte und fällt bei leerem Ergebnis auf „Anhang" zurück.

**Problem K4:** Der Druck-WebView (`MailPrinter`) lief ohne eigene Konfiguration und konnte JavaScript aus der Mail ausführen.

**Lösung:** `MailPrinter` erzeugt jetzt eine `WKWebViewConfiguration` mit `allowsContentJavaScript = false`. Bilder und Stylesheets werden weiterhin geladen, damit der Ausdruck vollständig bleibt.

**Zusätzlich:** `AttachmentManager.cleanupTempFiles()` löscht beim App-Start das Temp-Verzeichnis `Mailwerk-Attachments`. Der Aufruf erfolgt in `MailwerkApp.init`.

**Geänderte Dateien:**
- `Mailwerk/Services/AttachmentManager.swift` – `sanitizedFilename`, `cleanupTempFiles`, Konstante `tempSubdirectory`
- `Mailwerk/Views/MailPrinter.swift` – `WKWebViewConfiguration` mit JS-Sperre
- `Mailwerk/MailwerkApp.swift` – Aufruf `cleanupTempFiles` im `init`
- `MailwerkTests/AttachmentSanitizeTests.swift` – 9 neue Tests (Traversal, absolut, Backslash, Punkte, leer, Unicode)

---

## Geänderte Dateien (Übersicht)

```
Mailwerk/
├── MailwerkApp.swift                          # cleanupTempFiles beim Start
├── Services/
│   ├── AttachmentManager.swift                # sanitizedFilename, cleanupTempFiles, Ordner-Fix
│   ├── KeychainService.swift                  # Update statt Delete+Add, Synchronizable
│   ├── MailFetchService.swift                 # reconcile lädt fehlende UIDs nach
│   ├── MailSendService.swift                  # Origin mit Ordner, markOriginal im richtigen Ordner
│   └── Sync/
│       └── ServerReconciliation.swift         # missingUIDs im Plan
├── ViewModels/
│   └── ComposeViewModel.swift                 # origin() → Origin(composeKind:original:)
└── Views/
    └── MailPrinter.swift                      # JS-Sperre im Druck-WebView
MailwerkTests/
├── AttachmentSanitizeTests.swift              # 9 neue Tests (K3)
├── OutgoingMailOriginTests.swift              # 5 neue Tests (K1)
└── ServerReconciliationTests.swift            # 5 neue, 1 entfernt, 1 erweitert (a1b)
```

11 Dateien geändert, davon 2 neue Testdateien.

---

## Inline-Dokumentation

Ab v0.1.9a gilt folgender Standard für alle gelieferten Dateien:

- **Datei-Header:** Zweck, Verarbeitung/Abgrenzung, Abhängigkeiten (nach dem Xcode-Kopf).
- **Funktionen:** DocC-kompatibler Kopfkommentar mit Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`.
- **Testfunktionen:** Kurzform – eine Zeile `///` mit Zuordnung und Zweck.
- **Sprache:** Deutsch, keine Versionsverweise im Code.

Die 11 Dateien in v0.1.9a sind nach diesem Standard dokumentiert. Die übrigen Dateien folgen in v0.1.9e.

---

## Testverfahren

**Automatisch:** 139 Tests (130 bestehende + 5 Origin + 5 Reconciliation-Missing + 9 Sanitize – 1 entfernter – 9 bereits in der Summe enthaltene Bestandstests = 139 netto). Alle ohne Warnungen.

**Manuell:**
- a1: Antwort aus „Test Mailwerk" → Markierung im richtigen Ordner (Webmail gegengeprüft).
- a1b: Alte Mail in „Test Mailwerk" kopiert → erscheint nach Aktualisierung, Konsolenausgabe „1 nachgeladen".
- a2: Passwort geändert → Schlüsselbund zeigt einen Eintrag mit aktuellem Änderungsdatum, kein zweiter.
- a3/K4: HTML-Mail mit Bildern gedruckt → Bilder im Ausdruck, kein JavaScript-Fehler.

---

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.8e.

---

## Nächste Schritte

- **v0.1.9b:** Robuster Store – Transaktions-Wrapper, atomares Speichern, UIDVALIDITY, graceful Recovery statt `fatalError`, Backup-Ausschluss.
- **v0.1.9c:** Performance – Listenmodell ohne Bodies, Preview-Spalte, Index, Zähler, HTML-Reload-Optimierung, Laufzeitmessung.
- **v0.1.9d:** Struktur und Aufräumen – gemeinsame Credentials/Verbindung, `refresh()` zerlegen, Aktionen ins ViewModel, `os.Logger`, toter Code.
- **v0.1.9e:** Inline-Dokumentation für alle übrigen Dateien.
