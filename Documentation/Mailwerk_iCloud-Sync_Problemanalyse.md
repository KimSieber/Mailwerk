# Mailwerk – Problemanalyse: iCloud-Abgleich der Filterlisten

Stand: 27.09.2026, während der Arbeit an v0.1.6 (Ordnerverwaltung). Die Analyse wurde unterbrochen, um v0.1.6 abzuschließen. Dieses Dokument fasst alle bisherigen Erkenntnisse zusammen, damit die Fehlersuche in einem separaten Chat fortgesetzt werden kann.

---

## 1. Problem

Die Whitelist-/Blacklist-Einträge (Filterlisten des Spamfilters) werden **nicht zwischen Geräten abgeglichen**.

- Auf dem echten iPhone war die Whitelist nach der Erstinstallation leer, obwohl im iPhone-Simulator bereits Einträge existierten.
- Auf dem echten iPhone neu angelegte Einträge erscheinen **nicht** im iPhone-Simulator, auch nicht nach vollständigem Beenden und Neustart der App dort.

Die Postfach-Daten selbst (Konten über `NSUbiquitousKeyValueStore`) gleichen dagegen ab: Der iPad-Simulator zeigte nach iCloud-Anmeldung die drei Postfächer. Das Problem betrifft also speziell den CloudKit-Abgleich über SwiftData, nicht iCloud allgemein.

---

## 2. Architektur (relevanter Ausschnitt)

| Daten | Speicherung | Abgleich |
|---|---|---|
| Postfach-Konfiguration | `NSUbiquitousKeyValueStore` | iCloud Key-Value – **funktioniert** |
| Passwörter | Schlüsselbund mit `kSecAttrSynchronizable` | iCloud-Schlüsselbund – im Simulator grundsätzlich nicht verfügbar (erwartet) |
| Filterlisten (`FilterEntry`) | SwiftData mit CloudKit, private Datenbank | **funktioniert nicht** |
| Mail-Cache, Ordnerlisten | SQLite (`MessageStore`), lokal | kein Abgleich (gewollt) |

### SwiftData-Modell

```swift
@Model
final class FilterEntry {
    var id: UUID = UUID()
    var value: String = ""
    var kindRaw: String = FilterEntryKind.address.rawValue
    var listRaw: String = FilterList.black.rawValue
    var createdAt: Date = Date()
    // …
}
```

Das Modell erfüllt die CloudKit-Anforderungen: Alle Eigenschaften haben Standardwerte, es gibt keine `@Attribute(.unique)`-Regeln und keine Beziehungen.

### Container und Einrichtung

- CloudKit-Container: `iCloud.de.sieber-bw.Mailwerk`
- Der `ModelContainer` wird in `MailwerkApp.makeContainer()` angelegt. Zuerst wird die iCloud-Variante versucht, bei einem Fehler folgt der Rückfall auf einen rein lokalen Speicher. Beim Start wird ausgegeben, welcher Speicher aktiv ist: `🗂️ Filterlisten-Speicher: iCloud` bzw. `… lokal`.
- Im Testlauf (Xcode als Test-Host) verwendet die App einen reinen In-Memory-Container ohne CloudKit (seit v0.1.6, `MailwerkApp.isRunningTests`).

### Berechtigungen (`Mailwerk/Mailwerk.entitlements`)

```xml
<key>aps-environment</key>                              <string>development</string>
<key>com.apple.developer.aps-environment</key>          <string>development</string>
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.de.sieber-bw.Mailwerk</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
<key>keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)de.sieber-bw.Mailwerk</string></array>
```

`Info.plist` enthält `UIBackgroundModes` → `remote-notification`.

### Umgebung

- Xcode auf macOS 26.6.2
- iOS-Simulator 26.5 (iPhone 17, iPad), echtes iPhone per Kabel
- Deployment Target iOS/macOS 26.5
- Alle Builds sind Debug-Builds aus Xcode, also CloudKit-Umgebung **Development**

---

## 3. Was geprüft wurde und was es ergab

### 3.1 Geräte und Anmeldung

| Prüfung | Ergebnis |
|---|---|
| iPhone-Simulator in iCloud angemeldet | ja (laut Nutzer) |
| iPad-Simulator in iCloud angemeldet | ja, erst nachträglich; danach erschienen die Postfächer |
| iCloud für Mailwerk auf dem echten iPhone aktiviert | ja |
| Dieselbe Apple-ID auf allen Geräten | angenommen, nicht ausdrücklich bestätigt |
| App auf empfangendem Gerät beendet und neu gestartet | ja, ohne Wirkung |

### 3.2 Konsole auf dem echten iPhone

- **Filter „Filterlisten“:** `🗂️ Filterlisten-Speicher: iCloud`. Der iCloud-Container wurde also erfolgreich geöffnet, und es gab keinen Rückfall auf „lokal“.
- **Filter „CloudKit“** nach Anlegen eines Eintrags:
  ```
  updateTaskRequest failed for com.apple.coredata.cloudkit.activity.export.6D503994-E605-4173-8E7A-4F00FFE2C5EF
  Error updating background task request: Error Domain=BGSystemTaskSchedulerErrorDomain Code=3 "(null)"
  updateTaskRequest called for an already running/updated task com.apple.coredata.cloudkit.activity.export.6D503994-…
  ```
  Core Data plant also einen Export (Hochladen). Die Meldungen betreffen die Planung des Hintergrund-Vorgangs über `BGSystemTaskScheduler`. Ob sie harmlos sind oder das Hochladen tatsächlich verhindern, ist **offen**. Eine Meldung über Erfolg oder Fehlschlag des Exports erschien nicht.
- **Startparameter `-com.apple.CoreData.CloudKitDebug 1`** (Scheme → Run → Arguments Passed On Launch) wurde gesetzt. Mit dem Filter „error“ erschienen nur allgemeine Systemmeldungen (WebKit, Kontextmenü), sonst nur die obigen `updateTaskRequest`-Zeilen. Mit dem Filter **„CoreData+CloudKit“ erschien nichts**. Entweder greift der Parameter nicht, oder die Xcode-Konsole blendet diese Meldungen aus, etwa weil sie nur auf Debug-Protokollebene erscheinen.

### 3.3 CloudKit Dashboard (icloud.developer.apple.com), Umgebung Development

- **Schema → Record Types:** Der Typ **`CD_FilterEntry` existiert** mit 12 Feldern, darunter `CD_id`, `CD_value`, `CD_kindRaw`, `CD_listRaw`, `CD_createdAt` und `CD_entityName`. Dieser Typ entsteht in der Development-Umgebung erst beim **ersten erfolgreichen Export** durch Core Data. Mindestens ein Gerät bzw. Build hat also irgendwann erfolgreich hochgeladen. Container, Team und Berechtigungen sind damit grundsätzlich funktionsfähig.
- Für `CD_FilterEntry` wurde nachträglich ein Index auf `recordName` vom Typ QUERYABLE angelegt, der zum Auflisten der Einträge nötig ist. Das Speichern war erfolgreich.
- **Records → Private Database lässt sich nicht öffnen:** „Failed to access iCloud data – Click here to retry…“, auch nach mehrfachem Retry. Dasselbe gilt für die Shared Database. Es war deshalb **nicht prüfbar**, ob und welche Einträge in iCloud liegen.
  - Mögliche Ursachen, noch nicht geprüft:
    - „Auf iCloud-Daten im Web zugreifen“ ist auf dem iPhone ausgeschaltet. Das ist typisch bei aktivem Erweitertem Datenschutz für iCloud.
    - Der Browser blockiert die iCloud-Anmeldung des Dashboards (websiteübergreifende Cookies bzw. Tracking-Schutz in Safari).
    - Das Dashboard greift als andere Apple-ID zu als die auf den Geräten.
  - Hinweis für später: Core Data speichert in der Zone **`com.apple.coredata.cloudkit.zone`**, nicht in `_defaultZone`. Die Abfrage muss dort erfolgen.

---

## 4. Einordnung

Gesichert:

1. Die App öffnet den iCloud-Speicher (kein Rückfall auf lokal).
2. Das Datenmodell ist CloudKit-tauglich.
3. Der Container ist korrekt eingerichtet und wurde bereits mindestens einmal erfolgreich beschrieben (Schema existiert).
4. Nach dem Anlegen eines Eintrags plant Core Data einen Export.

Offen:

- Laufen die Exporte vom echten iPhone und vom Simulator erfolgreich durch, oder schlagen sie fehl? Mit welcher Meldung?
- Liegen die Einträge in der privaten Datenbank? Das Dashboard ist derzeit nicht zugänglich.
- Funktioniert das Herunterladen (Import) auf dem empfangenden Gerät?
- Sind die `BGSystemTaskSchedulerErrorDomain Code=3`-Meldungen nur Begleitrauschen oder die Ursache dafür, dass Exporte nicht ausgeführt werden?

### Hypothesen, grob nach Wahrscheinlichkeit

1. **Export oder Import scheitert mit einem CloudKit-Fehler**, der bisher nicht sichtbar war, weil Core Data seine Meldungen nicht in die Xcode-Konsole schreibt. Beispiele wären Konto-Status, Berechtigungen oder Teilfehler.
2. **Der Export wird geplant, aber nicht ausgeführt.** Dafür spricht der Zusammenhang mit den `BGSystemTaskScheduler`-Meldungen unter iOS 26.
3. **Der Simulator empfängt nicht.** Er bekommt die stillen Push-Benachrichtigungen von CloudKit nicht zuverlässig, und das Herunterladen beim Start scheitert ebenfalls.
4. **Unterschiedliche Apple-IDs oder iCloud-Konten** auf den Geräten. Das ist nicht ausdrücklich ausgeschlossen.
5. Frühere Einträge im Simulator entstanden, als der Speicher noch lokal war, und wurden nie hochgeladen. Das erklärt allerdings nicht, dass neue Einträge vom iPhone nicht ankommen.

---

## 5. Vorbereiteter nächster Schritt: `CloudSyncMonitor`

Zur Diagnose wurde eine kleine Komponente erstellt. Sie ist geliefert, aber **noch nicht ausgeführt bzw. ausgewertet**:

- **`Mailwerk/Services/CloudSyncMonitor.swift` (neu):** Beobachtet `NSPersistentCloudKitContainer.eventChangedNotification`. SwiftData sendet sie ebenfalls, weil es intern über Core Data abgleicht. Jedes Ereignis (Einrichtung, Hochladen, Herunterladen) wird mit Start, Erfolg oder Fehlschlag in die Konsole geschrieben, bei Fehlschlag mit der vollständigen Fehlermeldung von CloudKit. Ausgabeformat:
  ```
  ☁️ iCloud-Abgleich: Hochladen gestartet
  ☁️ iCloud-Abgleich: Hochladen FEHLGESCHLAGEN – <Meldung>
  ☁️ iCloud-Abgleich: Details – <vollständiger Fehler>
  ```
- **`Mailwerk/MailwerkApp.swift` (geändert):** Ruft `CloudSyncMonitor.start()` im `init()` vor dem Anlegen des `ModelContainer` auf, nicht im Testlauf.

**Vorgehen:**

1. Beide Dateien einbauen und die App über Xcode auf dem echten iPhone starten.
2. In der Xcode-Konsole unten rechts im Feld „Filter“ **Abgleich** eintippen.
3. Beim Start: Zeilen zur Einrichtung prüfen.
4. Whitelist-Eintrag anlegen, etwa eine Minute warten, dann die Zeilen zum Hochladen prüfen.
5. Dasselbe im Simulator: App neu starten und die Zeilen zum Herunterladen prüfen.

Die Ausgaben aus Schritt 3 bis 5 sollten die Ursache direkt benennen.

### Weitere Möglichkeiten, falls nötig

- **Console.app auf dem Mac:** echtes iPhone links auswählen, „Streaming starten“, über das Menü „Aktion“ Info- und Debug-Meldungen einschließen, nach `CloudKit` bzw. Prozess `Mailwerk` filtern. Dort erscheinen die Core-Data-Meldungen, die in Xcode fehlen.
- **Zugang zur privaten Datenbank im Dashboard herstellen:** „Auf iCloud-Daten im Web zugreifen“ auf dem iPhone einschalten, im Browser Tracking-Schutz vorübergehend lockern bzw. vorher auf icloud.com anmelden. Danach Records → Private Database → Zone `com.apple.coredata.cloudkit.zone` → Record Type `CD_FilterEntry` abfragen.
- **Test ohne Simulator:** Abgleich zwischen zwei echten Geräten mit derselben Apple-ID prüfen, etwa iPhone und iPad oder Mac. So lässt sich Hypothese 3 ausschließen.

---

## 6. Randbemerkungen aus der Analyse

- Der Startparameter `-com.apple.CoreData.CloudKitDebug 1` ist noch im Schema eingetragen (Run → Arguments). Nach der Analyse entfernen oder deaktivieren.
- Der Index `recordName` (QUERYABLE) auf `CD_FilterEntry` im Dashboard ist unschädlich und kann bleiben.
- Beim späteren Wechsel auf Produktion bzw. TestFlight muss das Schema einmal von Development nach Production übertragen werden (Dashboard → „Deploy Schema Changes“). Sonst gleicht die ausgelieferte App nicht ab. Mit dem aktuellen Problem hat das nichts zu tun, weil alle Builds Development nutzen.
