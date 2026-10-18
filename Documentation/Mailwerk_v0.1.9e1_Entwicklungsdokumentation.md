# Mailwerk – Entwicklungsdokumentation v0.1.9e1

2026-10-11 · Externe Inhalte in HTML-Mails, vertrauenswürdige Absender, Zitat ohne Regex-Filter (Review-Befund M5) – Code-Review Teil 8

---

## Zusammenfassung

Befund M5 aus dem Code-Review in drei Schritten mit je eigenem Commit:

- **e1a (`2785a45`):** Externe Inhalte (Bilder, Stylesheets, Schriften von fremden Servern) werden gesperrt. Ein schmaler Hinweis mit Knopf „Laden“ gibt sie je Mail frei. Drucken und Teilen folgen der Anzeige.
- **e1b (`7ed8661`, Dateiname korrigiert in `bc0c15e`/`d014020`):** Absender auf der Whitelist laden sofort, mit derselben Score-Obergrenze wie der Spamfilter. Dafür speichert der Cache die Spam-Einstufung des Servers je Mail (Schema-Stufe 4).
- **e1c:** Das Zitat beim Antworten und Weiterleiten übernimmt das Original unverändert. Der Regex-Filter entfällt, nur die Hüllen-Tags des Dokuments werden entfernt.

**Entschieden:**
- Mechanismus: Content-Security-Policy im Kopf des Grundgerüsts statt `WKContentRuleList`.
- Freigabe per Knopf gilt nur für die aktuelle Anzeige, keine eigene Liste.
- Whitelist-Absender laden sofort. Domain-Einträge zählen mit, und die Score-Obergrenze aus den Einstellungen gilt wie bei der Spam-Beurteilung. Das Restrisiko (gefälschter Absender unter der Obergrenze) ist bewusst eingegangen. Das gilt auch bei ausgeschaltetem Spamfilter.
- Drucken und Teilen folgen dem Zustand der Anzeige.
- Antworten und Weiterleiten verändern das HTML des Originals nicht. Externe Bilder, `<style>` und alles andere bleiben drin; der Empfänger behandelt externe Inhalte selbst.
- Kein Parser und kein neues Paket.
- `Spamclassifier.swift` heißt jetzt `SpamClassifier.swift`.

Tests: 360 → **382**, alle grün.

---

## e1a – Externe Inhalte sperren

**Problem:** `HTMLMailView` sperrte Navigation und JavaScript. Bilder, Stylesheets und CSS-`url(…)` sind aber keine Navigation und wurden ungefragt geladen. Tracking-Pixel verrieten Lesezeitpunkt und IP-Adresse. `MailPrinter` lud externe Bilder beim Drucken ebenfalls bewusst nach.

**Lösung:**
- **`RemoteContentPolicy` (neu):**
  - `headTags(allowsRemoteContent:)` liefert die CSP-Zeile und schaltet die DNS-Vorabfrage für Links ab.
    - Gesperrt: `default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; media-src data:; form-action 'none'; base-uri 'none'`
    - Freigegeben: zusätzlich `https:`/`http:` für Bilder, Stile, Schriften und Medien. Skripte und Frames bleiben verboten.
  - `containsRemoteReferences(_:)` erkennt externe Verweise (`src`, `background`, `poster`, `srcset`, CSS-`url(…)`, `@import`, `<link href>`). Das entscheidet nur über die Anzeige des Knopfs; geschützt wird allein durch die CSP.
- **`HTMLMailView`:**
  - Neuer Parameter `allowsRemoteContent` und `document(for:allowsRemoteContent:)` für das Grundgerüst.
  - Neu geladen wird bei geändertem HTML **oder** geänderter Freigabe.
  - Die Zitat-Vorschau im Verfassen-Fenster bleibt immer gesperrt.
- **`MessageDetailView`:** Hinweis „Externe Inhalte blockiert“ mit kleinem Knopf **Laden**, nur bei Mails mit externen Verweisen. Nach der Freigabe wird die Datei zum Teilen neu geschrieben.
- **`MailPrintFormatter`:** gleiche CSP im Dokument für Druck und Teilen. Sie gilt auch, wenn der Empfänger die geteilte Datei im Browser öffnet.

## e1b – Vertrauenswürdige Absender laden sofort

**Problem:** Die Score-Obergrenze braucht die Spam-Einstufung des Servers. Die las bisher nur der Spamfilter-Lauf und hielt sie nicht im Cache.

**Lösung – Lieferung 1, Spam-Angabe im Cache:**
- **`CachedMessageHeaders.spamVerdict`:** `nil` heißt „unbekannt“ und ist ausdrücklich etwas anderes als „kein Spam“.
- **`MailFetchService`:** Die Kopfdaten-Abfrage holt `X-Spam`/`X-Spam-Status` mit (`SpamHeaderParser.fieldNames`), ohne zusätzliche Server-Abfrage. Ausgewertet wird über `additionalHeaderFields`, damit eine gefälschte zweite Statuszeile die Einstufung nicht senken kann.
- **`MessageStore`:**
  - Schema-Stufe 4 mit den Spalten `spamFlag` (NULL = unbekannt) und `spamScore`.
  - Header-Version 2: Mails im Cache werden nachgefüllt, sobald ein Abruf sie ohnehin abfragt.

**Lösung – Lieferung 2, Entscheidung in der Anzeige:**
- **`SpamClassifier`:**
  - Gemeinsamer Listenabgleich `listMatch`: Adresse vor Domain, auf jeder Stufe Whitelist vor Blacklist.
  - `classify` (Filterlauf) und das neue `trustsSender` (Anzeige) nutzen ihn beide; die Regel steht nur einmal.
  - `trustsSender` vertraut nur bei Whitelist-Treffer mit bekannter Einstufung, unter derselben Score-Obergrenze.
- **`SpamFilterService.trustsRemoteContent(of:scoreLimit:)`:** gibt die aktuellen Listen dazu. Sind sie nicht lesbar, wird nicht vertraut.
- **`MessageDetailView`:**
  - Entscheidet einmal je Anzeige, **bevor** der HTML-Inhalt erscheint. Nichts wird doppelt geladen.
  - Eine Freigabe per Knopf bleibt erhalten, wenn die Aufgabe erneut läuft.
  - `InboxView` reicht die Score-Obergrenze durch.
- **Dateiname:** `Spamclassifier.swift` → `SpamClassifier.swift`. Git auf macOS erfasst reine Groß-/Kleinschreibungs-Änderungen nicht, deshalb war die Umbenennung über einen Zwischennamen in zwei Commits nötig.

## e1c – Zitat unverändert übernehmen

**Problem:**
- `ReplyBuilder.sanitizedBodyContent` filterte Skripte, Event-Handler und `javascript:` per Regex. Das war lückenhaft (z. B. `<svg/onload=…>`, Entities in `javascript:`) und veränderte die Mail.
- Ein Schutz war dort ohnehin unnötig:
  - In Mailwerk erscheint das Zitat nur über `HTMLMailView` (kein JavaScript, keine Navigation, externe Inhalte gesperrt).
  - Beim Empfänger schützt dessen Mailprogramm.

**Lösung:** `withoutDocumentWrapper(_:)` entfernt nur DOCTYPE sowie Start- und End-Tags von `html`, `head` und `body`, an jeder Stelle. Inhalt wird nie ausgeschnitten.

**Korrektur im Test:** Die erste Fassung übernahm nur den Inhalt von `<body>`. Bei einer Sunweb-Mail fehlten im Zitat daraufhin Logo, Buchungsnummer, Fußbereich und Schriftangaben, und damit auch der Knopf „Laden“.
- **Ursache, belegt am Quelltext:** Die Mail ist ein Fragment mit einem vollständigen zweiten Dokument mittendrin. Ein Browser übergeht die falschen Tags, das Ausschneiden schnitt Kopf- und Fußbereich ab.
- **Lösung:** nur die Tags entfernen. Das entspricht dem Verhalten des Browsers.
- **Folge:** Stile aus dem `<head>` bleiben im Zitat erhalten, wie in der Anzeige des Originals.

## Inline-Doku

Alle berührten Dateien haben einen vollständigen Kopf und DocC je Funktion, Testfunktionen eine `///`-Zeile. Neu vollständig dokumentiert sind `CachedMessage`, `SpamHeaderParser`, `SpamClassifier`, `ReplyBuilder`, `SpamClassifierTests` und `ReplyBuilderTests`; diese entfallen aus der Liste für Stufe f.

---

## Geänderte Dateien

```
Mailwerk/
├── Models/
│   └── CachedMessage.swift                    # spamVerdict, Doku (e1b)
├── Services/
│   ├── RemoteContentPolicy.swift              # neu (e1a)
│   ├── MailPrintFormatter.swift               # CSP je Freigabe (e1a)
│   ├── MailFetchService.swift                 # Spam-Kopfzeilen mitholen (e1b)
│   ├── MessageStore.swift                     # Schema-Stufe 4, Header-Version 2 (e1b)
│   ├── ReplyBuilder.swift                     # withoutDocumentWrapper, Doku (e1c)
│   └── Spam/
│       ├── SpamClassifier.swift               # umbenannt, listMatch, trustsSender (e1b)
│       ├── SpamFilterService.swift            # trustsRemoteContent (e1b)
│       └── SpamHeaderParser.swift             # Doku (e1b)
└── Views/
    ├── HTMLMailView.swift                     # CSP, allowsRemoteContent (e1a)
    ├── InboxView.swift                        # Score-Obergrenze durchreichen (e1b)
    ├── MailPrinter.swift                      # Kommentar (e1a)
    └── MessageDetailView.swift                # Hinweis/Knopf (e1a), Whitelist-Entscheidung (e1b)
MailwerkTests/
├── RemoteContentPolicyTests.swift             # neu: 8 Tests (e1a)
├── MailPrintFormatterTests.swift              # +2 Tests (e1a)
├── MessageStoreSpamVerdictTests.swift         # neu: 4 Tests (e1b)
├── MessageStoreListTests.swift                # Schema-Stufe 4 (e1b)
├── MessageStoreSyncTests.swift                # Schema-Stufe 4 (e1b)
├── MessageStoreTransactionTests.swift         # Schema-Stufe 4 (e1b)
├── SpamClassifierTests.swift                  # +6 Tests, Doku (e1b)
└── ReplyBuilderTests.swift                    # Zitat-Tests ersetzt/ergänzt, Doku (e1c)
```

---

## Testverfahren

**Automatisch:** 382 Tests (Simulator), alle grün.

**e1a:**
- Simulator: Newsletter in „Test Mailwerk“ zeigt den Hinweis, die Bilder fehlen, die Mail ist bis zum Ende sichtbar (Höhenmessung läuft unter der CSP). Nach **Laden** sind die Bilder da; erneutes Öffnen sperrt wieder.
- Drucken ohne und mit Freigabe: Bilder fehlen bzw. sind da.
- Zitat-Vorschau beim Weiterleiten: gesperrt, ohne Knopf.
- Mac: Hinweis, Laden, vollständige Anzeige.

**e1b:**
- Frische Installation im Simulator, größtes Postfach: „🔄 Refresh fertig. Fehler: 0, Nachrichten gesamt: 283“.
- Mac mit bestehender Installation: Migration auf Stufe 4 ohne Fehler. Beim ersten Abruf „2 Header nachgefüllt“, beim zweiten 0.
- Whitelist-Adresse und -Domain laden sofort, alle anderen zeigen den Knopf (Simulator). Auf dem Mac lädt eine neu hineinkopierte Mail eines Whitelist-Absenders sofort, eine ältere zeigt den Knopf (unbekannte Einstufung).

**e1c:**
- Antwort an sich selbst auf die Sunweb-Mail: Zitat mit Logo-Platzhalter, Buchungsnummer, Originalschrift und Fußbereich. Hinweis und **Laden** funktionieren.
- Weiterleitung einer Apple-Rechnung: Gestaltung erhalten, Hinweis und Knopf vorhanden.

---

## Beobachtungen

- **Nachfüllen nur bei abgefragten Mails:** Seit dem Sync-Zustand je Ordner fragt ein Abruf nur neu angekommene Mails ab. Auf bestehenden Installationen bleiben ältere Mails ohne Spam-Angabe und zeigen auch bei Whitelist-Absendern den Knopf. Das ist bewusst hingenommen: Alle Installationen sind Testinstallationen, echte beginnen frisch. „Unbekannt“ führt nie zu sofortigem Laden.
- **Fragmentierte HTML-Mails:** Mails mit eingebettetem zweitem Dokument kommen vor (Sunweb). Jede Verarbeitung von Mail-HTML muss wie ein Browser tolerant sein, statt an Tags auszuschneiden.
- **Dateinamen nur in der Schreibweise ändern:** braucht unter macOS zwei Commits über einen Zwischennamen.

## Funde (Liste offener Punkte, nicht v0.1.9)

- Eingebettete Bilder (`cid:`) werden nicht gespeichert und erscheinen als fehlendes Bild.
- Dunkelmodus: HTML-Mails mit eigenem weißem Hintergrund, aber ohne eigene Textfarbe erscheinen hellgrau auf weiß (z. B. Sunweb auf dem Mac).

## Nächste Schritte

- e3: Funde aus e2 (Trennzeichen in `FolderTreeBuilder`, toter Code `InboxMessage`, Zahlentastatur für Ports, Entscheidung N13).
- f: Inline-Doku für die übrigen Dateien.
- Abschluss v0.1.9: Diskussion M6.
