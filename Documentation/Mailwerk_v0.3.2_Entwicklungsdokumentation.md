# Mailwerk – Entwicklungsdokumentation v0.3.2

2026-10-31 · „Bugs und Optimierungen“: Watch startet in „Alle Eingänge“ und aktualisiert durch Herunterziehen, Mehrfachauswahl mit ⌘/⇧ auf dem Mac, einheitliche Fensterknöpfe auf iOS und Mac

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln und offene Punkte für den nächsten Chat zusammen. Ausgangsstand ist v0.3.1 (`ddb88b5`).

---

## Zusammenfassung

| Stufe | Vorgang | Inhalt |
|---|---|---|
| **a** | MW-62 | Watch: Start in „Alle Eingänge“, Aktualisieren durch Herunterziehen (eigene Erkennung) |
| **b** | MW-61 | Mac: Mehrfachauswahl wie Apple Mail, Kontextmenü und Entf für die Auswahl; Korrekturen „Über Mailwerk“ (iOS) und Testziel Mac |
| **c** | MW-60 | Einheitliche Fensterknöpfe: ✕ links schließt bzw. bricht ab, ✓/Senden rechts nur bei Speichern/Senden, „<“ nur auf Unterseiten; „Postfach hinzufügen“ unter der Liste |

| Kennzahl | v0.3.1 | v0.3.2 |
|---|---|---|
| Testfunktionen (`@Test`) | 885 | **891** |
| Neue Dateien | – | 3 (+ Bild `AboutIcon`) |

| Commit | Inhalt |
|---|---|
| `9d75f97` | v0.3.2a – Watch-Refresh |
| `4ff0615` | v0.3.2b – Mac: Mehrfachauswahl mit ⌘/⇧, Absturz „Über Mailwerk“ |
| (dieser) | v0.3.2c – Einheitliche Fensterknöpfe, Dokumentation v0.3.2 |

---

## 1. Entscheidungen

- **Watch-Start:** Die App öffnet direkt „Alle Eingänge“; das Menü mit Sammelansichten, Stand und „Aktualisieren“ liegt einen Schritt zurück (`NavigationStack` mit vorbelegtem Pfad).
- **Herunterziehen auf der Watch selbst erkennen:** `.refreshable` ist laut Dokumentation ab watchOS 8 verfügbar, führt die Aktion auf der Uhr aber nicht aus. Ausgelöst wird jetzt allein über die Zugstrecke über den Listenanfang hinaus (44 pt), einmal je Zug.
- **Mac-Mehrfachauswahl wie Apple Mail:** Klick öffnet, ⌘-Klick ergänzt, ⇧-Klick wählt einen Bereich, ⌥⌘A alle; bei mehreren zeigt die Mailansicht „n Mails ausgewählt“. Der Auswahlmodus von iPhone/iPad („Auswählen“, Kreise, „Fertig“) entfällt auf dem Mac.
- **Kontextmenü an der Liste (Mac):** `contextMenu(forSelectionType:)` statt eines Menüs je Zeile – nur so gilt es für die ganze Auswahl. Mehrere Mails: Kennzeichnung, Gelesen/Ungelesen, Verschieben, Löschen über die vorhandenen Sammelaktionen (mit „Rückgängig“).
- **Regel für Fensterknöpfe (iOS und Mac gleich):**
  - Fenster mit Speichern/Senden: ✕ links (Abbrechen), ✓ bzw. Senden rechts.
  - Fenster ohne Speichern (Einstellungen wirken sofort): nur ✕ links (Schließen).
  - Unterseite im selben Fenster: „<“ links (Zurück) – ein ✕ würde dort nicht schließen, sondern nur eine Ebene zurückführen.
  - Neue Listeneinträge über eine Zeile unter der Liste („Postfach hinzufügen“), kein „+“ oben.
  - Ziel: Fenster immer links oben schließen; Wiedererkennung beim Wechsel zwischen iPhone, iPad und Mac.
  - Auf iOS die Systemknöpfe von iOS 26 (Rollen `close`, `cancel`, `confirm`); ✕ für „Schließen“ entspricht der Rolle `close`, die anders als `cancel` keinen Verlust von Eingaben bedeutet.
- **App-Icon in „Über Mailwerk“ (iOS) als eigenes Bild:** Das App-Icon ist eine Icon-Composer-Datei (`AppIcon.icon`) und lässt sich nicht als Bild laden. Das Bild `AboutIcon` (1024 × 1024, aus Icon Composer exportiert) liegt im Asset-Katalog und muss bei einer Änderung des Icons neu exportiert werden.

---

## 2. Watch (Stufe a, MW-62)

- `WatchRootView`: `NavigationStack(path:)` startet mit `[.allInboxes]`; Aktualisieren beim Öffnen und bei Rückkehr in den Vordergrund unverändert.
- `WatchPullToRefresh` (neu): Modifier `watchPullToRefresh` und reine Logik `WatchPullTrigger` (Zonen „liegt an“, „gezogen“, „jenseits der Grenze“; Auslösen einmal je Zug, Rücksetzen, sobald die Liste wieder am Anfang anliegt). Haptik per `sensoryFeedback`.
- `WatchMailListView`: Herunterziehen in allen vier Listen, auch leer (Hinweis in einem `ScrollView`); während der Aktualisierung ein Rad oben rechts.
- Diagnose auf der Uhr (Simulator) belegte: Die Scroll-Phase bleibt beim Ziehen „idle“, eine zusätzliche Fingergeste (`simultaneousGesture`) blockiert das Scrollen. Finger und Krone lassen sich daher nicht unterscheiden; die Krone kann am oberen Anschlag ebenfalls auslösen (unschädlich).

---

## 3. Mac-Mehrfachauswahl (Stufe b, MW-61)

- `MacListSelection` (neu, reine Logik): wertet die Listenauswahl aus – leer → schließen, eine Mail → öffnen, mehrere → Anzahl; Zeilen ohne Mail (Serversuche) zählen nicht; `pruned` entfernt verschwundene Mails.
- `InboxView`: `macSelection` als Auswahl der Liste, mit der geöffneten Mail (`selectedMessageID`) abgeglichen; `macContextMenu`, `handleSelectionMenuAction`, `macMultiSelectionPlaceholder`; Entf löscht auch mehrere (`canDeleteFromCommand`, `deleteFromCommand`); `confirmDeleteSelection` für Befehlsleiste und Kontextmenü gemeinsam. Entwürfe: Liste ohne Auswahl, Klick öffnet weiterhin das Verfassen-Fenster.
- `MessageMenu`: `MessageSelectionMenuItems` (Menü für mehrere Mails), `MenuEntryButton` für beide Menüs, Eintrag „Mails löschen“.
- `MacListHeaderBar`: Auswahlzeile („Alle auswählen“, „Fertig“) entfernt.
- Korrekturen:
  - `AboutView`: `UIImage(named: "AppIcon")` brach im Simulator mit iOS 27 mit „Need an imageRef“ ab, statt `nil` zu liefern → Bild `AboutIcon` aus dem Asset-Katalog.
  - `RefreshEvaluationTests`: der Test von `WatchBridge` (gibt es nur unter iOS) nur unter iOS übersetzen; der Testbau für den Mac schlug fehl.

---

## 4. Fensterknöpfe (Stufe c, MW-60)

| Fenster | Mac | iOS |
|---|---|---|
| Postfächer | ✕ links (statt ✓ rechts) | ✕ links; „+“ oben entfernt, „Postfach hinzufügen“ unter der Liste |
| Postfach hinzufügen / bearbeiten | ✕ + ✓ (unverändert) | ✕ + ✓ statt „Abbrechen“ / „Speichern“ bzw. „Sichern“ |
| Spamfilter | ✕ links (statt ✓ rechts) | ✕ links (statt „Fertig“ rechts) |
| Spamliste (Unterseite) | „<“ (unverändert) | „<“ (unverändert) |
| Über Mailwerk | eigenes Fenster | ✕ als Systemknopf |
| Lizenzliste | ✕ links (statt ✓ rechts) | Unterseite mit „<“ |
| Kontaktkarte | ✕ links (statt „Fertig“ rechts) | Systemkarte (unverändert) |
| Signatur (Unterseite mit Speichern) | ✕ + ✓ (unverändert) | ✕ + ✓ statt Text |
| Entwurf laden, In Ordner verschieben | ✕ (unverändert) | ✕ statt „Abbrechen“ |
| Von der Watch übergebene Mail | – | ✕ statt „Fertig“ |

Bewusst unverändert: „Fertig“ im Auswahlmodus der Liste (iOS) – kein Fenster, sondern Ende des Modus, wie in Apple Mail. Verfassen, Originalquelle und Teilen-Erweiterung hatten ✕ bereits links.

---

## 5. Dateien

**Neu:**

| Datei | Inhalt |
|---|---|
| `MailwerkWatch/WatchPullToRefresh.swift` | Herunterziehen auf der Watch |
| `Mailwerk/ViewModels/MacListSelection.swift` | Regeln der Mac-Mehrfachauswahl |
| `MailwerkTests/MacListSelectionTests.swift` | Tests dazu (6) |
| `Mailwerk/Assets.xcassets/AboutIcon.imageset` | App-Icon als Bild für „Über Mailwerk“ |

**Geändert:** `WatchRootView`, `WatchMailListView`, `InboxView`, `MessageMenu`, `MacListHeaderBar`, `MacMenuCommands`, `AboutView`, `LicenseListView`, `AccountListView`, `AddAccountView`, `EditAccountView`, `SpamSettingsView`, `SignatureEditorView`, `DraftComposeLoader`, `FolderMoveSheet`, `ContactCardView`, `RefreshEvaluationTests`.

---

## 6. Tests

| Punkt | Ergebnis |
|---|---|
| Build aller Ziele, Unit-Tests (iOS und Mac) | erfolgreich |
| Watch: Start in „Alle Eingänge“, Zurück ins Menü, Herunterziehen (Simulator) | erfolgreich |
| Watch: Herunterziehen auf der echten Uhr | **offen** – mit dem nächsten TestFlight-Build |
| Mac: Klick, ⌘-Klick, ⇧-Klick, Alle auswählen; Kontextmenü für die Auswahl | erfolgreich |
| iPhone: Kontextmenü, Auswahlmodus, Befehlsleiste (Kennzeichnung, Löschen) | erfolgreich |
| iPhone: „Über Mailwerk“ (Simulator iOS 27) | erfolgreich nach Korrektur |
| Fensterknöpfe Mac und iPhone nach Abschnitt 4 | erfolgreich |

---

## 7. Beobachtungen und Erkenntnisse

- **`.refreshable` auf watchOS** ist verfügbar, löst auf der Uhr aber nichts aus. Die Scroll-Phase (`onScrollPhaseChange`) bleibt dort beim Ziehen „idle“; eine `simultaneousGesture` mit `DragGesture(minimumDistance: 0)` blockiert das Scrollen der Liste.
- **Icon-Composer-Icons** (`.icon`) stehen nicht im Asset-Katalog und lassen sich nicht per `UIImage(named:)` laden; unter iOS 27 (Simulator) bricht der Aufruf ab. Export als Bild: Icon Composer → File → Export.
- **Kontextmenü auf dem Mac:** Ein Menü je Zeile kennt nur diese Zeile; für eine Mehrfachauswahl muss es an der Liste hängen (`contextMenu(forSelectionType:)`).
- **Testziel Mac:** Tests, die nur unter iOS vorhandene Typen nutzen, brauchen dieselbe Bedingung wie der Typ (`#if os(iOS) && canImport(WatchConnectivity)`); auffällig erst, wenn die Tests mit „My Mac“ laufen.
- **Outlook (OAuth 2):** Eine abgelaufene Anmeldung zeigte sich als Zeitüberschreitung der XOAUTH2-Anmeldung (10 s, fest in SwiftMail) statt als Ablehnung; Mailwerk erkannte sie deshalb nicht als „Anmeldung erforderlich“. Nach erneuter Anmeldung lief alles.

---

## Gesamtstand des Projekts (Stand 31.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS, macOS und watchOS. Repo `github.com/KimSieber/Mailwerk` (public, MIT-Lizenz; Name und Icon ausgenommen), Branch `main`.
- Version **0.3.2** (die Versionsnummer `MARKETING_VERSION` wird manuell in Xcode gesetzt), **891 Testfunktionen**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkWatch Watch App, MailwerkWatchWidgetExtension, MailwerkTests, MailwerkUITests.
- **Ziel:** Veröffentlichung im App Store; neue Nacharbeiten nur aufnehmen, wenn sie dafür nötig sind.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; iOS/macOS/watchOS 26.5; getestet auch im Simulator mit iOS 27.
- **SwiftMail 1.15.0**, Versionen über `Package.resolved` festgelegt.
- Datenbank: SQLite (WAL, getrennte Lese-/Schreibverbindung), FTS5-Suchindex.
- Abruf: eine IMAP-Verbindung je Postfach und Runde, höchstens 3 Postfächer gleichzeitig (2 je Server); Entscheidungen in reinen Planern.
- Erscheinungsbild: Farben, Abstände, Radien und Animationen zentral in `AppTheme`; Fensterknöpfe nach der Regel in Abschnitt 1.

### Arbeitsregeln (verbindlich)
- Nichts bauen ohne ausdrückliche Freigabe; Inhalt jeder Version vorher abstimmen; große Schritte in 3–4 Teile mit eigenem Testpunkt.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen.
- Lieferung als ganze Dateien direkt in den Projektordner (Prüfsummen vorher und nachher); Claude committet nicht; Commit-Text erst nach erfolgreicher Abnahme einer Stufe.
- Inline-Doku: Datei-Header (Autor, Erstellt, Geändert, Zweck, Abgrenzung, Abhängigkeiten), Kopfkommentar je Funktion, Deutsch; „Geändert“ bei jeder Lieferung nachziehen.
- Ursache belegen statt raten (Protokoll, Diagnose-Anzeige auf dem Gerät).
- Code-Review nach `code-review.md` (Fassung 1.1) als Maßstab für neue Stufen.
- Öffentliche Dokumentation ohne persönliche Bezüge; Arbeitsdokumente in `Documentation/Intern/` (nicht in Git).

### Offene Punkte
- **Watch:** Herunterziehen auf der echten Uhr prüfen (Gefühl der Zugstrecke, Auslösen durch die Krone); Grenze ggf. anpassen.
- **Handoff Watch → iPhone** funktioniert nicht (auch in TestFlight); eigenes Thema.
- **Outlook:** abgelaufene Anmeldung als Zeitüberschreitung statt als „Anmeldung erforderlich“ erkannt; untersuchen.
- **Code-Review:** neuer Prüflauf mit Fassung 1.1.
- Übrige offene Punkte unverändert wie in v0.3.1 (Mac: größere HTML-Mails, Übersetzung für weitere Sprachen, Abnahme iPad/Watch über TestFlight, Ordnerliste über eigene Verbindung, Default Mail App, Azure-Herausgeber-Verifizierung vor dem App Store).

### Fahrplan
- **Jetzt:** Versionsnummer 0.3.2 setzen, TestFlight-Build hochladen, Watch auf der Uhr prüfen.
- **Danach:** Handoff, dann die für den App Store nötigen Punkte (Herausgeber-Verifizierung, Store-Auftritt, Screenshots).
