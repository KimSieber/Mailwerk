# Mailwerk – Entwicklungsdokumentation v0.1.8c

2026-09-30 · Verschieben-Dialog mit Ordnerbaum

---

## Zusammenfassung

Der Dialog „In Ordner verschieben“ zeigt jetzt denselben Ordnerbaum wie die Seitenleiste: gleiche Symbole, deutsche Namen der Sonderordner, lesbare Umlaute, Unterordner eingerückt. Die Ordnerliste kommt aus dem Cache und erscheint sofort, auch offline; im Hintergrund wird vom Server aktualisiert.

Nicht wählbar sind der Ordner, in dem die Mail liegt (mit „aktuell“ gekennzeichnet), und reine Container-Ordner. Alle übrigen sind Ziele, auch Posteingang, Archiv, Papierkorb und Spam. Offline bleibt der Dialog offen und meldet beim Tippen auf ein Ziel, dass Verschieben eine Verbindung braucht.

---

## Geänderte Dateien

```
Mailwerk/
├── Models/FolderNode.swift              # + isMoveTarget(from:)
├── Services/MailActionService.swift     # fetchFolders entfernt (ohne Nutzer)
└── Views/
    ├── MessageDetailView.swift          # neuer Dialog; FolderPickerSheet und
    │                                    #   das Laden je Öffnen entfernt
    └── Folders/
        ├── FolderMoveSheet.swift        # NEU – Verschieben-Dialog
        ├── FolderLabel.swift            # NEU – Symbol + Name, gemeinsam genutzt
        └── FolderSidebarView.swift      # nutzt FolderLabel (Aussehen unverändert)
MailwerkTests/
└── FolderTreeBuilderTests.swift         # + 2 Tests zur Zielregel
```

Datenbank: keine Änderung. Unterm Strich rund 60 Zeilen weniger Code.

---

## Entscheidungen

| Entscheidung | Begründung |
|---|---|
| Identische Anzeige wie in der Seitenleiste, über den gemeinsamen Baustein `FolderLabel` | Wiedererkennung. Beide Ansichten können nicht auseinanderlaufen |
| Ordnerliste aus dem Cache, Aktualisierung im Hintergrund | Der Dialog öffnet sofort und funktioniert offline. Bisher wurde bei jedem Öffnen vom Server geladen |
| Spam bleibt als Ziel | Etwas ablegen, ohne gleich eine Regel anzulegen |
| Posteingang ist jetzt Ziel | Bisher herausgefiltert. Eine Mail lässt sich damit aus dem Archiv zurückholen |
| Aktueller Ordner sichtbar, aber ausgegraut | Orientierung im Baum, ohne ein sinnloses Ziel anzubieten |
| Kein „Neuer Ordner …“ im Dialog | Ordner anzulegen soll ein bewusster, eigener Vorgang bleiben. Die Struktur bleibt flach |
| Kein „Zuletzt verwendet“ | Bei kurzer Ordnerstruktur ohne Nutzen |
| Offline erst beim Tippen auf ein Ziel melden, keine Warteschlange | Eine Warteschlange für offline ausgelöste Aktionen wäre ein eigenes, größeres Thema |
| Nur Ordner desselben Postfachs | IMAP verschiebt nicht über Postfächer hinweg |

---

## Tests

Insgesamt laufen 107 Tests ohne Warnungen. Neu sind zwei Tests zur Zielregel `isMoveTarget(from:)`, darunter, dass „INBOX“ unabhängig von der Schreibweise gilt (RFC 3501).

Manuell am iPhone geprüft: Aussehen wie in der Leiste, Verschieben in einen Unterordner, zurück in den Posteingang, nach Spam, Verhalten offline, Seitenleiste unverändert.

---

## Beobachtungspunkt

Einmalig, nicht reproduzierbar: Nach dem Verschieben saß der Knopf für die Seitenleiste kurz rechts bei Zahnrad und Verfassen statt links. Er war bedienbar, und nur die Darstellung war betroffen.

Vermutliche Ursache: Der Knopf nutzt die Rolle `.navigation`, nicht eine feste Seite. Berechnet SwiftUI die Werkzeugleiste mitten in der Schließen-Animation neu, während links noch der Zurück-Knopf liegt, kann der Knopf in die rechte Gruppe rutschen.

Falls das wieder auftritt: unter iOS ausdrücklich `.topBarLeading` setzen. Wegen der anderen Plattformen nicht ungeprüft ändern.

---

## Nächste Schritte

- **v0.1.8d:** Server-Abgleich des Caches (Gelesen- und Kennzeichnungsstatus älterer Mails, anderswo gelöschte oder verschobene Mails) sowie Bereinigung beim Löschen eines Postfachs.
- Später: Kontextmenü für Mails in der Liste (Verschieben, Gelesen, Kennzeichnen, Löschen) und Zoomen in Mails, beides zusammen mit der Detailansicht für iPad und Mac.

## Abhängigkeiten / Xcode-Konfiguration

Unverändert gegenüber v0.1.8b.
