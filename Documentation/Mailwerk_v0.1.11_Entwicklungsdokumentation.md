# Mailwerk – Entwicklungsdokumentation v0.1.11

2026-10-12 · Mehrere Mails auswählen und gemeinsam bearbeiten (Jira MW-9), gemeinsames Mail-Menü, Kontextmenü in der Liste

---

## Zusammenfassung

Langes Drücken auf eine Mail in der Liste öffnet ein Kontextmenü. Es ist dasselbe Menü wie in der Mailansicht, ergänzt um „Auswählen“. „Auswählen“ startet die Mehrfachauswahl: Vor den Zeilen erscheinen Kreise, unten schwebt eine Befehlsleiste mit vier Symbolen. Mailmenü und Kontextmenü kommen aus einem gemeinsamen Baustein, haben nur noch einzeilige Einträge und ein aufgeräumtes Spam-Untermenü. `MessageDetailView` ist aufgeteilt (N13).

**Entschieden:**
- **Geste:** Langes Drücken öffnet das Kontextmenü, darin „Auswählen“ als erster Eintrag (keine eigene Langdruck-Geste, die direkt in die Auswahl springt).
- **Menüs gleich:** Kontextmenü = Mailmenü plus „Auswählen“. Teilen, Drucken und Anlagen lokal löschen gibt es nur in der Mailansicht.
- **Eine Zeile je Eintrag:** „Kennzeichnung“ (Symbol zeigt die Wirkung), „Gelesen“/„Ungelesen“ (nach dem Zielzustand), „Verschieben“, „Mail löschen“. „Anlagen lokal löschen“ darf zweizeilig bleiben. Bei großer Systemschrift bricht iOS weiterhin um.
- **Spam-Untermenü:** je ein Abschnitt für Adresse und Domain, der Wert als kleine graue Überschrift, darunter „Blockieren“ und „Vertrauen“ (Mailansicht und Kontextmenü).
- **Auswahlmodus:** links „Alle auswählen“ (bei voller Auswahl „Auswahl aufheben“), Mitte „n ausgewählt“, rechts „Fertig“. Der Modus endet nach jeder Sammelaktion und beim Wechsel der Ansicht. Die Auswahl hängt an der Mail, nicht an der Position.
- **Befehlsleiste:** schwebende Glas-Kapsel unten, nur Symbole: Kennzeichnung, Gelesen, Verschieben, Löschen. Sie belegt den Platz, der sonst für die Suche vorgesehen ist. Jeder Knopf hat eine ausführliche Bezeichnung für VoiceOver und Sprachsteuerung; bei sehr großer Schrift zeigt iOS sie beim Gedrückthalten vergrößert.
- **Gemischte Auswahl:** mindestens eine nicht gekennzeichnet → kennzeichnen, sonst Kennzeichnung entfernen; mindestens eine ungelesen → gelesen, sonst ungelesen. Geändert werden nur die abweichenden Mails.
- **Verschieben** gesperrt, wenn die Auswahl aus mehreren Postfächern stammt.
- **Löschen** immer mit Rückfrage samt Anzahl.
- **Spam** nicht als Sammelaktion – bewusster Vorgang je Mail.
- **Rückgängig (5 Sekunden, unten)** nach jeder Änderung von Kennzeichnung oder Gelesen in der Liste: Wischaktion, Kontextmenü und Sammelaktion. Nicht für Verschieben und Löschen.
- **Mac:** nur Grundfunktion; Gestaltung in v0.2.x.

Tests: 431 → **446**, alle grün.

---

## MVP a – Gemeinsames Menü, Aufteilung der Mailansicht, Kontextmenü

**Problem:** Das Aktionsmenü lag fest in `MessageDetailView` (~760 Zeilen), mit langen, umbrechenden Einträgen. Die Liste hatte nur Wischaktionen. „Rückgängig“ gab es nur beim Entfernen der Kennzeichnung in „Gekennzeichnet“.

**Lösung:**
- `MessageMenu.swift` (neu): `MessageMenuItems` (Einträge für `Menu` und `contextMenu`, mit Platz für zusätzliche Einträge vor „Mail löschen“), `ReplyMenuButtons`, `MessageMenuContext`, `MessageMenuAction`, `SpamMenuRequest`, `MessageMenuLabels` (Texte, Symbole, Bezeichnungen für Bedienungshilfen – testbar an einer Stelle).
- `MessageActionDialogs.swift` (neu): Rückfrage Löschen (mit Anzahl), Rückfrage Spam, Ergebnis- und Fehlermeldung; `SpamMenuRequest.perform` für Mailansicht und Liste.
- N13: `MessageDetailHeader.swift` (neu, Kopfbereich und Hinweis „Externe Inhalte blockiert“), `MessageAttachmentList.swift` (neu). `MessageDetailView` 762 → 592 Zeilen, Spam-Logik nicht mehr doppelt.
- Kontextmenü in `InboxView`: Antworten/Weiterleiten lädt die vollständige Mail aus dem Cache; Verschieben über `FolderMoveSheet`; Löschen und Spam mit Rückfrage. Ein gemeinsamer Rückfragekanal der Liste (Kontextmenü vor der Warteschlange „Spam-Ordner anlegen?“).
- `MessageActions.StateChange` (neu): umkehrbare Änderung (Kennzeichnung, Gelesen) mit `reversed`; `UndoOffer` (neu) mit Text („Kennzeichnung entfernt“, „3 Mails als gelesen markiert“). `UndoBanner` zeigt den jeweiligen Text.

## MVP b – Mehrfachauswahl und Sammelaktionen

**Lösung:**
- `MailActionService`: Gelesen, Kennzeichnung, Löschen und Verschieben auch für mehrere UIDs eines Ordners (`uids:`) – **ein IMAP-Befehl je Ordner** über eine Verbindung (SwiftMail `store` mit `UIDSet`, `move(messages:)`). Die Einzelaktionen nutzen dieselben Wege.
- `MessageActions`: `groups` (je Postfach und Ordner, Reihenfolge des ersten Auftretens), Sammelfunktionen `apply`, `delete`, `move` mit `BatchOutcome` (gelungene Mails, gescheiterte Gruppen). Eine gescheiterte Gruppe hält die anderen nicht auf.
- `MessageSelection.swift` (neu): Regeln der gemischten Auswahl, betroffene Mails, Sperre beim Verschieben, gemeinsamer Ordner (im Verschieben-Dialog ausgegraut).
- `InboxViewModel`: `isSelecting`, `selectedIDs`, Auswahl beginnen/beenden/alle; Sammelaktionen; verschwundene Mails fallen beim Neuladen aus der Auswahl; ehrliche Meldung bei Teilerfolg („2 von 7 Mails nicht bearbeitet“ je Postfach). „Rückgängig“ läuft ebenfalls je Ordner als ein Befehl.
- `InboxView`: `List(selection:)` nur im Auswahlmodus (sonst `nil`, damit Öffnen per Tipp unverändert bleibt), auf iOS mit Bearbeitungsmodus (Kreise, Wischaktionen aus). Symbolleiste wechselt im Auswahlmodus. Leiste über `safeAreaInset` am unteren Rand.
- `SelectionActionBar.swift` (neu): Glas-Kapsel mit vier Symbolknöpfen, Löschen rot.

**Fund beim Bauen:** `.map(MessageActions.Target.init)` warnte „Call to main actor-isolated initializer in a synchronous nonisolated context“ – die Initialisierer-Referenz verliert die Main-Actor-Bindung. Ersetzt durch `.map { MessageActions.Target($0) }`.

---

## Geänderte Dateien

```
Mailwerk/
├── Services/
│   └── MailActionService.swift        # Sammelvarianten (uids:)
├── ViewModels/
│   ├── InboxViewModel.swift           # Kontextmenü-Aktionen, Rückgängig, Mehrfachauswahl
│   ├── MessageActions.swift           # StateChange, apply, Sammelaktionen, groups
│   ├── MessageSelection.swift         # neu
│   └── UndoOffer.swift                # neu
└── Views/
    ├── InboxView.swift                # Kontextmenü, Auswahlmodus, Leiste, Symbolleiste
    ├── MessageDetailView.swift        # aufgeteilt, gemeinsames Menü
    ├── MessageDetailHeader.swift      # neu
    ├── MessageAttachmentList.swift    # neu
    ├── MessageMenu.swift              # neu
    ├── MessageActionDialogs.swift     # neu
    └── SelectionActionBar.swift       # neu
Mailwerk.xcodeproj/project.pbxproj     # Version 0.1.11
MailwerkTests/
├── MessageMenuTests.swift             # neu, 8 Tests
└── MessageSelectionTests.swift        # neu, 7 Tests
```

---

## Testverfahren

**Automatisch:** 446 Tests (Simulator), alle grün.

**Manuell (Simulator/iPhone, Testordner „Test Mailwerk“):**
- Mailansicht: neues Menü mit einzeiligen Einträgen, Spam-Untermenü mit Überschriften, alle Aktionen.
- Kontextmenü im Posteingang und im Testordner: alle Aktionen; Rückgängig nach Wischaktion, Kontextmenü und Sammelaktion.
- Auswahl über „Auswählen“, Kennzeichnung, Gelesen, Verschieben, Löschen mit mehreren Mails.
- Mac: Grundfunktion.

---

## Beobachtungen

- Auf dem Mac ist die Liste im Auswahlmodus per Klick (⌘-Klick für mehrere) auswählbar; Kreise gibt es dort nicht. Gestaltung folgt in v0.2.x.
- Die Leiste belegt im Auswahlmodus den Platz der späteren Suche (v0.1.15); die Suche muss sich dort ausblenden.

## Nächste Schritte

- v0.1.12: Mails vollständig und lesbar anzeigen (`cid:`-Bilder, Dunkelmodus, Zoomen; zuletzt Originaltext/Header MW-5). Inhalt zuerst abstimmen.
- Merkliste unverändert: DKIM/Authentication-Results, H6, N14 Offline-Warteschlange, Ordner abonnieren, Vorschau-Spalte klären.
