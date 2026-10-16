# Mailwerk – Auftrag und Übergabe für den neuen Chat (ab v0.1.18)

Stand: 17.10.2026, nach Abschluss von v0.1.17 (Version 0.1.17, **606 Tests**). Dieses Dokument ersetzt den Verlauf des bisherigen Chats. Es enthält Projektstand, Fahrplan, Arbeitsregeln und den Auftrag.

---

## 1. Auftrag: v0.1.18 – Anmeldung (OAuth 2) für Outlook

**Erster Schritt im neuen Chat:**
1. Projektordner freigeben lassen und Repo prüfen:
   - letzter Commit „v0.1.17 Entwicklungsdokumentation und Übergabe v0.1.18“ (auf `ff345f0` folgend) oder später;
   - **606 Tests**;
   - lokale Dateien = Repo-Stand (`git status` leer).
2. Mit Kim **Umfang von v0.1.18** klären. Erst Kims Vorstellung einholen, Leitfragen mit Empfehlung stellen (einzeln!), dann Umfang und Aufteilung (Pakete mit Test- und Commit-Punkt) zur Freigabe vorlegen.
3. Erst nach ausdrücklicher Freigabe bauen.

**Hintergrund:** Microsoft lässt für Outlook-Postfächer die Anmeldung mit Benutzername und Passwort (IMAP/SMTP „Basic Auth“) nicht mehr bzw. nur noch eingeschränkt zu. Ein Outlook-Postfach braucht deshalb **OAuth 2** (Anmeldung im Browser bei Microsoft, danach Zugangs-Token). Den aktuellen Stand bei Microsoft vor der Planung per Websuche prüfen – nicht aus dem Gedächtnis.

**Was SwiftMail 1.15.0 schon kann (im Quelltext belegt, eigener Klon):**
- IMAP: `IMAPServer.authenticateXOAUTH2(email:accessToken:)` und `setXOAUTH2AccessTokenProvider(email:accessTokenProvider:)` (`IMAP/IMAPServer+Connection.swift`). Der Provider liefert bei jedem stillen Neuaufbau der Verbindung ein **frisches** Token – wichtig, weil SwiftMail abgerissene Verbindungen selbst neu aufbaut.
- SMTP: `SMTPServer.authenticateXOAUTH2(email:accessToken:)` (`SMTP/SMTPServer+Authentication.swift`); prüft vorher `capabilities.contains("AUTH XOAUTH2")`. Ob das bei Outlook (`AUTH LOGIN XOAUTH2` in einer Zeile) greift, **im Server-Dialog belegen**.
- Den Token-Abruf (Anmeldefenster, Token tauschen, erneuern) bringt SwiftMail **nicht** mit.

**Heutige Anmeldestellen in Mailwerk** (alle mit Passwort):
- `MailSession` – IMAP-Login für Abruf und Aktionen;
- `MailSendService` – SMTP-Login (auch in den Teilen-Erweiterungen);
- `MailConnectionTester` – Verbindungstest beim Anlegen/Bearbeiten;
- Passwort über `AccountStore.password(for:)` → `KeychainService` (iCloud-Schlüsselbund, mit den Erweiterungen geteilt).

**Leitfragen für die Klärung (Empfehlung jeweils mitgeben):**
1. Welche Postfächer: **Outlook.com/Hotmail (privat)**, **Microsoft 365 (geschäftlich)** oder beide? Hat Kim ein Testpostfach?
2. **App-Registrierung** bei Microsoft (Microsoft Entra, „App registrations“): Kim legt sie selbst an (Anleitung Schritt für Schritt). Kontotyp, Weiterleitungs-URI (z. B. `msauth.de.sieber-bw.Mailwerk://auth`), Berechtigungen `IMAP.AccessAsUser.All`, `SMTP.Send`, `offline_access`. Client-ID ist kein Geheimnis; **kein Client-Secret** in der App (öffentlicher Client mit PKCE).
3. **Anmeldefenster:** `ASWebAuthenticationSession` (Apple, ohne Zusatzpaket, iOS und macOS) mit PKCE – Empfehlung. Alternative MSAL (Microsoft-Paket) nur nach Rückfrage, denn neue Pakete sind zustimmungspflichtig.
4. **Token-Ablage:** Refresh-Token im iCloud-Schlüsselbund wie heute das Passwort (geteilte Gruppe, damit die Erweiterungen senden können); Access-Token nur im Speicher. Erneuern vor Ablauf bzw. nach Ablehnung, eine Erneuerung zur Zeit.
5. **Erweiterungen:** Dürfen sie ein Token erneuern (Schlüsselbund schreiben) oder nur nutzen? Kein Anmeldefenster in der Erweiterung – abgelaufene Anmeldung → Hinweis „Bitte in Mailwerk neu anmelden“.
6. **Oberfläche:** Beim Anlegen „Outlook / Microsoft“ als Art wählen → Server fest vorbelegt (`outlook.office365.com:993`, `smtp.office365.com:587` STARTTLS – vorher belegen), kein Passwortfeld, Knopf „Bei Microsoft anmelden“. Was passiert bei abgelaufener Anmeldung im Abruf (Kennzeichen am Postfach, Knopf „Neu anmelden“)?
7. Gmail später über denselben Weg? (Nur vormerken, nicht in v0.1.18.)

**Vorschlag zur Aufteilung (mit Kim abstimmen):**
- **a** Datenmodell (Anmeldeart am Postfach, abwärtsverträglich im iCloud-Key-Value-Speicher), Token-Ablage, reine Logik (PKCE, Token-Antwort, Ablauf) mit Tests;
- **b** Anmeldefenster und Token-Tausch, Postfach anlegen, Verbindungstest;
- **c** Abruf und Versand mit XOAUTH2 (IMAP-Provider, SMTP), Erneuern, Fehlerfälle, Erweiterungen.
Abruf und Versand sind riskant → eigenes Paket.

**Sicherheit:** Tokens und Passwörter nie in den Chat, nie ins Protokoll (auch nicht `privacy: .private` im Klartext prüfen lassen). Weiterleitungs-URI nur für die eigene App. `state` und PKCE prüfen.

## 2. Fahrplan bis zum Live-Gang (von Kim festgelegt)

| Version | Thema | Stand / Inhalt |
|---|---|---|
| v0.1.10 – v0.1.15 | Absenderbild, Auswahl, Anzeige, Signaturen, Fehler-Patch, Teilen | erledigt |
| v0.1.16 | Suche über alle Mails (MW-6), Sortierung, untere Leiste; Fix Abgleich | erledigt |
| v0.1.17 | Optimierungen: Farben, „Ungelesen“/„Spam“, Mailkopf, eigene untere Leiste, Rückgängig-Balken, Filterlisten bearbeiten | erledigt (`3baffd5` … `ff345f0`) |
| **v0.1.18** | **Anmeldung (OAuth 2) für Outlook** | **Auftrag** |
| danach | mit Kim festlegen | Kandidaten: Fehler-Patch mit Weg B „Kopfdaten außerhalb des Zeitfensters“; Klären, was „Live“ heißt |
| v0.2.x | Seitenleiste und Layout für iPad und Mac | Kim hat viele eigene Ideen (u. a. Auswahlkreise auf dem Mac); auch Gestaltung der Teilen-Erweiterung auf dem Mac |
| später | H6 Verbindungen wiederverwenden, Push/IDLE, N14 Offline-Warteschlange, Ordner abonnieren, Threading | nach Live |

Noch offen: was „Live“ genau heißt (TestFlight eigene Geräte oder App Store). Vor TestFlight/App Store:
- CloudKit-Schema nach Production übertragen;
- App Group und Schlüsselbundgruppe in den Release-Profilen prüfen.

---

## 3. Arbeitsregeln (verbindlich)

- **Nichts bauen ohne OK.** Erst Vorschlag bzw. Antwort auf Fragen, dann auf ausdrückliche Freigabe warten.
- **Inhalt jeder Version vorher abstimmen:** Kims Beschreibung einholen, Leitfragen mit Empfehlung stellen, Umfang und Aufteilung zur Freigabe vorlegen.
- **Schritt für Schritt:** Test- und Handlungsanweisungen einzeln geben und nach jedem Schritt auf Rückmeldung warten.
  - Kim fasst gern mehrere Teile zu einem Paket mit einem Test- und Commit-Punkt zusammen.
  - Riskante Änderungen (Schema, Abruf, Versand) bleiben in einem eigenen Paket, damit sie sich allein zurücknehmen lassen.
  - Zwischenrufe Kims (neue Wünsche während einer Version) werden als eigenes Paket eingeplant, nicht nebenbei eingebaut.
- **Klar reden:** Jede Anweisung ohne Vorwissen ausführbar – genauer Menüpfad, genaue Bezeichnung, was danach zu sehen sein soll.
- **Kurz fassen, eins nach dem anderen:** Kim möchte keine langen Erklärungen und nicht mehrere Schritte oder Themen auf einmal. Je Antwort ein nächster Schritt bzw. eine Frage.
- **Ursache belegen, nicht raten:** Bei Funden zuerst die Ursache belegen, z. B. Rohdaten der Mail (Apple Mail: **Darstellung → E-Mail → Rohdaten**, ⌥⌘U), Mailwerks **Originalquelle**, Prüfsummen, Protokoll, Quelltext von SwiftMail (eigener Klon), Server-Dialog im Terminal (`openssl s_client -connect host:port -crlf -quiet`; Passwörter nie in den Chat). Bei mehreren Fehlversuchen anhalten und ehrlich sagen, dass es nicht belegt ist.
- **Lieferung – Projektordner:**
  - Claude legt Dateien **direkt in Kims Projektordner** `/Users/kim/Dropbox/Dev/GitHub/Mailwerk` (Zugriff über die Desktop-App, Ordnerfreigabe anfragen).
  - **Vorher** prüfen, dass die betroffenen lokalen Dateien dem Repo-Stand bzw. der letzten Lieferung entsprechen (`git status`, Prüfsummen).
  - Der Mac ist gelegentlich kurz nicht erreichbar („Device did not respond“). Lesende Befehle dann einmal wiederholen; schreibende nicht doppelt ausführen.
  - **Für jede Lieferung einen frischen Zwischenpfad** (z. B. `outputs/c1/…`, Korrektur `outputs/c1fix1/…`) verwenden – das Ablege-Werkzeug schrieb bei wiederholtem gleichem Pfad teils den alten Inhalt und meldete trotzdem „geschrieben“.
  - **Nach jedem Ablegen die Prüfsummen auf dem Mac kontrollieren.**
  - **Git im Projektordner nur lesend** (`git log`, `git diff`, `git status`); nie `fetch`, `pull` o. Ä. (Sperrdatei, Löschen im Ordner nicht erlaubt). Das Repo prüft Claude in einem eigenen Klon in seiner Umgebung.
  - Ist der Mac nicht erreichbar: Dateien als Download im Chat.
  - Immer eine Tabelle *Datei · Ort · Art (neu/ersetzt/löschen)*.
  - **Löschen** macht Kim selbst in Xcode.
  - Ganze Dateien, keine Code-Schnipsel, keine Claude-Code-Prompts.
  - **Projekteinstellungen** (Build Settings, Version, Info-Texte, Capabilities) ändert Kim selbst in Xcode nach genauer Anleitung; Claude prüft danach die Projektdatei. `MARKETING_VERSION` nur aus Zahlen mit Punkten (z. B. `0.1.18`), Buchstaben nur im Commit-Text.
- **Entwicklungsdokumentationen** (OnePager, Übergaben): im Ordner `Documentation/` und zusätzlich **als Download im Chat**.
- **Neue Dateien:** auf **Target Membership** im Dateiinspektor (⌥⌘1) hinweisen.
  - Im Ordner `Mailwerk/` gehören neue Dateien automatisch zu **Mailwerk, MailwerkShare und MailwerkShareMac**, weil der Ordner allen drei Zielen gehört. Neuer Code dort muss deshalb auch in Erweiterungen übersetzbar sein: kein `UIApplication.shared`, kein `NSWorkspace`, Links über `openURL`.
  - Tests: `MailwerkTests`.
  - Neue Unterordner in synchronisierten Ordnern werden automatisch übernommen.
- **Commit:**
  - **Claude committet niemals.** Ob ein Stand commit-reif ist und der Commit selbst bleiben immer Kims Aufgabe, in Xcode (**Integrate → Commit…**, Push).
  - Commits je abgeschlossenem Paket; nie ein nicht lauffähiger Stand, möglichst ohne Warnungen.
  - **Zu jeder Lieferung den Commit-Text mitgeben** (Format z. B. `v0.1.18 a - …`).
  - Nach dem Push prüft Claude das Repo.
- **Funde** notieren und bewusst einplanen. Inhaltsverlust oder Fehler im Kern der laufenden Version werden in der Version behoben, nicht vertagt.
- **Keine Sonderlösungen** für Einzelfälle, einzelne Anbieter oder Übergangseffekte (alle Installationen sind Testinstallationen).
  - OAuth 2 für Outlook ist von Kim gewollt. Es wird **allgemein** gebaut (Anmeldeart XOAUTH2 mit Anbieter-Konfiguration), damit z. B. Gmail später denselben Weg nutzen kann.
- **Gestaltung** mit Apple-Bausteinen (SwiftUI, Liquid Glass). Seit v0.1.17 sind **eigene Anordnungen als USP** ausdrücklich erlaubt (z. B. `ListBottomBar`), wenn Kim sie wünscht.
- **SwiftMail wird nicht geforkt oder erweitert**; keine eigenen IMAP-Wege für Randfunktionen.
- **Tests dürfen keine Produktivmails verändern.** Testordner „Test Mailwerk“ im Webmail, Mails hineinkopieren. Antworten nur an sich selbst. Testmails mit Bildern: Apple Mail (Foto in den Text) und Spark (`cid:`).
- **Testaufwand gering halten:** nur die nötigsten Tests je Gerät.
- **Formulare:** Felder mit klarer, fester Beschriftung und angedrucktem Beispiel (`LabeledInputField`).
- **Rückfragen** einheitlich als `alert` über `Dialogs` (`AlertItem`, `ConfirmationRequest`, optional dritter Knopf `secondary`).

---

## 4. Test- und Dokumentationsstandard

**Tests:**
- Automatische Tests auf **Simulator** oder **My Mac**, nie auf dem iPhone.
- **Erwartete Testzahl** bei jeder Lieferung nennen.
  - Ändert sich die Schema-Version, **alle** Tests mit festen Versionszahlen anpassen (Suche nach `user_version`, `userVersion` und Zahlenvergleichen).
- **Vorprüfung unter Linux (Claude):** Swift 6.2 (`/opt/swift`, ggf. neu laden von download.swift.org) im eigenen SwiftPM-Paket:
  - Einstellungen: `defaultIsolation(MainActor.self)`, Swift-5-Modus, NonisolatedNonsendingByDefault, InferIsolatedConformances;
  - Quell- und Testdateien symbolisch verlinkt;
  - Platzhalter für `os.Logger` (`Log`) und `FileManager.containerURL`.
  - Reine Logik (ohne SwiftUI/UIKit) vor jeder Lieferung übersetzen und testen. Das ersetzt nicht den Build in Xcode, und NSItemProvider, AccountStore, Oberfläche lassen sich dort nicht prüfen.
- **Isolation (Swift 6.2, Standard MainActor):** Standardwerte von Parametern werden außerhalb des Main-Actors ausgewertet (kein `= MainActorTyp()` als Standardwert). Eigene `init` reiner Datentypen, die auch außerhalb des Main-Actors gebraucht werden, als `nonisolated` kennzeichnen; Initialisierer nicht als Funktionsverweis weitergeben (`.map(Typ.init)` → Warnung).
- Änderungen an Abruf oder Abgleich immer mit dem größten Postfach (Kim.Sieber@ordinum.com, rund 8.800 Mails) und einer **frischen Installation** im Simulator testen.
- Neue Funktionen kurz auch auf dem **Mac** prüfen (Gestaltung iPad/Mac erst v0.2.x). Nach Änderungen am Verfassen-Fenster auch das **Teilen** kurz prüfen (iPhone und Mac).
- Protokoll: Xcode-Konsole (Kategorien Abruf, Aktionen, Spam, Versand, Cache, Ansicht), nur Mailwerk mit Filter `subsystem:de.sieber-bw.Mailwerk`; zum Kopieren mit Zeitstempel die App **Konsole** auf dem Mac (Gerät wählen, Streaming starten, gleicher Filter). SwiftMail schreibt ohne Subsystem (z. B. „Connected …“).

**Inline-Dokumentation** (in jeder neuen oder geänderten Datei vollständig):
- Datei-Header mit **Zweck**, **Abgrenzung** und **Abhängigkeiten**.
- DocC-Kopf je Funktion: Kurzbeschreibung, Verarbeitung (das Warum), `- Parameters:`, `- Returns:`, `- Throws:`. Gespeicherte Eigenschaften und Typen mit einer Zeile.
- Testfunktionen und Testhilfen: eine Zeile `///`.
- Deutsch, **keine Versionsverweise im Code**.

**OnePager je Version:** `Documentation/Mailwerk_v0.1.xx_Entwicklungsdokumentation.md` – Zusammenfassung mit Entscheidungen, Problem/Lösung je Paket, geänderte Dateien, Testverfahren mit Testzahl, Beobachtungen, nächste Schritte. Vorlage: v0.1.17.

---

## 5. Projektstand

**Projekt:**
- Mailwerk, Mail-Client in Swift/SwiftUI für iOS und macOS.
- Repo `github.com/KimSieber/Mailwerk`, Branch `main`, Bundle `de.sieber-bw.Mailwerk`.
- Postfächer: drei bei manitu (größtes Kim.Sieber@ordinum.com, rund 8.800 Mails), Posteo (Krisenfall, meist Abruf aus), GMX und Gmail (Benutzername = Gmail-Adresse, Gesendet-Kopie aus).
- `MARKETING_VERSION` 0.1.17, **606 Tests**. Die Version immer in **allen drei Zielen** gleich setzen (Mailwerk, MailwerkShare, MailwerkShareMac).

**Technik:**
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, Approachable Concurrency, MemberImportVisibility; Deployment Target iOS/macOS 26.5.
  - Jede Datei braucht ihren eigenen `import`.
  - Reine Logik ohne Oberfläche als `nonisolated enum`/`struct` (z. B. `HTMLRichTextParser`, `DraftFormat`, `FetchSelection`, `SignatureRules`, `MailLineEndings`, `SMTPLoginFailure`).
  - Arbeit neben dem Main-Actor: `@concurrent` oder `Task.detached` mit synchroner Funktion.
- Xcode-Projekt mit synchronisierten Ordnern; Swift Testing (`@Test`, `#expect`).
- **SwiftMail 1.15.0** (wird nicht geforkt). Keine weiteren Pakete; neue nur nach Rückfrage.
  - Genutzt u. a.: `extendedSearch` (ohne SORT), `fetchStructure`, `fetchPart` (`BODY.PEEK`), `fetchRawMessage` (10 s), `examineMailbox`, `append(email:to:flags:)` (liefert UID bei UIDPLUS), `store`, `expunge(messages:)` (UID EXPUNGE), `createMailbox`, `Attachment(contentID:isInline:)`.
  - Nicht vorhanden: Teilabruf der ganzen Mail, `BODY[HEADER]`, `BODY[n.MIME]`, SUBSCRIBE.
- Mail-Cache: System-SQLite `MessageStore`, WAL und Transaktionen, **Schema-Stufe 7** (Suchindex FTS5 „trigram“ `message_search`, Spalte `preview` entfallen), Ordner `Cache` ohne Backup, Sync-Zustand je Ordner.
- Postfächer im iCloud-Key-Value-Speicher (inkl. `storesSentCopy`), Passwörter im iCloud-Schlüsselbund (Gruppe `$(AppIdentifierPrefix)de.sieber-bw.Mailwerk`, mit den Erweiterungen geteilt); **Filterlisten und Signaturen** über SwiftData/CloudKit (`FilterEntry`, `AccountSignature`, Container `iCloud.de.sieber-bw.Mailwerk`, Schema bisher nur Development); **Abruf-Schalter je Gerät** in `UserDefaults` (`mailwerk.fetchPausedAccounts`).

**Teilen mit Mailwerk (v0.1.15):**
- Ziele `MailwerkShare` (iOS) und `MailwerkShareMac` (macOS):
  - in der App mit Plattform-Filter eingebettet;
  - Mitglied des ganzen `Mailwerk/`-Ordners außer `MailwerkApp.swift` und `Info.plist`;
  - Capabilities: App Group `group.de.sieber-bw.Mailwerk`, Keychain Sharing `de.sieber-bw.Mailwerk`; Mac zusätzlich Sandbox mit ausgehenden Verbindungen und Kontakten.
- **Abschrift** `ShareContext.json` in der App Group (Postfächer, Standard-Postfach, Signaturen, keine Passwörter). Die App hält sie über `ShareContextPublisher` (in `AppObjects`) aktuell. Die Erweiterung liest sie über `AccountStore(shareContext:)` und `InMemorySignatureStorage`.
- Gemeinsam: `ShareRootView`, `SharedItemLoader` (in `MailwerkShare/`, auch Mac-Ziel), `SharedContent`/`SharedContentRules`. Je System eigener `ShareViewController`.
- Übernahme je Anbieter: Web-Link → Dateiverweis (immer Anlage) → markierter Text → Daten (Bilder als JPEG, wenn angeboten).
- Aktivierungsregel `SUBQUERY` auf `public.data`, `public.url`, `public.vcard`.
- `ComposeView(…, shared:, onClose:)`. Auf dem Mac zeigt das Fenster in der Erweiterung eine eigene Kopfleiste (✕, Titel, Senden), weil dort keine Symbolleiste erscheint.

**Suche und Sortierung (v0.1.16):**
- Untere Leiste: seit v0.1.17 Eigenbau `ListBottomBar` (siehe unten). Mac: obere Symbolleiste. `searchPresentationToolbarBehavior(.avoidHidingContent)` hält die obere Leiste während der Suche.
- `MessageSort` (Von/An, Betreff, Datum, Größe; Gleichstand: neueste zuerst). `InboxViewModel.sort` gilt nur für die gezeigte Ansicht, Rücksetzen bei Ansichtswechsel, keine Speicherung. Abweichend = weißes Symbol auf einem Kreis in der Akzentfarbe (`SortBarLabel`).
- Suchindex: `SearchText` (Aufbereitung, Phrase-Ausdruck, Personen `Name <adresse>`), `writeSearchEntry` in denselben Transaktionen wie das Speichern, Trigger beim Löschen, `SearchIndexBuilder` trägt Fehlendes beim Start nach.
- `SearchViewModel` + `SearchScope` (gezeigte Ansicht) + `SearchPerson` (Vorschläge, Marke). Die lokale Suche liefert Cache-IDs → `InboxViewModel.searchFilter` → `visibleMessages` (Liste, Auswahl, „Alle auswählen“).
- Serversuche `MailFetchService.searchOnServer` (EXAMINE, TEXT bzw. FROM/TO/CC, 300 höchste UIDs → neueste 100, nichts gespeichert); Öffnen über `ServerMessageLoader` → `MailFetchService.loadMessage`.

**Optimierungen (v0.1.17):**
- **Farben:** `AppTheme` – Hintergrund Nebelblau #DFE5F5 / Nachtblau #121827, Karten Weiß / #1C2438; `View.appBackground()` und `View.cardRowBackground(isSelected:)` in allen Listen und Blättern. **Akzentfarbe** Asset `AccentColor` (Mailwerk-Blau #3A6FE8 / #5B8AF0); Erweiterungen über `NSAccentColorName` in ihrer Info.plist.
- **Sammelansichten** (`MailboxSelection`): Alle Eingänge, **Ungelesen** (Zähler, Posteingänge), Mit Kennzeichnung (Zähler), **Spam** (Spam-Ordner, ohne Zähler). Abfragen über Ordnerpaare `FolderKey(accountID, folder)` (`MessageStore.messages(in:)`, `unreadInboxMessages`, `unreadInboxCount`). Gelesen markierte Mails bleiben bis Verlassen/Ziehen (`InboxViewModel.keptUnreadIDs`). Hinweis am Listenende statt Knopf.
- **Ältere Ungelesene:** `SyncStatePlanner.unreadBackfill` (höchstens 200 je Abruf, höchste UIDs zuerst), `MailFetchService.refreshAndCache` Schritt 6 lädt sie vollständig.
- **Mailkopf:** Betreff markierbar; Personen als `HeaderPerson` mit Menü (`HeaderPersonMenu`: Adresse kopieren, Suchen nach, Kontaktkarte `ContactCardView`, Neue E-Mail an).
- **Untere Leiste** `ListBottomBar` in `safeAreaInset(edge: .bottom)`: Glas-Kapsel (Sortieren | Neue Mail) und darüber getrennt der Suchkreis (`glassProminent`, Kreis, `.extraLarge`, Akzentfarbe). **Suchfeld oben** (`navigationBarDrawer(displayMode: .automatic)`), Tastatur unten. Während der Suche keine Leiste; im Auswahlmodus die Befehlsleiste.
- **Rückgängig-Balken** `UndoBar`: Glas in der Akzentfarbe, Füllung läuft per `TimelineView` über `UndoOffer.duration` (5 s), Antippen = rückgängig, nach unten wischen = ausblenden.
- **Filterlisten:** `FilterListEditing` (Plan + Speichern: erst neu anlegen, dann alt entfernen), `FilterListView` mit „Neuer Eintrag …“, Kontextmenü Bearbeiten/Löschen (langes Drücken), Wischen mit Bestätigung; kurzes Antippen bearbeitet nicht.

**Verfassen:**
- `ComposeView`/`ComposeViewModel` mit `RichTextEditor`.
  - **Formatierungsleiste** `FormattingToolbar` im Liquid-Glass-Stil (`GlassEffectContainer`, `glassEffect`), nur Symbole (`FormatIcon`), Gruppen nach Häufigkeit: Anhang + Link | B I U | Listen | Größe + Farbe; Plätze `leading`/`trailing` (Anhang, Logo der Signatur).
  - HTML-Rückweg: `HTMLRichTextParser` (fehlertolerant) → `RichTextImport`.
  - Bilder im Text: `MailImageAttachment`, `EditorImageData`, Versand als Inline-Teil (`RichTextHTML.images(in:)`).
- **Absende-Postfach:** Antwort/Weiterleiten = Postfach der Originalmail; neue Mail = Postfach des gezeigten Ordners (`MailboxSelection.accountID`) bzw. bei mailto das Postfach der geöffneten Mail; Sammelansichten = Standard-Postfach (`senderAccountID`).
- **Signaturen:** `SignatureStore`, `SignatureEditorView`, `SignatureEditing` (`.mailwerkSignature`, `split`), `HTMLSignatureBlock` (+ `init(restoredHTML:images:)`) + `SignatureBlockView`, `CodeTextEditor`.
- **Entwürfe:** `DraftFormat` (Marken, Datenblock, `quotedText`), `DraftService` (APPEND, Ordner suchen/anlegen, `removeDraft` per UID EXPUNGE), `DraftComposeLoader` (öffnet Entwurf aus dem Ordner „Entwürfe“, lädt fehlende Bilder und Anhänge), Wiederherstellen in `ComposeViewModel.init(accountStore:draft:attachments:)`.
- **Versand** `MailSendService`: Zeilenenden CRLF (`MailLineEndings`), Schritt/Protokoll und `loginRejected` (`SMTPLoginFailure`), Gesendet-Kopie nur bei `savesSentCopy`, Markieren des Originals (`\Answered`, `$Forwarded`).

**Abruf:**
- `InboxViewModel` (Runde über `AccountStore.fetchingAccounts`), `FetchCoordinator`, `FetchSelection`, `FolderCatalog`, Kennzeichen `FetchPausedBadge`.
- `MailFetchService.searchNewestFirst` (ohne SORT, UIDs absteigend).
- Abgleich: Grenze für „gelöscht“ ist UIDNEXT − 1 aus dem SELECT (`ServerReconciliation.removalLimit`), ersatzweise die höchste UID.

**Anzeige:**
- Liste `InboxView`: Titel (`InboxTitle`, Farbpunkt, Symbol, Standzeile mit Ladeanzeige) als `.principal` mit Mindestbreite → stets linksbündig; Ordner-Knopf fest `.topBarLeading`.
- Mail: `MessageDetailView`, `HTMLMailView` (CSP, Dunkelmodus, Links über `openURL`), eingebettete Bilder, Originalquelle; `MessageRow`, `SenderAvatarView`, Kontextmenü, Auswahlmodus, 5-Sekunden-Rückgängig.

---

## 6. Liste offener Punkte

- **Sporadischer Gmail-Timeout (IMAP):** „Operation timed out“ beim Spam-Ordner in der Abrufrunde bzw. bei einer schnell folgenden Verbindung, nie beim manuellen Öffnen; vermutet 5-s-Wartezeit auf die Begrüßung. Nicht belegt. Bei erneutem Auftreten Zeilen mit Zeitstempel sichern; Lösung ggf. mit H6.
- **H6:** Verbindungen je Konto wiederverwenden (ggf. mit Push-Stufe).
- **N14 „Warteschlange offline“:** Aktionen ohne Netz merken und später ausführen (auch Entwurf sichern offline).
- **DKIM / Authentication-Results:** später prüfen, für Logos und ggf. Spam-Prüfung.
- **Ordner abonnieren:** In Mailwerk angelegte Ordner (auch ein neu angelegter „Drafts“) werden nicht abonniert (SwiftMail ohne SUBSCRIBE).
- **Kopfdaten außerhalb des Zeitfensters nachfüllen (Weg B):** `messageIDsNeedingHeaders` wird nur für Mails der Datumssuche (30 Tage) ausgewertet; per „Ältere laden“ geholte Mails mit veralteter Header-Version werden nie nachgefüllt (Folge in v0.1.16: keine Absenderbilder vor etwa 10.09. auf Testinstallationen, von Kim per Neuinstallation gelöst). Alle Mails des Ordners erfassen; Änderung am Abruf → eigenes Paket.
- **Suchfeld unten** statt oben (Kims Wunsch), sobald iOS es neben der eigenen Leiste ohne zweiten Suchknopf erlaubt.
- **Warnungen** zur isolierten `Hashable`-Konformität von `FilterListInputEntry` (bestehen seit Längerem) – bei Gelegenheit bereinigen.
- **Strukturempfehlungen:** Protokolle/Injektion für Tests ohne Server, SwiftLint/SwiftFormat, Lokalisierung.
- **Empfangsdatum** statt Kopfdatum – nur bei Bedarf.
- **Inline-Foto ohne Verweis bei einer Mail mit einem einzigen HTML-Teil** steht in der Anhangliste statt im Text – beobachten.
- **Originalquelle großer Mails** (über 5 MB): nicht möglich ohne Teilabruf in SwiftMail.
- **Logo-Breite einer einfachen Signatur** fest 150 pt (änderbar nur über Art HTML) – bei Bedarf Feld ergänzen.
- **Titel-Mindestbreite** (200 pt für Knöpfe) auf iPad/Querformat beobachten; Gestaltung iPad/Mac in v0.2.x.
- **CloudKit-Schema** vor TestFlight/App Store nach Production übertragen.
- **Teilen:**
  - große Videos nicht getestet (Speichergrenze der Erweiterung);
  - HEIC geht als Original raus, wenn die teilende App kein JPEG anbietet;
  - die Mac-Gestaltung der Erweiterung ist vorläufig (v0.2.x).
- Verworfen (nicht wieder aufgreifen ohne Kims Wunsch): Abruf-Schalter in der Postfachliste kleiner/anders; Schriftfarbe Schwarz/Weiß als Auswahl; Mails als Markdown exportieren; Filterlisten-Eintrag per kurzem Antippen bearbeiten.

---

## 7. Bekannte Besonderheiten der Umgebung

- **Arbeitsumgebung (seit 16.10.2026):** **macOS 27.0.1, Xcode 27.1.** Unter macOS 26.4 mit älterem Xcode ließen sich auf dem Mac keine Mails öffnen (Web-Prozess beendet, `XPCConnectionTerminationWatchdog`). Bei ähnlichen Funden zuerst System und Xcode prüfen.
- **Ältere Stände auschecken** (Xcode: Source Control Navigator → Rechtsklick auf den Commit → **„Check out "<hash>"…“**, zurück mit **„Switch to "main"…“**):
  - Stände vor Schema-Stufe 7 (vor v0.1.16) lesen den Cache nicht – keine Mails;
  - noch nicht eingecheckte neue Dateien vorher aus dem Projektordner nehmen, sonst scheitert der Build.
- **Untere Leiste (iOS 26):** Steht das Suchfeld in der Symbolleiste, setzt iOS unten einen eigenen Suchknopf ein – neben `ListBottomBar` wären es zwei. Deshalb steht das Suchfeld oben (`navigationBarDrawer`). Mehrere Glasflächen in einem `GlassEffectContainer` verschmelzen (der Suchkreis wurde beschnitten) – Kapsel und Kreis bleiben getrennt.
- **Animation beim Einblenden:** Ein `withAnimation` in `onAppear` einer eingeblendeten Ansicht wird von der Einblende-Animation übernommen. Laufende Anzeigen deshalb mit `TimelineView` aus der Zeit berechnen.
- **Akzentfarbe in Erweiterungen:** die Build-Einstellung „Global Accent Color Name“ war im Ziel nicht zu finden; `NSAccentColorName` in der Info.plist wirkt.

- **Suche (iOS 26):** Ohne `searchPresentationToolbarBehavior(.avoidHidingContent)` blendet iOS die obere Leiste während der Suche aus.
- **FTS5 „trigram“:** Mindestens 3 Zeichen je Phrase; Groß-/Kleinschreibung wird auch für Umlaute gefaltet; Eingaben immer als Phrase in Anführungszeichen (Sonderzeichen sonst als Befehl).
- **Simulator:**
  - behält Postfächer und Passwörter (iCloud-Speicher des Simulators), solange er nicht neu aufgesetzt wird;
  - kein CloudKit-Abgleich mit echten Geräten (Signaturen/Filterlisten nur iPhone ↔ Mac prüfbar);
  - zeigt private Protokollwerte im Klartext;
  - hat nur Beispielkontakte;
  - Tastatur: **I/O → Keyboard → Toggle Software Keyboard** (⌘K);
  - Hell/Dunkel: **Features → Toggle Appearance** (⇧⌘A);
  - **Hängende Sondertaste:** Tippen markiert alles, Pfeiltasten springen wortweise, Rückschritt löscht ganze Zeilen (auch in Safari) → zuerst **I/O → Keyboard → Connect Hardware Keyboard** (⇧⌘K) aus und wieder ein, sonst Simulator neu starten; kein Fehler in Mailwerk;
  - App löschen: Postfächer bleiben (iCloud-Key-Value-Speicher), Abruf-Schalter (UserDefaults) und Cache sind weg; Signaturen/Filterlisten kommen nur zurück, wenn CloudKit im Simulator sie hatte.
- **Netzstatus:** meldet ein fehlendes Netz direkt nach dem Flugmodus manchmal noch nicht; Verbindungsfehler zusätzlich über `ConnectionErrorClassifier` als „offline“ behandeln.
- **Teilen-Erweiterungen:**
  - Nach frischer Installation Mailwerk einmal öffnen, sonst fehlt die Abschrift („Bitte öffne Mailwerk einmal …“).
  - Mailwerk im Teilen-Menü anfangs unter **Mehr**.
  - Eigener Prozess: Protokoll mit eigenem Subsystem (`…MailwerkShare`, `…MailwerkShareMac`) in der App **Konsole**.
  - Ein hängendes Erweiterungsfenster auf dem Mac schließen: Aktivitätsanzeige → `MailwerkShareMac` beenden oder `killall MailwerkShareMac`.
  - Geänderte Aktivierungsregeln greifen nach erneutem Run, ggf. Neustart des Geräts.
- **Xcode/Developer-Portal:** „PLA Update available“ blockiert das Erneuern der Profile, bis die neue Lizenzvereinbarung auf developer.apple.com/account bestätigt ist (dann **Try Again**). Bei App Groups zeigt Xcode keine Haken mehr; steht die Gruppe in der Liste, ist sie aktiv.
- **Compiler-Absturz (Swift 6.2):** „Command SwiftCompile failed with a nonzero exit code“ ohne Meldung = Compiler abgestürzt. Ursache im **Report Navigator (⌘9)**. Bekannte Auslöser: `async`-Form von Objective-C-Delegate-Methoden (deshalb Rückruf-Form, z. B. in `SignatureBlockView`); gespeicherte async-Closures ohne feste Isolation.
- **Xcode + Kabel + VPN:** Mit NordVPN bricht die Debug-Verbindung zum iPhone ab; VPN am Mac aus.
- **Git auf macOS:** Reine Groß-/Kleinschreibungs-Änderungen an Dateinamen erfasst Git nicht – über Zwischennamen in zwei Commits.
- **SwiftMail:**
  - baut abgerissene Verbindungen still neu auf, ohne den Ordner neu auszuwählen (abgefangen);
  - `deleteMailbox` löscht samt Inhalt (Vorprüfung in `FolderDeletion`);
  - liefert je Mail nur den ersten Text- und HTML-Teil (in `MessageContentPlan` gelöst);
  - `search(…sortCriteria:)` braucht die Server-Erweiterung SORT (Gmail hat sie nicht) – Mailwerk sucht deshalb immer ohne Sortierung (`searchNewestFirst`);
  - sendet Text/HTML bei 8BITMIME unverändert als `8bit` – Zeilenenden müssen vorher CRLF sein (`MailLineEndings`);
  - SMTP-Anmeldung: nach Ablehnung von `AUTH PLAIN` versucht es `AUTH LOGIN` auf derselben Verbindung; schließt der Server sofort (Gmail), kommt nur `ChannelError` 5 (`ioOnClosedChannel`) – Mailwerk meldet das als abgelehnte Anmeldung (`SMTPLoginFailure`);
  - wartet nach dem Verbindungsaufbau 5 s auf die Begrüßung des Servers (vermutete Ursache sporadischer Gmail-Timeouts).
- **WKWebView:** JavaScript der Mail/Signatur ist aus; Skripte der App laufen in eigener Welt (`WKContentWorld.defaultClient`) bzw. per `evaluateJavaScript`.
- **MemberImportVisibility:** Jede Datei braucht den Import des Moduls, aus dem ein Name stammt, z. B. `NSAttributedString.Key.link` → UIKit bzw. AppKit.
- **Apple Mail** schickt Fotos im Text als Folge von Teilen ohne Content-ID; **Spark** und Outlook nutzen `cid:`.
- **Postfächer:** im August 2026 per IMAPSYNC umgezogen; Sequenznummern sind kein Datumsindikator.
- **Gmail:** IMAP nimmt den Google-Kontonamen an, SMTP nur die Gmail-Adresse → Benutzername = Gmail-Adresse. Gmail legt Gesendetes selbst ab → Schalter „Kopie in ‚Gesendet‘ ablegen“ aus. Sonderordner unter dem Behälter `[Gmail]` (SPECIAL-USE).
- **Posteo:** lehnt nackte LF ab (`521 5.5.2 bare <LF>`) und schließt die Verbindung.
- **Symbolleiste iOS 26:**
  - `.navigation` ist nur ein Wunsch; kommen und gehen Elemente, ordnet iOS um → feste Plätze (`.topBarLeading`), keine wechselnden Elemente.
  - `.principal` wird nur zentriert, wenn der Titel zwischen die Knöpfe passt, sonst rückt er nach links; `.frame(maxWidth:)` wirkt dort nicht. Mailwerk gibt dem Titel deshalb eine Mindestbreite (Bildschirmbreite − 200 pt).
  - Titel als `.topBarLeading` geht nicht (iOS setzt dann den Fenstertitel in die Mitte).
  - Der Standard-Schalter (`Toggle`) hat auf dem iPhone eine feste Größe (`.controlSize` wirkt nur auf dem Mac).
- **HTML-Mails** können fehlerhaft aufgebaut sein. Jede Verarbeitung von Mail-HTML muss tolerant sein und darf nicht an Tags ausschneiden; Ersetzungen nur per Textsuche (so auch Logo-Platzhalter und Entwurfs-Marken).
