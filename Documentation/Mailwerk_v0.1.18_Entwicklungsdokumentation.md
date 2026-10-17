# Mailwerk – Entwicklungsdokumentation v0.1.18

2026-10-17/18 · Anmeldung per OAuth 2 für Outlook.com, Spamfilter ohne eigene IMAP-Schlüsselwörter, CloudKit Production, Entwicklungs-App „Mailwerk Dev“ neben der TestFlight-App, Import der Spamlisten, Sicht „Spam“ unabhängig vom Filter

Dieses Dokument ersetzt zugleich das Übergabedokument: Der Abschnitt „Gesamtstand des Projekts“ am Ende fasst Stand, Arbeitsregeln, Umgebung und offene Punkte für den nächsten Chat zusammen.

---

## Zusammenfassung

v0.1.18 war als „Anmeldung (OAuth 2) für Outlook“ geplant. Im Verlauf kamen durch die erste TestFlight-Verteilung zwei grundsätzliche Themen dazu: die Trennung der CloudKit-Umgebungen (Development/Production) und die Trennung von Test und Produktion auf denselben Geräten.

| Paket | Inhalt | Commit |
|---|---|---|
| a–c | OAuth 2 für Outlook.com: Anbieter-Konfiguration, PKCE, Token-Dienst, Anmeldefenster, Postfach anlegen/bearbeiten, Abruf und Versand per XOAUTH2, Hinweis bei abgelaufener Anmeldung, Teilen-Erweiterungen | `a4ae9c2` (gemeinsam mit d) |
| a–c Fix | Anmeldename getrennt von der Absenderadresse (Feld „Benutzername“ auch bei Microsoft) | `a4ae9c2` |
| d | Spamfilter auf Servern ohne eigene IMAP-Schlüsselwörter (Outlook) | `a4ae9c2` |
| – | CloudKit-Schema nach Production übertragen (CloudKit Console, kein Code) | – |
| e | Entwicklungs-App „Mailwerk Dev“ (Bundle-ID `.dev`) neben der TestFlight-App, eigene App-Gruppe | `0730dd0` |
| e2 | Eigener Key-Value-Speicher für „Mailwerk Dev“ → getrennte Postfächer für Test und Produktion | `ebc4245` |
| f+g | Spamfilter nach Erstinstallation eingeschaltet; Import von White-/Blacklist aus Textdatei | `e6fb6d1` |
| h | Sicht „Spam“ auch bei ausgeschaltetem Spamfilter | Commit durch Kim |

Tests: 606 → **651** (45 neue), alle grün. `MARKETING_VERSION` 0.1.18 in allen drei Zielen.

**Meilenstein:** Mailwerk läuft erstmals über **TestFlight** produktiv (Kim: iPhone, iPad; Kims Frau eingeladen). Entwicklung und Tests laufen parallel in „Mailwerk Dev“ aus Xcode – mit eigenen Testpostfächern und eigenen CloudKit-Daten.

---

## 1. Outlook: Warum OAuth 2 – und wie Microsoft es verlangt

**Ausgangslage:** Microsoft lässt bei privaten Outlook.com-Konten (Hotmail, Live, outlook.de …) keine Anmeldung mit Benutzername und Passwort mehr zu. Laut Microsoft-Seite „POP, IMAP, and SMTP settings for Outlook.com“: „Outlook.com requires the use of Modern Auth / OAuth2.“

**Belegte Fakten (Websuche, Okt. 2026):**
- Server: IMAP `outlook.office365.com:993` (SSL/TLS), SMTP `smtp-mail.outlook.com:587` (STARTTLS). Die Übergabe nannte `smtp.office365.com` – das ist der Server für Microsoft 365, nicht für Outlook.com.
- IMAP ist bei Outlook.com ab Werk **aus**: Webmail → Einstellungen → E-Mail → Weiterleitung und IMAP.
- Berechtigungen: `https://outlook.office.com/IMAP.AccessAsUser.All`, `https://outlook.office.com/SMTP.Send`, `offline_access`.
- Anmeldung am Server mit SASL XOAUTH2: `base64("user=" + user + "\x01auth=Bearer " + token + "\x01\x01")`.
- Öffentlicher Client: PKCE (S256), **kein** Client-Geheimnis. Refresh-Tokens haben keine feste Laufzeit; bei jeder Erneuerung kommt ein neues, das alte soll ersetzt werden.
- Microsoft 365 (geschäftlich): Passwort-SMTP standardmäßig ab Ende Dezember 2026 aus. Für Mailwerk **kein Einsatzszenario** (Kim: Geschäftsmails laufen auf verwalteten Geräten).

**Entscheidungen mit Kim:**

| Frage | Entscheidung |
|---|---|
| Welche Konten? | Nur **Outlook.com privat**. Bestehende sechs Postfächer bleiben unverändert (Passwort). |
| Gmail umstellen? | **Nein** – Gmail läuft mit App-Passwort. OAuth ist allgemein gebaut, damit Gmail später denselben Weg nehmen *könnte*. Nur vorgemerkt. |
| Wer registriert die App? | **Einmalig der Anbieter (Kim)**, nicht jeder Nutzer. Nutzer melden sich nur im Anmeldefenster an und stimmen zu – wie bei Apple Mail, Thunderbird, Spark. |
| Anmeldefenster | Apple `ASWebAuthenticationSession` (SwiftUI `webAuthenticationSession`), private Browser-Sitzung (`.ephemeral`). Kein MSAL, kein neues Paket. |
| Token-Ablage | Refresh-Token im iCloud-Schlüsselbund (geteilte Gruppe), Access-Token nur im Speicher. Eine Erneuerung zur Zeit. |
| Teilen-Erweiterungen | Dürfen selbst erneuern (Komfort). Kein Anmeldefenster; ist die Anmeldung ganz abgelaufen: „Bitte in Mailwerk neu anmelden“, Fenster bleibt offen (ein Entwurf ist dann auch nicht möglich). |
| Postfach anlegen | Zuerst die **Art** wählen: „Microsoft (Outlook.com, Hotmail, Live)“ oder „Anderer Anbieter (IMAP/SMTP)“. Microsoft: Bezeichnung, Absendername, E-Mail-Adresse, Benutzername (optional), Farbe, Knopf „Bei Microsoft anmelden“. Server fest, kein Passwort. Nach der Anmeldung automatischer Verbindungstest, dann automatisch gespeichert. |
| Postfach bearbeiten | Statt Passwort und Servern: Stand der Anmeldung und „Erneut bei Microsoft anmelden“. E-Mail-Adresse und Benutzername änderbar (ohne neue Anmeldung). |
| Abgelaufene Anmeldung | Nur bei klarer Ablehnung durch Microsoft (`invalid_grant`), nie bei fehlendem Netz. Postfach wird übersprungen, Mails bleiben sichtbar. Rotes Warnzeichen am Postfach (Postfachliste, Seitenleiste) und Hinweisleiste über der Mailliste „Anmeldung für ‚…‘ abgelaufen – Neu anmelden“; ein Tipp öffnet direkt das Anmeldefenster. Keine wiederkehrenden Fehlermeldungen. |

---

## 2. App-Registrierung bei Microsoft (Azure / Entra)

**Fund:** Mit einem privaten Microsoft-Konto lassen sich Apps **nicht mehr außerhalb eines Verzeichnisses** registrieren („The ability to create applications outside of a directory has been deprecated“). Es braucht einen eigenen Entra-Mandanten.

**Durchgeführt (Kim, nach Anleitung):**
1. Azure-Portal mit Kims Microsoft-Konto (`Kim.Sieber@ordinum.com`) → „Starten Sie mit einer kostenlosen Azure-Testversion“ → Azure-Free-Account, „For personal use“, Land Deutschland (nicht mehr änderbar), Kreditkarte zur Identitätsprüfung. Danach: „DEFAULT DIRECTORY“.
2. App-Registrierung „Mailwerk“:
   - Kontotyp **„Nur persönliche Microsoft-Konten“** → Endpunkt `consumers`.
   - Umleitungs-URI (öffentlicher Client) `msauth.de.sieber-bw.Mailwerk://auth` – von Azure als Plattform „iOS/macOS“ eingeordnet.
   - **Client-ID:** `9cad2233-5a8c-4b11-845e-c21b19ae2e0a` (öffentlich, steht im Code).
   - Kein Client-Geheimnis.
3. API-Berechtigungen (delegiert, Microsoft Graph): `IMAP.AccessAsUser.All`, `SMTP.Send`, `offline_access`, `User.Read`. Keine Administratorzustimmung nötig.

**Azure-Probephase (30 Tage):** Pay-As-You-Go ist **nicht** zwingend. Nach Ablauf wird das Azure-Abo deaktiviert, der Mandant mit der Registrierung bleibt. Die Registrierung kostet nichts (Entra ID Free). Offiziell nicht garantiert ist nur, dass sie dauerhaft ohne aktives Abo weiterläuft. **Vorgehen:** auslaufen lassen, danach in „Mailwerk Dev“ einmal Outlook neu anmelden. Scheitert das, auf Pay-As-You-Go wechseln (0 €, solange keine kostenpflichtigen Dienste angelegt werden; danach gibt es kein Ausgabenlimit).

**Vor App-Store-Veröffentlichung:** Herausgeber-Verifizierung bei Microsoft prüfen (sonst steht im Zustimmungsfenster „nicht überprüft“; für private Konten nur ein Hinweis).

---

## 3. Pakete a–c: Umsetzung OAuth 2

### Neue Dateien – `Mailwerk/Services/OAuth/`

| Datei | Inhalt |
|---|---|
| `OAuthProvider.swift` | Anbieter-Konfiguration (Endpunkte, Client-ID, Weiterleitung, Berechtigungen, Server). Erster Anbieter `.microsoft`; weitere als zusätzlicher Fall. |
| `OAuthPKCE.swift` | Prüfwert (32 Zufallsbytes → 43 Zeichen Base64-URL), Abbild SHA-256 (S256), Zufallswerte für `state`. |
| `OAuthError.swift` | `signInRequired`, `cancelled`, `signInUnavailable`, `stateMismatch`, `providerError`, `invalidResponse`, `missingRefreshToken`, `randomUnavailable` – deutsche Meldungen. |
| `OAuthAuthorization.swift` | Anmelde-Adresse bauen (`login_hint`), Rückkehr prüfen (`state`, Code, Fehler des Anbieters), Anfragen für Code-Tausch und Erneuerung (Formular-Kodierung nach RFC 3986). |
| `OAuthTokenResponse.swift` | Antwort lesen: Tokens + Ablaufzeit; `invalid_grant` → `signInRequired`. `OAuthTokenSet.isUsable` mit 5 Minuten Vorlauf. |
| `OAuthTokenService.swift` | `actor`: Access-Token aus dem Speicher oder erneuert; eine Erneuerung je Postfach (`pending`); neues Refresh-Token sofort gespeichert; abgelehntes Token gemerkt (`rejected`) → keine weitere Anfrage, bis im Schlüsselbund ein anderes liegt (z. B. von einem anderen Gerät). Verbindungsfehler gehen unverändert weiter. |
| `OAuthSignInState.swift` | `@Observable`: Postfächer mit abgelaufener Anmeldung, Anmeldefenster (`webSignIn`, von der App gesetzt), `signIn`, `renewSignIn` (mit IMAP-Probe, damit kein fremdes Konto gespeichert wird). Hier entsteht auch `OAuthTokenService.shared`. |

### Neue Ansichten
- `SignInRequiredBadge.swift` – rotes Ausrufezeichen (Gegenstück zum orangefarbenen Pause-Zeichen).
- `SignInRequiredBar.swift` – Hinweisleiste über der Mailliste.

### Geänderte Dateien (Auszug)
- `MailAccount` – neues optionales Feld `oauthProvider` (fehlt = Passwort; ältere Postfächer bleiben lesbar).
- `KeychainService` – `nonisolated`; Refresh-Token unter eigenem Service-Namen `de.sieber-bw.Mailwerk.oauth.refreshtoken`.
- `AccountStore` – `addAccount(_:refreshToken:)`, `updateRefreshToken`, Entfernen löscht Refresh-Token und Zustand.
- `MailSession` – `MailSecret` (`.password` / `.oauth`), `authenticate` für IMAP und SMTP. IMAP bekommt zusätzlich eine **Token-Quelle** (`setXOAUTH2AccessTokenProvider`), damit SwiftMails stilles Neuverbinden ein frisches Token nutzt. Lehnt der Server ein Token ab, wird es im Speicher verworfen.
- `MailSendService` – Anmeldung über `MailSession`; abgelehntes Token → `SendError.tokenRejected` (statt „Benutzername/Passwort prüfen“); `OAuthError` geht unverändert weiter.
- `MailConnectionTester` – `MailLogin` (`.password` / `.accessToken`), `test(_:)` für gespeicherte Postfächer.
- `AddAccountView`/`ViewModel`, `EditAccountView` – siehe Entscheidungen; Farbe jetzt auch beim Anlegen.
- `InboxView`/`ViewModel`, `AccountListView`, `FolderSidebarView` – Warnzeichen, Hinweisleiste, Überspringen abgelaufener Postfächer, nach erneuter Anmeldung sofortiger Abruf.
- `MailwerkApp` – stellt das Anmeldefenster bereit (`OAuthWebSignInInstaller`). **Nur hier**, weil diese Datei nicht zu den Teilen-Erweiterungen gehört – dort gibt es kein Anmeldefenster.
- `Log` – neue Kategorie „Anmeldung“ (nie Tokens im Protokoll).

### Belegt im Server-Dialog / Quelltext
- `smtp-mail.outlook.com:587` meldet nach `EHLO`: `250-AUTH LOGIN XOAUTH2`.
- SwiftMail 1.15.0 zerlegt die AUTH-Zeile in `AUTH LOGIN` und `AUTH XOAUTH2` → `capabilities.contains("AUTH XOAUTH2")` greift.

### Fund und Fix: Anmeldename ≠ Absenderadresse
- **Symptom:** IMAP mit dem Token in Ordnung, SMTP `535 5.7.3 Authentication unsuccessful`.
- **Ursache (belegt per Gegenprobe):** Microsoft nimmt bei **SMTP** per XOAUTH2 nur die **Haupt-Anmeldeadresse** des Microsoft-Kontos an (bei Kim `Kim.Sieber@ordinum.com`), nicht den Alias `Kim.Sieber@outlook.de`. IMAP akzeptiert den Alias.
- **Lösung (Kims Wunsch, analog zu den anderen Postfächern):** Feld **„Benutzername“** (leer = E-Mail-Adresse) auch bei Microsoft. Anmeldung mit dem Benutzernamen, Absender bleibt die E-Mail-Adresse. Getestet: Versand kommt beim Empfänger mit `@outlook.de` an.

### Kopie in „Gesendet“
Outlook.com legt per SMTP gesendete Mails selbst ab – mit Mailwerks Kopie lagen sie doppelt. Kim hat „Kopie in ‚Gesendet‘ ablegen“ beim Outlook-Postfach ausgeschaltet. (Standard beim Anlegen bleibt „an“; Schalter unter „Postfach bearbeiten → Versand“.)

### Simulator
Die Microsoft-Anmeldung ist im Simulator nicht möglich (Passkey verlangt QR-Code bzw. Bluetooth zum Gerät). Outlook-Tests nur auf dem iPhone.

---

## 4. Paket d: Spamfilter ohne eigene IMAP-Schlüsselwörter (Outlook)

**Symptom:** Beim Abruf über „Alle Eingänge“: „Spamfilter: Extended search failed: BAD Command Argument Error. 11“. Einzelne Ordner (auch Spam) ließen sich abrufen.

**Ursache (belegt):** Die Suche des Spamfilters enthält `UNKEYWORD $MailwerkChecked`. Exchange Online speichert keine eigenen Schlüsselwörter – `PERMANENTFLAGS` ohne `\*` (Rebex-Forum: `(\Seen \Answered \Flagged \Deleted \Draft $MDNSent)`). Die Suche ohne Schlüsselwort (normaler Abruf) funktioniert.

**Lösung (allgemein, keine Outlook-Sonderregel):**
- `KeywordSupport` (neu): prüft `PERMANENTFLAGS` – leer = wie bisher erlaubt, `\*` (SwiftMail: „wildcard“) = erlaubt, sonst nur ausdrücklich genannte.
- Server **mit** Schlüsselwörtern (manitu, Gmail, GMX …): unverändert.
- Server **ohne**: „schon geprüft“ = Mail liegt bereits im lokalen Cache des Posteingangs (der Filter läuft vor jedem Abruf). Schlüsselwörter werden nicht gesetzt; Blockieren, Vertrauen, Verschieben laufen gleich.
- Einschränkung: Mails, die bei ausgeschaltetem Filter abgerufen wurden, prüft dieses Gerät später nicht nach.

**„Weitergeleitet“ (`$Forwarded`) bei Outlook:** Kims Beobachtung – die Markierung bleibt erhalten, auch nach Neuinstallation. Outlook speichert `$Forwarded` also dauerhaft; keine Änderung nötig. (Kim hat auf Wunsch „Weitergeleitet“ aus Paket d herausgenommen.)

---

## 5. TestFlight-Fund: Filterlisten und Signaturen fehlten

**Symptom:** Erste TestFlight-Installation (iPad): Postfächer und sogar die Outlook-Anmeldung sofort da, aber keine White-/Blacklist und keine Signaturen.

**Ursache (belegt in der CloudKit Console):**
- Postfächer liegen im iCloud-**Key-Value-Speicher**, Zugänge im **Schlüsselbund** – beide ohne getrennte Umgebungen.
- Filterlisten und Signaturen liegen per SwiftData in **CloudKit**. Xcode-Builds nutzen **Development**, TestFlight/App Store **Production**. In Production fehlte das Schema (`CD_FilterEntry`, `CD_AccountSignature`) – nur `Users` war vorhanden.

**Behebung:** CloudKit Console → Development → „Deploy Schema Changes…“ → beide Typen in Production. Achtung: In Production lässt sich nichts mehr löschen, nur ergänzen. Die **Daten** werden dabei nicht übertragen – Production war leer.

---

## 6. Pakete e und e2: „Mailwerk Dev“ neben der TestFlight-App

**Kims Ziel:** iPhone weiter als Testgerät nutzen, aber nicht dauerhaft zwei Datenstände pflegen. Erster Plan (gemeinsame Postfächer, Sichern/Einlesen aller Einstellungen) wurde von Kim **verworfen** zugunsten einer klaren Trennung: Testpostfächer (neues Ordinum-Testpostfach, Outlook, web.de, GMX, Gmail …) nur in „Mailwerk Dev“, produktive Postfächer (ordinum, sieber-bw) nur in der TestFlight-App. Begründung: Ein Komplett-Export wird sonst nie mehr gebraucht (iCloud gleicht ab), ein Spamlisten-Import dagegen dauerhaft und für viele Nutzer.

**Einstellungen (Kim in Xcode, nach Anleitung):**

| Einstellung | Debug („Mailwerk Dev“) | Release (TestFlight/App Store) |
|---|---|---|
| `MAILWERK_BUNDLE_SUFFIX` (Projekt, User-Defined) | `.dev` | leer |
| Bundle-ID App | `de.sieber-bw.Mailwerk.dev` | `de.sieber-bw.Mailwerk` |
| Bundle-ID Erweiterungen | `…Mailwerk.dev.MailwerkShare(Mac)` | `…Mailwerk.MailwerkShare(Mac)` |
| Anzeigename (App und Erweiterungen) | „Mailwerk Dev“ | „Mailwerk“ |
| App-Gruppe | `group.de.sieber-bw.Mailwerk.dev` | `group.de.sieber-bw.Mailwerk` |
| Key-Value-Speicher (Postfächer, Standard-Postfach, Spamfilter an/aus) | eigener (`…Mailwerk.dev`) | bisheriger |
| CloudKit (Filterlisten, Signaturen) | Development | Production |
| Schlüsselbundgruppe | gemeinsam (unschädlich: Einträge hängen an der Postfach-Kennung) | gemeinsam |

- Werte in den Entitlements mit `$(MAILWERK_BUNDLE_SUFFIX)` bzw. `$(TeamIdentifierPrefix)…`.
- **Code:** `ShareContextFile.appGroupID` liest die App-Gruppe aus der Info.plist (`MailwerkAppGroupID` = `group.de.sieber-bw.Mailwerk$(MAILWERK_BUNDLE_SUFFIX)`), Rückfall auf die bisherige Gruppe.
- Teilen-Erweiterungen haben bewusst keinen Abschnitt „iCloud“.

**Reihenfolge (wichtig, so durchgeführt):** erst Key-Value-Speicher trennen und mit einem Kontrolllauf belegen („Mailwerk Dev“ ohne Postfächer, iPad unverändert), **dann** alte Xcode-„Mailwerk“ löschen, TestFlight installieren, Testpostfächer in Dev anlegen und in der Produktion entfernen. Vorher hätte das Löschen in Dev auch die Produktion getroffen.

**Regel:** Kein Postfach in beiden Apps zugleich – der Spamfilter merkt sich geprüfte Mails per Schlüsselwort auf dem Server; die Apps haben verschiedene Listen.

**Nebenbefund beim Aufräumen:** Nach dem Entfernen der Testpostfächer standen noch GMX-Mails in „Alle Eingänge“. Ursache: Sie lagen rechtmäßig im produktiven Postfach Kim.Sieber@ordinum.com (Kopfzeilen: manitu). Kein Fehler in Mailwerk; Kim prüft die Weiterleitung bei GMX.

---

## 7. Paket f: Spamfilter nach Erstinstallation eingeschaltet

**Fund:** In „Mailwerk Dev“ (neuer Key-Value-Speicher) war der Spamfilter aus – Standard war `false`. Folge siehe Paket h.
**Kims Entscheidung:** Nach der Erstinstallation ist der Filter **immer eingeschaltet**. `SpamSettings.defaultEnabled = true`; ein gespeicherter Wert (auch „aus“) hat Vorrang.

---

## 8. Paket g: Import von White-/Blacklist

**Entscheidungen:**
- Knopf **„Importieren“** (Pfeil nach unten) in der jeweiligen Liste neben „Liste teilen“ – die Datei hat keine Listenkennung, das Ziel ist so eindeutig.
- Format wie Export und manitu-Portal: eine Angabe je Zeile, Domains als `*@firma.de`. Erkannt mit derselben Zerlegung wie „Neuer Eintrag …“ (`FilterListInput`).
- Rückfrage mit Anzahl neuer und schon vorhandener Einträge, dann je Eintrag die Prüfung gegen die andere Liste wie bei manueller Anlage.
- Ergebnismeldung: übernommen, schon vorhanden, abgelehnt (andere Liste, einzeln benannt), nicht verwertbar.

**Umsetzung:** `FilterListImport` (neu, reine Logik: Text lesen UTF-8 mit BOM bzw. Windows-1252, Plan, Zusammenfassung); `FilterListView` mit `fileImporter`, Rückfrage, gemeinsamer Eintrage-Schleife. `FilterListInputEntry` jetzt `nonisolated … Hashable, Sendable` – beseitigt die alten Warnungen zur isolierten `Hashable`-Konformität.

**Getestet:** Simulator, iPhone (Dev, Doppelte erkannt), TestFlight-App: Kims gesicherte Listen erfolgreich eingelesen.

---

## 9. Paket h: Sicht „Spam“ auch bei ausgeschaltetem Filter

**Fund:** Die Sammelansicht „Spam“ und der Abruf der Spam-Ordner nutzen den am Postfach gemerkten Spam-Ordner. Diesen ermittelte bisher nur der Spamfilter. Mit ausgeschaltetem Filter blieb „Spam“ leer, obwohl die Ordner Mails hatten.
**Kims Vorgabe:** „Spam“ zeigt den Inhalt aller Spam-Ordner, egal ob der Filter aktiv ist.
**Umsetzung:** `SpamFilterService.locateSpamFolder(for:)` sucht den Ordner wie der Filter (gemerkt, `\Junk`, Namen) und merkt ihn; `InboxViewModel.locateSpamFolderIfNeeded` ruft das beim Abruf auf, wenn der Filter aus und noch kein Ordner bekannt ist. Fehlt ein Spam-Ordner, wird ohne Filter nichts angelegt und nicht nachgefragt.

---

## Geänderte Dateien (gesamte Version)

**Neu:**
- `Mailwerk/Services/OAuth/` – `OAuthProvider`, `OAuthPKCE`, `OAuthError`, `OAuthAuthorization`, `OAuthTokenResponse`, `OAuthTokenService`, `OAuthSignInState`
- `Mailwerk/Services/Spam/KeywordSupport.swift`, `FilterListImport.swift`
- `Mailwerk/Views/SignInRequiredBadge.swift`, `SignInRequiredBar.swift`
- Tests: `OAuthAuthorizationTests`, `OAuthTokenResponseTests`, `OAuthTokenServiceTests`, `MailAccountOAuthTests`, `KeywordSupportTests`, `FilterListImportTests`

**Geändert:**
- `MailwerkApp`, `MailAccount`, `AccountStore`, `KeychainService`, `Log`, `MailConnectionTester`, `MailSendService`, `MailSession`, `ShareContext`
- `SpamFilterService`, `SpamSettings`, `FilterListInput`
- `AddAccountViewModel`, `InboxViewModel`
- `AccountListView`, `AddAccountView`, `EditAccountView`, `FolderSidebarView`, `InboxView`, `FilterListView`
- `Mailwerk/Info.plist`, `MailwerkShare/Info.plist`, `MailwerkShareMac/Info.plist` (`MailwerkAppGroupID`)
- Tests: `MailSessionTests`, `ShareContextTests`
- Projekt/Entitlements (Kim in Xcode): `MAILWERK_BUNDLE_SUFFIX`, Bundle-IDs, Anzeigenamen, App-Gruppe, Key-Value-Kennung

---

## Testverfahren

- Automatische Tests: **651**, Simulator, alle grün. Vorprüfung unter Linux (Swift 6.2): reine Logik übersetzt und getestet; `MailSession`, `MailConnectionTester`, `OAuthSignInState`, `AddAccountViewModel` sowie die neuen SwiftMail-Aufrufe des Spamfilters gegen den echten SwiftMail-1.15.0-Quelltext übersetzt (ohne Warnungen).
- Outlook: nur iPhone (Passkey). Anlegen mit Alias + Benutzername, Abruf aller Ordner, Versand (Absender `@outlook.de`), Weiterleiten, „Alle Eingänge“ ohne Spamfilter-Fehler.
- TestFlight: iPad und iPhone, Listenimport in Production.
- Trennung Dev/Produktion: Kontrolllauf vor jedem Löschen.

---

## Beobachtungen und Erkenntnisse

- **Xcode-Builds ↔ Development, TestFlight ↔ Production.** Alles in CloudKit ist je Umgebung getrennt; Key-Value-Speicher und Schlüsselbund kennen keine Umgebungen.
- **Bundle-ID bestimmt die Installation:** Gleiche ID → TestFlight und Xcode ersetzen sich gegenseitig.
- **Microsoft SMTP verlangt die Haupt-Anmeldeadresse** bei XOAUTH2; IMAP nimmt auch Aliasse.
- **Exchange Online:** keine eigenen IMAP-Schlüsselwörter für Suche (`UNKEYWORD` → BAD), `$Forwarded` wird aber gespeichert.
- **`ASWebAuthenticationSession` in Erweiterungen:** Verfügbarkeit nicht belegt – deshalb nur in `MailwerkApp.swift` eingebunden.
- Kims Arbeitsweise (neu bekräftigt): Arbeitszeit ist das Wertvollste – kleine Änderungen nicht einzeln testen und committen, sondern mit dem nächsten größeren Paket zusammen. Immer nur ein Schritt; bei Haltepunkten („merken!“) den Stand festhalten und nicht vorgreifen.

---

## Gesamtstand des Projekts (Stand 18.10.2026)

### Produkt
- **Mailwerk**, Mail-Client in Swift/SwiftUI für iOS/iPadOS und macOS. Repo `github.com/KimSieber/Mailwerk` (public), Branch `main`. Projektordner auf Kims Mac: `/Users/kim/Dropbox/Dev/GitHub/Mailwerk`.
- Version **0.1.18**, **651 Tests**. Ziele: Mailwerk, MailwerkShare (iOS), MailwerkShareMac, MailwerkTests, MailwerkUITests.
- **Verteilung:** TestFlight (Kim, Kims Frau). „Mailwerk Dev“ per Xcode auf iPhone und Mac. Auf dem Mac ist die produktive App noch nicht installiert.

### Funktionsumfang (bis v0.1.18)
- Unified Inbox mehrerer IMAP/SMTP-Postfächer, Abruf je Postfach ein-/ausschaltbar (je Gerät), Farben je Postfach, Absenderbilder (Kontakte, Favicons).
- Sammelansichten: Alle Eingänge, Ungelesen (Zähler), Mit Kennzeichnung (Zähler), Spam (alle Spam-Ordner, auch ohne Filter).
- Ordnerleiste mit Ordnerbaum, Ordner anlegen/löschen, Verschieben-Dialog, Offline-Cache (SQLite, WAL, Schema-Stufe 7, FTS5-Suchindex), Server-Abgleich, „Ältere laden“.
- Mailansicht: HTML sicher (CSP, externe Inhalte auf Knopf), Dunkelmodus, Zoom, eingebettete Bilder, Originalquelle, Drucken, Teilen, Mailkopf mit Adressmenü.
- Verfassen: Rich-Text-Editor mit Formatierungsleiste, Anhänge, Bilder im Text, Signaturen je Postfach (einfach/HTML, mit Logo), Entwürfe, Absender-Regeln.
- Spamfilter (clientseitig): White-/Blacklist über CloudKit, Spam-Header-Auswertung, Blockieren/Vertrauen je Mail, Listen bearbeiten, exportieren, **importieren**; funktioniert auch auf Servern ohne eigene Schlüsselwörter.
- Suche (lokal, Namen, Server), Sortierung, Mehrfachauswahl, Kontextmenü, Rückgängig-Balken, eigene untere Leiste (Liquid Glass).
- Teilen mit Mailwerk (Erweiterungen iOS und Mac).
- **Anmeldung:** Passwort (manitu, GMX, web.de, Posteo, Gmail mit App-Passwort) und **OAuth 2 (Outlook.com)**.

### Technik (Kurzfassung)
- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift-5-Modus, MemberImportVisibility; iOS/macOS 26.5. Xcode 27.1, macOS 27.0.1.
- **SwiftMail 1.15.0** (nicht forken, keine weiteren Pakete ohne Rückfrage).
- Postfächer: iCloud-Key-Value-Speicher; Passwörter/Refresh-Tokens: iCloud-Schlüsselbund (Gruppe `$(AppIdentifierPrefix)de.sieber-bw.Mailwerk`); Filterlisten und Signaturen: SwiftData/CloudKit (`iCloud.de.sieber-bw.Mailwerk`, Schema jetzt auch in **Production**); Abruf-Schalter: UserDefaults (je Gerät).
- Test/Produktion: siehe Abschnitt 6 (Bundle-Suffix `.dev`).

### Arbeitsregeln (verbindlich, unverändert)
- Nichts bauen ohne Kims ausdrückliches OK; Inhalt jeder Version vorher mit Leitfragen (einzeln, mit Empfehlung) abstimmen.
- Immer nur einen Schritt bzw. eine Frage; kurz fassen; klare Anweisungen mit genauem Menüpfad.
- Ursache belegen, nicht raten (Rohdaten, Server-Dialog, Quelltext, Console).
- Lieferung als ganze Dateien direkt in den Projektordner (frischer Zwischenpfad, Prüfsummen vor und nach dem Ablegen, Tabelle *Datei · Ort · Art*); Git im Projektordner nur lesend; Projekteinstellungen ändert Kim in Xcode nach Anleitung.
- **Claude committet nie** – Commit-Text mitliefern; Kim committet in Xcode.
- Inline-Doku: Datei-Header (Zweck, Abgrenzung, Abhängigkeiten), DocC je Funktion, Deutsch, keine Versionsverweise.
- Keine Sonderlösungen für einzelne Anbieter; Gestaltung mit Apple-Bausteinen, eigene Anordnungen als USP erlaubt.
- Tests dürfen keine Produktivmails verändern – Tests jetzt mit den **Testpostfächern in „Mailwerk Dev“**.
- Arbeitszeit sparen: kleine Änderungen mit dem nächsten Paket gemeinsam testen und committen.

### Offene Punkte
- **Mac:** produktive „Mailwerk“ (TestFlight) noch nicht installiert; eine alte Xcode-„Mailwerk“ ggf. vorher löschen.
- **Azure-Probephase:** nach Ablauf Outlook in „Mailwerk Dev“ neu anmelden; bei Problemen Pay-As-You-Go. Vor App Store: Herausgeber-Verifizierung.
- **Gmail per OAuth:** nur vorgemerkt.
- **Kopfdaten außerhalb des Zeitfensters nachfüllen (Weg B):** per „Ältere laden“ geholte Mails mit veralteter Header-Version werden nie nachgefüllt.
- **H6:** Verbindungen je Konto wiederverwenden (ggf. mit Push/IDLE); **N14:** Offline-Warteschlange.
- **Ordner abonnieren:** in Mailwerk angelegte Ordner werden nicht abonniert (SwiftMail ohne SUBSCRIBE).
- **DKIM/Authentication-Results** für Logos und Spam-Prüfung.
- **Sporadischer Gmail-Timeout** (IMAP, Spam-Ordner in der Runde) – beobachten.
- **Suchfeld unten**, sobald iOS es ohne zweiten Suchknopf erlaubt.
- **Teilen:** große Videos ungetestet; HEIC als Original; Mac-Gestaltung vorläufig.
- **Strukturempfehlungen:** Protokolle/Injektion für Tests ohne Server, SwiftLint/SwiftFormat, Lokalisierung.
- Sonstiges: Empfangsdatum statt Kopfdatum nur bei Bedarf; Inline-Foto ohne Verweis bei einzelnem HTML-Teil beobachten; Originalquelle > 5 MB nicht möglich; Logo-Breite einfacher Signatur fest 150 pt; Titel-Mindestbreite iPad/Querformat beobachten.

### Fahrplan
- **Nächste Version:** mit Kim festlegen. Kandidaten: Fehler-Patch mit Weg B, weitere Funde aus dem produktiven Einsatz über TestFlight.
- **v0.2.x:** Seitenleiste und Layout für iPad und Mac (Kim hat viele eigene Ideen), Gestaltung der Teilen-Erweiterung auf dem Mac.
- **Später:** H6, Push/IDLE, N14, Ordner abonnieren, Threading; App-Store-Veröffentlichung (Herausgeber-Verifizierung Microsoft, Datenschutzangaben).
