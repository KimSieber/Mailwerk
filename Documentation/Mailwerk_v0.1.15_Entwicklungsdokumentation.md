# Mailwerk – Entwicklungsdokumentation v0.1.15

2026-10-15 · Teilen mit Mailwerk (Jira MW-15): Dateien, Fotos, Kontakte, Links und Text aus anderen Apps als neue Mail – iPhone/iPad und Mac

---

## Zusammenfassung

Anforderung: Bilder, Dokumente und andere Inhalte (bei Apple üblich, z. B. Kontakte) über „Teilen mit …“ an Mailwerk übergeben. Sie sollen als Anlage in einer neuen Mail landen, wie in anderen Mailprogrammen.

**Entscheidungen (abgestimmt):**

| Frage | Entscheidung |
|---|---|
| Wo wird verfasst? | **Direkt im Teilen-Fenster** (Variante A, wie Apple Mail/Spark): volles Verfassen-Fenster über der teilenden App, Versand von dort. Verworfen: nur übergeben und in der App weiterschreiben (iOS erlaubt einer Erweiterung nicht, die App zu öffnen). |
| Mac gleich mit? | **Ja.** Die Funktion ist auf dem Mac vorhanden, Gestaltung und Feinschliff folgen mit v0.2.x. |
| Absender und Signatur | **Wie eine neue Mail in einer Sammelansicht der App:** Standard-Postfach vorbelegt und änderbar, ohne Standard leer. Die Signatur des Postfachs wird eingesetzt und wechselt mit dem Absender. Postfächer mit ausgeschaltetem Abruf bleiben wählbar. |
| Was wird wie übernommen? | Fotos, Videos, PDFs, sonstige Dateien → **Anlage**. Kontakt → Anlage `.vcf`. Link → antippbarer Link im Text, Seitentitel als Betreff. Markierter Text → Text. **Fotos immer als Anlage**, nicht in den Text (wer ein Foto im Text will, nutzt Kopieren und Einfügen). **Geteilte Dateien immer als Anlage**, auch Text- und CSV-Dateien. |
| Senden und Fehler | Nach „Senden“ bleibt das Fenster mit Fortschritt offen, bis Versand und Gesendet-Kopie fertig sind. Bei einem Fehler bleibt es offen mit Hinweis: erneut senden, **als Entwurf sichern** oder verwerfen (dieselbe Rückfrage wie in der App). Offline wie in der App, keine eigene Warteschlange (N14). Keine eigene Größengrenze. |

**Umsetzung in zwei Commits:**

| Paket | Inhalt | Commit |
|---|---|---|
| **a+b** | Grundlage (App Group, Abschrift) und Erweiterung für iPhone/iPad. Auf Wunsch zusammen mit einem Testdurchlauf. | `47bd2f8` |
| **c** | Erweiterung für den Mac, dazu zwei Korrekturen aus dem Mac-Test, die auch iOS betreffen (Dateiverweise, Datei vor Text) | (folgt) |

Tests: 540 → **551** (11 neue), alle grün. `MARKETING_VERSION` 0.1.15 für App und beide Erweiterungen.

---

## Aufbau

```
Teilende App ──Teilen──▶ Erweiterung (eigener Prozess, eigene Sandbox)
                          ├─ ShareViewController   (iOS: UIKit / Mac: AppKit, je Ziel)
                          ├─ ShareRootView         (gemeinsam, SwiftUI)
                          │    ├─ liest ShareContext.json  ◀── App Group ◀── App: ShareContextPublisher
                          │    ├─ SharedItemLoader → SharedContent
                          │    └─ ComposeView(kind: .new, shared:, onClose:)
                          └─ Passwort über gemeinsame Schlüsselbundgruppe
```

**Ziele in Xcode:**

| Ziel | Plattform | Bundle | Eingebettet |
|---|---|---|---|
| `Mailwerk` | iOS, macOS | `de.sieber-bw.Mailwerk` | – |
| `MailwerkShare` | iOS | `…Mailwerk.MailwerkShare` | nur iOS (Plattform-Filter) |
| `MailwerkShareMac` | macOS | `…Mailwerk.MailwerkShareMac` | nur macOS (Plattform-Filter) |

Beide Erweiterungen:
- sind Mitglied des gesamten Ordners `Mailwerk/`, ausgenommen `MailwerkApp.swift` (`@main`) und `Info.plist`;
- binden SwiftMail ein;
- haben die Capabilities **App Groups** `group.de.sieber-bw.Mailwerk` und **Keychain Sharing** `de.sieber-bw.Mailwerk`;
- der Mac zusätzlich **App Sandbox** mit „Outgoing Connections (Client)“ und „Contacts“.

`ShareRootView.swift` und `SharedItemLoader.swift` liegen in `MailwerkShare/` und gehören zusätzlich zum Mac-Ziel. Die App hat zusätzlich die App Group.

**Warum der ganze Mailwerk-Ordner:** Das Verfassen-Fenster hängt an vielen Diensten (Versand, Signaturen, Entwürfe, Editor, HTML-Rückweg). Eine Auswahl einzelner Dateien wäre anfällig, sobald eine neue Abhängigkeit dazukommt. Nicht genutzter Code kostet nur Größe, keinen Speicher zur Laufzeit.

---

## Paket a+b – Grundlage und Erweiterung iPhone/iPad

### Passwörter

Die Passwörter liegen schon bisher im ersten Eintrag von `keychain-access-groups` der App (`$(AppIdentifierPrefix)de.sieber-bw.Mailwerk`, synchronisiert über iCloud). Die Erweiterung bekommt dieselbe Gruppe. `KeychainService` sucht ohne Gruppenangabe, also in allen Gruppen. **Keine Codeänderung, keine Migration.**

### Abschrift für die Erweiterung (`ShareContext`, `ShareContextPublisher`)

**Problem:** Postfächer liegen im iCloud-Key-Value-Speicher der App, Signaturen in SwiftData mit CloudKit. Ein zweiter Prozess mit eigenem CloudKit-Abgleich auf denselben Daten wäre fehleranfällig und beim ersten Start langsam.

**Lösung:**
- `ShareContext` (Codable): Postfächer, Standard-Postfach, Signaturen (samt Logo), Formatfassung.
- `ShareContextFile` schreibt und liest `ShareContext.json` im Ordner der App Group:
  - schreibt nur bei Änderung (sortierte Schlüssel, byte-genauer Vergleich), atomar, iOS-Dateischutz „nach erstem Entsperren“;
  - Lesen liefert `.loaded`, `.missing` oder `.unreadable` (auch bei neuerer Formatfassung).
- `ShareContextPublisher` (in `AppObjects`) beobachtet `AccountStore` und `SignatureStore` per `withObservationTracking` und schreibt bei jeder Änderung, auch bei Änderungen per iCloud von anderen Geräten. Er hält sich bewusst selbst fest, weil er so lange wie die App lebt.
- **Keine Passwörter** in der Abschrift.

**In der Erweiterung:**
- `AccountStore(shareContext:)`: nur lesender Store ohne iCloud. `store` ist jetzt optional, Schreibwege werden ohne Store übersprungen. Ein nicht mehr vorhandenes Standard-Postfach entfällt.
- Signaturen über den vorhandenen `InMemorySignatureStorage` (ohne iCloud-Abo).
- `SignatureKind`/`SignatureItem` sind dafür `Codable`.

### Geteilte Inhalte (`SharedContent`, `SharedItemLoader`)

`SharedContent` enthält reine Regeln ohne Oberfläche, unter Linux testbar:
- **Betreff** = mitgelieferte Überschrift, nur wenn ein Link geteilt wurde, einzeilig und höchstens 200 Zeichen.
- **Text:** erst Texte, dann Links als eigene Absätze. Leere Texte entfallen, ebenso ein Text, der nur einer der Links ist (manche Apps liefern beides).
- **Dateinamen:** Endung des Typs ergänzen, wenn keine vorhanden ist. Ersatzname nach Art des Inhalts (Foto, Video, Kontakt, Dokument, Anhang). Gleiche Namen nummerieren („Foto 2.jpeg“). Keine Pfadzeichen.

`SharedItemLoader` (nonisolated, Rückrufe des Systems kommen auf beliebigen Threads) übernimmt je Anbieter (`NSItemProvider`) genau einen Inhalt. Rangfolge in der Endfassung nach Paket c:
1. Web-Link (http/https) → Link.
2. **Dateiverweis** (`public.file-url`, Finder, Dateien-App) → immer Anlage mit Originalname, Datei im Rückruf gelesen (mit Zugriffsrecht).
3. Reiner Text ohne Dateinamen (markierter Text) → Text.
4. Sonst Daten → Anlage. Bei Bildern **JPEG, wenn angeboten** (Empfänger ohne HEIC), sonst das erste Bildformat. Passt die Endung des vorgeschlagenen Namens nicht zum gewählten Typ (z. B. `IMG_1.HEIC` als JPEG), wird sie ersetzt.

Weitere Regeln:
- Anbieter werden nacheinander gelesen, nicht parallel (Speicher der Erweiterung).
- Nicht lesbare Teile werden gezählt. Ein Hinweis „Nicht alles übernommen“ erscheint, der Rest wird übernommen.

### Verfassen-Fenster

- `ComposeViewModel.init(…, shared:)`:
  - Anlagen anhängen, Text über `sharedBody` (Links mit Attribut `.link`, der Versand macht daraus `<a href>`), Betreff setzen.
  - Die Vorbelegung zählt beim Schließen nicht als Eingabe, wie bei mailto.
- `ComposeView(…, shared:, onClose:)`: Mit `onClose` schließt das Fenster über die Erweiterung statt per `dismiss` (alle bisherigen `dismiss()`-Stellen laufen über `close()`).
- `HTMLMailView` öffnet Links jetzt über `openURL` aus der SwiftUI-Umgebung statt `UIApplication.shared`/`NSWorkspace`. Grund: `UIApplication.shared` ist in Erweiterungen gesperrt. In der App ist das Verhalten gleich.

### Erweiterung iOS

- `ShareViewController` (UIKit) bettet `ShareRootView` per `UIHostingController` ein.
- `isModalInPresentation = true`: Herunterwischen schließt nicht, nur ✕ mit der gewohnten Rückfrage.
- Nach Versand bzw. Entwurf `completeRequest`, sonst `cancelRequest`.
- `ShareRootView`:
  - Laden („Inhalte werden übernommen …“), dann Verfassen-Fenster.
  - Ohne Abschrift: Hinweis „Bitte öffne Mailwerk einmal …“.
  - Ohne Postfach: „Bitte richte zuerst … ein Postfach ein.“
- **Aktivierungsregel** (`Info.plist`): Abfrage (`SUBQUERY`) auf Anhänge, die `public.data`, `public.url` oder `public.vcard` entsprechen. Die erste Fassung mit festen Kategorien (Anhänge, Dateien, Bilder …) bot Mailwerk in **Kontakte** nicht an, weil eine vCard in keine dieser Kategorien fiel. Ursache am Verhalten belegt, nach der Umstellung behoben.

### Korrekturen während der Umsetzung

- **`.link` braucht UIKit/AppKit:** Wegen MemberImportVisibility braucht jede Datei den Import des Moduls, aus dem ein Name stammt. `ComposeViewModel` und `ShareContextTests` importieren UIKit bzw. AppKit.
- **Warnung „captured var 'self' in concurrently-executing code“** im Publisher: `[weak self]` an eine nebenläufige `Task` weitergereicht. Lösung: Der Beobachter hält sich selbst fest (siehe oben).

---

## Paket c – Erweiterung Mac

### Mac-Ziel

- Eigenes Ziel `MailwerkShareMac`, weil Xcode die Share Extension je System als eigene Vorlage anbietet.
- `ShareViewController` (AppKit) ohne xib, `NSHostingView`, Größe `MacSheetSize.composer` (720 × 640).
- Gleiche `Info.plist`-Regel wie iOS, ohne Vorlage-Symbol.
- **Plattform-Filter** in **Build Phases** der App: Target Dependencies und Embed Foundation Extensions, `MailwerkShare` → iOS, `MailwerkShareMac` → macOS. Ohne Filter würde der iOS-Build die Mac-Erweiterung einbetten und umgekehrt.
- `ShareRootView` hat auch beim Laden und bei Hinweisen die Größe des Verfassen-Fensters (`macSheetFrame(.composer)`).

### Fund 1: Kein Senden-Knopf auf dem Mac

**Ursache:** In der App öffnet sich das Verfassen-Fenster als Sheet, dort zeigt macOS ✕ und Senden in der Symbolleiste. In der Erweiterung gibt es keine Fensterleiste, die Symbolleiste blieb unsichtbar (auch der Titel).

**Lösung:** Läuft das Fenster in der Erweiterung (`onClose` gesetzt), bekommt es auf dem Mac eine eigene **Kopfleiste** mit ✕, Titel und Senden (`safeAreaInset`, `.bar`). Die Knöpfe sind dieselben (`closeButton`, `sendButton`), in der App bleibt es bei der Symbolleiste.

**Hängendes Fenster** (vor der Korrektur): Prozess `MailwerkShareMac` in der Aktivitätsanzeige beenden oder `killall MailwerkShareMac`, ohne Neustart.

### Fund 2: Datei aus dem Finder kam als „Anhang.html“

**Ursache (vermutet, nicht belegt):** Der Finder übergibt Dateien als Verweis (`public.file-url`). Ohne eigene Behandlung wurde der Verweis statt der Datei übernommen.

**Lösung:** eigener Zweig für Dateiverweise (Datei lesen, Originalname, Typ aus der Endung). Gilt auch für die Dateien-App auf iOS.

### Fund 3: `.csv`/`.txt` aus dem Finder landeten im Mailtext

**Ursache:** Text- und CSV-Dateien gelten als `public.plain-text`. Der Finder liefert keinen vorgeschlagenen Namen, deshalb griff die Text-Regel vor der Datei.

**Lösung:** Dateiverweise werden **vor** Text geprüft, eine geteilte Datei wird also immer angehängt.

---

## Geänderte Dateien (gesamte Version)

```
Mailwerk.xcodeproj/project.pbxproj          # Ziele MailwerkShare, MailwerkShareMac, Filter, Version 0.1.15
Mailwerk/
├── Mailwerk.entitlements                   # + App Group
├── ContentView.swift                       # AppObjects: ShareContextPublisher
├── Services/
│   ├── AccountStore.swift                  # init(shareContext:), store optional
│   ├── Share/
│   │   ├── ShareContext.swift              # neu: Abschrift + Datei
│   │   ├── ShareContextPublisher.swift     # neu: Abschrift aktuell halten
│   │   └── SharedContent.swift             # neu: Regeln geteilter Inhalte
│   └── Signatures/
│       └── SignatureRules.swift            # SignatureKind/SignatureItem Codable
├── ViewModels/
│   └── ComposeViewModel.swift              # shared:, sharedBody, Import UIKit/AppKit
└── Views/
    ├── ComposeView.swift                   # shared:, onClose:, close(), Kopfleiste Mac
    └── HTMLMailView.swift                  # Links über openURL
MailwerkShare/                              # Ziel MailwerkShare (iOS)
├── Info.plist                              # Aktivierungsregel, Kontakte-Text
├── MailwerkShare.entitlements              # App Group, Keychain Sharing
├── ShareViewController.swift               # iOS-Einstieg
├── ShareRootView.swift                     # gemeinsam (auch Mac-Ziel)
└── SharedItemLoader.swift                  # gemeinsam (auch Mac-Ziel)
MailwerkShareMac/                           # Ziel MailwerkShareMac (macOS)
├── Info.plist
├── MailwerkShareMac.entitlements           # App Group, Keychain Sharing (+ Sandbox per Build Settings)
└── ShareViewController.swift               # Mac-Einstieg
MailwerkTests/
├── SharedContentTests.swift                # neu, 6 Tests
└── ShareContextTests.swift                 # neu, 5 Tests
```

Gelöscht (Vorlagen): `MailwerkShare/Base.lproj/MainInterface.storyboard`, `MailwerkShareMac/Base.lproj/ShareViewController.xib`, `MailwerkShareMac/icon.icns`.

---

## Testverfahren

**Automatisch:** **551 Tests** (Simulator), alle grün. Vorab unter Linux (Swift 6.2): `SharedContent`, `ShareContext`/`ShareContextFile` (mit Platzhaltern für `os.Logger` und `containerURL`).

**Manuell iPhone** (echtes Gerät, Mails nur an sich selbst):

| Nr. | Teilen aus … | Ergebnis |
|---|---|---|
| 1 | Fotos, 3 Fotos | Standard-Postfach, Signatur, 3 Anlagen, gesendet, Kopie in „Gesendet“ ✔ |
| 2 | Safari | Betreff = Seitentitel, Link im Text ✔ |
| 3 | Kontakte | erst nicht angeboten → Regel umgestellt → `.vcf` ✔ |
| 4 | Notizen (markierter Text) | Text im Mailtext ✔ |
| 5 | Absender wechseln | Signatur wechselt ✔ |
| 6 | Text eintippen, ✕ | Rückfrage mit „Als Entwurf sichern“ ✔ |
| 7 | 10 Fotos | kein Absturz ✔ |

**Manuell Mac:** Finder (PDF, CSV, TXT als Anlage), Fotos und Browser geteilt und versendet ✔.

**Simulator (Gegenprobe nach Paket c):** Dateien, Fotos, Vorschau, Kontakte, Text aus Erinnerungen ✔.

---

## Beobachtungen

- **Erster Aufruf:** Mailwerk steht anfangs evtl. nicht in der App-Reihe des Teilen-Menüs: ganz rechts **Mehr** → Mailwerk wählen bzw. zu den Favoriten hinzufügen.
- **Abschrift:** Nach einer frischen Installation muss Mailwerk einmal geöffnet werden, sonst meldet die Erweiterung „Bitte öffne Mailwerk einmal …“.
- **Lizenzvereinbarung:** Beim Hinzufügen der App Group konnte Xcode keine Profile erneuern („PLA Update available“). Nach Bestätigen der neuen Vereinbarung auf developer.apple.com/account und **Try Again** ging es.
- **HEIC:** JPEG nur, wenn die teilende App es anbietet. Sonst geht das Originalformat raus.
- **Große Videos** sind nicht getestet. Erweiterungen haben eine knappe Speichergrenze, beim Auftreten von Abstürzen hier ansetzen.
- **Protokoll der Erweiterungen:** eigenes Subsystem (`…Mailwerk.MailwerkShare` bzw. `…MailwerkShareMac`). Es läuft in einem eigenen Prozess, deshalb in der App **Konsole** auf dem Mac ansehen.
- **Mac-Gestaltung** der Erweiterung (Kopfleiste, Größe) ist vorläufig, Feinschliff mit v0.2.x.
- **Leerer Ordner** `MailwerkShareMac/Base.lproj` lokal: harmlos, Git übernimmt ihn nicht.
- **Drucken in Erweiterungen:** `MailPrinter` (UIPrintInteractionController/NSApp) wird mit übersetzt, Xcode meldete keine Sperre.

## Nächste Schritte

- **v0.1.16 – Suche über alle Mails** (MW-6).
- Vor dem Live-Gang:
  - CloudKit-Schema nach Production übertragen;
  - App Group und Schlüsselbundgruppe im Developer-Portal für die Release-Profile prüfen (Xcode verwaltet sie bisher automatisch).
