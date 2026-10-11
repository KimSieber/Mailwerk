# Mailwerk – Entwicklungsdokumentation v0.1.9g

2026-10-11 · Eigene E-Mail-Adresse je Postfach (Review-Befund M6) – Abschluss des Code-Reviews v0.1.9

---

## Zusammenfassung

Ein Postfach kennt jetzt neben dem Benutzernamen eine eigene **E-Mail-Adresse**. Der Benutzername dient nur noch der Anmeldung; Versand („From“) und „Allen antworten“ nutzen die Adresse. In den Formularen ist die Adresse Pflicht und der Benutzername optional.

**Entschieden (Kim):**
- M6 wird noch in v0.1.9 umgesetzt (Variante A), damit Mailwerk mit jedem Anbieter und mit Alias-Adressen funktioniert.
- Nach dem ersten Test umgedreht: Die E-Mail-Adresse wird immer eingetragen, der Benutzername nur, wenn er davon abweicht (leer = Anmeldung mit der Adresse).
- Reihenfolge im Abschnitt „Konto“: Bezeichnung, Absendername, E-Mail-Adresse, Benutzername, Passwort.
- Jedes Feld zeigt eine feste Beschriftung und ein Beispiel, weil viele Nutzer über reine Feldbezeichnungen stolpern.

Tests: 382 → **388**, alle grün.

---

## Problem

`MailAccount.username` erfüllte drei Aufgaben: Anmeldung, Absenderadresse beim Versand und Erkennen der eigenen Adresse bei „Allen antworten“. Bei manitu ist der Benutzername die Adresse, deshalb fiel das nicht auf. Es bricht aber in drei Fällen:

- **Anmeldename ist keine Adresse** (z. B. `m0123456`): Jeder Versand scheitert mit „Absenderadresse ungültig“.
- **Absender soll eine andere Adresse sein** (Alias, iCloud mit Apple-ID als Anmeldung): Die Mail geht mit falschem Absender raus oder wird abgelehnt.
- **„Allen antworten“** erkennt die eigene Adresse nicht und setzt den Nutzer selbst auf die Empfängerliste.

## Lösung

- **`MailAccount.emailAddress`:** bei neu angelegten und bearbeiteten Postfächern immer gesetzt; `nil` nur bei älteren gespeicherten Postfächern.
- **`MailAccount.username`:** tatsächlicher Anmeldename – der eingetragene Benutzername, sonst die Adresse (`MailAccount.loginName`).
- **`MailAccount.senderAddress`**: die Adresse, sonst der Benutzername, ohne Leerraum. Einzige Quelle für Absender und eigene Adresse.
- **Ältere gespeicherte Postfächer** (iCloud-Key-Value-Speicher) haben das Feld nicht. Das synthetisierte `Codable` liest es dann als `nil`; alles läuft unverändert weiter, ohne Migration.
- **`MailSendService`:** Absender aus `senderAddress`; die Fehlermeldung verweist auf die E-Mail-Adresse statt auf den Benutzernamen.
- **`ComposeViewModel`:** eigene Adresse für „Allen antworten“ aus `senderAddress`.
- **Formulare** („Postfach hinzufügen“, „Postfach bearbeiten“):
  - Konto-Felder in der Reihenfolge Bezeichnung (z. B. Privat), Absendername (z. B. Max Müller), E-Mail-Adresse (z. B. max.mueller@mail.org), Benutzername (leer = E-Mail-Adresse), Passwort. Server: Host (z. B. imap.mail.org bzw. smtp.mail.org), Port.
  - **`LabeledInputField` (neu):** Beschriftung links fest, rechts das Feld mit dem Beispiel als Platzhalter. Ein reines Textfeld zeigt seine Bezeichnung auf dem iPhone nur als Platzhalter, der beim Tippen verschwindet.
  - Speichern geht nur mit gültiger E-Mail-Adresse; bei ungültiger Adresse erscheint ein roter Hinweis.
  - Beim Bearbeiten erscheint der Benutzername nur, wenn er von der Adresse abweicht. Ältere Postfächer zeigen ihren Benutzernamen als Adresse und bekommen sie beim Sichern eingetragen.
  - Der Verbindungstest meldet sich mit dem tatsächlichen Anmeldenamen an.
- **Postfachliste:** zeigt unter dem Namen die Absenderadresse statt des Benutzernamens.

---

## Geänderte Dateien

```
Mailwerk/
├── Models/MailAccount.swift              # emailAddress, senderAddress, loginName
├── Services/MailSendService.swift        # Absender aus senderAddress, Meldungstext
├── ViewModels/
│   ├── AddAccountViewModel.swift         # E-Mail-Adresse Pflicht, loginName, Prüfung
│   └── ComposeViewModel.swift            # eigene Adresse aus senderAddress
└── Views/
    ├── LabeledInputField.swift           # neu: Beschriftung + Feld mit Beispiel
    ├── AddAccountView.swift              # neue Reihenfolge, Beispiele, Hinweis
    ├── EditAccountView.swift             # neue Reihenfolge, Beispiele, Hinweis
    └── AccountListView.swift             # Anzeige der Absenderadresse
MailwerkTests/
└── AccountAddressTests.swift             # neu: 6 Tests
```

---

## Testverfahren

**Automatisch:** 388 Tests (Simulator), alle grün.

**Manuell:**
- Bestehende Postfächer: Liste zeigt die Adresse; „Postfach bearbeiten“ zeigt die Adresse und ein leeres Feld Benutzername.
- „Postfach hinzufügen“: Beschriftungen und Beispiele sichtbar; ungültige Adresse → roter Hinweis, Speichern gesperrt; gültige Adresse → Hinweis weg.
- Antwort aus „Test Mailwerk“ an sich selbst: Absender wie bisher, Versand ohne Fehler.
- „Allen antworten“: eigene Adresse steht nicht unter den Empfängern.

---

## Abschluss v0.1.9

Mit dieser Stufe ist das Code-Review v0.1.9 abgeschlossen. Offen gebliebene Befunde stehen bewusst auf der Liste offener Punkte:

- H6 (Verbindungen wiederverwenden)
- N14 Teil „Warteschlange offline“
- N13 (`MessageDetailView` aufteilen)
- Strukturempfehlungen (Protokolle/Injektion, SwiftLint, Lokalisierung)
- Funde aus e1: `cid:`-Bilder, Dunkelmodus bei Mails mit eigenem Hintergrund

## Nächste Schritte

- Neue Version mit funktionalen Erweiterungen auf dem Weg zum ersten Live-Gang.
