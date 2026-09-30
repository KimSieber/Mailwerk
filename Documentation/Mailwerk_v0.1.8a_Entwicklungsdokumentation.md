# Mailwerk – Entwicklungsdokumentation v0.1.8a

2026-09-30 · Ordner anlegen und löschen, Umlaute in Ordnernamen

---

## Zusammenfassung

Mit Version 0.1.8a lassen sich Ordner direkt in der Seitenleiste verwalten. Ein **langes Drücken** (Mac: Rechtsklick) öffnet ein Kontextmenü:

- Am Postfachnamen steht **„Neuer Ordner …“**.
- An jedem Ordner steht **„Neuer Unterordner …“**, auch am Posteingang und an Sonderordnern.
- An gewöhnlichen Ordnern steht zusätzlich **„Löschen …“**.

Gelöscht werden **nur leere Ordner**, also Ordner ohne Mails und ohne Unterordner. Sonderordner sind geschützt. Umbenennen ist bewusst nicht enthalten. Was Mailwerk nicht kann, erledigt das Webmail.

**Ordnernamen mit Umlauten** werden jetzt lesbar angezeigt und korrekt angelegt. Der Server überträgt sie als modified UTF-7, zum Beispiel wird „Müller“ zu `M&APw-ller`.

Das Löschen läuft über einen **eigenen, schlanken IMAP-Weg**, weil SwiftMail 1.12.0 kein öffentliches DELETE anbietet. Er wird zurückgebaut, sobald SwiftMail es bereitstellt.

---

## Projektstruktur (Änderungen gegenüber v0.1.7e)

```
Mailwerk/
├── Models/
│   └── MailFolder.swift              # Kommentare: Namespace, Namen in Server-Form
├── Services/
│   ├── Folders/
│   │   ├── MailboxNameCodec.swift    # NEU – modified UTF-7 (RFC 3501, 5.1.3)
│   │   ├── FolderCreationPlanner.swift # NEU – Pfadregel und Namensprüfung
│   │   ├── FolderDeletion.swift      # NEU – IMAP-Dialog zum Löschen (reine Logik)
│   │   ├── IMAPLineConnection.swift  # NEU – TLS-Transport über Network.framework
│   │   └── FolderTreeBuilder.swift   # Namen dekodiert, Namespace-Kommentar korrigiert
│   ├── MailActionService.swift       # createFolder(named:parentPath:), deleteFolder
│   └── MessageStore.swift            # deleteFolder: Cache eines Ordners abräumen
├── Views/
│   ├── Folders/FolderSidebarView.swift # Kontextmenü, Dialoge, Rückfrage, Meldungen
│   └── InboxView.swift               # Verdrahtung, Ansicht verlassen nach Löschen
MailwerkTests/
├── MailboxNameCodecTests.swift       # NEU
├── FolderCreationPlannerTests.swift  # NEU
├── FolderDeletionTests.swift         # NEU – simulierter Dovecot-Server
├── FolderTreeBuilderTests.swift      # + echte manitu-Liste, Umlaute
└── MessageStoreFolderTests.swift     # + Ordner-Cache abräumen
```

Datenbank: keine Schemaänderung.

---

## Getroffene Entscheidungen (v0.1.8a)

| Entscheidung | Begründung |
|---|---|
| SwiftMail nicht forken oder erweitern | Ein früherer Versuch führte zum Zurücksetzen einer ganzen Version |
| DELETE über einen eigenen IMAP-Weg, CREATE weiter über SwiftMail | Nur DELETE fehlt öffentlich. Der eigene Weg bleibt so klein wie möglich |
| Nur leere Ordner löschen | DELETE entfernt enthaltene Mails ohne Rückfrage. Aufräumen geht manuell nacheinander oder im Webmail |
| Prüfung und DELETE in *einer* Verbindung | Die Prüfung findet unmittelbar vor dem Löschen statt, nicht anhand einer älteren Liste |
| Prüfung auf Unterordner zusätzlich per LIST, nicht nur über `\HasChildren` | Funktioniert auch bei Servern ohne die CHILDREN-Erweiterung |
| Anmeldung per `AUTHENTICATE PLAIN` mit SASL-IR | Zugangsdaten in Base64, keine Probleme mit Sonderzeichen im Passwort |
| Eigener Weg nur mit TLS ab dem ersten Byte (Port 993) | Ohne STARTTLS bleibt der eigene Code halb so groß. Alle Postfächer laufen über 993 |
| Keine Ordnerpfade mit `*`/`%` und keine als Literal gemeldeten Namen | Im Zweifel wird nicht gelöscht |
| Sonderordner unveränderlich | Schutz vor Fehlbedienung |
| Unterordner unter dem Posteingang erlaubt | Gängige Praxis. Bei manitu eindeutig (`INBOX.Name`) |
| Kein Umbenennen | Selten gebraucht. Das Webmail kann es |
| Kontextmenü nur per langem Drücken, kein Drei-Punkte-Symbol | Das Symbol braucht zu viel Platz. Apple Mail nutzt dieselbe Geste |
| Intern immer Server-Form der Namen, lesbar nur in der Anzeige | Pfade, Cache und Befehle bleiben eindeutig. Umwandlung an genau zwei Stellen |
| Doppelte Namen ohne Rücksicht auf Groß- und Kleinschreibung ablehnen | „Test“ und „test“ auf einer Ebene wären verwirrend |

---

## Erkenntnisse im Verlauf

| Thema | Erkenntnis |
|---|---|
| Namespace bei manitu | Der Server meldet `(("" "."))`, also **kein** Präfix `INBOX.` wie bisher angenommen. Ordner liegen auf oberster Ebene (`Test`), Unterordner des Posteingangs heißen `INBOX.Name`. Die Code-Kommentare sind korrigiert. Der Baum war dank der Server-Auskunft schon richtig |
| Ordnernamen in SwiftMail | SwiftMail wandelt modified UTF-7 in keiner Richtung um. Der Umwandler in NIOIMAP ist nur intern |
| Abonnieren | Mit Mailwerk angelegte Ordner werden nicht abonniert, weil SwiftMail kein SUBSCRIBE hat. Das Webmail zeigt sie erst, nachdem man sie in dessen Ordnerverwaltung abonniert hat |
| Warnung zu `[weak self]` | Eine äußere Closure, die `self` implizit stark fängt, kollidiert mit `[weak self]` in einer inneren Closure. Deshalb auch außen ausdrücklich `[weak self]` angeben |
| Test-Werkzeug | SwiftPM plant unter Linux sehr langsam. Direktes Bauen mit `swiftc` ist deutlich schneller |

---

## Tests

| Testdatei | Tests | Inhalt |
|---|---|---|
| `MailboxNameCodecTests.swift` | 10 | Umlaute, `&`, RFC-Beispiel, Emoji, Hin- und Rückweg, ungültige Eingaben |
| `FolderCreationPlannerTests.swift` | 14 | Pfadregel mit und ohne Präfix, Unterordner, Namensprüfung, doppelte Namen |
| `FolderDeletionTests.swift` | 18 | Befehlsfolge, kein DELETE bei Mails, Unterordnern, Anmeldefehler oder falscher Begrüßung, Quoting, Parser |
| `FolderTreeBuilderTests.swift` | +4 | Echte manitu-Liste, dekodierte Namen, kodierte Kandidatennamen, ungültige Kodierung |
| `MessageStoreFolderTests.swift` | +1 | Cache eines gelöschten Ordners wird vollständig und ausschließlich abgeräumt |

Insgesamt laufen 84 Tests ohne Warnungen, mit echtem SQLite.

Manuell am iPhone geprüft:
- Umlaute aus dem Webmail werden in der Leiste lesbar angezeigt.
- Anlegen funktioniert auf oberster Ebene, unter dem Posteingang und unter einem Ordner.
- Fehlerfälle beim Anlegen: Trennzeichen im Namen, doppelter Name.
- Löschen leerer Ordner. Ein Ordner mit Mail wird abgelehnt, bei Unterordnern ist der Eintrag ausgegraut, Sonderordner haben keinen Eintrag.
- Wird der gerade geöffnete Ordner gelöscht, springt die Ansicht auf „Alle Eingänge“.
- Anlegen und Löschen im Flugmodus liefern eine Fehlermeldung.

---

## Bekannte Einschränkungen

- Neue Ordner sind nicht abonniert (siehe oben, als Technical Debt vermerkt).
- Der eigene IMAP-Weg für DELETE muss selbst gepflegt werden (Technical Debt, Rückbau vorgesehen).
- Die Ordnerleiste ist offline nicht verfügbar. Scheitert das Neuladen, verwirft sie auch einen schon geladenen Baum. Beides wird in v0.1.8b behoben.
- Reine Container-Ordner (`\Noselect`) haben kein Kontextmenü.
- Auf dem Mac ist noch nicht getestet. Das geschieht zusammen mit der Gestaltung der Leiste für iPad und Mac.

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.7e. Neu genutzt wird Network.framework, das Teil des Systems ist.
