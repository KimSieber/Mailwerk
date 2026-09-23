# Mailwerk – Entwicklungsdokumentation v0.1.4

2026-09-23 · Commit-Stand vor Übergang auf 0.1.5

---

## Zusammenfassung

Version 0.1.4 bringt den **SMTP-Versand** und damit den letzten großen Baustein aus MVP1: Neue Nachricht, Antworten, Allen antworten und Weiterleiten – inklusive Cc/Bcc, Adressvervollständigung aus den Systemkontakten, formatierbarem HTML-Editor und eigenen Anhängen.

Versendet wird in drei Schritten: SMTP-Versand, Ablage einer Kopie im Gesendet-Ordner per IMAP APPEND und Markierung der Originalmail als beantwortet (`\Answered`) bzw. weitergeleitet (`$Forwarded`). Schlagen Schritt 2 oder 3 fehl, ist die Nachricht trotzdem versendet – der Nutzer bekommt dann einen Hinweis statt einer Fehlermeldung, damit er nicht versehentlich ein zweites Mal sendet.

Sicherheitsseitig wurde eine ernste Lücke geschlossen: Verbindungen entstehen jetzt ausschließlich verschlüsselt (siehe `MailServerFactory`). Zuvor hätte SwiftMail auf Port 587 STARTTLS nur genutzt, *wenn der Server es anbietet* – ein Angreifer im selben Netz hätte das Angebot unterdrücken und das Passwort im Klartext mitlesen können.

Zusätzlich wurden mehrere verdeckte Fehler im SQLite-Cache behoben, die bisher nur deshalb nicht aufgefallen waren, weil keine Neuinstallation getestet wurde (siehe Bugfixes).

---

## Projektstruktur (Änderungen gegenüber v0.1.3)

```
Mailwerk/
├── Models/
│   ├── MailAccount.swift               # + senderName; imapUseTLS/smtpUseTLS entfernt
│   ├── MailAddress.swift               # NEU – Adresse mit optionalem Namen (Parsing, Validierung)
│   ├── CachedMessage.swift             # + isAnswered, isForwarded, CachedMessageHeaders
│   ├── AccountColor.swift              # unverändert
│   └── InboxMessage.swift              # unverändert (nicht aktiv genutzt)
├── ViewModels/
│   ├── AddAccountViewModel.swift       # + senderName
│   ├── ComposeViewModel.swift          # NEU – Zustand/Ablauf des Verfassen-Fensters
│   └── InboxViewModel.swift            # unverändert
├── Views/
│   ├── AccountListView.swift           # + Standard-Postfach-Auswahl, Fehler beim Löschen
│   ├── AddAccountView.swift            # + Absendername, Fehlerbehandlung beim Speichern
│   ├── EditAccountView.swift           # + Absendername, Fehlerbehandlung beim Speichern
│   ├── ComposeView.swift               # NEU – Verfassen-Fenster
│   ├── RecipientField.swift            # NEU – An/Cc/Bcc mit Chips und Kontaktvorschlägen
│   ├── FlowLayout.swift                # NEU – umbrechendes Layout für die Chips
│   ├── RichTextEditor.swift            # NEU – UITextView/NSTextView-Wrapper + RichTextController
│   ├── FormattingToolbar.swift         # NEU – Formatierungsleiste
│   ├── InboxView.swift                 # + Verfassen-Knopf, Antwort-/Weiterleiten-Symbole
│   ├── MessageDetailView.swift         # + Antworten/Allen antworten/Weiterleiten, Cc-Anzeige
│   ├── ColorPickerGrid.swift           # unverändert
│   ├── AttachmentRow.swift             # unverändert
│   └── HTMLMailView.swift              # unverändert
├── Services/
│   ├── MailServerFactory.swift         # NEU – einzige Stelle für IMAP/SMTP-Verbindungen, TLS-Pflicht
│   ├── MailSendService.swift           # NEU – Versand, Gesendet-Kopie, Flag-Markierung
│   ├── ReplyBuilder.swift              # NEU – Vorbelegung für Antwort/Weiterleitung
│   ├── RichTextHTML.swift              # NEU – formatierter Text → HTML + Nur-Text
│   ├── RecipientInput.swift            # NEU – Zerlegen von Adresseingaben
│   ├── ContactSuggestionService.swift  # NEU – Kontaktvorschläge (CNContactStore)
│   ├── AccountStore.swift              # + Standard-Postfach, Main-Thread-Sicherheit
│   ├── MessageStore.swift              # + Migrationen, Header-Spalten, Bugfixes
│   ├── MailFetchService.swift          # + Threading-Header, \Answered/$Forwarded
│   ├── MailActionService.swift         # Verbindung über MailServerFactory
│   ├── MailConnectionTester.swift      # Verbindung über MailServerFactory, Leck geschlossen
│   ├── AttachmentManager.swift         # Verbindung über MailServerFactory
│   └── KeychainService.swift           # unverändert
├── MailwerkApp.swift
└── ContentView.swift

MailwerkTests/
├── ReplyBuilderTests.swift             # NEU – 19 Tests
├── RecipientInputTests.swift           # NEU – 6 Tests
└── RichTextHTMLTests.swift             # NEU – 10 Tests
```

---

## Erledigte Schritte (v0.1.4)

### Standard-Postfach (Schritt 2)

- `AccountStore` verwaltet `defaultAccountID` im `NSUbiquitousKeyValueStore` (geräteübergreifend).
- `setDefaultAccount(_:)` ignoriert unbekannte IDs; beim Löschen des Standard-Postfachs wird die Einstellung automatisch zurückgesetzt.
- Auswahl über ein Menü am Ende der Postfach-Liste inklusive Option „Keins".
- Externe iCloud-Änderungen werden jetzt auf dem Main-Thread übernommen (vorher wurde `@Observable`-State aus einem Hintergrund-Thread geändert).

### Cache-Erweiterung und Flags (Schritt 3 + 4a)

- `CachedMessage` erhält `isAnswered`, `isForwarded` und `headers: CachedMessageHeaders`.
- `CachedMessageHeaders` speichert An-, Cc- und Reply-To-Listen als JSON-Arrays sowie Message-ID, In-Reply-To und References.
- Neue Spalten per Migration: `isAnswered`, `isForwarded`, `toJSON`, `ccJSON`, `replyToJSON`, `rfcMessageID`, `rfcInReplyTo`, `rfcReferences`, `headersVersion`.
- `headersVersion` markiert, welche Nachrichten die neuen Felder schon haben. Bereits gecachte Mails werden beim nächsten Refresh aus den ohnehin geladenen Headern nachgefüllt – ohne zusätzliche Netzwerklast.
- `MailFetchService` fordert zusätzlich den `References`-Header an und wertet `\Answered` sowie das Keyword `$Forwarded` aus.
- Die Inbox zeigt beantwortete und weitergeleitete Mails mit eigenem Symbol. **TD-4 ist damit vollständig geschlossen.**

### TLS-Pflicht (Schritt 4b)

- Neue `MailServerFactory` ist die einzige Stelle, die `IMAPServer`/`SMTPServer` erzeugt.
- Port 993/465: TLS ab dem ersten Byte. Alle anderen Ports: STARTTLS ist Pflicht, sonst bricht die Verbindung ab, bevor Zugangsdaten gesendet werden.
- Zertifikate werden vollständig geprüft, Mindestversion TLS 1.2.
- Die ungenutzten Felder `imapUseTLS`/`smtpUseTLS` in `MailAccount` sind entfallen.

### Absendername (Schritt 4c)

- `MailAccount.senderName` (optional) erscheint beim Empfänger vor der Adresse.
- Klare Trennung in den Formularen: „Bezeichnung" ist die interne Anzeige in Mailwerk, „Absendername" geht nach außen.
- `MailAccount.normalized(_:)` macht aus leeren bzw. reinen Leerzeichen-Eingaben `nil`.

### Versand-Logik (Schritt 4d)

- `MailAddress`: Adresse mit optionalem Namen, Parsing formatierter Adressen (auch `"Sieber, Kim" <…>`), Validierung, Vergleich ohne Groß-/Kleinschreibung.
- `ReplyBuilder`: Betreff-Präfixe (`Re:`/`Fwd:`, erkennt AW:, WG:, RE[2]: usw.), Empfängerermittlung, Threading-Header, Zitat bzw. weitergeleiteter Inhalt.
- `MailSendService`: Versand, Gesendet-Kopie mit Bcc-Header, Markierung der Originalmail, verständliche Fehlermeldungen. Bei unklarem Versandstatus (`unsafeToRetry`) wird ausdrücklich vor einem zweiten Versand gewarnt.
- Größenlimit des Servers (`SIZE`) wird vor dem Versand geprüft.

### Empfängerfelder (Schritt 5)

- `RecipientField`: Chips, Vorschläge, Tastaturbedienung (Enter übernimmt den hervorgehobenen Vorschlag, Pfeiltasten wechseln, Escape blendet aus), Tap auf einen Chip zeigt die Adresse.
- `RecipientInput`: Zerlegen an Komma/Semikolon außerhalb von Anführungszeichen und spitzen Klammern, Dublettenprüfung, ungültige Eingaben bleiben als roter Chip erhalten.
- `ContactSuggestionService`: Suche über Name und – sobald ein `@` getippt wurde – über die Adresse. Läuft außerhalb des Haupt-Threads.
- `FlowLayout`: umbrechendes Layout, begrenzt jedes Element auf die Zeilenbreite.

### HTML-Editor (Schritt 6)

- `RichTextEditor` kapselt `UITextView` (iOS) bzw. `NSTextView` (macOS) auf Basis von TextKit 2.
- `RichTextController` steuert Fett, Kursiv, Unterstrichen, drei Schriftgrößen, Textfarbe, Aufzählung und nummerierte Liste – und meldet den Zustand an der Cursorposition zurück.
- `RichTextHTML` erzeugt schlankes HTML mit Inline-Styles sowie die Nur-Text-Fassung (Listen werden dort als „•" bzw. „1." ausgeschrieben).

### Verfassen-Fenster (Schritt 7a)

- `ComposeView` + `ComposeViewModel`: Absenderauswahl, An/Cc immer sichtbar, Bcc auf Knopfdruck, Betreff, Anhänge, Editor mit Formatierungsleiste, zitierter Originaltext schreibgeschützt in einem aufklappbaren Bereich.
- Anhänge: Dateien über den Dateiauswahl-Dialog, Fotos über den System-Picker. Beim Weiterleiten werden die Anhänge der Originalmail übernommen; noch nicht geladene werden beim Senden nachgeholt.
- Einstiegspunkte: Stift-Knopf in der Inbox; in der Detailansicht ein Antwort-Knopf (Tap = Antworten, langes Drücken = alle drei Varianten) sowie dieselben Einträge im Drei-Punkte-Menü.
- Die Rückfrage „Entwurf verwerfen?" erscheint nur, wenn tatsächlich etwas geändert wurde – eine reine Vorbelegung zählt nicht.

---

## Getroffene Architektur- & Design-Entscheidungen (v0.1.4)

| Entscheidung | Begründung |
|---|---|
| **Standard-Postfach statt „zuletzt verwendet"** | Vorhersehbar und selbst bestimmt. Ohne Standard bleibt der Absender leer und muss bewusst gewählt werden. |
| **Auswahl über ein Menü in der Postfach-Liste** | Zeigt die Einfachauswahl und die Option „Keins" von selbst. Ein Schalter je Postfach wäre versteckt und würde den Wechsel verschleiern. |
| **Bei Antwort/Weiterleitung das Postfach des Originals, änderbar** | Entspricht Apple Mail. Der Regelfall ist vorbelegt, der Sonderfall bleibt mit einem Tap erreichbar. |
| **Nur die Adresse des antwortenden Postfachs bei „Allen antworten" entfernen** | Erste Fassung entfernte *alle* eigenen Adressen – bei mehreren eigenen Postfächern blieben dadurch echte Empfänger auf der Strecke. |
| **Zentrale `MailServerFactory` statt Verbindungsaufbau an fünf Stellen** | Eine Stelle entscheidet über Verschlüsselung. Eine unverschlüsselte Verbindung kann konstruktiv nicht mehr entstehen. |
| **STARTTLS als Pflicht statt „falls angeboten"** | Verhindert das Unterdrücken des STARTTLS-Angebots durch einen Angreifer im selben Netz (Downgrade). |
| **Kürzere SMTP-Zeitlimits (60/120 s) statt RFC-Vorgabe (bis 10 min)** | In einer interaktiven App muss ein hängender Server zu einer klaren Meldung führen, nicht zu minutenlangem Warten. |
| **Message-ID einmal erzeugen, für Versand und Gesendet-Kopie** | Vermeidet Dubletten und hält Versand und Kopie eindeutig verknüpft. |
| **Bcc nur in der Gesendet-Kopie** | Im Versand darf Bcc nicht im Kopf stehen; in der eigenen Kopie ist die Information dagegen nützlich (wie bei Apple Mail). |
| **Fehler nach erfolgreichem Versand als Warnung, nicht als Fehler** | Die Nachricht ist raus. Eine Fehlermeldung würde zu einem zweiten Versand verleiten. |
| **Originalmail wird beim Antworten nicht in den Editor übernommen** | Eine Umwandlung von HTML in den Editor wäre verlustbehaftet. Das Original bleibt unverändert und wird beim Senden als Zitat angehängt. |
| **Adresslisten als JSON-Array im Cache** | Ein komma-getrennter String wäre nicht eindeutig zerlegbar, weil Namen selbst Kommas enthalten („Sieber, Kim"). |
| **Eigener HTML-Serializer statt Apples HTML-Export** | Apples Export erzeugt aufgeblähtes Markup mit Stylesheet im Kopf. Inline-Styles werden von Mail-Programmen zuverlässiger dargestellt. |
| **Immer HTML *und* Nur-Text senden (multipart/alternative)** | Kein Umschalter in der Oberfläche nötig; reine HTML-Mails werden von Spam-Filtern wie rspamd schlechter bewertet. |
| **Formatvorlage `{decimal}.` für nummerierte Listen** | Das eingebaute Format erzeugt nur die nackte Ziffer ohne Punkt. |
| **Nativer Textsystem-Wrapper statt WebView-Editor** | Eine Codebasis für iOS und macOS, keine JavaScript-Brücke, keine externe Abhängigkeit. |
| **Kontakte-Berechtigung erst beim ersten Antippen eines Adressfelds** | Kein Berechtigungsdialog beim App-Start. Ohne Berechtigung bleibt das Feld voll benutzbar, nur ohne Vorschläge. |
| **Kontakte werden nie gespeichert** | Nur Live-Abfrage; kein Cache, keine Übertragung. |
| **Basisschema + Migrationen statt vollständigem `CREATE TABLE`** | Garantiert identische Spaltenreihenfolge auf Neu- und Bestandsinstallationen. |

---

## Bugfixes (v0.1.4)

| Fund | Wirkung | Behebung |
|---|---|---|
| **`isFlagged` doppelt im `CREATE TABLE`** | Auf einer **Neuinstallation** wäre die Tabelle nie angelegt worden – der Fehler wurde von `exec` still geschluckt. Bestandsinstallationen waren nicht betroffen. | Basisschema v0.1.0 + Migrationen |
| **`SELECT *` mit festen Spaltennummern** | Frisch angelegte und migrierte Datenbanken hätten unterschiedliche Spaltenreihenfolgen → vertauschte Werte | Explizite Spaltenliste |
| **Text/Blobs ohne Kopie an SQLite übergeben** | Möglicher Zugriff auf bereits freigegebenen Speicher | `SQLITE_TRANSIENT` |
| **UID als `Int32`** | Absturz bei UIDs über 2,1 Mrd. | 64-Bit-Bindung |
| **Gemeinsame SQLite-Verbindung aus parallelen Tasks** | Nicht definiertes Verhalten bei gleichzeitigen Zugriffen | `SQLITE_OPEN_FULLMUTEX` |
| **Mehrfachlöschung von Postfächern über Indizes** | Nach dem ersten Löschen verschieben sich die Indizes → falsches Postfach getroffen | Konten vorher ermitteln |
| **`MailConnectionTester` schloss die Verbindung bei fehlgeschlagenem Login nicht** | Offene Verbindungen bis zum Server-Timeout | `disconnect()` im Fehlerpfad |
| **`CNContactFormatter` ohne vollständige Feldliste** | Absturz (`CNPropertyNotFetchedException`) beim ersten Kontakttreffer | `descriptorForRequiredKeys(for:)` mit anfordern |
| **Cc-Empfänger in der Detailansicht nicht sichtbar** | Cc-Angaben lagen im Cache, wurden aber nicht dargestellt | Zeile „Kopie:" ergänzt |
| **Fokus nach Enter im Adressfeld verloren** | Nach jedem Chip musste neu ins Feld getippt werden | Eingabetaste bei Hardware-Tastatur selbst behandeln (`onKeyPress(.return)`) |
| **Verwerfen-Rückfrage bei unveränderter Antwort** | Rückfrage, obwohl nichts verloren gehen konnte | Vergleich mit dem Ausgangszustand der Vorbelegung |

---

## Tests

| Testdatei | Tests | Inhalt |
|---|---|---|
| `ReplyBuilderTests.swift` | 19 | Betreff-Präfixe, Empfängerermittlung, Threading-Header, Zitat, HTML-Bereinigung |
| `RecipientInputTests.swift` | 6 | Zerlegen von Eingaben, Anführungszeichen, ungültige Adressen, Dubletten |
| `RichTextHTMLTests.swift` | 10 | Absätze, Maskierung, Zeichenformate, Listen, Nur-Text-Fassung |

Manuell geprüft: Versand mit und ohne Anhänge, Antworten, Allen antworten (auch zwischen eigenen Postfächern), Weiterleiten inkl. Anhängen, Bcc, Gesendet-Kopie, Flag-Markierung von Originalmails, Kontaktvorschläge.

---

## Bekannte Technical Debts / Offene Nacharbeiten

| # | Bereich | Beschreibung | Priorität | Status |
|---|---|---|---|---|
| TD-1 | Postfach-UI | ~~`try?` beim Speichern/Löschen/Aktualisieren von Accounts~~ | ~~Mittel~~ | **Erledigt (v0.1.4)**: Fehler werden in `AccountListView`, `AddAccountView` und `EditAccountView` angezeigt |
| TD-2 | IMAP-Verbindung | Kein Connection-Pooling/IDLE, für jeden Refresh und jede Aktion neue Verbindung | Niedrig | Offen (geplant für 0.4.x) |
| TD-3 | Cache-Sync | Kein Abgleich bei serverseitiger Löschung/Verschiebung – Mail bleibt dauerhaft im Cache | Mittel | Offen (aus v0.1.0) |
| TD-4 | Cache-Flags | ~~Nur `isUnread`/`\Flagged` wurden synchronisiert~~ | ~~Mittel~~ | **Erledigt (v0.1.4)**: `\Answered` und `$Forwarded` werden synchronisiert und angezeigt |
| TD-7 | Inbox-UI | `ContentUnavailableView` ist nicht scrollbar → Pull-to-Refresh greift im leeren Zustand nicht | Mittel | Offen (aus v0.1.1) |
| TD-8 | Erster Abruf | Erstabruf dauert ca. 4–6 Minuten bei 300 Mails (Body-Download pro Mail) | Niedrig | Offen (aus v0.1.1) |
| TD-9 | Diagnose-Logging | `print()`-Ausgaben (📬, 📋, 🔄, 📎, ✉️, 📤 …) sind aktiv – vor einer Release-Version entfernen oder hinter ein Debug-Flag setzen | Niedrig | Offen (aus v0.1.1) |
| TD-10 | Ordnerverwaltung | Ordner anlegen und löschen (IMAP CREATE/DELETE) fehlt | Mittel | Offen (aus v0.1.2) |
| TD-11 | IMAP-Aktionen | Jede Aktion baut eine eigene IMAP-Verbindung auf und ab; Zusammenlegung mit TD-2 sinnvoll | Niedrig | Offen (aus v0.1.2) |
| TD-12 | Datenschutz/Cache | Beim Löschen eines Postfachs bleiben dessen Mails und Anhänge im lokalen SQLite-Cache liegen – unsichtbar, aber auf dem Gerät gespeichert | Mittel | Offen (neu in v0.1.4) |
| TD-13 | macOS-Composer | Verfassen läuft auch auf dem Mac als Sheet; dort wäre ein eigenes Fenster üblich (Schritt 7b) | Mittel | Zurückgestellt (neu in v0.1.4) – erst wenn die Mac-Variante getestet wird |
| TD-14 | Gesendet-Ordner | Der Gesendet-Ordner wird beschrieben, aber nicht synchronisiert; gesendete Mails erscheinen in Mailwerk nicht | Mittel | Offen (neu in v0.1.4) – hängt an „Weitere Ordner" |
| TD-15 | Zitat-Aufbereitung | Beim Zitieren wird nur der `<body>`-Inhalt übernommen; Stylesheets aus dem Kopf gehen verloren, die Darstellung kann daher vom Original abweichen | Niedrig | Offen (neu in v0.1.4) |

---

## Noch nicht implementiert (geplant für 0.1.x / später)

- [x] ~~**SMTP-Versand**: Senden / Antworten / Weiterleiten~~ **Erledigt (v0.1.4)**
- [ ] **Weitere Ordner**: aktuell wird nur INBOX synchronisiert – Sent, Drafts, Trash etc. fehlen (TD-14), zusätzlich Ordner anlegen/löschen (TD-10)
- [ ] **Entwürfe**: Zwischenspeichern unfertiger Nachrichten (Drafts-Ordner)
- [ ] **Signaturen**: HTML-Signaturen zur Auswahl, teils je Postfach unterschiedlich (bewusst auf eine spätere Version verschoben)
- [ ] **Optische Überarbeitung**: eigenständiges Design mit Wiedererkennungswert, inklusive Neuaufbau der Composer-Maske
- [ ] **Fehlerhandling**: durchgängig saubere Fehlermeldungen statt `try?` (Rest außerhalb der Postfach-Verwaltung)

---

## Abhängigkeiten

| Package | Version | Zweck |
|---|---|---|
| [SwiftMail](https://github.com/Cocoanetics/SwiftMail) | **1.12.0** (Up to Next Major, Untergrenze 1.12.0) | IMAP- und SMTP-Client (baut auf Swift NIO) |
| System-SQLite (`import SQLite3`) | – | Lokaler Nachrichten-Cache |
| QuickLook (`import QuickLook`) | System-Framework | Anhang-Vorschau |
| Contacts (`import Contacts`) | System-Framework | Adressvervollständigung |
| PhotosUI (`import PhotosUI`) | System-Framework (iOS) | Fotos als Anhang |

**Hinweis:** Die Anhebung auf 1.12.0 war nötig, weil `MessageInfo.replyTo` erst ab dieser Version verfügbar ist. Ein Vergleich der öffentlichen API von 1.11.0 und 1.12.0 zeigte ausschließlich Ergänzungen, keine Entfernungen.

---

## Xcode-Konfiguration

| Einstellung | Wert |
|---|---|
| **Xcode** | 26.6 |
| **Swift** | 5.0 (Default Actor Isolation: MainActor) |
| **Deployment Targets** | iOS 26.5, macOS 26.5, visionOS 26.5 |
| **Bundle Identifier** | `de.sieber-bw.Mailwerk` |
| **Development Team** | 62QD57DH52 |
| **Capabilities** | iCloud (Key-value storage), Keychain Sharing |
| **Info.plist** | **Neu:** `NSContactsUsageDescription` (Privacy – Contacts Usage Description) |
| **Supported Platforms** | iphoneos, iphonesimulator, macosx, xros, xrsimulator |
| **Localizations** | German (default), English |
| **MARKETING_VERSION** | 0.1.4 → ab nächstem Commit 0.1.5 |

**Offen für die Mac-Variante:** Für den Kontaktzugriff unter macOS wird zusätzlich das Entitlement `com.apple.security.personal-information.addressbook` benötigt. Das ist noch nicht gesetzt, weil Mailwerk bisher nur im iPhone-Simulator getestet wird.
