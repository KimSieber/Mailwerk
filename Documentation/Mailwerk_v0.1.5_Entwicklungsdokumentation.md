# Mailwerk – Entwicklungsdokumentation v0.1.5

2026-09-24 · Commit-Stand vor Übergang auf 0.1.6

---

## Zusammenfassung

Version 0.1.5 bringt den **eigenen Spamfilter** – vorgezogen aus der ursprünglich geplanten Stufe 0.3.x, weil die serverseitige Kennzeichnung bei manitu (rspamd) allein nicht ausreicht.

Der Filter läuft beim Abrufen vor dem eigentlichen Posteingangs-Abgleich. Er bewertet ungeprüfte Mails der letzten 30 Tage anhand der Server-Header `X-Spam` / `X-Spam-Status` und zweier selbst gepflegter Listen (Whitelist, Blacklist) und verschiebt erkannten Spam in den Spam-Ordner **desselben** Postfachs. Die Listen liegen in iCloud (CloudKit über SwiftData) und gelten für alle Postfächer und Geräte gemeinsam.

Der Verarbeitungsstand wird über das IMAP-Keyword `$MailwerkChecked` **auf dem Server** gehalten. Damit prüft kein zweites Gerät dieselbe Mail erneut, und eine von Hand zurückgeholte Mail bleibt zurückgeholt.

Zwei Dinge wurden zusätzlich vorbereitet, obwohl sie erst mit den Ordner-Sichten in 0.1.6 sichtbar werden: Der lokale Cache ist **ordnerfähig** (neue Spalte `folder`, neues Kennungsschema inkl. einmaliger Migration), und sämtliche IMAP-Aktionen kennen ihren Quellordner statt fest `INBOX` zu verwenden.

Der Filter ist **standardmäßig ausgeschaltet**. Er verschiebt Mails selbsttätig, deshalb wird er bewusst eingeschaltet.

---

## Projektstruktur (Änderungen gegenüber v0.1.4)

```
Mailwerk/
├── MailwerkApp.swift                   # + ModelContainer (CloudKit → lokal → flüchtig)
├── ContentView.swift                   # + FilterListRepository, SpamSettings
├── Models/
│   ├── MailAccount.swift               # + spamFolder (gemerkter Spam-Ordner je Postfach)
│   └── CachedMessage.swift             # + folder, + makeID(accountID:folder:uid:)
├── ViewModels/
│   └── InboxViewModel.swift            # + Filterlauf vor dem Abruf, Rückfrage Spam-Ordner
├── Views/
│   ├── InboxView.swift                 # + Einstellungs-Menü, Rückfrage Spam-Ordner
│   ├── MessageDetailView.swift         # + Spam-Menü (blockieren / vertrauen) mit Rückfrage
│   ├── SpamSettingsView.swift          # NEU – Schalter, Score-Obergrenze, Zugang zu den Listen
│   └── FilterListView.swift            # NEU – Listenpflege inkl. Sammeleingabe und Export
└── Services/
    ├── MailActionService.swift         # + folder-Parameter, createFolder, mailboxes(on:), MOVE liefert neue UID
    ├── MailFetchService.swift          # + folder-Parameter, inboxFolder, Kennung über makeID
    ├── MessageStore.swift              # + Spalte folder, Migration, relocateMessage, init(path:)
    ├── RecipientInput.swift            # tokens(_:) herausgelöst (nonisolated, auch vom Filter genutzt)
    └── Spam/                           # NEU – gesamter Filter
        ├── SpamKeyword.swift           # $MailwerkChecked / $MailwerkBlacklisted + Atom-Prüfung
        ├── SpamHeaderParser.swift      # X-Spam / X-Spam-Status auswerten
        ├── FilterAddress.swift         # Absender/Domain normalisieren
        ├── SpamClassifier.swift        # Entscheidung je Mail
        ├── SpamFilterPlanner.swift     # Bündelung zum Arbeitsplan eines Laufs
        ├── SpamFolderResolver.swift    # Spam-Ordner finden bzw. vorschlagen
        ├── FilterEntry.swift           # SwiftData-Modell + Wertetypen + Fehler
        ├── FilterListRepository.swift  # Protokoll + In-Memory-Variante
        ├── SwiftDataFilterListRepository.swift  # iCloud-Variante
        ├── FilterListRules.swift       # Normalisieren, Zusammenführen, Momentaufnahme
        ├── FilterListInput.swift       # Sammeleingabe zerlegen
        ├── FilterListExporter.swift    # Textausgabe + Datei zum Teilen
        ├── SpamSettings.swift          # Schalter und Score-Obergrenze (iCloud-KVS)
        └── SpamFilterService.swift     # Filterlauf, Blockieren, Vertrauen, Ordner anlegen
```

---

## Erledigte Schritte (v0.1.5)

### SwiftMail-Prüfung (Schritt 1)

Vor dem ersten Codezeile wurde SwiftMail 1.12.0 im Quelltext geprüft. Alles Nötige ist vorhanden: `SearchCriteria.unkeyword`, `BODY.PEEK[HEADER.FIELDS (…)]` über `fetchMessageInfosBulk(headerFields:)`, `store` mit eigenen Keywords, `createMailbox`, `move` mit `CopyUID`-Rückgabe.

Drei Fallstricke wurden dabei gefunden und im Code umgangen (siehe Entscheidungen): das Header-Wörterbuch `additionalFields`, die stille Ersetzung ungültiger Keywords durch `CUSTOM` und die eigene `markAsJunk`-Funktion von SwiftMail.

### Entscheidungslogik (Schritt 2)

`SpamHeaderParser`, `FilterAddress`, `SpamClassifier` und `SpamKeyword` – reine Logik, testgetrieben entstanden, ohne IMAP-Bezug und `nonisolated`, weil der Filterlauf außerhalb des Main-Actors arbeitet.

### Listen in iCloud (Schritt 3)

`FilterEntry` als SwiftData-Modell, `FilterListRepository` als Protokoll mit In-Memory- und CloudKit-Variante. In Xcode wurden CloudKit, der Container `iCloud.de.sieber-bw.Mailwerk`, Push Notifications und Background Modes → Remote notifications eingerichtet.

### Ordnerfähiger Cache (Schritt 4)

Spalte `folder`, Kennungsschema `Konto-Ordner-UID`, einmalige Migration der Bestandsdaten inkl. Anhänge, `relocateMessage` für den Umzug nach einem serverseitigen MOVE. `MessageStore` lässt sich für Tests mit eigenem Dateipfad anlegen.

### Spam-Ordner finden (Schritt 5)

`SpamFolderResolver` mit vierstufiger Suche: gemerkter Ordner → SPECIAL-USE `\Junk` → gebräuchliche Namen → Vorschlag zum Anlegen. Alle IMAP-Aktionen bekamen einen `folder`-Parameter, `MOVE` liefert die Ziel-UID zurück.

### Filterlauf (Schritt 6)

`SpamFilterPlanner` bündelt die Einzelentscheidungen zu einem Arbeitsplan, `SpamFilterService` führt ihn aus: Suche `UNKEYWORD $MailwerkChecked SINCE …`, Header per PEEK, Keywords setzen, verschieben, Cache nachziehen.

### Oberfläche (Schritt 7)

Schalter und Score-Obergrenze in den Einstellungen, Pflege beider Listen mit Sammeleingabe, Spam-Menü an der Mail mit Rückfrage, Rückfrage zum Anlegen eines fehlenden Spam-Ordners, Export als Textdatei zum Teilen.

---

## Getroffene Architektur- & Design-Entscheidungen (v0.1.5)

| Entscheidung | Begründung |
|---|---|
| **Verarbeitungsstand als IMAP-Keyword (`$MailwerkChecked`) statt lokal** | Der Stand gehört zur Mail, nicht zum Gerät. Zwei Geräte prüfen dieselbe Mail nicht doppelt, und eine von Hand zurückgeholte Mail bleibt unangetastet. |
| **`$MailwerkChecked` wird nie entfernt, auch nicht beim Vertrauen** | Nach dem Zurückholen bekommt die Mail eine neue UID; ohne das Keyword liefe sie sofort wieder in denselben Server-Treffer. |
| **`$MailwerkBlacklisted` nur bei Blacklist-Treffern** | Sagt im Spam-Ordner, warum eine Mail dort liegt, und wird beim Vertrauen gezielt entfernt. |
| **Keywords setzen, dann verschieben** | Bricht die Verbindung dazwischen ab, trägt die Mail ihre Kennzeichnung bereits mit in den Zielordner. |
| **Nur `X-Spam` und `X-Spam-Status` auswerten, nie den Betreff** | Die Betreff-Kennzeichnung `[SPAM]` ist eine Portal-Einstellung und soll abschaltbar bleiben. |
| **Höchster Score gewinnt bei mehreren `X-Spam-Status`-Zeilen** | Ein Absender kann eigene Header mitschicken. Ein gefälschter niedriger Score darf die Einstufung nicht senken. |
| **`additionalHeaderFields` statt `additionalFields`** | Das Wörterbuch behält bei Wiederholungen nur die letzte Zeile – genau der Angriffsweg von oben. |
| **Whitelist schützt nur unterhalb einer Score-Obergrenze (Vorgabe 15)** | Absenderadressen sind fälschbar. Ohne Obergrenze wäre ein Whitelist-Eintrag ein Freifahrtschein für jeden, der die Adresse fälscht. Ohne lesbaren Score gilt er als unendlich. |
| **Reihenfolge: Adresse vor Domain, Whitelist vor Blacklist** | Der spezifischere Eintrag gewinnt. So lässt sich eine einzelne Adresse einer sonst blockierten Domain freigeben. |
| **Bei Sync-Konflikt gewinnt die Whitelist** | Eine fälschlich behaltene Mail ist ärgerlich, eine fälschlich aussortierte kann teuer werden. |
| **Ein Datensatz je Listeneintrag statt einer Liste als Ganzes** | Gleichzeitige Änderungen auf zwei Geräten überschreiben sich nicht. |
| **Doppelte beim Lesen zusammenführen statt beim Schreiben verhindern** | CloudKit erlaubt in SwiftData keine eindeutigen Attribute. Es gewinnt der älteste Datensatz, damit alle Geräte denselben wählen. |
| **Listen gelten für alle Postfächer, Ordner je Postfach** | Eine Mail ist nicht in einem Postfach Spam und im anderen nicht. Verschoben wird trotzdem immer innerhalb desselben IMAP-Kontos. |
| **Spam-Ordner nur nach Rückfrage anlegen** | Ein selbsttätig erzeugter Ordner taucht in allen Mail-Programmen auf; das ist eine Änderung am Postfach, die der Nutzer bestätigen soll. |
| **`createFolder` gibt den tatsächlichen Pfad zurück** | SwiftMail ergänzt beim Anlegen das Namespace-Präfix des Servers; aus „Junk" kann „INBOX.Junk" werden. |
| **Exakter Domain-Vergleich, keine Subdomains** | `firma.de` darf weder `mail.firma.de` noch `evil-firma.de` treffen. |
| **Eigene, tolerante Adressprüfung für den Filter** | Die strenge Versandprüfung lehnt Absender wie `bounce=123@…` ab – genau die müssen blockierbar bleiben. |
| **Ordner in der Cache-Kennung (`Konto-Ordner-UID`)** | UIDs sind nur innerhalb eines Ordners eindeutig; ohne Ordner kollidiert eine Junk-Mail mit einer Posteingangs-Mail. |
| **Migration: Anhänge vor Nachrichten umschreiben, Fremdschlüssel kurz aus** | SQLite kennt hier kein `ON UPDATE CASCADE`; in umgekehrter Reihenfolge würden Anhänge verwaisen. |
| **Nach dem Verschieben umziehen statt löschen** | Mit der vom Server gemeldeten Ziel-UID bleibt die Mail samt Anhängen im Cache. Ohne UIDPLUS wird sie entfernt – lieber neu laden als Falsches anzeigen. |
| **Arbeitsplan statt Befehl je Mail** | Ein Lauf schickt wenige gebündelte Befehle. Nebeneffekt: Die Entscheidung ist ohne IMAP testbar. |
| **Filter vor dem Abruf, Fehler im Filter blockiert den Abruf nicht** | Erkannter Spam taucht gar nicht erst im Posteingang auf; ein kaputter Filter darf den Posteingang nicht lahmlegen. |
| **Filter standardmäßig aus** | Er verschiebt Mails selbsttätig. Das wird eingeschaltet, nicht stillschweigend aktiviert. |
| **Sammeleingabe mit dem Zerleger der Empfängerfelder** | Ein Komma in `"Muster, Anna" <anna@firma.de>` darf nicht trennen. Der Zerleger war schon da und wurde herausgelöst. |
| **Export als Datei statt als Text** | Nur eine Datei lässt sich aus dem Teilen-Menü als Mailanhang versenden. Domains in der Portal-Schreibweise `*@firma.de`. |
| **Spam-Logik durchgehend `nonisolated`** | Reine Berechnung ohne UI-Bezug; der Filterlauf ruft sie aus dem Hintergrund auf. |

---

## Bugfixes und Funde (v0.1.5)

| Fund | Wirkung | Behebung |
|---|---|---|
| **SwiftMail ersetzt ungültige Keywords still durch `CUSTOM`** | Ein Tippfehler in einer Keyword-Konstante hätte alle Mails mit demselben falschen Keyword markiert – ohne Fehlermeldung | Eigene Atom-Prüfung nach RFC 3501, per Test auf beide Konstanten angewandt |
| **`MailFolder.hierarchyDelimiter` als `Character?` angenommen** | Build-Fehler; SwiftMail liefert `String?` | Durchgängig `String?` |
| **`search(criteria:)` ohne Sortierung ist veraltet** | Compiler-Warnung | Umstellung auf `extendedSearch`, Auswertung von `all` bzw. `ordered` |
| **Standardwerte von Parametern außerhalb des Main-Actors** | Zwei Warnungen (`FilterLists.empty`, `MailFetchService.inboxFolder`) | Betroffene Typen und Konstanten `nonisolated` |
| **Erster Filterlauf traf Bestandsmails** | 20 bereits gesichtete Mails wurden aussortiert, weil sie noch kein `$MailwerkChecked` trugen | Von Hand zurückgeholt; als Konsequenz wurde die Listenpflege vor das Mail-Menü gezogen und der Filter standardmäßig ausgeschaltet |

---

## Tests

| Testdatei | Tests | Inhalt |
|---|---|---|
| `SpamKeywordTests.swift` | 4 Gruppen | Gültigkeit der IMAP-Atome, Eindeutigkeit der Keywords |
| `SpamHeaderParserTests.swift` | 16 | Einstufung, Score, mehrfache Zeilen, gefaltete Header, ignorierte Header |
| `FilterAddressTests.swift` | 11 | Absender aus `From`, Normalisierung, Domain-Eingaben, Ablehnungen |
| `SpamClassifierTests.swift` | 14 | Vorrangregeln, Score-Obergrenze, exakter Domain-Vergleich |
| `SpamFilterPlannerTests.swift` | 10 | Gruppenbildung, Sortierung, Dubletten |
| `SpamFolderResolverTests.swift` | 14 | Gemerkter Ordner, SPECIAL-USE, Namenssuche, Vorschlag |
| `FilterListRepositoryTests.swift` | 12 | Anlegen, Normalisieren, Dubletten, Konflikte, Entfernen, Zusammenführen |
| `MessageStoreFolderTests.swift` | 9 | Trennung der Ordner, Umzug mit Anhängen, Migration von v0.1.4 |
| `FilterListInputTests.swift` | 11 | Sammeleingabe, Trennzeichen, Anzeigenamen, Unbrauchbares |
| `FilterListExporterTests.swift` | 7 | Textausgabe, Sortierung, Datei schreiben und überschreiben |

Manuell geprüft: Filterlauf über drei Postfächer (325 Mails), Blockieren aus dem Posteingang inkl. Verschieben und Listeneintrag, Listenpflege mit Sammeleingabe, Export als Datei, CloudKit-Anbindung im Simulator.

**Nicht belegt:** Das Greifen eines Whitelist-Eintrags im laufenden Betrieb. Nach dem ersten Lauf trugen alle Bestandsmails `$MailwerkChecked`; der Nachweis kommt mit der nächsten eingehenden Mail eines eingetragenen Absenders. Die Logik selbst ist durch `SpamClassifierTests` abgedeckt.

---

## Bekannte Technical Debts / Offene Nacharbeiten

| # | Bereich | Beschreibung | Priorität | Status |
|---|---|---|---|---|
| TD-2 | IMAP-Verbindung | Kein Connection-Pooling/IDLE | Niedrig | Offen (geplant für 0.4.x) |
| TD-3 | Cache-Sync | Kein Abgleich bei serverseitiger Löschung/Verschiebung | Mittel | Offen (aus v0.1.0) |
| TD-7 | Inbox-UI | `ContentUnavailableView` nicht scrollbar → Pull-to-Refresh greift im leeren Zustand nicht | Mittel | Offen (aus v0.1.1) |
| TD-8 | Erster Abruf | Erstabruf dauert 4–6 Minuten bei 300 Mails | Niedrig | Offen (aus v0.1.1) |
| TD-9 | Diagnose-Logging | `print()`-Ausgaben aktiv, jetzt zusätzlich 🛡️ und 🗂️ | Niedrig | Offen (aus v0.1.1) |
| TD-10 | Ordnerverwaltung | Ordner anlegen und löschen; **CREATE ist mit v0.1.5 da**, DELETE und die Oberfläche fehlen | Mittel | Teilweise erledigt |
| TD-11 | IMAP-Aktionen | Jede Aktion baut eine eigene Verbindung auf; Filterlauf und Mail-Aktion ebenso | Niedrig | Offen (aus v0.1.2) |
| TD-12 | Datenschutz/Cache | Beim Löschen eines Postfachs bleiben Mails und Anhänge im Cache | Mittel | Offen (aus v0.1.4) |
| TD-13 | macOS-Composer | Verfassen auf dem Mac als Sheet statt eigenem Fenster | Mittel | Zurückgestellt (aus v0.1.4) |
| TD-14 | Weitere Ordner | Nur INBOX wird synchronisiert; Sent, Trash **und der Spam-Ordner** fehlen in der Anzeige | **Hoch** | Offen – nächste Version |
| TD-15 | Zitat-Aufbereitung | Beim Zitieren gehen Stylesheets aus dem Kopf verloren | Niedrig | Offen (aus v0.1.4) |
| TD-S1 | Spam-Sichtbarkeit | Bis die Ordner-Sichten da sind, ist aussortierter Spam in Mailwerk unsichtbar; Fehleinstufungen nur im Webmail auffindbar | **Hoch** | Offen – Gegenmaßnahme: `[SPAM]`-Betreffkennzeichnung im Portal vorerst aktiv lassen |
| TD-S2 | Filterlauf-Umfang | Ein Lauf prüft alle ungeprüften Mails der letzten 30 Tage, also auch Bestandsmails. Beim erstmaligen Einschalten kann das viele Mails auf einmal verschieben | Mittel | Offen – Vorschlag: beim ersten Lauf nur Mails ab dem Einschaltzeitpunkt prüfen |
| TD-S3 | Blockieren ohne Spam-Ordner | Fehlt der Ordner, ist der Listeneintrag schon gesetzt, das Verschieben schlägt fehl | Niedrig | Offen – Rückfrage zum Anlegen auch aus dem Mail-Menü heraus anbieten |
| TD-S4 | Blockieren wirkt nur auf die aktuelle Mail | Weitere Mails desselben Absenders im Posteingang bleiben liegen | Niedrig | Bewusste Entscheidung; ggf. später „alle passenden mitverschieben" anbieten |
| TD-S5 | Veraltete Suche im Abruf | `MailFetchService` nutzt noch `search(criteria:sortCriteria:)`; SwiftMail empfiehlt `extendedSearch` | Niedrig | Offen (neu in v0.1.5) – nicht mitgeändert, um den laufenden Abruf nicht anzufassen |
| TD-S6 | Keine Rücknahme eines Laufs | Ein versehentlich ausgeführter Lauf lässt sich nicht in einem Schritt rückgängig machen | Niedrig | Offen – Mails tragen `$MailwerkChecked`, ein Rückholen ist daher manuell möglich |
| TD-S7 | Liste per Mail versenden | Export geht über das System-Teilen-Menü; eine neue Mail direkt in Mailwerk mit der Liste als Anhang wäre naheliegend | Niedrig | Vorschlag (neu in v0.1.5) |

---

## Noch nicht implementiert (geplant für 0.1.x / später)

- [x] ~~**Spamfilter**: eigene Listen, Server-Header, Verschieben in den Spam-Ordner~~ **Erledigt (v0.1.5)**
- [ ] **Weitere Ordner (0.1.6)**: Ordnerliste anzeigen, Spam-Ordner und Gesendet synchronisieren (TD-14, TD-S1). Der Unterbau steht: ordnerfähiger Cache, ordnerbezogene Aktionen, `refreshAndCache(folder:)`, `relocateMessage`
- [ ] **Ordnerverwaltung**: Ordner anlegen (da) und löschen (fehlt), Oberfläche dazu (TD-10)
- [ ] **Entwürfe**: Zwischenspeichern unfertiger Nachrichten
- [ ] **Signaturen**: HTML-Signaturen je Postfach
- [ ] **Optische Überarbeitung**: eigenständiges Design, Neuaufbau der Composer-Maske
- [ ] **Fehlerhandling**: durchgängig saubere Fehlermeldungen statt `try?`

---

## Abhängigkeiten

| Package | Version | Zweck |
|---|---|---|
| [SwiftMail](https://github.com/Cocoanetics/SwiftMail) | **1.12.0** (Up to Next Major, Untergrenze 1.12.0) | IMAP- und SMTP-Client |
| System-SQLite (`import SQLite3`) | – | Lokaler Nachrichten-Cache |
| SwiftData (`import SwiftData`) | System-Framework | **Neu:** Filterlisten mit CloudKit-Abgleich |
| QuickLook, Contacts, PhotosUI | System-Frameworks | unverändert |

---

## Xcode-Konfiguration

| Einstellung | Wert |
|---|---|
| **Xcode** | 26.6 |
| **Swift** | 5.0 (Default Actor Isolation: MainActor) |
| **Deployment Targets** | iOS 26.5, macOS 26.5, visionOS 26.5 |
| **Bundle Identifier** | `de.sieber-bw.Mailwerk` |
| **Development Team** | 62QD57DH52 |
| **Capabilities** | iCloud (Key-value storage **+ CloudKit**, Container `iCloud.de.sieber-bw.Mailwerk`), Keychain Sharing, **Push Notifications**, **Background Modes → Remote notifications** |
| **MARKETING_VERSION** | 0.1.5 → ab nächstem Commit 0.1.6 |

**Offen vor einer Veröffentlichung:** Das CloudKit-Entwicklungsschema muss im CloudKit-Dashboard einmalig nach Produktion übernommen werden. Im Entwicklungsbetrieb legt SwiftData es automatisch an.

---

## Hinweise für v0.1.6

1. **Ordner-Sichten haben Vorrang.** Bis dahin bleibt aussortierter Spam in Mailwerk unsichtbar (TD-S1).
2. **Der Unterbau ist da.** Nötig sind im Wesentlichen: Ordnerliste in der Oberfläche, Abruf weiterer Ordner über `refreshAndCache(account:password:folder:)` und eine Umschaltung der Anzeige über `allMessages(accountIDs:folder:)`.
3. **Im Spam-Ordner sichtbar machen, warum eine Mail dort liegt.** Das Keyword `$MailwerkBlacklisted` unterscheidet Blacklist-Treffer von Server-Einstufungen; dafür muss der Abruf die Keywords des Ordners mitlesen.
4. **„Vertrauen" ist fertig, hat aber noch keinen Ort.** Sobald der Spam-Ordner angezeigt wird, ist der Menüpunkt dort ohne weitere Änderung nutzbar.
