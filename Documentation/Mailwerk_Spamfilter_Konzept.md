# Mailwerk – Spam-Filter: Konzept & Umsetzungsanleitung

2026-09-23 · Ergebnis der Klärung „Kein ManageSieve bei manitu" · Zielversion laut Roadmap: 0.3.x (MVP3)

---

## Zusammenfassung

manitu bietet **kein ManageSieve** und keine API zur Pflege von Filterregeln. Die ursprünglich geplante serverseitige Pflege der Black-/Whitelist aus dem Client heraus ist damit nicht möglich.

**Entscheidung: Option C – Filterung ausschließlich im Client.** Mailwerk prüft beim Abruf neue Mails in der INBOX gegen eine eigene Black- und Whitelist sowie gegen die Spam-Einstufung von manitu (rspamd) und verschiebt Spam in den Ordner `Junk`. Die Listen liegen zentral in iCloud (CloudKit), damit alle Mailwerk-Installationen dieselben Listen nutzen. Der Verarbeitungszustand wird über **IMAP-Keywords auf dem Server** gespeichert, damit alle Geräte denselben Stand sehen.

Ergänzend kann Mailwerk beide Listen als Text exportieren, die Kim von Zeit zu Zeit manuell in den manitu-Portaldialog „Mail-Filter (Spam, Virus)" einfügt. So filtert auch der Server, unabhängig vom Client.

Kein eigener Server, kein Hintergrunddienst, keine Zugangsdaten außerhalb der Geräte.

---

## Ausgangslage

- **ManageSieve:** Support-Antwort manitu (2026-09): wird nicht angeboten. Port 4190 lehnt Verbindungen ab.
- **Sieve-Datei:** nur manuell im Kundenportal (hinter 2FA) bearbeitbar. Sieve selbst kann keine externen Listen abrufen (`include`, `extlists` und `vnd.dovecot.*` erfordern serverseitige Konfiguration).
- **Portal-Dialog „Mail-Filter (Spam, Virus)":** Bietet je ein Freitextfeld für *Erwünschte Absender (Allowlist)* und *Unerwünschte Absender (Blocklist)*, ein Eintrag pro Zeile, einzelne Adresse oder `*@domain.de` für eine ganze Domain. Ohne Rückwirkung auf andere Sieve-Einträge.
- **Aktuelle Portal-Einstellungen:** Spam wird in den Posteingang zugestellt, der Betreff wird mit `[SPAM]` gekennzeichnet, Empfindlichkeit 5.0.

### Geprüfte und verworfene Optionen

| Option | Bewertung |
|---|---|
| A – Sieve-Block aus dem Client generieren, manuell einfügen | Verworfen: Jede Änderung über Portal und 2FA; Risiko, den manitu-Block zu beschädigen. Durch den Portal-Dialog ohnehin überholt. |
| B/B+ – Eigener Filterdienst (Cron bzw. IDLE-Daemon) mit Listen im Backend | Verworfen für jetzt: eigener Dienst und Zugangsdaten auf einem Server. Kann bei Einführung eines Push-Servers (0.4.x) neu bewertet werden. |
| **C – Filterung im Client** | **Gewählt:** minimal, keine weiteren Abhängigkeiten. Die Nutzungslücke (Filterung nur bei geöffnetem Mailwerk) ist akzeptiert, da Kim künftig ausschließlich Mailwerk nutzt. |
| D – Automatisierung des manitu-Portals (Scraping) | Abgelehnt: umgeht die 2FA, fragil, vermutlich AGB-widrig. |
| E – Anbieterwechsel zu einem Anbieter mit ManageSieve | Verworfen: Umzugsaufwand steht in keinem Verhältnis. |

---

## Ergebnisse der Server-Prüfung (manitu, 2026-09-23)

### IMAP-Fähigkeiten (Dovecot, nach Login)

Relevant vorhanden: `MOVE`, `UIDPLUS`, `SPECIAL-USE`, `CONDSTORE`, `QRESYNC`, `ESEARCH`, `IDLE`, `LIST-STATUS`.
Nicht vorhanden: `CREATE-SPECIAL-USE`, d. h. ein neu angelegter Ordner kann nicht mit dem Attribut `\Junk` versehen werden.

### Eigene Keywords

`PERMANENTFLAGS` der INBOX enthält `\*`: **eigene Keywords sind erlaubt.**

### Ordner

| Ordner | Attribut | Bemerkung |
|---|---|---|
| `Junk` | `\Junk` | Offizieller Spam-Ordner. Im manitu-Webmail als „Spam" angezeigt. |
| `Trash`, `Sent`, `Drafts` | `\Trash`, `\Sent`, `\Drafts` | Standard |
| `Archive`, `Later`, `Notes`, `Deleted Messages` | – | Nicht relevant für den Filter |

### Spam-Header

Untersucht an einer internen Weiterleitung und an einer externen Spam-Mail:

- Vorhanden: `X-Spam: Yes` und `X-Spam-Status: Yes, score=<Wert>` (Beispiele: 10.00 und 5.34).
- **Nicht vorhanden:** `X-Spam-Flag`, `X-Spamd-Result`, `Authentication-Results`. manitu gibt die Ergebnisse von DKIM/SPF/DMARC nicht nach außen weiter.
- Die DKIM-Signaturen beider Beispiele umfassen den Betreff (`h=…Subject…`). Solange manitu `[SPAM]` einfügt, ist die Signatur dieser Mails ungültig.

### Aufräumarbeiten (durchgeführt)

- Unbekannte Keywords aus einem früheren Client entfernt: `Kaufen` (1 Mail) und `Whitelist` (5 Mails). Andere Markierungen blieben erhalten.
- Doppelter, gewöhnlicher Ordner `Spam` (ohne Attribut): eine Mail nach `Junk` verschoben, Ordner gelöscht.
- Kim wird die 6 bestehenden Einträge der Portal-Allowlist nicht migrieren, sondern in Mailwerk neu markieren, damit sie für alle Postfächer gelten.

---

## Fachliche Regeln

### Umfang

- Gefiltert wird **nur die INBOX**. Unterordner enthalten bewusst einsortierte Mails und bleiben unangetastet.
- Geprüft werden nur Mails der **letzten 30 Tage** (relevant beim ersten Start und nach längerer Nichtnutzung eines Geräts).
- Geprüft werden nur Mails **ohne** das Keyword `$MailwerkChecked`.

### Keywords

| Keyword | Bedeutung | Gesetzt, wenn |
|---|---|---|
| `$MailwerkChecked` | Mail wurde vom Filter verarbeitet | nach jeder Prüfung, unabhängig vom Ergebnis |
| `$MailwerkBlacklisted` | Mail wurde durch die Blacklist als Spam erkannt | zusätzlich bei einem Blacklist-Treffer |

Bei `MOVE` bleiben Keywords erhalten. Holt Kim eine Mail aus `Junk` zurück, auch über einen anderen Client, trägt sie weiterhin `$MailwerkChecked` und wird **nicht erneut gefiltert**. Das verhindert die Fehlalarm-Schleife, die bei rein lokaler UID-Verwaltung entstünde (eine zurückverschobene Mail bekommt eine neue UID). Deshalb die Keywords **immer vor dem MOVE setzen**.

Bestehende fremde Keywords wie `$MailFlagBit0` oder `$Forwarded` werden nie verändert.

### Server-Einstufung

- Mailwerk wertet **nur Header** aus, nie den Betreff. So funktioniert die Logik mit und ohne `[SPAM]`-Kennzeichnung gleich.
- Spam laut Server, wenn **irgendeine** Zeile `X-Spam: Yes` lautet oder **irgendeine** `X-Spam-Status`-Zeile mit `Yes` beginnt.
- Score: der **höchste** Wert aller `X-Spam-Status`-Zeilen. Ein Absender kann eigene Header mitschicken; ein gefälschter niedriger Score darf die Einstufung nicht senken.
- Ist die Mail als Spam markiert, aber kein Score lesbar, gilt der Score als unendlich (konservativ).

### Entscheidungsregel (Vorrang)

Es entscheidet der **spezifischste** Treffer:

1. **Exakte Adresse** auf Whitelist → behalten* · auf Blacklist → Junk
2. sonst **Domain** auf Whitelist → behalten* · auf Blacklist → Junk
3. sonst **Server-Einstufung** Spam → Junk
4. sonst → behalten

\* **Score-Obergrenze:** Ein Whitelist-Treffer behält eine vom Server als Spam markierte Mail nur, wenn deren Score **unter** der einstellbaren Obergrenze liegt (Standard: 15). Andernfalls wird sie wie Server-Spam behandelt. Hintergrund: Der `From`-Header ist fälschbar, eine DKIM-Prüfung ist mangels `Authentication-Results` nicht möglich (siehe TD-S1). Gefälschte Absender bekannter Marken erzeugen typischerweise hohe Scores.

Ergänzend:

- Derselbe Eintrag (gleiche Adresse bzw. gleiche Domain) darf nicht auf beiden Listen stehen. Die Eingabe wird abgelehnt mit dem Hinweis, auf welcher Liste er schon steht.
- Whitelist schlägt Blacklist nur über die Spezifität (Adresse vor Domain). Beispiel: Domain `firma.de` auf der Blacklist, `rechnung@firma.de` auf der Whitelist → die Adresse gewinnt.

### Adressvergleich

- Absender = erste Adresse im `From`-Header.
- Normalisierung: Leerzeichen entfernen, kleinschreiben.
- Domain-Vergleich **exakt**: `firma.de` trifft `x@firma.de`, aber weder `x@mail.firma.de` noch `x@evil-firma.de`.
- Beim Anlegen eines **Domain-Eintrags** auf der Whitelist erscheint ein Hinweis auf das Fälschungsrisiko (Empfehlung: bei Banken, Zahlungsdiensten, Versandhändlern nur exakte Adressen).

### Spam-Ordner

1. Ordner mit Attribut `\Junk` suchen (über die bestehende Ordnerliste in `MailActionService`).
2. Sonst Ordner namens `Junk` oder `Spam` suchen (Groß-/Kleinschreibung egal).
3. Sonst **einmalig pro Postfach nachfragen** und `Junk` anlegen (ohne Attribut, da `CREATE-SPECIAL-USE` fehlt). Ohne Zustimmung filtert Mailwerk dieses Postfach nicht.

In der Oberfläche heißt der Ordner „Spam", der Servername bleibt `Junk`.

### Betreff

Der Betreff wird **nie verändert** (IMAP kann Mails nicht ändern, Umschreiben hieße Download + APPEND + Löschen mit Risiko von Duplikaten oder Datenverlust). Die `[SPAM]`-Kennzeichnung bleibt vorerst zur Kontrolle aktiv. Kim schaltet sie später im Portal ab. Danach entfällt auch das Präfix beim Antworten und Weiterleiten.

### Export für das manitu-Portal

- Je ein Textblock für Whitelist (→ Feld *Erwünschte Absender*) und Blacklist (→ Feld *Unerwünschte Absender*).
- Ein Eintrag pro Zeile, getrennt durch Zeilenumbruch, ohne weitere Formatierung.
- Adressen unverändert, Domains als `*@domain.de`.
- Kleingeschrieben, ohne Duplikate, alphabetisch sortiert.
- Kopieren in die Zwischenablage bzw. Teilen-Menü.
- Kein Import. Die Listen in Mailwerk gelten für alle Postfächer; der Export wird bei Bedarf in den Dialog jedes manitu-Postfachs eingefügt.

---

## Architektur

### Neue Bausteine

| Baustein | Aufgabe |
|---|---|
| `FilterEntry` (SwiftData-Modell) | Ein Listeneintrag: `id`, `value` (normalisiert), `kind` (`address`/`domain`), `list` (`white`/`black`), `createdAt` |
| `FilterListRepository` (Protokoll) | Lesen, Anlegen, Löschen von Einträgen. Einzige Stelle, die den Speicherort kennt. |
| `CloudKitFilterListRepository` | Implementierung über SwiftData mit CloudKit-Sync (private Datenbank) |
| `InMemoryFilterListRepository` | Implementierung für Tests und Vorschauen |
| `SpamHeaderParser` | Liest `X-Spam`/`X-Spam-Status` robust aus (mehrfache Zeilen, höchster Score) |
| `SpamClassifier` | **Reine Logik ohne IMAP**: Absender + Header-Befund + Listen + Obergrenze → Entscheidung (`keep`, `junkServer`, `junkBlacklist`) |
| `SpamFilterService` | Ablauf je Postfach über **eine** IMAP-Verbindung (`MailServerFactory`): suchen, Header laden, klassifizieren, Keywords setzen, verschieben |
| `FilterListExporter` | Erzeugt die beiden Textblöcke im manitu-Format |

`SpamClassifier` und `SpamHeaderParser` sind bewusst frei von Abhängigkeiten, damit sie vollständig per Unit-Test abgedeckt werden können.

### Ablauf eines Filterlaufs (je Postfach, nach dem INBOX-Abruf)

1. Spam-Ordner ermitteln (siehe oben). Fehlt er und wurde nicht zugestimmt: Lauf für dieses Postfach überspringen.
2. `UID SEARCH UNKEYWORD $MailwerkChecked SINCE <heute − 30 Tage>`
3. Für die Treffer: `UID FETCH <uids> (BODY.PEEK[HEADER.FIELDS (FROM X-SPAM X-SPAM-STATUS)])`
   **Unbedingt `PEEK`**, sonst werden die Mails als gelesen markiert.
4. Je Mail `SpamClassifier` aufrufen.
5. Keywords setzen: `UID STORE <alle> +FLAGS.SILENT ($MailwerkChecked)` und für Blacklist-Treffer zusätzlich `$MailwerkBlacklisted`.
6. `UID MOVE <junk-uids> <Spam-Ordner>`.
7. Verschobene Mails aus dem lokalen Cache entfernen.

Fehlerverhalten: Meldet der Server beim MOVE, dass eine UID nicht mehr existiert, hat vermutlich ein anderes Gerät die Mail schon verarbeitet. Das ist kein Fehler und wird ignoriert.

### Manuelle Aktionen in der Oberfläche

- **Wisch-/Kontextaktion „Spam"** (der seit v0.1.1 vorhandene Platzhalter): Auswahl „Absender" oder „Domain" → Eintrag auf die Blacklist, aktuelle Mail sofort mit `$MailwerkChecked $MailwerkBlacklisted` nach Junk verschieben.
- **Listenpflege in den Einstellungen:** beide Listen ansehen, Einträge hinzufügen und löschen, Export.
- **Einstellungen:** Score-Obergrenze (Standard 15).

### Speicherung in iCloud

- SwiftData-Modell mit CloudKit-Sync in der **privaten** Datenbank des iCloud-Kontos.
- Revidiert die Entscheidung aus v0.1.0 („CloudKit verworfen zugunsten NSUbiquitousKeyValueStore"): Diese Entscheidung setzte voraus, dass die Listen serverseitig gepflegt werden. `NSUbiquitousKeyValueStore` speichert die Liste als einen Wert, bei gleichzeitigen Änderungen gewinnt die letzte, die andere geht verloren. Mit einem Datensatz pro Eintrag tritt das nicht auf.
- CloudKit-Einschränkungen für SwiftData-Modelle beachten: keine `@Attribute(.unique)`, alle Eigenschaften optional oder mit Standardwert. Duplikate (z. B. derselbe Eintrag gleichzeitig auf zwei Geräten angelegt) werden deshalb im Repository beim Lesen zusammengeführt.
- Xcode: Capability *iCloud* mit CloudKit-Container, auf iOS zusätzlich *Background Modes → Remote notifications*. CloudKit erfordert die Mitgliedschaft im Apple Developer Program.
- Später austauschbar gegen eine eigene API, z. B. wenn ein Push-Server (0.4.x) die Listen kennen muss: nur eine neue Implementierung von `FilterListRepository`.

---

## Voraussetzungen und Einstellungen im manitu-Portal

- **„Was soll mit Spam passieren?" muss auf „E-Mail in Posteingang zustellen" bleiben.** Würde manitu Spam direkt verschieben, könnte die Whitelist in Mailwerk nichts mehr retten, da nur die INBOX gefiltert wird.
- „Betreff kennzeichnen" bleibt vorerst aktiv, wird später abgeschaltet. Mailwerk braucht dafür keine Änderung.
- Das Feld „IMAP-Ordner zum Verschieben" bleibt leer.

---

## Umsetzungsanleitung (Reihenfolge)

Jeder Schritt wird einzeln umgesetzt und bestätigt, bevor der nächste beginnt.

1. **SwiftMail-API prüfen:** Unterstützt SwiftMail 1.12.0 `BODY.PEEK[HEADER.FIELDS (…)]`, `STORE` mit eigenen Keywords, `SEARCH` mit `UNKEYWORD` und `SINCE` sowie `CREATE`? Fehlende Teile identifizieren, bevor Code entsteht.
2. **`SpamHeaderParser` und `SpamClassifier` testgetrieben:** Tests zuerst (siehe Testfälle), dann Implementierung.
3. **Datenmodell und Repository:** `FilterEntry`, Protokoll, In-Memory-Variante mit Tests, dann CloudKit-Variante, Xcode-Capabilities einrichten.
4. **Spam-Ordner-Ermittlung** inkl. Rückfrage und `CREATE` (berührt TD-10).
5. **`SpamFilterService`** und Einbindung nach dem INBOX-Abruf.
6. **Oberfläche:** Wischaktion „Spam" aktivieren, Listenpflege, Export, Einstellung Score-Obergrenze.
7. **Manueller Test auf manitu** (siehe unten).

### Testfälle für Unit-Tests (Auswahl)

- Header: `X-Spam: Yes` ohne Status; `X-Spam-Status` mit und ohne Score; mehrere `X-Spam-Status`-Zeilen (höchster Score gewinnt); gefalteter Header über mehrere Zeilen; Groß-/Kleinschreibung der Header-Namen.
- Vorrang: Adresse-Whitelist vs. Domain-Blacklist; Adresse-Blacklist vs. Domain-Whitelist; Domain-Whitelist bei Server-Spam unter bzw. über der Obergrenze; Server-Spam ohne lesbaren Score bei Whitelist-Treffer.
- Domain-Vergleich: `evil-firma.de` und `mail.firma.de` treffen `firma.de` nicht.
- `From` mit Anzeigename, Anführungszeichen, spitzen Klammern, Großbuchstaben.
- Export: Sortierung, Duplikate, Domain-Format `*@`.

### Manuelle Testszenarien

- Mail eines Absenders auf der Blacklist → landet in `Junk`, trägt `$MailwerkChecked` und `$MailwerkBlacklisted`, bleibt ungelesen.
- Server-Spam eines Whitelist-Absenders unter der Obergrenze → bleibt in der INBOX.
- Dasselbe über der Obergrenze → landet in `Junk`.
- Mail aus `Junk` per Webmail zurück in die INBOX → wird beim nächsten Lauf nicht erneut verschoben.
- Zwei Geräte gleichzeitig → keine Fehlermeldung, Mail nur einmal verschoben.
- Mail älter als 30 Tage und Mails in Unterordnern → unverändert.
- Export in den manitu-Dialog einfügen und speichern → wird vom Portal akzeptiert.

---

## Neue Technical Debts / offene Punkte

| # | Bereich | Beschreibung | Priorität |
|---|---|---|---|
| TD-S1 | Whitelist-Sicherheit | Echte DKIM-Prüfung im Client (DNS-Abfrage + Signaturprüfung) statt Score-Obergrenze. Erst sinnvoll, wenn die `[SPAM]`-Kennzeichnung im Portal abgeschaltet ist. | Mittel |
| TD-S2 | Normalisierung | Internationale Domains (Umlaute) werden nicht in Punycode umgewandelt; Vergleich erfolgt auf dem kleingeschriebenen Text. | Niedrig |
| TD-S3 | Rettung aus Junk | Die Aktion „Kein Spam" (Mail zurück + Absender auf die Whitelist) setzt die Anzeige des Spam-Ordners voraus; hängt an „Weitere Ordner" (TD-14). Bis dahin Whitelist-Pflege über die Einstellungen. | Mittel |
| TD-S4 | Rückwirkung | Neue Listeneinträge wirken nur auf künftige Mails (bzw. die gerade gewischte Mail), nicht auf bereits geprüfte Mails in INBOX oder Junk. Bewusst einfach gehalten. | Niedrig |
| TD-S5 | manitu-Allowlist | Offen, ob manitus Allowlist nur die `From`-Adresse vergleicht oder DKIM/SPF voraussetzt. Bei Bedarf beim Support erfragen. Bis dahin: keine Domain-Einträge für häufig gefälschte Marken exportieren. | Niedrig |
| TD-S6 | Push (0.4.x) | Ein späterer Push-Server würde auch für Spam benachrichtigen, solange er die Listen nicht kennt. Bei Einführung neu bewerten (ggf. API-Implementierung von `FilterListRepository`). | Niedrig |

Berührte bestehende Punkte: TD-2/TD-11 (Filterlauf nutzt eine Verbindung pro Postfach), TD-3 (verschobene Mails aus dem Cache entfernen), TD-10 (`CREATE` für den Spam-Ordner), TD-14 (Anzeige weiterer Ordner).
