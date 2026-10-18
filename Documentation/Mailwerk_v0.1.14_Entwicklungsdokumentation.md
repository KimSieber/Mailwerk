# Mailwerk – Entwicklungsdokumentation v0.1.14

2026-10-14 · Fehler-Patch-Version: Gmail und Posteo, Entwürfe weiterbearbeiten (Jira MW-16, Teil 2), Formatierungsleiste, Absende-Postfach, Titelleiste

---

## Zusammenfassung

v0.1.14 war als Fehler-Patch-Version geplant. Liste zu Beginn:

1. Gmail-Fehler beim Abruf, Posteo-Fehler beim Versand
2. Entwurf-Mails weiterbearbeiten
3. Postfach-Abruf-Schalter kleiner?
4. Formatierungsleiste eleganter, nur Symbole
5. Absende-Postfach aus dem aktuellen Postfach, nur Sammelansichten nutzen das Standard-Postfach
6. Knopf der Seitenleiste rutscht immer wieder nach rechts

Umgesetzt in acht Commits, jeder mit eigenem Test:

| Paket | Inhalt | Commit |
|---|---|---|
| **1a** | Gmail-Abruf: Suche ohne SORT | `e8d0bd8` |
| **1b** | Versand: Zeilenenden CRLF (Posteo „bare &lt;LF&gt;“) | `e702f29` |
| **1c** | Verständliche Meldung bei abgelehnter SMTP-Anmeldung, Versand-Protokoll | `94f6c26` |
| **1d** | Schalter „Kopie in Gesendet ablegen“ je Postfach (Gmail-Duplikate) | `7ffc99f` |
| **2** | Entwürfe weiterbearbeiten: öffnen, wiederherstellen, alte Fassung ersetzen | `a626954` |
| **3** | Abruf-Schalter kleiner – **verworfen** (siehe unten) | – |
| **4** | Formatierungsleiste im Liquid-Glass-Stil, nur Symbole, nach Häufigkeit geordnet | `78e0777` |
| **5** | Neue Mail: Absender = Postfach des gezeigten Ordners bzw. der geöffneten Mail | `3fb52d8` |
| **6** | Seitenleisten-Knopf fest links, Ladeanzeige und Titel einheitlich in der Titelzeile | `bebadda` |

Tests: 528 → 531 (1b) → 534 (1c) → 536 (1d) → **540** (2), alle grün. `MARKETING_VERSION` 0.1.14.

---

## 1a – Gmail: Abruf scheitert mit „SORT command not supported“

**Problem:** Beim Abruf eines Gmail-Postfachs kam „Command not supported: SORT command not supported by server“. Anmeldung, Ordnerliste und Spamfilter liefen durch.

**Ursache (belegt):**
- `MailFetchService` suchte an drei Stellen mit Server-Sortierung (`search(criteria:sortCriteria: [.descending(.date)])`): Standardfenster, gekennzeichnete Mails, ältere Mails nachladen.
- Dafür braucht der Server die IMAP-Erweiterung SORT. Gmail bietet sie nicht an, manitu (Dovecot) schon.
- SwiftMail 1.15.0 prüft das vor dem Senden und bricht ab.
- Der Spamfilter suchte schon immer ohne Sortierung und lief deshalb.

**Entscheidung:** Ein Weg für alle Server statt „SORT, wenn vorhanden, sonst ohne“. Ein Weg statt zwei heißt keine Abfrage der Server-Fähigkeiten und weniger Fehlerquellen.

**Lösung:**
- Neue Hilfsfunktion `searchNewestFirst(on:criteria:calendar:)`. Sie sucht per `extendedSearch` ohne Sortierung und liest das Ergebnis von ESEARCH- und SEARCH-Servern gleich aus (`all` bzw. `ordered`). Danach ordnet sie die UIDs absteigend.
- Die Reihenfolge wird nur für das Laden der Kopfdaten in 100er-Paketen gebraucht. Die Liste sortiert sich ohnehin aus dem Cache nach Datum.

**Test:** Gmail-Abruf. Das größte manitu-Postfach in einer frischen Simulator-Installation. „Ältere Mails laden“.

---

## 1b – Posteo: Versand scheitert mit „521 5.5.2 bare &lt;LF&gt; received“

**Problem:** Mails über Posteo mit Signatur oder mehreren Zeilen wurden abgelehnt. Mit einem Bild in der Signatur kam stattdessen „connection lost (message not accepted)“.

**Ursache (belegt):**
- Meldet der Server 8BITMIME und ist der Text „8-Bit-tauglich“, übergibt SwiftMail (`Email+Content.swift`) Text- und HTML-Teil **unverändert** als `8bit`.
- Mailwerk lieferte Zeilenumbrüche als einzelnes LF. Posteo lehnt nackte LF ab, das ist sein Schutz gegen SMTP Smuggling, und schließt die Verbindung (Code 521). manitu und Gmail sind toleranter.
- Mit Bild ist die Nachricht größer. Posteo schließt dann, während Mailwerk noch überträgt, und es entsteht „connection lost“. Base64-Zeilen von Anhängen bricht SwiftMail korrekt mit CRLF um. Sie waren nicht die Ursache.

**Lösung:**
- Neu `MailLineEndings.crlf` (reine Funktion): CRLF und CR werden zu LF, dann jedes LF zu CRLF.
- `MailSendService.makeEmail` wendet sie auf Text und HTML an. Das wirkt für Versand, Gesendet-Kopie und Entwurf.

**Test:** Posteo und eigene Domain (manitu), ein- und mehrzeilig, mit einfacher Signatur und mit Bild in der Signatur. Gesendet-Kopie geprüft.

---

## 1c – Gmail-SMTP: unverständliche Meldung „NIOCore.ChannelError 5“

**Problem:** Versand und Verbindungstest bei Gmail scheiterten mit „Command failed … NIOCore.ChannelError-Fehler 5“. IMAP lief.

**Ursache (belegt, im Terminal mit `openssl s_client`):**
- Gmail nimmt `EHLO [127.0.0.1]` an.
- Auf `AUTH PLAIN` mit `name@example.com` (eigene Domain) antwortet Gmail mit `535 5.7.8 Username and Password not accepted` und **schließt sofort die Verbindung**.
- SwiftMail versucht danach auf der geschlossenen Verbindung `AUTH LOGIN`. Daraus wird `ChannelError` Fall `ioOnClosedChannel` (Code 5), und Googles Antwort geht verloren.

**Lösung des Kontos:** Google nimmt für IMAP den Kontonamen (`name@example.com`) an, für SMTP nur die Gmail-Adresse. Benutzername im Postfach daher `vorname.nachname@gmail.com`, damit funktionieren beide.

**Lösung in Mailwerk:**
- Neu `SMTPLoginFailure` mit `SMTPStep` (Verbinden, Anmelden, Senden).
- `MailSendService` und `MailConnectionTester` merken sich den erreichten Schritt.
- Scheitert erst die Anmeldung, lautet die Meldung „Anmeldung am Versandserver abgelehnt (…)“ bzw. „… der Server hat die Verbindung beendet. Meist sind Benutzername oder Passwort falsch“.
- Neuer Fall `SendError.loginRejected`, im Verbindungstest `TestError.smtpLoginRejected`.
- Protokoll (Kategorie Versand): „✉️ Versand beginnt über host:port“ und „❌ … gescheitert beim Schritt …“.

**Test:** Falscher Benutzername im Formular, Verbindungstest und Versand. Danach Versand mit richtigem Benutzernamen.

---

## 1d – Gmail: Mails doppelt im Ordner „Gesendet“

**Problem:** Gmail legt jede über seinen SMTP-Server gesendete Mail selbst in „Gesendet“ ab. Mailwerks eigene Kopie ergab ein Duplikat. Zeitweise scheiterte die Ablage der Kopie auch mit einem Timeout (siehe Beobachtungen).

**Entscheidung:**
- Keine Erkennung des Anbieters. `X-GM-EXT-1` ist eine Gmail-eigene Erweiterung, kein Standard, und wäre eine Sonderlösung.
- Stattdessen wie in anderen Mail-Programmen ein **Schalter je Postfach** im Abschnitt SMTP: „Kopie in ‚Gesendet‘ ablegen“, standardmäßig an.

**Lösung:**
- `MailAccount.storesSentCopy` (optional, `nil` = an, damit ältere gespeicherte Postfächer weiter eine Kopie ablegen), ausgewertet über `savesSentCopy`.
- Der Schalter steht in „Postfach bearbeiten“ und „Postfach hinzufügen“.
- `MailSendService.send` überspringt die Kopie, wenn er aus ist. Gespeichert wird er mit dem Postfach, also über iCloud auf allen Geräten.

**Test:** eigene Domain (an) und Gmail (aus) haben jeweils genau eine Kopie in „Gesendet“.

---

## 2 – Entwürfe weiterbearbeiten (MW-16 Teil 2)

**Konzept** aus v0.1.13 (abgestimmt). Auf Wunsch in **einem** Paket mit einem Testdurchlauf und einem Commit umgesetzt.

**Öffnen:**
- Ein Tipp auf eine Mail im Ordner „Entwürfe“ (Rolle `.drafts` aus dem Ordnerbaum) öffnet das Verfassen-Fenster statt der Leseansicht.
- `DraftComposeLoader` (neu) lädt Entwurf und Anhänge aus dem Cache. Fehlende eingebettete Bilder (Text, Signatur, Zitat) holt er über `InlineImageLoader`, fehlende Anhänge über `AttachmentManager`.
- Ohne Verbindung öffnet der Entwurf mit dem, was vorliegt.

**Wiederherstellen** (`ComposeViewModel.init(accountStore:draft:attachments:)`):
- **Absender** ist das Postfach des Entwurfs. **An, Cc, Betreff** kommen aus dem Cache.
- **Mailwerk-Entwurf** (`DraftFormat.parse`): Bcc, Art, Threading und Bezug zur Originalmail aus dem Datenblock.
  - Text vor und nach der Signatur über `RichTextImport`. `cid:`-Bilder werden zu Editor-Bildern mit derselben Content-ID.
  - Eine **einfache Signatur** steht wieder markiert im Text (`.mailwerkSignature`). Eine **HTML-Signatur** kommt als Block (`HTMLSignatureBlock.init(restoredHTML:images:)`, Logo `cid:` → `data:`). Beide bleiben beim Postfachwechsel austauschbar.
  - Das **Zitat** bleibt unverändert. Sein Text kommt aus dem Textteil des Entwurfs (`DraftFormat.quotedText`), sonst aus dem Zitat-HTML.
- **Fremde Entwürfe** (z. B. Apple Mail) kommen als Ganzes vereinfacht in den Editor.
- **Anhänge** stehen in der Liste und lassen sich entfernen.
- Fehlen Bilder, erscheint beim Öffnen der Hinweis „Entwurf geöffnet“.
- Ein unveränderter Entwurf schließt ohne Rückfrage. Die Signatur wird beim Erscheinen nicht neu eingesetzt.

**Alte Fassung ersetzen:**
- Nach dem Senden oder erneuten Sichern entfernt `DraftService.removeDraft` die alte Fassung endgültig: `\Deleted` + UID EXPUNGE, ohne UIDPLUS ein einfaches EXPUNGE, nicht über den Papierkorb.
- Danach wird sie aus dem Cache gelöscht. Scheitert das, erscheint ein Hinweis. Die neue Fassung bzw. Mail ist dann schon gesendet bzw. gesichert.

**Weitere Punkte:**
- Ein gesendeter Antwort-Entwurf setzt „Beantwortet“ an der Originalmail (`ComposeViewModel.origin(kind:draft:)` aus dem Datenblock).
- Nach Senden oder Sichern aus einem Entwurf wird der angezeigte Ordner neu abgerufen, damit die neue Fassung sofort erscheint.
- Bilder des Zitats und übernommene Anhänge stammen beim Entwurf aus dem Entwurf selbst (`contentSource`, `imageReferenceHTML`).

**Test:**
- Mailwerk- und Apple-Mail-Entwürfe öffnen, ergänzen, senden.
- Neue Entwürfe sichern, später öffnen und senden.
- Antwort-Entwurf → „Beantwortet“.
- Bcc und Anhang (Anhang sofort geladen und entfernbar).
- HTML-Signatur mit Logo.
- Erneut sichern → sofort wieder in der Liste.

---

## 3 – Abruf-Schalter kleiner (verworfen)

Auf dem iPhone hat der Standard-Schalter eine feste Größe. Kleiner geht er nur auf dem Mac (`.controlSize`). Die Alternativen bedeuten eine andere Bedienung: Schalter nur in „Postfach bearbeiten“ plus Wischaktion, oder ein Symbol-Knopf. Eine andere Bedienung war nicht gewünscht, das Thema ist verworfen.

---

## 4 – Formatierungsleiste

**Wunsch:** Texte raus, die Symbole sprechen für sich. Eleganteres Design im Sinne von iOS 26, keine Sonderlösung.

**Lösung (Standard, Liquid Glass):**
- Nur Symbole (`FormatIcon`, 40 × 36 pt Tippfläche, etwas größere Symbole).
- Gruppen als Glas-Kapseln (`GlassEffectContainer`, `.glassEffect(.regular.interactive(), in: .capsule)`). Aktive Formate sind farbig hinterlegt.
- Reihenfolge nach Häufigkeit der Nutzung: **Anhang + Link** | **Fett, Kursiv, Unterstrichen** | **Aufzählung, Nummerierung** | **Schriftgröße, Farbe**. Die letzte Gruppe ist auf dem iPhone erst nach Scrollen sichtbar.
- `FormattingToolbar` hat Plätze `leading` (Anhang, in der Gruppe mit dem Link) und `trailing` (Logo der Signatur, eigene Gruppe).
- Die Trennlinie über der Leiste im Verfassen-Fenster ist entfallen.
- Verworfen: Leiste über der Tastatur (fehlt ohne Tastatur und auf dem Mac) und Apples Formatfenster (bietet Formate, die der HTML-Rückweg nicht abbildet).

---

## 5 – Absende-Postfach einer neuen Mail

**Regel:**
- **Antworten und Weiterleiten:** Postfach der Originalmail (unverändert).
- **Neue Mail** im Ordner eines Postfachs: dieses Postfach.
- **Neue Mail** in Sammelansichten (Alle Eingänge, Mit Kennzeichnung, künftige Sammelordner): das Standard-Postfach.
- **mailto-Link** in einer geöffneten Mail: das Postfach dieser Mail.

**Hintergrund:** Wer gezielt aus einem Postfach arbeitet (z. B. mit einem Reserve-Postfach bei Posteo), soll nicht versehentlich aus einem anderen senden.

**Lösung:**
- `ComposeViewModel`/`ComposeView` nehmen `senderAccountID` an. Ein unbekanntes Postfach fällt auf das Standard-Postfach zurück.
- `InboxView` übergibt `viewModel.selection.accountID`. Nur ein einzelner Ordner nennt ein Postfach, künftige Sammelansichten fallen also automatisch unter die Standard-Regel.
- `MessageDetailView` übergibt bei mailto das Postfach der Mail.

---

## 6 – Titelleiste: Seitenleisten-Knopf und Titel

**Problem 1:** Der Knopf der Seitenleiste stand gelegentlich ganz rechts, nicht gezielt reproduzierbar.

**Ursache (wahrscheinlich, nicht belegt):** Links standen der Knopf (`.navigation`) und eine nur während des Abrufs sichtbare Ladeanzeige (`.topBarLeading`). Unter iOS 26 ordnet das System die Leiste neu, wenn Elemente kommen und gehen, und `.navigation` ist dort nur ein Wunsch.

**Lösung:**
- Knopf und „Alle auswählen“ stehen auf iPhone und iPad fest auf `.topBarLeading` (Mac: `.navigation`).
- Die Ladeanzeige steht als kleines Drehsymbol vor „Aktualisiert: …“ in der Titelzeile. Die Leiste ist damit immer gleich aufgebaut. Auf dem Mac bleibt die Ladeanzeige in der Leiste.

**Problem 2:** Der Titel stand mal mittig („Gesendet“, „Papierkorb“), mal links („Posteingang“, „Alle Eingänge“).

**Ursache (belegt am Verhalten):**
- iOS zentriert einen Titel (`.principal`) nur, solange er zwischen die Knöpfe passt. Rechts belegen zwei Knöpfe mehr Platz, und dieser Platz ist die Grenze. Darüber rückt iOS den Titel ganz nach links.
- Maßgeblich ist die breitere der beiden Zeilen. Auch „vor 2 Minuten“ statt „jetzt“ kann den Titel verschieben.

**Lösung:**
- Der Titel bekommt eine Mindestbreite: Bildschirmbreite (`onGeometryChange`) minus 200 pt für Knöpfe und Ränder (`toolbarButtonsWidth`). Damit ist er immer breiter als der zentrierte Platz und steht stets links. Titel und Standzeile sind links ausgerichtet.
- Farbpunkt und Ordnersymbol bleiben, sie dienen zur Orientierung.
- Verworfene Versuche:
  - `.frame(maxWidth: .infinity)` im `.principal`-Titel: wirkungslos, iOS gibt ihm nur die benötigte Breite.
  - Titel als `.topBarLeading`: iOS setzte zusätzlich den Fenstertitel in die Mitte, und unser Titel wurde abgeschnitten.
  - `navigationTitle` + `navigationSubtitle` (`.inlineLarge`): Punkt und Symbol entfielen.

---

## Geänderte Dateien (gesamte Version)

```
Mailwerk/
├── Models/
│   └── MailAccount.swift                  # storesSentCopy / savesSentCopy (1d)
├── Services/
│   ├── MailFetchService.swift             # searchNewestFirst (1a)
│   ├── MailLineEndings.swift              # neu (1b)
│   ├── MailSendService.swift              # CRLF (1b), Schritt/Protokoll/loginRejected (1c), Kopie optional (1d)
│   ├── MailConnectionTester.swift         # Schritt, smtpLoginRejected (1c)
│   ├── SMTPLoginFailure.swift             # neu (1c)
│   ├── Drafts/
│   │   ├── DraftFormat.swift              # quotedText (2)
│   │   └── DraftService.swift             # removeDraft (2)
│   └── Signatures/
│       └── HTMLSignatureBlock.swift       # init(restoredHTML:images:) (2)
├── ViewModels/
│   ├── AddAccountViewModel.swift          # savesSentCopy (1d)
│   └── ComposeViewModel.swift             # Entwurf wiederherstellen/ersetzen (2), senderAccountID (5)
└── Views/
    ├── AddAccountView.swift               # Schalter Gesendet-Kopie (1d)
    ├── EditAccountView.swift              # Schalter Gesendet-Kopie (1d)
    ├── ComposeView.swift                  # Entwurf-Init, Hinweise (2), Leiste (4), senderAccountID (5)
    ├── DraftComposeLoader.swift           # neu (2)
    ├── FormattingToolbar.swift            # Liquid Glass, FormatIcon, Reihenfolge (4)
    ├── SignatureEditorView.swift          # Leiste mit Logo-Gruppe (4)
    ├── InboxView.swift                    # Entwurf öffnen, Ordner neu abrufen (2), Absender (5), Titelleiste (6)
    └── MessageDetailView.swift            # mailto-Absender (5)
MailwerkTests/
├── MailLineEndingsTests.swift             # neu, 3 Tests (1b)
├── SMTPLoginFailureTests.swift            # neu, 3 Tests (1c)
├── SentCopySettingTests.swift             # neu, 2 Tests (1d)
└── DraftRestoreTests.swift                # neu, 4 Tests (2)
```

---

## Testverfahren

**Automatisch:** **540 Tests** (Simulator), alle grün. Reine Logik zusätzlich unter Linux (Swift 6.2) vorab geprüft: `MailLineEndings`, `SMTPLoginFailure`, `MailAccount` (Kodierung), `DraftFormat.quotedText`.

**Manuell**, Mails nur an sich selbst:
- Gmail-Abruf (Posteingang, Spam-Ordner).
- Größtes manitu-Postfach in frischer Simulator-Installation.
- Versand über Posteo und eigene Domain, ein- und mehrzeilig, mit Signatur und Logo.
- Gmail-Versand mit falschem und richtigem Benutzernamen.
- Gesendet-Kopie an/aus.
- Entwürfe (siehe Paket 2).
- Formatierungsleiste im Verfassen-Fenster und bei der Signatur.
- Absende-Postfach aus Ordnern, Sammelansichten und mailto.
- Titelleiste in allen Ansichten.

---

## Beobachtungen

- **Sporadischer Timeout bei Gmail (IMAP):** „Operation timed out“ beim Spam-Ordner in der Abrufrunde und einmal bei der Gesendet-Kopie, nie beim manuellen Öffnen.
  - Der zeitliche Abstand (≈ 6,5 s nach der vorigen Verbindung) passt zu SwiftMails 5-Sekunden-Wartezeit auf die Server-Begrüßung, wenn Google eine schnell folgende Verbindung verzögert. Belegt ist das nicht.
  - Seit 1d (keine eigene Gesendet-Kopie bei Gmail) seltener. Die eigentliche Lösung wäre H6 (Verbindung je Postfach wiederverwenden).
  - Tritt er erneut auf, Zeilen mit Zeitstempel sichern.
- **Gmail-Anmeldename:** IMAP akzeptiert den Google-Kontonamen, SMTP nur die Gmail-Adresse. Als Benutzername die Gmail-Adresse eintragen.
- **Gmail-Ordner:** Sonderordner liegen unter dem Behälter `[Gmail]`, Mailwerk zeigt ihn ausgegraut. Spam-Ordner `[Gmail]/Spam` per SPECIAL-USE erkannt.
- **Simulator nach Neuinstallation:** Postfächer (iCloud-Key-Value-Speicher) bleiben. Abruf-Schalter (UserDefaults) und lokaler SwiftData-Speicher gehen verloren. Signaturen kommen über CloudKit zurück, sofern der Simulator-iCloud sie hatte. Auf echten Geräten unkritisch.
- **Xcode-Konsole:** Nur Mailwerk-Zeilen mit dem Filter `subsystem:de.sieber-bw.Mailwerk`. Zum Kopieren mit Zeitstempel eignet sich die App **Konsole** auf dem Mac.
- **Simulator-Tastatur** hängt gelegentlich: Hardware-Tastatur aus und wieder ein (⇧⌘K) statt Neustart.

## Nächste Schritte

- **v0.1.15 – Teilen mit Mailwerk** (Share Extension, MW-15), danach **v0.1.16 – Suche** (MW-6).
- Offen aus dieser Version:
  - Timeout-Beobachtung bei Gmail weiter verfolgen, ggf. mit H6.
  - Vor dem Live-Gang das CloudKit-Schema nach Production übertragen.
